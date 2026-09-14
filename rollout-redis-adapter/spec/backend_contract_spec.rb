require "spec_helper"
require_relative "../../spec/support/backend_contract"

RSpec.describe Rollout::Adapters::RedisAdapter do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { redis_adapter }
  end

  it "keeps Rollout::Redis::Backend as an alias" do
    expect(Rollout::Redis::Backend).to eq described_class
    expect(redis_backend).to be_a(described_class)
  end
end
