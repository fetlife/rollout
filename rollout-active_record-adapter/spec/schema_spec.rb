require "spec_helper"
require "erb"

RSpec.describe "Rollout ActiveRecord schema" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:percentage) { 33.333333333333336 }

  it "creates double-precision percentages, case-sensitive names, and a hidden-event index" do
    assert_installed_schema(connection)
    assert_percentage_round_trip
    assert_large_payload_round_trip
  end

  it "installs the same schema through the generated migration" do
    Rollout::ActiveRecord::Schema.drop(connection)
    run_install_migration

    assert_installed_schema(connection)
    assert_percentage_round_trip
    assert_large_payload_round_trip
  ensure
    create_rollout_schema
  end

  def assert_installed_schema(connection)
    percentage_column = column(connection, "rollout_features", "percentage")
    expect(percentage_column.limit).to eq 53 if ADAPTER == "mysql2"
    expect(percentage_column.sql_type).to match(/double/i) if ADAPTER == "mysql2"

    if ADAPTER == "mysql2"
      expect(column(connection, "rollout_features", "name").collation).to eq "utf8mb4_bin"
      expect(column(connection, "rollout_events", "feature_name").collation).to eq "utf8mb4_bin"
      %w[users groups data].each do |name|
        expect(column(connection, "rollout_features", name).sql_type).to match(/mediumtext/i)
      end
      %w[data context].each do |name|
        expect(column(connection, "rollout_events", name).sql_type).to match(/mediumtext/i)
      end
    end

    expect(connection.indexes("rollout_events").map(&:columns)).to include(
      ["feature_visible", "global_visible"],
    )
  end

  def assert_percentage_round_trip
    adapter = active_record_adapter
    adapter.save_feature(Rollout::FeatureState.new(name: :chat, percentage: percentage))

    expect(adapter.fetch_feature(:chat).percentage).to eq percentage
  end

  def assert_large_payload_round_trip
    adapter = active_record_adapter
    blob = "x" * 70_000
    adapter.save_feature(
      Rollout::FeatureState.new(
        name: :chat,
        percentage: 1,
        users: Array.new(8_000) { |index| "user-#{index}" },
        data: { "blob" => blob },
      ),
    )
    state = adapter.fetch_feature(:chat)
    expect(state.users.size).to eq 8_000
    expect(state.data["blob"].bytesize).to eq 70_000

    rollout = Rollout.new(adapter: adapter, logging: true)
    rollout.logging.with_context(note: blob) do
      rollout.activate_percentage(:chat, 2)
    end
    event = rollout.logging.last_event(:chat)
    expect(event.context[:note].bytesize).to eq 70_000
  end

  def column(connection, table, name)
    connection.columns(table).find { |current| current.name == name }
  end

  def run_install_migration
    template = File.read(
      File.expand_path(
        "../lib/generators/rollout/active_record/templates/create_rollout_tables.rb.tt",
        __dir__,
      ),
    )
    class_name = "CreateRolloutTables#{object_id}"
    source = ERB.new(template).result
    source = source.sub("class CreateRolloutTables", "class #{class_name}")
    eval(source, TOPLEVEL_BINDING)
    Object.const_get(class_name).suppress_messages { Object.const_get(class_name).migrate(:up) }
  end
end
