require "spec_helper"

RSpec.describe Rollout do
  let(:rollout) { described_class.new(adapter: RolloutMemoryBackend.new) }

  describe "#initialize" do
    it "exposes the adapter" do
      adapter = RolloutMemoryBackend.new
      rollout = described_class.new(adapter: adapter)

      expect(rollout.adapter).to eq adapter
    end
  end

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
      rollout = described_class.new(adapter: RolloutMemoryBackend.new, logging: true)

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
      rollout = described_class.new(adapter: backend, logging: true)

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

    it "does not record a history event when metadata JSON is unchanged" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(adapter: backend, logging: true)
      released_at = Time.utc(2026, 1, 1)

      rollout.set_feature_data(:chat, released_at: released_at, label: "beta")
      expect(backend.feature_events(:chat).count).to eq 1

      rollout.set_feature_data(:chat, released_at: released_at, label: :beta)
      expect(backend.feature_events(:chat).count).to eq 1
    end

    it "records canonical metadata in history events" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(adapter: backend, logging: true)
      released_at = Time.utc(2026, 1, 1)

      rollout.set_feature_data(:chat, released_at: released_at, label: :beta)
      event = backend.feature_events(:chat).last

      expect(event.data).to eq(
        before: { "data.released_at" => nil, "data.label" => nil },
        after: {
          "data.released_at" => JSON.parse({ "value" => released_at }.to_json)["value"],
          "data.label" => "beta",
        },
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

      described_class.new(adapter: backend).clear!
    end
  end

  describe "#delete" do
    it "does not delete feature history when logging is disabled" do
      backend = RolloutMemoryBackend.new
      logged = described_class.new(adapter: backend, logging: true)
      logged.activate_percentage(:chat, 25)

      described_class.new(adapter: backend).delete(:chat)

      expect(logged.exists?(:chat)).to eq false
      expect(logged.logging.events(:chat)).not_to eq []
    end

    it "deletes feature history when logging is enabled" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(adapter: backend, logging: true)
      rollout.activate_percentage(:chat, 25)
      rollout.delete(:chat)

      expect(rollout.logging.events(:chat)).to eq []
    end

    it "records a global deletion event with the current context" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(adapter: backend, logging: { global: true })
      rollout.activate_percentage(:chat, 25)

      rollout.logging.with_context(actor: "alice") { rollout.delete(:chat) }

      event = rollout.logging.global_events.last
      expect(event.name).to eq :delete
      expect(event.feature).to eq "chat"
      expect(event.data).to eq({})
      expect(event.context).to eq(actor: "alice")
      expect(event.created_at).to be_a(Time)
    end

    it "does not record a deletion event when the feature is missing or logging is suppressed" do
      backend = RolloutMemoryBackend.new
      rollout = described_class.new(adapter: backend, logging: { global: true })
      rollout.activate_percentage(:chat, 25)
      rollout.delete(:chat)
      event_count = rollout.logging.global_events.count

      rollout.delete(:chat)
      rollout.activate_percentage(:signup, 25)
      rollout.logging.without { rollout.delete(:signup) }

      expect(rollout.logging.global_events.count).to eq event_count + 1
      expect(rollout.logging.global_events.last.name).to eq :update
      expect(rollout.exists?(:signup)).to eq false
    end

    it "preserves deletion behavior for adapters without event-aware deletion" do
      backend_class = Class.new(RolloutMemoryBackend) do
        undef_method :delete_feature_with_history
      end
      backend = backend_class.new
      rollout = described_class.new(adapter: backend, logging: { global: true })
      rollout.activate_percentage(:chat, 25)

      expect { rollout.delete(:chat) }.not_to raise_error

      expect(rollout.exists?(:chat)).to eq false
      expect(rollout.logging.events(:chat)).to eq []
      expect(rollout.logging.global_events.map(&:name)).to eq [:update]
    end
  end
end
