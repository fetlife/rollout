require "spec_helper"

RSpec.describe Rollout::Adapters::ActiveRecord, "#import_features" do
  let(:adapter) { active_record_adapter }

  def chat_state
    Rollout::FeatureState.new(
      name: :chat,
      percentage: 10.5,
      users: ["123"],
      groups: ["employees"],
      data: { "description" => "New navigation", "label" => "beta" },
    )
  end

  def history_entry(feature:, data:, feature_visible: true, global_visible: false, created_at: Time.utc(2026, 1, 1))
    Struct.new(:event, :feature_visible, :global_visible).new(
      Rollout::Logging::Event.new(
        feature: feature,
        name: "update",
        data: data,
        context: { actor: "alice" },
        created_at: created_at,
      ),
      feature_visible,
      global_visible,
    )
  end

  it "imports feature state in one transaction" do
    adapter.import_features([
      chat_state,
      Rollout::FeatureState.new(name: :signup, percentage: 0),
    ])

    expect(adapter.feature_names).to eq %w[chat signup]
    expect(adapter.fetch_feature(:chat)).to eq chat_state
    expect(adapter.fetch_feature(:signup).percentage).to eq 0.0
    expect(adapter.feature_events(:chat)).to eq []
  end

  it "imports history without pruning or synthesizing events" do
    first = history_entry(feature: "chat", data: { after: { percentage: 25 } }, global_visible: true)
    second = history_entry(
      feature: "chat",
      data: { after: { percentage: 50 } },
      created_at: Time.utc(2026, 1, 2),
    )

    adapter.import_features([chat_state], history: [first, second])

    events = adapter.feature_events(:chat)
    expect(events.map { |event| event.data }).to eq [
      { after: { percentage: 25 } },
      { after: { percentage: 50 } },
    ]
    expect(events.first.context).to eq(actor: "alice")
    expect(adapter.global_events.map { |event| event.data }).to eq [{ after: { percentage: 25 } }]
  end

  it "rejects a destination that already has features" do
    adapter.save_feature(Rollout::FeatureState.new(name: :existing, percentage: 1))

    expect {
      adapter.import_features([chat_state])
    }.to raise_error(ArgumentError, "destination already has rollout data")

    expect(adapter.feature_names).to eq ["existing"]
  end

  it "rejects a destination that already has history" do
    Rollout.new(adapter: adapter, logging: true).activate_percentage(:chat, 25)
    adapter.delete_feature(:chat)

    expect(adapter.feature_names).to eq []
    expect(adapter.feature_events(:chat)).not_to eq []

    expect {
      adapter.import_features([chat_state])
    }.to raise_error(ArgumentError, "destination already has rollout data")
  end

  it "rolls back all imported rows when a write fails" do
    feature_record = adapter.instance_variable_get(:@feature_record)
    calls = 0
    allow(feature_record).to receive(:create!).and_wrap_original do |method, *args, **kwargs|
      calls += 1
      raise ActiveRecord::StatementInvalid, "insert failed" if calls > 1

      method.call(*args, **kwargs)
    end

    expect {
      adapter.import_features([
        chat_state,
        Rollout::FeatureState.new(name: :signup, percentage: 100),
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect(adapter.feature_names).to eq []
    expect(adapter).not_to be_occupied
  end

  it "rolls back when the import block raises ActiveRecord::Rollback" do
    adapter.import_features([chat_state]) do
      raise ActiveRecord::Rollback
    end

    expect(adapter.feature_names).to eq []
    expect(adapter).not_to be_occupied
  end

  it "rolls back when verification raises ActiveRecord::Rollback inside an outer transaction" do
    ActiveRecord::Base.transaction do
      adapter.import_features([chat_state]) do
        raise ActiveRecord::Rollback
      end
    end

    expect(adapter.feature_names).to eq []
    expect(adapter).not_to be_occupied
  end
end
