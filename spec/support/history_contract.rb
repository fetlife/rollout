RSpec.shared_examples "a rollout history backend" do
  let(:rollout) { Rollout.new(backend: backend, logging: logging) }
  let(:logging) { true }
  let(:feature) { :foo }

  it "persists feature events oldest-to-newest" do
    rollout.activate_percentage(feature, 50)
    rollout.activate_percentage(feature, 75)
    rollout.activate_group(feature, :hipsters)

    events = rollout.logging.events(feature)
    expect(events.map(&:name)).to eq %w[update update update]
    expect(events.map { |event| event.data }).to eq [
      { before: { percentage: 0 }, after: { percentage: 50 } },
      { before: { percentage: 50 }, after: { percentage: 75 } },
      { before: { groups: [] }, after: { groups: ["hipsters"] } },
    ]
    expect(rollout.logging.updated_at(feature)).to_not be_nil
  end

  it "persists metadata changes and actor context" do
    rollout.logging.with_context(actor: "alice") do
      rollout.with_feature(feature) do |current|
        current.percentage = 25.0
        current.data.update(description: "New navigation")
      end
    end

    event = rollout.logging.last_event(feature)
    expect(event.data).to eq(
      before: { percentage: 0, "data.description": nil },
      after: { percentage: 25.0, "data.description": "New navigation" },
    )
    expect(event.context).to eq(actor: "alice")
    expect(rollout.logging.events(feature).count).to eq 1
  end

  context "history truncation" do
    let(:logging) { { history_length: 1 } }

    it "keeps only the configured number of events" do
      rollout.activate_percentage(feature, 25)
      rollout.activate_percentage(feature, 30)

      expect(rollout.logging.events(feature).map { |event| event.data[:after][:percentage] }).to eq [30]
    end
  end

  context "global logs" do
    let(:logging) { { global: true } }

    it "logs changes across features oldest-to-newest" do
      rollout.activate_percentage("foo", 25)
      rollout.activate_percentage("bar", 30)
      rollout.activate_percentage("baz", 40)

      expect(rollout.logging.global_events.map(&:feature)).to eq %w[foo bar baz]
      expect(rollout.logging.global_events(limit: 2).map(&:feature)).to eq %w[bar baz]
    end
  end

  it "removes feature history on delete" do
    rollout.activate_percentage(feature, 25)
    rollout.delete(feature)

    expect(rollout.logging.events(feature)).to eq []
  end

  it "keeps feature history on clear!" do
    rollout.activate_percentage(feature, 25)
    rollout.clear!

    expect(rollout.features).to eq []
    expect(rollout.logging.events(feature).map { |event| event.data[:after][:percentage] }).to eq [25, 0]
  end

  it "keeps feature history when deleting without logging" do
    rollout.activate_percentage(feature, 25)

    Rollout.new(backend: backend).delete(feature)

    expect(rollout.exists?(feature)).to be_falsey
    expect(rollout.logging.events(feature)).not_to eq []
  end

  it "logging.delete removes feature history only" do
    rollout.activate_percentage(feature, 25)
    rollout.logging.delete(feature)

    expect(rollout.logging.events(feature)).to eq []
    expect(rollout.logging.updated_at(feature)).to be_nil
    expect(rollout.get(feature).percentage).to eq 25
  end

  it "backend delete_feature preserves history" do
    rollout.activate_percentage(feature, 25)
    rollout.backend.delete_feature(feature)

    expect(rollout.exists?(feature)).to be_falsey
    expect(rollout.logging.events(feature)).not_to eq []
  end

  it "returns the newest events oldest-to-newest when limited" do
    rollout.activate_percentage(feature, 25)
    rollout.activate_percentage(feature, 50)
    rollout.activate_percentage(feature, 75)

    expect(rollout.logging.events(feature, limit: 2).map { |event| event.data[:after][:percentage] }).to eq [50, 75]
    expect(rollout.logging.events(feature, limit: 0)).to eq []
    expect(rollout.logging.last_event(feature).data[:after][:percentage]).to eq 75
  end

  it "rejects an invalid history limit" do
    expect { rollout.logging.events(feature, limit: -1) }.to raise_error(ArgumentError)
    expect { rollout.backend.feature_events(feature, limit: 1.5) }.to raise_error(ArgumentError)
  end
end
