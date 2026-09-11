require "spec_helper"
require_relative "../../spec/support/rollout_backend_integration"

RSpec.describe "Rollout Redis integration" do
  it_behaves_like "a rollout backend integration" do
    let(:backend) { redis_backend }
  end

  describe "persisted redis format" do
    let(:rollout) { Rollout.new(backend: redis_backend) }

    it "writes the current feature payload and registry keys" do
      rollout.activate_percentage(:chat, 20)
      rollout.activate_user(:chat, 42)
      rollout.activate_group(:chat, :employees)
      rollout.set_feature_data(:chat, description: "foo")

      expect($redis.get("feature:chat")).to eq('20.0|42|employees|{"description":"foo"}')
      expect($redis.get("feature:__features__")).to eq("chat")
    end

    it "reads an existing payload without rewriting it" do
      $redis.set("feature:chat", '10.5|7,8|greeters|{"description":"legacy"}')
      $redis.set("feature:__features__", "chat")

      feature = rollout.get(:chat)

      expect(feature.percentage).to eq 10.5
      expect(feature.users).to eq %w[7 8]
      expect(feature.groups).to eq [:greeters]
      expect(feature.data).to eq("description" => "legacy")
      expect($redis.get("feature:chat")).to eq('10.5|7,8|greeters|{"description":"legacy"}')
    end
  end

  describe "mutation semantics" do
    let(:rollout) { Rollout.new(backend: redis_backend) }

    it "writes the deactivated redis payload" do
      rollout.activate_user(:chat, 42)
      rollout.activate_group(:chat, :employees)
      rollout.activate_percentage(:chat, 50)
      rollout.set_feature_data(:chat, description: "foo")

      rollout.deactivate(:chat)

      expect($redis.get("feature:chat")).to eq("0.0|||{}")
    end
  end
end
