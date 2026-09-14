require "date"

RSpec.shared_examples "a rollout feature backend" do
  def empty_state(name)
    Rollout::FeatureState.new(name: name, percentage: 0)
  end

  def json_metadata
    {
      "description" => "New navigation",
      "updated_at" => 1,
      "enabled" => true,
      "ratio" => 0.5,
      "owner" => nil,
      "label" => :beta,
      "released_at" => Time.utc(2026, 1, 1),
      "day" => Date.new(2026, 1, 1),
      "labels" => ["a", { "nested" => :ok }],
    }
  end

  it "returns an empty state for a missing feature" do
    state = backend.fetch_feature(:chat)

    expect(state).to eq empty_state(:chat)
  end

  it "preserves fetch_features order and duplicates" do
    backend.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))

    states = backend.fetch_features([:chat, :missing, :chat])

    expect(states.map(&:name)).to eq %w[chat missing chat]
    expect(states.map(&:percentage)).to eq [25.0, 0.0, 25.0]
  end

  it "returns no features for an empty fetch_features request" do
    expect(backend.fetch_features([])).to eq []
  end

  it "does not share nested data with a fetched state" do
    backend.save_feature(
      Rollout::FeatureState.new(name: :chat, percentage: 0, data: { "labels" => ["a"] }),
    )

    backend.fetch_feature(:chat).data["labels"] << "b"

    expect(backend.fetch_feature(:chat).data).to eq("labels" => ["a"])
  end

  it "does not share nested data with a saved state" do
    state = Rollout::FeatureState.new(name: :chat, percentage: 0, data: { "labels" => ["a"] })
    backend.save_feature(state)

    state.data["labels"] << "b"

    expect(backend.fetch_feature(:chat).data).to eq("labels" => ["a"])
  end

  it "returns the same canonical metadata after save_feature" do
    state = Rollout::FeatureState.new(name: :chat, percentage: 0, data: json_metadata)
    backend.save_feature(state)

    expect(backend.fetch_feature(:chat)).to eq state
    expect(state.data["label"]).to eq "beta"
    expect(state.data["labels"]).to eq ["a", { "nested" => "ok" }]
  end

  it "tracks existence and names after save and delete" do
    backend.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))

    expect(backend.feature_exists?(:chat)).to be_truthy
    expect(backend.feature_names).to eq ["chat"]

    backend.delete_feature(:chat)

    expect(backend.feature_exists?(:chat)).to be_falsey
    expect(backend.fetch_feature(:chat)).to eq empty_state(:chat)
  end

  it "does not persist when mutate_feature's block raises" do
    expect {
      backend.mutate_feature(:chat) { raise "nope" }
    }.to raise_error("nope")

    expect(backend.feature_exists?(:chat)).to be_falsey
  end
end
