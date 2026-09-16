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

    expect(adapter.fetch_features([:chat, :signup, :chat]).map(&:percentage)).to eq [10.0, 20.0, 10.0]
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

  it "allows concurrent cache reads" do
    save(25)
    adapter.fetch_feature(:chat)
    threads = Array.new(8) { Thread.new { adapter.fetch_feature(:chat).percentage } }

    expect(threads.map(&:value).uniq).to eq [25.0]
  end
end
