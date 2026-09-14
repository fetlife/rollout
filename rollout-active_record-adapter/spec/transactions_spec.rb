require "spec_helper"

RSpec.describe "Rollout ActiveRecord transactions" do
  let(:adapter) { active_record_adapter }

  it "rolls back feature state when history persistence fails" do
    event_record_class = adapter.instance_variable_get(:@event_record)
    allow(event_record_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "insert failed")

    expect do
      Rollout.new(adapter: adapter, logging: true).activate_percentage(:chat, 50)
    end.to raise_error(ActiveRecord::StatementInvalid)

    expect(adapter.feature_exists?(:chat)).to be false
    expect(adapter.feature_events(:chat)).to eq []
  end

  it "re-raises ActiveRecord::Rollback from with_feature and does not notify observers" do
    observer = double("observer")
    expect(observer).not_to receive(:update)

    rollout = Rollout.new(adapter: adapter)
    rollout.add_observer(observer)

    expect do
      rollout.with_feature(:chat) do |feature|
        feature.percentage = 100
        raise ActiveRecord::Rollback
      end
    end.to raise_error(ActiveRecord::Rollback)

    expect(adapter.feature_exists?(:chat)).to be false
  end
end
