require "spec_helper"
require_relative "../../spec/support/history_contract"

RSpec.describe "Rollout ActiveRecord history" do
  it_behaves_like "a rollout history backend" do
    let(:backend) { active_record_backend }
  end

  let(:backend) { active_record_backend }
  let(:rollout) { Rollout.new(backend: backend, logging: logging) }
  let(:logging) { { history_length: 2, global: true } }
  let(:feature) { :foo }

  it "stores one event row with independent feature and global visibility" do
    rollout.activate_percentage(feature, 25)

    expect(ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM rollout_events").to_i).to eq 1

    rollout.logging.delete(feature)

    expect(rollout.logging.events(feature)).to eq []
    expect(rollout.logging.global_events.map(&:feature)).to eq %w[foo]
  end

  it "deletes events that are no longer visible to feature or global history" do
    rollout.activate_percentage(feature, 25)
    rollout.activate_percentage(feature, 50)
    rollout.activate_percentage(feature, 75)

    expect(ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM rollout_events").to_i).to eq 2
  end
end
