require "spec_helper"
require_relative "../../spec/support/backend_contract"

RSpec.describe Rollout::Adapters::ActiveRecord do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { active_record_adapter }
  end

  it_behaves_like "a rollout feature backend" do
    let(:backend) { active_record_adapter(cache_ttl: 10) }
  end
end

