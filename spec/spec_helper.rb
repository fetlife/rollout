# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

require 'bundler/setup'
require 'rollout'

class RolloutMemoryBackend
  def initialize
    @features = {}
    @events = Hash.new { |hash, key| hash[key] = [] }
  end

  def fetch_feature(name)
    @features[name.to_s] || Rollout::FeatureState.new(name: name, percentage: 0)
  end

  def fetch_features(names)
    names.map { |name| fetch_feature(name) }
  end

  def feature_names
    @features.keys
  end

  def feature_exists?(name)
    @features.key?(name.to_s)
  end

  def save_feature(state)
    @features[state.name] = state
  end

  def delete_feature(name)
    @features.delete(name.to_s)
  end

  def clear_features
  end

  def mutate_feature(name)
    mutation = yield fetch_feature(name)
    save_feature(mutation.fetch(:state))
    event = mutation[:event]
    @events[name.to_s] << event if event
    mutation
  end

  def feature_events(name, limit: nil)
    limited_events(@events[name.to_s], limit)
  end

  def global_events(limit: nil)
    limited_events([], limit)
  end

  def feature_updated_at(_name)
  end

  def delete_feature_events(name)
    @events.delete(name.to_s)
  end

  private

  def limited_events(events, limit)
    return events if limit.nil?
    raise ArgumentError, "limit must be an Integer" unless limit.is_a?(Integer)
    raise ArgumentError, "limit must be >= 0" if limit < 0

    events.last(limit)
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
