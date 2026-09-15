require "spec_helper"

RSpec.describe "Rollout ActiveRecord feature identity" do
  let(:adapter) { active_record_adapter }
  let(:rollout) { Rollout.new(adapter: adapter, logging: true) }

  it "treats feature names as case-sensitive for reads, writes, history, and deletion" do
    rollout.activate("Chat")
    rollout.activate_percentage("chat", 25)

    expect(rollout.get("Chat").percentage).to eq 100.0
    expect(rollout.get("chat").percentage).to eq 25.0
    expect(rollout.multi_get("Chat", "chat").map(&:percentage)).to eq [100.0, 25.0]
    expect(rollout.features).to contain_exactly(:Chat, :chat)

    expect(rollout.logging.events("Chat").map { |event| event.data[:after][:percentage] }).to eq [100]
    expect(rollout.logging.events("chat").map { |event| event.data[:after][:percentage] }).to eq [25]

    rollout.delete("Chat")

    expect(rollout.exists?("Chat")).to eq false
    expect(rollout.exists?("chat")).to eq true
    expect(rollout.get("chat").percentage).to eq 25.0
    expect(rollout.logging.events("Chat")).to eq []
    expect(rollout.logging.events("chat")).not_to eq []
  end

  it "installs case-sensitive MySQL name columns from Schema.create" do
    skip "MySQL-specific collation" unless ADAPTER == "mysql2"

    name = ActiveRecord::Base.connection.columns("rollout_features").find { |column| column.name == "name" }
    feature_name = ActiveRecord::Base.connection.columns("rollout_events").find { |column| column.name == "feature_name" }

    expect(name.collation).to eq "utf8mb4_bin"
    expect(feature_name.collation).to eq "utf8mb4_bin"
  end

  it "keeps the generated migration in sync with MySQL name collation" do
    template = File.read(
      File.expand_path(
        "../lib/generators/rollout/active_record/templates/create_rollout_tables.rb.tt",
        __dir__,
      ),
    )

    expect(template).to include('name_options[:collation] = "utf8mb4_bin"')
    expect(template).to include("connection.adapter_name.match?(/mysql/i)")
    expect(template).to include("t.string :name, **name_options")
    expect(template).to include("t.string :feature_name, **name_options")
  end
end
