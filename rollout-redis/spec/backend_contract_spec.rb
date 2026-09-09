require "spec_helper"
require File.expand_path("../../../spec/support/backend_contract", __dir__)

RSpec.describe Rollout::Redis::Backend do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { redis_backend }
  end
end
