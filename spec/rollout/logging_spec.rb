require "spec_helper"

RSpec.describe "Rollout::Logging" do
  let(:rollout) { Rollout.new(Redis.current, logging: logging) }
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

  context "no logging" do
    let(:logging) { nil }

    it "doesn't even respond to logging" do
      expect(rollout).not_to respond_to :logging
    end
  end

  context "history truncation" do
    let(:logging) { { history_length: 1 } }

    it "logs changes" do
      expect(rollout.logging.last_event(feature)).to be_nil

      rollout.activate_percentage(feature, 25)

      first_event = rollout.logging.last_event(feature)

      expect(first_event.name).to eq "update"
      expect(first_event.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })

      rollout.activate_percentage(feature, 30)

      second_event = rollout.logging.last_event(feature)

      expect(second_event.name).to eq "update"
      expect(second_event.data).to eq(before: { percentage: 25 }, after: { percentage: 30 })

      expect(rollout.logging.events(feature)).to eq [second_event]
    end
  end

  context 'with context' do
    let(:current_user) { double(nickname: 'lester') }

    it "adds context to the event" do
      rollout.logging.with_context(actor: current_user.nickname) do
        rollout.activate_percentage(feature, 25)
      end

      event = rollout.logging.last_event(feature)

      expect(event.name).to eq "update"
      expect(event.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })
      expect(event.context).to eq(actor: current_user.nickname)
    end
  end
end

