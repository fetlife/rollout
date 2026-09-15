require "spec_helper"

RSpec.describe "rollout-redis-adapter" do
  it "can be required by gem name" do
    expect { require "rollout-redis-adapter" }.not_to raise_error
    expect(Rollout::Adapters::Redis).to be_a(Class)
  end
end
