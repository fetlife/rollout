RSpec.shared_examples "a rollout feature backend" do
  def empty_state(name)
    Rollout::FeatureState.new(name: name, percentage: 0)
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

  it "saves and fetches a complete feature state" do
    state = Rollout::FeatureState.new(
      name: :chat,
      percentage: 10.5,
      users: ["1"],
      groups: ["employees"],
      data: { "description" => "foo", "labels" => ["a"] },
    )

    backend.save_feature(state)

    expect(backend.fetch_feature(:chat)).to eq state
    expect(backend.fetch_feature("chat")).to eq state
  end

  it "persists the state returned by mutate_feature" do
    backend.mutate_feature(:chat) do |current|
      {
        state: Rollout::FeatureState.new(name: current.name, percentage: 50),
        event: nil,
      }
    end

    expect(backend.fetch_feature(:chat).percentage).to eq 50.0
    expect(backend.feature_exists?(:chat)).to be_truthy
  end
end
