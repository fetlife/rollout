require "spec_helper"
require_relative "../../spec/support/history_contract"

RSpec.describe "Rollout Redis history" do
  it_behaves_like "a rollout history backend" do
    let(:backend) { redis_adapter }
  end

  let(:rollout) { Rollout.new(adapter: redis_adapter, logging: logging) }
  let(:logging) { true }
  let(:feature) { :foo }

  it "logs changes" do
    expect(rollout.logging.last_event(feature)).to be_nil

    rollout.activate_percentage(feature, 50)

    expect(rollout.logging.updated_at(feature)).to_not be_nil

    first_event = rollout.logging.last_event(feature)

    expect(first_event.name).to eq "update"
    expect(first_event.data).to eq(before: { percentage: 0 }, after: { percentage: 50 })

    rollout.activate_percentage(feature, 75)

    second_event = rollout.logging.last_event(feature)

    expect(second_event.name).to eq "update"
    expect(second_event.data).to eq(before: { percentage: 50 }, after: { percentage: 75 })

    rollout.activate_group(feature, :hipsters)

    third_event = rollout.logging.last_event(feature)

    expect(third_event.name).to eq "update"
    expect(third_event.data).to eq(before: { groups: [] }, after: { groups: ["hipsters"] })

    expect(rollout.logging.events(feature)).to eq [first_event, second_event, third_event]
  end

  it "logs data changes" do
    rollout.set_feature_data(feature, description: "foo")

    event = rollout.logging.last_event(feature)

    expect(event.name).to eq "update"
    expect(event.data).to eq(before: { "data.description": nil }, after: { "data.description": "foo" })
  end

  it "does not log metadata that round-trips to the same JSON" do
    released_at = Time.utc(2026, 1, 1)
    rollout.set_feature_data(feature, released_at: released_at, label: "beta")

    expect do
      rollout.set_feature_data(feature, released_at: released_at, label: :beta)
    end.not_to change { rollout.logging.events(feature).count }
  end

  it "logs canonical metadata values" do
    released_at = Time.utc(2026, 1, 1)
    rollout.set_feature_data(feature, released_at: released_at, label: :beta)

    expect(rollout.logging.last_event(feature).data).to eq(
      before: { "data.released_at": nil, "data.label": nil },
      after: {
        "data.released_at": JSON.parse({ "value" => released_at }.to_json)["value"],
        "data.label": "beta",
      },
    )
  end

  it "adds context to the event" do
    rollout.logging.with_context(actor: "lester") do
      rollout.activate_percentage(feature, 25)
    end

    expect(rollout.logging.last_event(feature).context).to eq(actor: "lester")
  end

  it "does not log inside without" do
    rollout.logging.without do
      rollout.activate_percentage(feature, 25)
    end

    expect(rollout.logging.last_event(feature)).to be_nil
  end

  it "does not write a history event when nothing changes" do
    rollout.activate_percentage(feature, 25)

    expect do
      rollout.activate_percentage(feature, 25)
    end.not_to change { rollout.logging.events(feature).count }
  end

  it "records one event for a with_feature block" do
    rollout.logging.with_context(actor: "alice") do
      rollout.with_feature(feature) do |current|
        current.percentage = 25.0
        current.groups = [:employees]
        current.users = ["123"]
        current.data.update(description: "New navigation")
      end
    end

    events = rollout.logging.events(feature)
    expect(events.count).to eq 1
    expect(events.first.context).to eq(actor: "alice")
  end

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
