require "spec_helper"

RSpec.describe Rollout::ActiveRecord::Migration do
  FakeExport = Struct.new(:states, :missing_names, :unregistered_names, :history, keyword_init: true) do
    def initialize(states: [], missing_names: [], unregistered_names: [], history: [])
      super(
        states: states,
        missing_names: missing_names,
        unregistered_names: unregistered_names,
        history: history,
      )
    end

    def valid?
      missing_names.empty? && unregistered_names.empty?
    end
  end

  FakeSource = Struct.new(:export) do
    def export_features(include_history: false)
      export
    end
  end

  FakeHistory = Struct.new(:event, :feature_visible, :global_visible, keyword_init: true)

  let(:destination) { active_record_adapter }
  let(:chat) do
    Rollout::FeatureState.new(
      name: :chat,
      percentage: 10.5,
      users: ["123"],
      groups: ["employees"],
      data: { "description" => "New navigation" },
    )
  end
  let(:signup) { Rollout::FeatureState.new(name: :signup, percentage: 0) }
  let(:source) { FakeSource.new(FakeExport.new(states: [chat, signup])) }
  let(:migration) { described_class.new(source: source, destination: destination) }

  def destination_names
    destination.feature_names
  end

  it "dry-run leaves the destination empty" do
    result = migration.dry_run

    expect(result).to be_success
    expect(result.status).to eq :ready
    expect(result.feature_count).to eq 2
    expect(result.summary).to eq "Ready to import 2 features"
    expect(destination_names).to eq []
  end

  it "copies current feature state" do
    result = migration.run

    expect(result).to be_success
    expect(result.status).to eq :ok
    expect(result.feature_count).to eq 2
    expect(result.summary).to eq "Imported 2 features"
    expect(destination.fetch_feature(:chat)).to eq chat
    expect(destination.fetch_feature(:signup)).to eq signup
  end

  it "rejects a second import into an occupied destination" do
    migration.run

    result = migration.run

    expect(result).not_to be_success
    expect(result.status).to eq :destination_conflict
    expect(result.summary).to eq "Destination already has rollout data"
    expect(destination.fetch_feature(:chat)).to eq chat
  end

  it "does not overwrite a destination that already has rollout data" do
    destination.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 99))

    result = migration.run

    expect(result).not_to be_success
    expect(result.status).to eq :destination_conflict
    expect(destination.fetch_feature(:chat).percentage).to eq 99.0
    expect(destination.feature_exists?(:signup)).to eq false
  end

  it "fails closed on source inconsistencies" do
    invalid = FakeSource.new(
      FakeExport.new(
        states: [chat],
        missing_names: ["ghost"],
        unregistered_names: ["orphan"],
      ),
    )

    result = described_class.new(source: invalid, destination: destination).run

    expect(result).not_to be_success
    expect(result.status).to eq :source_invalid
    expect(result.missing_names).to eq ["ghost"]
    expect(result.unregistered_names).to eq ["orphan"]
    expect(destination_names).to eq []
  end

  it "rolls back when verification does not match the source" do
    allow(destination).to receive(:fetch_features).and_wrap_original do |method, *args|
      method.call(*args).map do |state|
        Rollout::FeatureState.new(name: state.name, percentage: state.percentage + 1)
      end
    end

    result = migration.run

    expect(result.status).to eq :verification_failed
    expect(destination_names).to eq []
    expect(destination).not_to be_occupied
  end

  it "imports retained history when requested" do
    event = Rollout::Logging::Event.new(
      feature: "chat",
      name: "update",
      data: { before: { percentage: 0 }, after: { percentage: 10.5 } },
      context: { actor: "alice" },
      created_at: Time.utc(2026, 1, 1, 12),
    )
    history_source = FakeSource.new(
      FakeExport.new(
        states: [chat],
        history: [
          FakeHistory.new(event: event, feature_visible: true, global_visible: true),
        ],
      ),
    )
    history_migration = described_class.new(
      source: history_source,
      destination: destination,
      include_history: true,
    )

    result = history_migration.run

    expect(result).to be_success
    expect(result.history_count).to eq 1
    expect(result.summary).to eq "Imported 1 features and 1 history events"
    imported = destination.feature_events(:chat).last
    expect(imported.data).to eq(before: { percentage: 0 }, after: { percentage: 10.5 })
    expect(imported.context).to eq(actor: "alice")
    expect(destination.global_events.map(&:feature)).to eq %w[chat]
  end
end
