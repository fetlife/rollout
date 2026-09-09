require "spec_helper"

RSpec.describe Rollout::Redis::Codec do
  it "decodes a missing payload as an empty feature" do
    state = described_class.decode(:chat, nil)

    expect(state).to eq(
      Rollout::FeatureState.new(
        name: :chat,
        percentage: 0,
        users: [],
        groups: [],
        data: {},
      ),
    )
  end

  it "decodes an empty payload as an empty feature" do
    state = described_class.decode(:chat, "")

    expect(state.percentage).to eq 0.0
    expect(state.users).to eq []
    expect(state.groups).to eq []
    expect(state.data).to eq({})
  end

  it "decodes a stored payload" do
    state = described_class.decode(
      :chat,
      '10.5|7,8|greeters|{"description":"legacy"}',
    )

    expect(state.name).to eq "chat"
    expect(state.percentage).to eq 10.5
    expect(state.users).to eq %w[7 8]
    expect(state.groups).to eq %w[greeters]
    expect(state.data).to eq("description" => "legacy")
  end

  it "decodes payloads with no metadata" do
    expect(described_class.decode(:chat, "0||").data).to eq({})
    expect(described_class.decode(:chat, "|||   ").data).to eq({})
  end

  it "encodes feature state using the current redis format" do
    state = Rollout::FeatureState.new(
      name: :chat,
      percentage: 20,
      users: ["42"],
      groups: ["employees"],
      data: { "description" => "foo" },
    )

    expect(described_class.encode(state)).to eq('20.0|42|employees|{"description":"foo"}')
  end

  it "round-trips a payload" do
    payload = '10.5|7,8|greeters|{"description":"legacy"}'
    state = described_class.decode(:chat, payload)

    expect(described_class.encode(state)).to eq payload
  end

  describe ".decode_event" do
    it "decodes a persisted history member using the sorted-set score" do
      created_at = Time.at(1_735_689_600)
      value = JSON.dump(
        feature: "chat",
        name: "update",
        data: { before: { percentage: 0 }, after: { percentage: 25 } },
        context: { actor: "lester" },
        created_at: Time.utc(2000, 1, 1),
      )

      event = described_class.decode_event(value, -(created_at.to_f * 1_000_000))

      expect(event.feature).to eq "chat"
      expect(event.name).to eq "update"
      expect(event.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })
      expect(event.context).to eq(actor: "lester")
      expect(event.created_at.to_i).to eq created_at.to_i
    end
  end
end
