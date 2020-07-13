require "spec_helper"

RSpec.describe "Rollout::Logging" do
  let(:rollout) { Rollout.new(Redis.current, logging: true) }
  let(:feature) { :foo }

  it "logs changes" do
    expect(rollout.logging.last_event(feature)).to be_nil

    rollout.activate_percentage(feature, 50)

    expect(rollout.logging.updated_at(feature)).to_not be_nil

    first_event = rollout.logging.last_event(feature)

    expect(first_event.name).to eq "update"
    expect(first_event.data).to eq({ before: { percentage: 0 }, after: { percentage: 50 } })

    rollout.activate_percentage(feature, 75)

    second_event = rollout.logging.last_event(feature)

    expect(second_event.name).to eq "update"
    expect(second_event.data).to eq({ before: { percentage: 50 }, after: { percentage: 75 } })

    rollout.activate_group(feature, :hipsters)

    third_event = rollout.logging.last_event(feature)

    expect(third_event.name).to eq "update"
    expect(third_event.data).to eq({ before: { groups: [] }, after: { groups: ["hipsters"] } })

    expect(rollout.logging.events(feature)).to eq [first_event, second_event, third_event]
  end
end

