require "spec_helper"

RSpec.describe "Rollout ActiveRecord configuration" do
  it "rejects a non-positive cache_ttl" do
    expect { active_record_adapter(cache_ttl: 0) }.to raise_error(ArgumentError, "cache_ttl must be an Integer > 0")
    expect { active_record_adapter(cache_ttl: 1.5) }.to raise_error(ArgumentError, "cache_ttl must be an Integer > 0")
  end

  it "uses a configured abstract base record class" do
    base = Class.new(ActiveRecord::Base)
    base.abstract_class = true
    adapter = active_record_adapter(base_record_class: base)

    adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: 25))

    expect(adapter.fetch_feature(:chat).percentage).to eq 25.0
  end

  it "keeps table configuration isolated between adapters" do
    connection = ActiveRecord::Base.connection
    create_rollout_schema(
      connection,
      features_table: "custom_rollout_features",
      events_table: "custom_rollout_events",
    )

    default_adapter = active_record_adapter
    custom_adapter = active_record_adapter(
      features_table_name: "custom_rollout_features",
      events_table_name: "custom_rollout_events",
    )
    default_rollout = Rollout.new(adapter: default_adapter, logging: true)
    custom_rollout = Rollout.new(adapter: custom_adapter, logging: true)

    default_rollout.activate_percentage(:chat, 10)
    custom_rollout.activate_percentage(:chat, 90)

    expect(default_adapter.fetch_feature(:chat).percentage).to eq 10.0
    expect(custom_adapter.fetch_feature(:chat).percentage).to eq 90.0
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
