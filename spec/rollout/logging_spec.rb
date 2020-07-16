require 'spec_helper'

RSpec.describe 'Rollout::Logging' do
  let(:rollout) { Rollout.new(Redis.current, logging: logging) }
  let(:logging) { true }
  let(:feature) { :foo }

  it 'logs changes' do
    expect(rollout.logging.last_event(feature)).to be_nil

    rollout.activate_percentage(feature, 50)

    expect(rollout.logging.updated_at(feature)).to_not be_nil

    first_event = rollout.logging.last_event(feature)

    expect(first_event.name).to eq 'update'
    expect(first_event.data).to eq(before: { percentage: 0 }, after: { percentage: 50 })

    rollout.activate_percentage(feature, 75)

    second_event = rollout.logging.last_event(feature)

    expect(second_event.name).to eq 'update'
    expect(second_event.data).to eq(before: { percentage: 50 }, after: { percentage: 75 })

    rollout.activate_group(feature, :hipsters)

    third_event = rollout.logging.last_event(feature)

    expect(third_event.name).to eq 'update'
    expect(third_event.data).to eq(before: { groups: [] }, after: { groups: ['hipsters'] })

    expect(rollout.logging.events(feature)).to eq [first_event, second_event, third_event]
  end

  context 'logging data changes' do
    it 'logs changes' do
      expect(rollout.logging.last_event(feature)).to be_nil

      rollout.set_feature_data(feature, description: "foo")

      event = rollout.logging.last_event(feature)

      expect(event).not_to be_nil
      expect(event.name).to eq 'update'
      expect(event.data).to eq(before: { "data.description": nil }, after: { "data.description": "foo" })
    end
  end

  context 'no logging' do
    let(:logging) { nil }

    it 'doesnt even respond to logging' do
      expect(rollout).not_to respond_to :logging
    end
  end

  context 'history truncation' do
    let(:logging) { { history_length: 1 } }

    it 'logs changes' do
      expect(rollout.logging.last_event(feature)).to be_nil

      rollout.activate_percentage(feature, 25)

      first_event = rollout.logging.last_event(feature)

      expect(first_event.name).to eq 'update'
      expect(first_event.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })

      rollout.activate_percentage(feature, 30)

      second_event = rollout.logging.last_event(feature)

      expect(second_event.name).to eq 'update'
      expect(second_event.data).to eq(before: { percentage: 25 }, after: { percentage: 30 })

      expect(rollout.logging.events(feature)).to eq [second_event]
    end
  end

  context 'with context' do
    let(:current_user) { double(nickname: 'lester') }

    it 'adds context to the event' do
      rollout.logging.with_context(actor: current_user.nickname) do
        rollout.activate_percentage(feature, 25)
      end

      event = rollout.logging.last_event(feature)

      expect(event.name).to eq 'update'
      expect(event.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })
      expect(event.context).to eq(actor: current_user.nickname)
    end
  end

  context 'global logs' do
    let(:logging) { { global: true } }
    let(:feature_foo) { 'foo' }
    let(:feature_bar) { 'bar' }

    it 'logs changes' do
      expect(rollout.logging.last_event(feature_foo)).to be_nil

      rollout.activate_percentage(feature_foo, 25)

      event_foo = rollout.logging.last_event(feature_foo)

      expect(event_foo.feature).to eq feature_foo
      expect(event_foo.name).to eq 'update'
      expect(event_foo.data).to eq(before: { percentage: 0 }, after: { percentage: 25 })

      expect(rollout.logging.events(feature_foo)).to eq [event_foo]

      rollout.activate_percentage(feature_bar, 30)

      event_bar = rollout.logging.last_event(feature_bar)

      expect(event_bar.feature).to eq feature_bar
      expect(event_bar.name).to eq 'update'
      expect(event_bar.data).to eq(before: { percentage: 0 }, after: { percentage: 30 })

      expect(rollout.logging.events(feature_bar)).to eq [event_bar]

      expect(rollout.logging.global_events).to eq [event_foo, event_bar]
    end
  end

  context 'no logging for block' do
    it 'doesnt log' do
      rollout.logging.without do
        rollout.activate_percentage(feature, 25)
      end

      event = rollout.logging.last_event(feature)

      expect(event).to be_nil
    end
  end
end

