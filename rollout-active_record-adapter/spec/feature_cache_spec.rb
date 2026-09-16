require "spec_helper"

RSpec.describe Rollout::ActiveRecord::FeatureCache do
  let(:clock) { { now: 0.0 } }

  def build_cache(**options)
    described_class.new(ttl_seconds: 10, clock: -> { clock[:now] }, **options)
  end

  def state(name, percentage: 0)
    Rollout::FeatureState.new(name: name, percentage: percentage)
  end

  it "stores a fill when generation is unchanged" do
    cache = build_cache
    cache.fill(cache.generation, [state(:chat, percentage: 10)], context: :alpha)

    expect(cache.read(:chat, context: :alpha).percentage).to eq 10.0
  end

  it "does not store a fill after invalidation" do
    cache = build_cache
    generation = cache.generation
    cache.delete(:chat, context: :alpha)
    cache.fill(generation, [state(:chat, percentage: 10)], context: :alpha)

    expect(cache.read(:chat, context: :alpha)).to be_nil
  end

  it "does not store a fill after clear" do
    cache = build_cache
    generation = cache.generation
    cache.clear
    cache.fill(generation, [state(:chat, percentage: 10)], context: :alpha)

    expect(cache.read(:chat, context: :alpha)).to be_nil
  end

  it "isolates entries by context" do
    cache = build_cache
    cache.fill(cache.generation, [state(:chat, percentage: 10)], context: :alpha)
    cache.fill(cache.generation, [state(:chat, percentage: 90)], context: :beta)

    expect(cache.read(:chat, context: :alpha).percentage).to eq 10.0
    expect(cache.read(:chat, context: :beta).percentage).to eq 90.0
  end

  it "invalidates one context without removing another" do
    cache = build_cache
    cache.fill(cache.generation, [state(:chat, percentage: 10)], context: :alpha)
    cache.fill(cache.generation, [state(:chat, percentage: 90)], context: :beta)
    cache.delete(:chat, context: :alpha)

    expect(cache.read(:chat, context: :alpha)).to be_nil
    expect(cache.read(:chat, context: :beta).percentage).to eq 90.0
  end

  it "expires an entry without extending TTL on read" do
    cache = build_cache
    cache.fill(cache.generation, [state(:chat, percentage: 10)], context: :alpha)
    clock[:now] = 9.0
    expect(cache.read(:chat, context: :alpha).percentage).to eq 10.0

    clock[:now] = 10.0
    expect(cache.read(:chat, context: :alpha)).to be_nil
  end

  it "evicts expired entries before inserting at capacity" do
    cache = build_cache(max_size: 2)
    cache.fill(cache.generation, [state(:a, percentage: 1), state(:b, percentage: 2)], context: :alpha)
    clock[:now] = 11.0
    cache.fill(cache.generation, [state(:c, percentage: 3)], context: :alpha)

    expect(cache.read(:a, context: :alpha)).to be_nil
    expect(cache.read(:b, context: :alpha)).to be_nil
    expect(cache.read(:c, context: :alpha).percentage).to eq 3.0
  end

  it "evicts the oldest live entry when at capacity" do
    cache = build_cache(max_size: 2)
    cache.fill(cache.generation, [state(:a, percentage: 1), state(:b, percentage: 2)], context: :alpha)
    cache.fill(cache.generation, [state(:c, percentage: 3)], context: :alpha)

    expect(cache.read(:a, context: :alpha)).to be_nil
    expect(cache.read(:b, context: :alpha).percentage).to eq 2.0
    expect(cache.read(:c, context: :alpha).percentage).to eq 3.0
  end

  it "does not share nested data with a cached state" do
    cache = build_cache
    cache.fill(
      cache.generation,
      [Rollout::FeatureState.new(name: :chat, percentage: 0, data: { "labels" => ["a"] })],
      context: :alpha,
    )

    cache.read(:chat, context: :alpha).data["labels"] << "b"

    expect(cache.read(:chat, context: :alpha).data).to eq("labels" => ["a"])
  end
end
