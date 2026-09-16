require "spec_helper"

RSpec.describe "Rollout ActiveRecord feature cache" do
  let(:clock) { { now: 0.0 } }
  let(:adapter) { cached_adapter }

  def cached_adapter
    active_record_adapter(cache_ttl: 10).tap do |current|
      current.instance_variable_set(
        :@feature_cache,
        Rollout::ActiveRecord::FeatureCache.new(ttl: 10, clock: -> { clock[:now] }),
      )
    end
  end

  def save(percentage, name: :chat)
    adapter.save_feature(Rollout::FeatureState.new(name: name, percentage: percentage))
  end

  def select_count
    count = 0
    callback = lambda do |*_args, payload|
      sql = payload[:sql].to_s
      next unless sql.match?(/\A\s*SELECT/i)
      next if payload[:cached]

      count += 1
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  it "returns cached feature state until the TTL expires" do
    save(10)
    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0

    other = active_record_adapter
    other.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 90))

    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0

    clock[:now] = 11.0
    expect(adapter.fetch_feature(:chat).percentage).to eq 90.0
  end

  it "does not share nested data with a cached state" do
    adapter.save_feature(
      Rollout::FeatureState.new(name: :chat, percentage: 0, data: { "labels" => ["a"] }),
    )

    adapter.fetch_feature(:chat).data["labels"] << "b"

    expect(adapter.fetch_feature(:chat).data).to eq("labels" => ["a"])
  end

  it "caches missing features" do
    expect(adapter.fetch_feature(:chat).percentage).to eq 0.0

    other = active_record_adapter
    other.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))

    expect(adapter.fetch_feature(:chat).percentage).to eq 0.0
  end

  it "fills fetch_features misses in one query" do
    save(10, name: :chat)
    adapter.fetch_feature(:chat)
    save(20, name: :signup)

    expect(select_count { adapter.fetch_features([:chat, :signup, :chat]) }).to eq 1
    expect(adapter.fetch_features([:chat, :signup, :chat]).map(&:percentage)).to eq [10.0, 20.0, 10.0]
    expect(select_count { adapter.fetch_features([:chat, :signup]) }).to eq 0
  end

  it "invalidates a feature after a local write" do
    save(10)
    adapter.fetch_feature(:chat)
    save(50)

    expect(adapter.fetch_feature(:chat).percentage).to eq 50.0
  end

  it "invalidates after delete_feature and clear_features" do
    save(10)
    adapter.fetch_feature(:chat)
    adapter.delete_feature(:chat)
    expect(adapter.fetch_feature(:chat).percentage).to eq 0.0

    save(20)
    adapter.fetch_feature(:chat)
    adapter.clear_features
    expect(adapter.fetch_feature(:chat).percentage).to eq 0.0
  end

  it "invalidates after mutate_feature commits" do
    save(10)
    adapter.fetch_feature(:chat)
    Rollout.new(adapter: adapter).activate_percentage(:chat, 50)

    expect(adapter.fetch_feature(:chat).percentage).to eq 50.0
  end

  it "reads through to the database inside an open transaction" do
    save(10)
    adapter.fetch_feature(:chat)

    ActiveRecord::Base.transaction do
      other = active_record_adapter
      other.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 90))
      expect(adapter.fetch_feature(:chat).percentage).to eq 90.0
      raise ActiveRecord::Rollback
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0
  end

  it "invalidates after an outer transaction commits" do
    save(10)
    adapter.fetch_feature(:chat)

    ActiveRecord::Base.transaction do
      adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 50))
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 50.0
  end

  it "keeps the cached value when an outer transaction rolls back" do
    save(10)
    adapter.fetch_feature(:chat)

    ActiveRecord::Base.transaction do
      adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 50))
      raise ActiveRecord::Rollback
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0
  end

  it "does not cache uncommitted state from mutate_feature" do
    save(10)
    adapter.fetch_feature(:chat)

    ActiveRecord::Base.transaction do
      Rollout.new(adapter: adapter).activate_percentage(:chat, 50)
      raise ActiveRecord::Rollback
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0
  end

  it "does not invalidate until a non-joinable outer transaction commits" do
    save(10)
    adapter.fetch_feature(:chat)
    cache = adapter.instance_variable_get(:@feature_cache)
    context = adapter.send(:cache_context)

    ActiveRecord::Base.transaction(joinable: false) do
      adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 50))
      expect(cache.read(:chat, context: context).percentage).to eq 10.0
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 50.0
  end

  it "does not invalidate delete_feature until a non-joinable outer transaction commits" do
    save(10)
    adapter.fetch_feature(:chat)
    cache = adapter.instance_variable_get(:@feature_cache)
    context = adapter.send(:cache_context)

    ActiveRecord::Base.transaction(joinable: false) do
      adapter.delete_feature(:chat)
      expect(cache.read(:chat, context: context).percentage).to eq 10.0
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 0.0
  end

  it "allows concurrent cache reads" do
    save(25)
    adapter.fetch_feature(:chat)
    threads = Array.new(8) { Thread.new { adapter.fetch_feature(:chat).percentage } }

    expect(threads.map(&:value).uniq).to eq [25.0]
  end

  it "does not restore a stale fetch_feature fill after invalidation" do
    save(10)
    stale = Rollout::FeatureState.new(name: :chat, percentage: 10)

    allow(adapter).to receive(:load_feature) do
      adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 90))
      stale
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0

    allow(adapter).to receive(:load_feature).and_call_original
    expect(adapter.fetch_feature(:chat).percentage).to eq 90.0
  end

  it "does not restore a stale fetch_features fill after invalidation" do
    save(10)
    stale = Rollout::FeatureState.new(name: :chat, percentage: 10)

    allow(adapter).to receive(:load_features) do
      adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 90))
      [stale]
    end

    expect(adapter.fetch_features([:chat]).first.percentage).to eq 10.0

    allow(adapter).to receive(:load_features).and_call_original
    expect(adapter.fetch_feature(:chat).percentage).to eq 90.0
  end

  it "scopes cache entries to the current connection pool" do
    alpha = adapter.send(:cache_context)
    save(10)
    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0

    ActiveRecord::Base.connection.execute("UPDATE rollout_features SET percentage = 90 WHERE name = 'chat'")
    allow(adapter).to receive(:cache_context).and_return(:beta)

    expect(adapter.fetch_feature(:chat).percentage).to eq 90.0

    allow(adapter).to receive(:cache_context).and_return(alpha)
    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0
  end

  it "loads cache fills through Active Record uncached" do
    save(10)
    feature_record = adapter.instance_variable_get(:@feature_record)
    allow(feature_record).to receive(:uncached).and_call_original
    adapter.fetch_feature(:chat)
    expect(feature_record).to have_received(:uncached).at_least(:once)
  end

  it "does not bypass Active Record query cache when adapter caching is disabled" do
    uncached = active_record_adapter
    uncached.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 10))
    feature_record = uncached.instance_variable_get(:@feature_record)
    allow(feature_record).to receive(:uncached).and_call_original

    uncached.fetch_feature(:chat)

    expect(feature_record).not_to have_received(:uncached)
  end

  it "reuses Active Record query cache when adapter caching is disabled" do
    uncached = active_record_adapter
    uncached.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 10))

    ActiveRecord::Base.cache do
      expect(select_count { uncached.fetch_feature(:chat) }).to eq 1
      expect(select_count { uncached.fetch_feature(:chat) }).to eq 0
    end
  end

  it "does not refresh expired entries from the Active Record query cache" do
    save(10)

    ActiveRecord::Base.cache do
      expect(adapter.fetch_feature(:chat).percentage).to eq 10.0

      ActiveRecord::Base.uncached(dirties: false) do
        ActiveRecord::Base.connection.execute("UPDATE rollout_features SET percentage = 90 WHERE name = 'chat'")
      end

      clock[:now] = 11.0
      expect(adapter.fetch_feature(:chat).percentage).to eq 90.0
    end
  end
end
