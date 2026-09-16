require "spec_helper"

RSpec.describe Rollout::Adapters::Redis, "#export_features" do
  let(:backend) { redis_adapter }

  def export
    backend.export_features
  end

  it "exports registered feature state" do
    backend.save_feature(
      Rollout::FeatureState.new(
        name: :chat,
        percentage: 10.5,
        users: ["123"],
        groups: ["employees"],
        data: { "description" => "New navigation", "label" => :beta },
      ),
    )
    backend.save_feature(Rollout::FeatureState.new(name: :signup, percentage: 0))

    result = export

    expect(result).to be_valid
    expect(result.missing_names).to eq []
    expect(result.unregistered_names).to eq []
    expect(result.states.map(&:name)).to eq %w[chat signup]
    expect(result.states[0]).to eq(
      Rollout::FeatureState.new(
        name: :chat,
        percentage: 10.5,
        users: ["123"],
        groups: ["employees"],
        data: { "description" => "New navigation", "label" => "beta" },
      ),
    )
    expect(result.states[1].percentage).to eq 0.0
    expect(result.history).to eq []
  end

  it "reports registered names whose feature keys are missing" do
    backend.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))
    $redis.set("feature:__features__", "chat,ghost")
    $redis.del("feature:ghost")

    result = export

    expect(result).not_to be_valid
    expect(result.missing_names).to eq ["ghost"]
    expect(result.states.map(&:name)).to eq %w[chat]
    expect(result.states.first.percentage).to eq 25.0
  end

  it "reports feature keys that are not in the registry" do
    backend.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))
    $redis.set("feature:orphan", "100.0|||{}")

    result = export

    expect(result).not_to be_valid
    expect(result.unregistered_names).to eq ["orphan"]
    expect(result.states.map(&:name)).to eq %w[chat]
  end

  it "does not treat history keys as unregistered features" do
    rollout = Rollout.new(adapter: backend, logging: { history_length: 10, global: true })
    rollout.activate_percentage(:chat, 25)
    backend.delete_feature(:chat)

    result = export

    expect(result).to be_valid
    expect(result.states).to eq []
    expect($redis.type("feature:chat:logging:events")).to eq "zset"
    expect($redis.type("feature:_global_:logging:events")).to eq "zset"
  end

  it "exports an empty source" do
    result = export

    expect(result).to be_valid
    expect(result.states).to eq []
  end

  it "combines per-feature and global history for the same event" do
    rollout = Rollout.new(adapter: backend, logging: { history_length: 10, global: true })
    rollout.logging.with_context(actor: "alice") do
      rollout.activate_percentage(:chat, 25)
    end

    result = backend.export_features(include_history: true)

    expect(result.history.size).to eq 1
    entry = result.history.first
    expect(entry.feature_visible).to eq true
    expect(entry.global_visible).to eq true
    expect(entry.event.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })
    expect(entry.event.context).to eq(actor: "alice")
  end

  it "keeps independent visibility for deleted-feature history" do
    rollout = Rollout.new(adapter: backend, logging: { history_length: 10, global: true })
    rollout.activate_percentage(:chat, 25)
    backend.delete_feature(:chat)
    rollout.activate_percentage(:signup, 50)
    rollout.logging.delete(:signup)

    result = backend.export_features(include_history: true)
    by_feature = result.history.each_with_object({}) do |entry, hash|
      hash[entry.event.feature.to_s] = entry
    end

    expect(by_feature["chat"].feature_visible).to eq true
    expect(by_feature["chat"].global_visible).to eq true
    expect(by_feature["signup"].feature_visible).to eq false
    expect(by_feature["signup"].global_visible).to eq true
  end

  it "preserves distinct events that share a timestamp" do
    created_at = Time.at(1_700_000_000)
    first = Rollout::Logging::Event.new(
      feature: "chat",
      name: "update",
      data: { after: { percentage: 10 } },
      context: {},
      created_at: created_at,
    )
    second = Rollout::Logging::Event.new(
      feature: "chat",
      name: "update",
      data: { after: { percentage: 20 } },
      context: {},
      created_at: created_at,
    )
    backend.record_event(first, history_length: 10, global: false)
    backend.record_event(second, history_length: 10, global: false)

    result = backend.export_features(include_history: true)
    exported = result.history.map { |entry| entry.event.data[:after][:percentage] }

    expect(exported).to eq backend.feature_events("chat").map { |event| event.data[:after][:percentage] }
    expect(exported).to eq [20, 10]
    expect(backend.feature_events("chat", limit: 1).map { |event| event.data[:after][:percentage] }).to eq [10]
    expect(result.history.map { |entry| entry.event.timestamp }.uniq.size).to eq 1
  end

  it "exports equal-timestamp events in Redis history order" do
    created_at = Time.at(1_700_000_000)
    [
      ["chat", 10],
      ["chat", 20],
      ["signup", 30],
    ].each do |feature, percentage|
      backend.record_event(
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

    result = backend.export_features(include_history: true)
    percentages = lambda do |events|
      events.map { |event| [event.feature.to_s, event.data[:after][:percentage]] }
    end
    exported = lambda do |entries|
      percentages.call(entries.map(&:event))
    end

    expect(exported.call(result.history.select { |entry| entry.event.feature.to_s == "chat" })).to eq(
      percentages.call(backend.feature_events("chat")),
    )
    expect(exported.call(result.history.select { |entry| entry.event.feature.to_s == "signup" })).to eq(
      percentages.call(backend.feature_events("signup")),
    )
    expect(exported.call(result.history.select(&:global_visible))).to eq(
      percentages.call(backend.global_events),
    )
    expect(percentages.call(backend.feature_events("chat", limit: 1))).to eq(
      percentages.call(backend.feature_events("chat").last(1)),
    )
    expect(percentages.call(backend.global_events(limit: 1))).to eq(
      percentages.call(backend.global_events.last(1)),
    )
  end

  it "does not duplicate history when SCAN yields a key twice" do
    rollout = Rollout.new(adapter: backend, logging: { history_length: 10, global: true })
    rollout.activate_percentage(:chat, 25)

    allow($redis).to receive(:scan_each).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do |key|
        block.call(key)
        block.call(key) if key.to_s.end_with?(":logging:events")
      end
    end

    result = backend.export_features(include_history: true)

    expect(result.history.size).to eq 1
    expect(result.history.first.feature_visible).to eq true
    expect(result.history.first.global_visible).to eq true
    expect(result.history.first.event.feature).to eq "chat"
  end
end
