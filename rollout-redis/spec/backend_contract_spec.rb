require "spec_helper"
require_relative "../../spec/support/backend_contract"

RSpec.describe Rollout::Redis::Backend do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { redis_backend }
  end
end
