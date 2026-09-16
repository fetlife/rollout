require "spec_helper"

begin
  require "redis"
  require "rollout/adapters/redis"
rescue LoadError
end

RSpec.describe "Redis to Active Record migration" do
  def redis_client
    Redis.new(
      host: ENV.fetch("REDIS_HOST", "127.0.0.1"),
      port: ENV.fetch("REDIS_PORT", "6379"),
      db: ENV.fetch("REDIS_MIGRATION_DB", "8"),
    )
  end

  let(:redis) { redis_client }
  let(:source) { Rollout::Adapters::Redis.new(redis) }
  let(:destination) { active_record_adapter }
  let(:migration) do
    Rollout::ActiveRecord::Migration.new(source: source, destination: destination)
  end

  before do
    unless defined?(::Redis)
      raise LoadError, "redis is required for migration examples" if ENV["CI"]

      skip "redis gem is not available"
    end

    redis.ping
    redis.flushdb
  rescue Redis::BaseConnectionError, Errno::ECONNREFUSED => error
    raise error if ENV["CI"]

    skip "Redis is not available: #{error.message}"
  end

  def seed_redis
    rollout = Rollout.new(adapter: source, logging: { history_length: 10, global: true })
    rollout.logging.with_context(actor: "alice") do
      rollout.with_feature(:chat) do |feature|
        feature.percentage = 10.5
        feature.users = ["123"]
        feature.groups = [:employees]
        feature.data.update(description: "New navigation", label: :beta)
      end
    end
    rollout.activate_user(:signup, 8)
    rollout.set_feature_data(:signup, "|call||text|" => "a|bunch|of|stuff")
    rollout.deactivate(:legacy)
    rollout
  end

  it "copies current Redis feature state into Active Record" do
    redis_rollout = seed_redis

    result = migration.run

    expect(result).to be_success
    expect(result.status).to eq :ok
    expect(result.feature_count).to eq 3

    copied = Rollout.new(adapter: destination)
    expect(copied.get(:chat).percentage).to eq 10.5
    expect(copied.get(:chat).users).to eq %w[123]
    expect(copied.get(:chat).groups).to eq [:employees]
    expect(copied.get(:chat).data).to eq("description" => "New navigation", "label" => "beta")
    expect(copied.get(:signup).users).to eq %w[8]
    expect(copied.get(:signup).data).to include("|call||text|" => "a|bunch|of|stuff")
    expect(copied.get(:legacy).percentage).to eq 0
    expect(copied.exists?(:legacy)).to eq true
    expect(copied.active?(:chat, double(id: 123))).to eq redis_rollout.active?(:chat, double(id: 123))
    expect(destination.feature_events(:chat)).to eq []
  end

  it "dry-run does not write Redis or Active Record" do
    seed_redis
    before = source.export_features.states

    result = migration.dry_run

    expect(result.status).to eq :ready
    expect(destination.feature_names).to eq []
    expect(source.export_features.states).to eq before
  end

  it "detects a missing Redis feature key" do
    seed_redis
    redis.set("feature:__features__", (source.feature_names + ["ghost"]).join(","))

    result = migration.run

    expect(result.status).to eq :source_invalid
    expect(result.missing_names).to eq ["ghost"]
    expect(destination.feature_names).to eq []
  end

  it "detects an unregistered Redis feature key" do
    seed_redis
    redis.set("feature:orphan", "100.0|||{}")

    result = migration.run

    expect(result.status).to eq :source_invalid
    expect(result.unregistered_names).to eq ["orphan"]
    expect(destination.feature_names).to eq []
  end

  it "copies retained Redis history when requested" do
    rollout = seed_redis
    rollout.activate_percentage(:chat, 25)
    rollout.activate_percentage(:legacy, 50)
    source.delete_feature(:legacy)
    rollout.logging.delete(:signup)

    result = Rollout::ActiveRecord::Migration.new(
      source: source,
      destination: destination,
      include_history: true,
    ).run

    expect(result).to be_success
    expect(result.history_count).to be > 0

    copied = Rollout.new(adapter: destination, logging: { global: true })
    chat_events = copied.logging.events(:chat)
    expect(chat_events.map { |event| event.data[:after][:percentage] }).to eq [10.5, 25]
    expect(chat_events.first.context).to eq(actor: "alice")
    expect(copied.logging.events(:signup)).to eq []
    expect(copied.logging.global_events.map(&:feature)).to include("signup")
    expect(copied.logging.events(:legacy).map { |event| event.data[:after][:percentage] }).to eq [50]
    expect(copied.exists?(:legacy)).to eq false
  end

  it "preserves Redis history order for equal timestamps" do
    created_at = Time.at(1_700_000_000)
    [
      ["chat", 10],
      ["chat", 20],
      ["signup", 30],
    ].each do |feature, percentage|
      source.save_feature(Rollout::FeatureState.new(name: feature, percentage: percentage))
      source.record_event(
        Rollout::Logging::Event.new(
          feature: feature,
          name: "update",
          data: { after: { percentage: percentage } },
          context: {},
          created_at: created_at,
        ),
        history_length: 10,
        global: true,
      )
    end

    redis_chat = source.feature_events("chat")
    redis_signup = source.feature_events("signup")
    redis_global = source.global_events

    result = Rollout::ActiveRecord::Migration.new(
      source: source,
      destination: destination,
      include_history: true,
    ).run

    expect(result).to be_success
    expect(destination.feature_events("chat").map(&:data)).to eq redis_chat.map(&:data)
    expect(destination.feature_events("signup").map(&:data)).to eq redis_signup.map(&:data)
    expect(destination.global_events.map(&:data)).to eq redis_global.map(&:data)
    expect(destination.feature_events("chat", limit: 1).map(&:data)).to eq redis_chat.last(1).map(&:data)
    expect(destination.global_events(limit: 1).map(&:data)).to eq redis_global.last(1).map(&:data)
  end

  it "preserves Redis history timestamps at microsecond precision" do
    source.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 10))
    [100, 500].each do |usec|
      source.record_event(
        Rollout::Logging::Event.new(
          feature: "chat",
          name: "update",
          data: { after: { percentage: usec } },
          context: {},
          created_at: Time.at(Rational(1_700_000_000 * 1_000_000 + usec, 1_000_000)),
        ),
        history_length: 10,
        global: true,
      )
    end

    result = Rollout::ActiveRecord::Migration.new(
      source: source,
      destination: destination,
      include_history: true,
    ).run

    expect(result).to be_success
    expect(destination.feature_events("chat").map { |event| event.created_at.usec }).to eq [100, 500]
    expect(destination.feature_events("chat").map { |event| (event.created_at.to_r * 1_000_000).round }).to eq [
      1_700_000_000_000_100,
      1_700_000_000_000_500,
    ]
  end
end
