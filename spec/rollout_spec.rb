require "spec_helper"

RSpec.describe Rollout do
  let(:rollout) { described_class.new(backend: RolloutMemoryBackend.new) }

  describe "#get" do
    it "preserves the requested name type" do
      expect(rollout.get("chat").name).to eq "chat"
      expect(rollout.get(:chat).name).to eq :chat
    end
  end

  describe "#multi_get" do
    it "preserves the requested name types" do
      expect(rollout.multi_get("chat", :beta).map(&:name)).to eq ["chat", :beta]
    end
  end

  describe "#with_feature" do
    it "preserves the requested name type" do
      feature = rollout.with_feature("chat") do |current|
        current.percentage = 25
      end

      expect(feature.name).to eq "chat"
      expect(rollout.get("chat").name).to eq "chat"
    end

    it "persists a mutation when nested without resets the thread flag" do
      rollout = described_class.new(backend: RolloutMemoryBackend.new, logging: true)

      rollout.logging.without do
        rollout.with_feature(:chat) do |feature|
          feature.percentage = 25
          rollout.logging.without {}
        end
      end

      expect(rollout.get(:chat).percentage).to eq 25.0
    end

    it "does not notify an observer registered during a mutation" do
      observer = double("observer")
      expect(observer).not_to receive(:update)

      rollout.with_feature(:chat) do |feature|
        feature.percentage = 25
        rollout.add_observer(observer)
      end
    end

    it "notifies observers registered before a mutation" do
      observer = double("observer")
      expect(observer).to receive(:update) do |_event, before, after|
        expect(before.name).to eq :chat
        expect(before.percentage).to eq 0
        expect(after.percentage).to eq 25
      end

      rollout.add_observer(observer)
      rollout.activate_percentage(:chat, 25)
    end
  end
end
