require "spec_helper"
require_relative "../../spec/support/backend_contract"

RSpec.describe Rollout::Adapters::Redis do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { redis_adapter }
  end
end
