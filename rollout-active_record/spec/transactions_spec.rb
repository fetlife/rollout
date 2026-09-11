require "spec_helper"

RSpec.describe "Rollout ActiveRecord transactions" do
  let(:backend) { active_record_backend }

  it "rolls back feature state when history persistence fails" do
    event_record_class = backend.instance_variable_get(:@event_record)
    allow(event_record_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "insert failed")

    expect do
      Rollout.new(backend: backend, logging: true).activate_percentage(:chat, 50)
    end.to raise_error(ActiveRecord::StatementInvalid)

    expect(backend.feature_exists?(:chat)).to be false
    expect(backend.feature_events(:chat)).to eq []
  end

  it "re-raises ActiveRecord::Rollback from with_feature and does not notify observers" do
    observer = double("observer")
    expect(observer).not_to receive(:update)

    rollout = Rollout.new(backend: backend)
    rollout.add_observer(observer)

    expect do
      rollout.with_feature(:chat) do |feature|
        feature.percentage = 100
        raise ActiveRecord::Rollback
      end
    end.to raise_error(ActiveRecord::Rollback)

    expect(backend.feature_exists?(:chat)).to be false
  end
end
