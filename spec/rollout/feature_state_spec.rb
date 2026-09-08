require "spec_helper"

RSpec.describe Rollout::FeatureState do
  let(:rollout) { Rollout.new($redis) }

  def build_state(overrides = {})
    described_class.new(**{
      name: :chat,
      percentage: 25,
      users: [123, "456"],
      groups: [:employees, "supporters"],
      data: { description: "New navigation", "updated_at" => 1 },
    }.merge(overrides))
  end

  def feature_for(state, options: rollout.options)
    Rollout::Feature.new(state: state, rollout: rollout, options: options)
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
      rollout.define_group(:employees) { |user| user.id == 1 }
      rollout.activate_percentage(:chat, 20)
      rollout.activate_user(:chat, 42)
      rollout.activate_group(:chat, :employees)
      rollout.set_feature_data(:chat, description: "New navigation")

      feature = rollout.get(:chat)
      state = feature.to_feature_state
      restored = feature_for(state)

      expect(state.name).to eq "chat"
      expect(state.percentage).to eq 20.0
      expect(state.users).to eq %w[42]
      expect(state.groups).to eq %w[employees]
      expect(state.data).to eq("description" => "New navigation")
      expect(restored.name).to eq :chat

      expect(restored.active?(double(id: 1))).to eq feature.active?(double(id: 1))
      expect(restored.active?(double(id: 42))).to eq feature.active?(double(id: 42))
      expect(restored.active?(double(id: 2))).to eq feature.active?(double(id: 2))
      expect(restored.to_hash).to eq feature.to_hash
    end

    it "does not expose assign_state" do
      feature = rollout.get(:chat)

      expect(feature).not_to respond_to(:assign_state)
      expect(feature.private_methods).to include(:assign_state)
    end

    it "does not share nested data with the source feature" do
      rollout.set_feature_data(:chat, labels: ["a"])
      feature = rollout.get(:chat)
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
      randomized = Rollout.new($redis, randomize_percentage: true)
      randomized.activate_percentage(:chat, 20)

      feature = randomized.get(:chat)
      restored = Rollout::Feature.new(
        state: feature.to_feature_state,
        rollout: randomized,
        options: randomized.options,
      )

      expect(restored.active?(double(id: 1))).to eq true
      expect(restored.active?(double(id: 2))).to eq false
      expect(restored.active?(double(id: 1))).to eq feature.active?(double(id: 1))
      expect(restored.active?(double(id: 2))).to eq feature.active?(double(id: 2))
    end
  end
end
