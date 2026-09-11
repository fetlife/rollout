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

    it "does not persist when the mutation block raises" do
      expect {
        rollout.with_feature(:chat) { raise "nope" }
      }.to raise_error("nope")

      expect(rollout.exists?(:chat)).to eq false
    end

    it "records a history event only when logging is enabled and state changes" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(backend: backend, logging: true)

      rollout.activate_percentage(:chat, 25)
      expect(backend.feature_events(:chat).count).to eq 1

      rollout.activate_percentage(:chat, 25)
      expect(backend.feature_events(:chat).count).to eq 1
    end

    it "canonicalizes metadata assigned during a mutation" do
      released_at = Time.utc(2026, 1, 1)

      rollout.with_feature(:chat) do |feature|
        feature.data["released_at"] = released_at
        feature.data["label"] = :beta
      end

      expect(rollout.get(:chat).data).to eq(
        "released_at" => JSON.parse({ "value" => released_at }.to_json)["value"],
        "label" => "beta",
      )
    end
  end

  describe "#set_feature_data" do
    def json_value(value)
      JSON.parse({ "value" => value }.to_json)["value"]
    end

    it "canonicalizes JSON-serializable metadata" do
      released_at = Time.utc(2026, 1, 1)

      rollout.set_feature_data(:chat, released_at: released_at, label: :beta)

      expect(rollout.get(:chat).data).to eq(
        "released_at" => json_value(released_at),
        "label" => "beta",
      )
    end

    it "does not persist metadata that cannot be serialized as JSON" do
      rollout.set_feature_data(:chat, description: "foo")
      cyclic = {}
      cyclic["self"] = cyclic

      expect {
        rollout.set_feature_data(:chat, cyclic)
      }.to raise_error(JSON::JSONError)

      expect(rollout.get(:chat).data).to eq("description" => "foo")
    end
  end

  describe "#clear!" do
    it "asks the backend to clear remaining registry state" do
      backend = RolloutMemoryBackend.new
      expect(backend).to receive(:clear_features).and_call_original

      described_class.new(backend: backend).clear!
    end
  end

  describe "#delete" do
    it "does not delete feature history when logging is disabled" do
      backend = RolloutMemoryBackend.new
      logged = described_class.new(backend: backend, logging: true)
      logged.activate_percentage(:chat, 25)

      described_class.new(backend: backend).delete(:chat)

      expect(logged.exists?(:chat)).to eq false
      expect(logged.logging.events(:chat)).not_to eq []
    end

    it "deletes feature history when logging is enabled" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(backend: backend, logging: true)
      rollout.activate_percentage(:chat, 25)
      rollout.delete(:chat)

      expect(rollout.logging.events(:chat)).to eq []
    end
  end
end
