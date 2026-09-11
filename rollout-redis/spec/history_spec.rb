require "spec_helper"
require_relative "../../spec/support/history_contract"

RSpec.describe "Rollout Redis history" do
  it_behaves_like "a rollout history backend" do
    let(:backend) { redis_backend }
  end

  let(:rollout) { Rollout.new(backend: redis_backend, logging: logging) }
  let(:logging) { true }
  let(:feature) { :foo }

  it "removes the features registry after clear!" do
    rollout.activate(:chat)
    rollout.clear!

    expect($redis.get("feature:__features__")).to be_nil
  end

  it "removes an already empty features registry" do
    $redis.set("feature:__features__", "")
    rollout.clear!

    expect($redis.get("feature:__features__")).to be_nil
  end

  it "does not decode older events when reading last_event" do
    rollout.activate_percentage(feature, 25)
    $redis.zadd("feature:#{feature}:logging:events", -1, "not-json")

    expect(rollout.logging.last_event(feature).data[:after][:percentage]).to eq 25
  end

  context "persisted history keys" do
    let(:logging) { { history_length: 2, global: true } }

    it "writes truncated per-feature and global sorted sets" do
      rollout.activate_percentage(feature, 25)
      rollout.activate_percentage(feature, 50)
      rollout.activate_percentage(feature, 75)

      expect($redis.zcard("feature:#{feature}:logging:events")).to eq 2
      expect($redis.zcard("feature:_global_:logging:events")).to eq 2
    end
  end
end
