require "spec_helper"

RSpec.describe "Rollout ActiveRecord configuration" do
  it "uses a configured abstract base record class" do
    base = Class.new(ActiveRecord::Base)
    base.abstract_class = true
    backend = active_record_backend(base_record_class: base)

    backend.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))

    expect(backend.fetch_feature(:chat).percentage).to eq 25.0
  end

  it "keeps table configuration isolated between backends" do
    connection = ActiveRecord::Base.connection
    create_rollout_schema(
      connection,
      features_table: "custom_rollout_features",
      events_table: "custom_rollout_events",
    )

    default_backend = active_record_backend
    custom_backend = active_record_backend(
      features_table_name: "custom_rollout_features",
      events_table_name: "custom_rollout_events",
    )
    default_rollout = Rollout.new(backend: default_backend, logging: true)
    custom_rollout = Rollout.new(backend: custom_backend, logging: true)

    default_rollout.activate_percentage(:chat, 10)
    custom_rollout.activate_percentage(:chat, 90)

    expect(default_backend.fetch_feature(:chat).percentage).to eq 10.0
    expect(custom_backend.fetch_feature(:chat).percentage).to eq 90.0
    expect(default_rollout.logging.events(:chat).last.data[:after][:percentage]).to eq 10
    expect(custom_rollout.logging.events(:chat).last.data[:after][:percentage]).to eq 90
  ensure
    Rollout::ActiveRecord::Schema.drop(
      connection,
      features_table: "custom_rollout_features",
      events_table: "custom_rollout_events",
    )
  end
end
