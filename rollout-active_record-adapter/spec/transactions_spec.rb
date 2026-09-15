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

  it "rolls back a failed new-feature mutation independently of an outer transaction" do
    ActiveRecord::Base.transaction do
      begin
        Rollout.new(adapter: adapter, logging: { history_length: -1 }).activate_percentage(:chat, 50)
      rescue ArgumentError
      end
    end

    expect(adapter.feature_exists?(:chat)).to be false
    expect(adapter.feature_events(:chat)).to eq []
  end

  it "rolls back a failed existing-feature mutation independently of an outer transaction" do
    Rollout.new(adapter: adapter, logging: true).activate_percentage(:chat, 10)

    ActiveRecord::Base.transaction do
      begin
        Rollout.new(adapter: adapter, logging: { history_length: -1 }).activate_percentage(:chat, 50)
      rescue ArgumentError
      end
    end

    expect(adapter.fetch_feature(:chat).percentage).to eq 10.0
    expect(adapter.feature_events(:chat).map { |event| event.data[:after][:percentage] }).to eq [10]
  end

  it "rolls back a successful mutation when the outer transaction rolls back" do
    ActiveRecord::Base.transaction do
      Rollout.new(adapter: adapter, logging: true).activate_percentage(:chat, 50)
      raise ActiveRecord::Rollback
    end

    expect(adapter.feature_exists?(:chat)).to be false
    expect(adapter.feature_events(:chat)).to eq []
  end
end
