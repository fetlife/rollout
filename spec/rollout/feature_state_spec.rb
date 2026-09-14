require "spec_helper"
require "date"

RSpec.describe Rollout::FeatureState do
  def build_state(overrides = {})
    described_class.new(**{
      name: :chat,
      percentage: 25,
      users: [123, "456"],
      groups: [:employees, "supporters"],
      data: { description: "New navigation", "updated_at" => 1 },
    }.merge(overrides))
  end

  def feature_for(state, options: {}, rollout: Object.new)
    Rollout::Feature.new(state: state, rollout: rollout, options: options)
  end

  def json_value(value)
    JSON.parse({ "value" => value }.to_json)["value"]
  end

  it "normalizes persistence types" do
    state = build_state

    expect(state.name).to eq "chat"
    expect(state.percentage).to eq 25.0
    expect(state.users).to eq %w[123 456]
    expect(state.groups).to eq %w[employees supporters]
    expect(state.data).to eq("description" => "New navigation", "updated_at" => 1)
  end

  it "does not share collections with the caller" do
    users = ["123"]
    groups = ["employees"]
    nested = ["a"]
    data = { "labels" => nested }
    state = build_state(users: users, groups: groups, data: data)

    users << "456"
    groups << "supporters"
    nested << "b"
    data["labels"] << "c"

    expect(state.users).to eq %w[123]
    expect(state.groups).to eq %w[employees]
    expect(state.data).to eq("labels" => ["a"])
  end

  it "canonicalizes nested JSON-compatible metadata" do
    state = build_state(
      data: {
        "description" => "New navigation",
        "updated_at" => 1,
        "enabled" => true,
        "ratio" => 0.5,
        "owner" => nil,
        "kind" => :beta,
        "labels" => ["a", { "nested" => :ok }],
      },
    )

    expect(state.data).to eq(
      "description" => "New navigation",
      "updated_at" => 1,
      "enabled" => true,
      "ratio" => 0.5,
      "owner" => nil,
      "kind" => "beta",
      "labels" => ["a", { "nested" => "ok" }],
    )
  end

  it "canonicalizes Time, Date, and custom JSON values" do
    custom = Object.new
    def custom.to_json(*)
      '"widget"'
    end

    released_at = Time.utc(2026, 1, 1)
    day = Date.new(2026, 1, 1)
    state = build_state(
      data: {
        "released_at" => released_at,
        "day" => day,
        "item" => custom,
      },
    )

    expect(state.data).to eq(
      "released_at" => json_value(released_at),
      "day" => json_value(day),
      "item" => "widget",
    )
  end

  it "canonicalizes BigDecimal through JSON" do
    require "bigdecimal"

    amount = BigDecimal("1.5")
    state = build_state(data: { "amount" => amount })

    expect(state.data).to eq("amount" => json_value(amount))
  end

  it "rejects metadata that cannot be serialized as JSON" do
    cyclic = {}
    cyclic["self"] = cyclic

    expect {
      build_state(data: cyclic)
    }.to raise_error(JSON::JSONError)
  end

  it "rejects non-hash metadata" do
    expect {
      build_state(data: "nope")
    }.to raise_error(ArgumentError, "data must be a Hash")
  end

  it "does not share nested data or strings with its clone" do
    description = +"hello"
    state = build_state(data: { "description" => description, "labels" => ["a"] })
    clone = state.deep_clone

    clone.users << "999"
    clone.groups << "admins"
    clone.data["labels"] << "b"
    clone.data["description"] << "!"
    description << "?"

    expect(state.users).to eq %w[123 456]
    expect(state.groups).to eq %w[employees supporters]
    expect(state.data).to eq("description" => "hello", "labels" => ["a"])
    expect(clone.data["description"]).to eq "hello!"
  end

  describe "Feature conversion" do
    it "round-trips evaluation and metadata" do
      rollout = Object.new
      def rollout.active_in_group?(group, user)
        group == :employees && user.id == 1
      end

      state = build_state(percentage: 20, users: ["42"], groups: ["employees"], data: { "description" => "New navigation" })
      feature = feature_for(state, rollout: rollout)
      restored = feature_for(feature.to_feature_state, rollout: rollout)

      expect(feature.to_feature_state.name).to eq "chat"
      expect(feature.to_feature_state.percentage).to eq 20.0
      expect(feature.to_feature_state.users).to eq %w[42]
      expect(feature.to_feature_state.groups).to eq %w[employees]
      expect(feature.to_feature_state.data).to eq("description" => "New navigation")
      expect(restored.name).to eq :chat

      expect(restored.active?(double(id: 1))).to eq feature.active?(double(id: 1))
      expect(restored.active?(double(id: 42))).to eq feature.active?(double(id: 42))
      expect(restored.active?(double(id: 2))).to eq feature.active?(double(id: 2))
      expect(restored.to_hash).to eq feature.to_hash
    end

    it "canonicalizes JSON-serializable metadata when converting a Feature" do
      released_at = Time.utc(2026, 1, 1)
      feature = feature_for(build_state)
      feature.data["released_at"] = released_at
      feature.data["kind"] = :beta

      expect(feature.to_feature_state.data).to eq(
        "description" => "New navigation",
        "updated_at" => 1,
        "released_at" => json_value(released_at),
        "kind" => "beta",
      )
    end

    it "does not share nested data with the source feature" do
      feature = feature_for(build_state(data: { "labels" => ["a"] }))
      state = feature.to_feature_state

      feature.data["labels"] << "b"

      expect(state.data).to eq("labels" => ["a"])
    end

    it "does not share nested data with a reconstructed feature" do
      nested = ["a"]
      state = build_state(data: { "labels" => nested })
      feature = feature_for(state)

      feature.data["labels"] << "b"
      nested << "c"
      state.data["labels"] << "d"

      expect(feature.data).to eq("labels" => ["a", "b"])
      expect(state.data).to eq("labels" => ["a", "d"])
    end

    it "uses sets when use_sets is enabled" do
      feature = feature_for(build_state, options: { use_sets: true })

      expect(feature.users).to eq %w[123 456].to_set
      expect(feature.groups).to eq %i[employees supporters].to_set
    end

    it "preserves randomized percentage evaluation through a round trip" do
      options = { randomize_percentage: true }
      feature = feature_for(
        Rollout::FeatureState.new(name: :chat, percentage: 20),
        options: options,
      )
      restored = feature_for(feature.to_feature_state, options: options)

      expect(restored.active?(double(id: 1))).to eq true
      expect(restored.active?(double(id: 2))).to eq false
      expect(restored.active?(double(id: 1))).to eq feature.active?(double(id: 1))
      expect(restored.active?(double(id: 2))).to eq feature.active?(double(id: 2))
    end
  end
end
