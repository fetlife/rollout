require "spec_helper"

RSpec.describe "Rollout::Logging" do
  def build_feature(percentage: 0, groups: [], users: [], data: {})
    Rollout::Feature.new(
      state: Rollout::FeatureState.new(
        name: :foo,
        percentage: percentage,
        users: users,
        groups: groups,
        data: data,
      ),
      rollout: Object.new,
      options: {},
    )
  end

  let(:logger) { Rollout::Logging::Logger.new(backend: Object.new) }

  it "does not respond to logging unless enabled" do
    rollout = Rollout.new(backend: Object.new)

    expect(rollout).not_to respond_to :logging
  end

  it "builds an event for percentage changes" do
    event = logger.event_for(build_feature, build_feature(percentage: 50))

    expect(event.name).to eq :update
    expect(event.data).to eq(before: { percentage: 0 }, after: { percentage: 50 })
  end

  it "builds an event for metadata changes" do
    event = logger.event_for(
      build_feature,
      build_feature(data: { "description" => "foo" }),
    )

    expect(event.data).to eq(before: { "data.description" => nil }, after: { "data.description" => "foo" })
  end

  it "does not build an event when nothing changes" do
    feature = build_feature(percentage: 25)

    expect(logger.event_for(feature, feature)).to be_nil
  end

  it "adds context to the event" do
    event = nil
    logger.with_context(actor: "lester") do
      event = logger.event_for(build_feature, build_feature(percentage: 25))
    end

    expect(event.context).to eq(actor: "lester")
  end

  it "does not build an event when logging is disabled" do
    event = logger.without do
      logger.event_for(build_feature, build_feature(percentage: 25))
    end

    expect(event).to be_nil
  end

  it "restores nested without state" do
    nested_enabled = nil
    outer_enabled = nil

    logger.without do
      logger.without {}
      nested_enabled = logger.logging_enabled?
    end
    outer_enabled = logger.logging_enabled?

    expect(nested_enabled).to eq false
    expect(outer_enabled).to eq true
  end

  it "forwards a history limit to the backend" do
    backend = double("backend")
    logger = Rollout::Logging::Logger.new(backend: backend)
    events = [Object.new]

    expect(backend).to receive(:feature_events).with(:chat, limit: 2).and_return(events)
    expect(logger.events(:chat, limit: 2)).to eq events
  end

  it "requests one event for last_event" do
    backend = double("backend")
    logger = Rollout::Logging::Logger.new(backend: backend)
    event = Object.new

    expect(backend).to receive(:feature_events).with(:chat, limit: 1).and_return([event])
    expect(logger.last_event(:chat)).to eq event
  end

  it "forwards a global history limit to the backend" do
    backend = double("backend")
    logger = Rollout::Logging::Logger.new(backend: backend)
    events = [Object.new]

    expect(backend).to receive(:global_events).with(limit: 2).and_return(events)
    expect(logger.global_events(limit: 2)).to eq events
  end

  it "delegates history deletion" do
    backend = double("backend")
    logger = Rollout::Logging::Logger.new(backend: backend)

    expect(backend).to receive(:delete_feature_events).with(:chat)
    logger.delete(:chat)
  end
end
