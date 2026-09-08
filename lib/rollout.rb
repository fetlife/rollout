# frozen_string_literal: true

require 'rollout/feature'
require 'rollout/logging'
require 'rollout/version'
require 'zlib'
require 'set'
require 'json'
require 'observer'

class Rollout
  include Observable

  RAND_BASE = (2**32 - 1) / 100.0

  attr_reader :options, :backend

  def initialize(backend:, **options)
    @backend = backend
    @options = options
    @groups  = { all: ->(_user) { true } }

    extend(Logging) if options[:logging]
  end

  def groups
    @groups.keys
  end

  def activate(feature)
    with_feature(feature) do |f|
      f.percentage = 100
    end
  end

  def deactivate(feature)
    with_feature(feature, &:clear)
  end

  def delete(feature)
    @backend.delete_feature(feature)

    if respond_to?(:logging)
      logging.delete(feature)
    end
  end

  def set(feature, desired_state)
    with_feature(feature) do |f|
      if desired_state
        f.percentage = 100
      else
        f.clear
      end
    end
  end

  def activate_group(feature, group)
    with_feature(feature) do |f|
      f.add_group(group)
    end
  end

  def deactivate_group(feature, group)
    with_feature(feature) do |f|
      f.remove_group(group)
    end
  end

  def activate_user(feature, user)
    with_feature(feature) do |f|
      f.add_user(user)
    end
  end

  def deactivate_user(feature, user)
    with_feature(feature) do |f|
      f.remove_user(user)
    end
  end

  def activate_users(feature, users)
    with_feature(feature) do |f|
      users.each { |user| f.add_user(user) }
    end
  end

  def deactivate_users(feature, users)
    with_feature(feature) do |f|
      users.each { |user| f.remove_user(user) }
    end
  end

  def set_users(feature, users)
    with_feature(feature) do |f|
      f.users = []
      users.each { |user| f.add_user(user) }
    end
  end

  def define_group(group, &block)
    @groups[group.to_sym] = block
  end

  def active?(feature, user = nil)
    feature = get(feature)
    feature.active?(user)
  end

  def user_in_active_users?(feature, user = nil)
    feature = get(feature)
    feature.user_in_active_users?(user)
  end

  def inactive?(feature, user = nil)
    !active?(feature, user)
  end

  def activate_percentage(feature, percentage)
    with_feature(feature) do |f|
      f.percentage = percentage
    end
  end

  def deactivate_percentage(feature)
    with_feature(feature) do |f|
      f.percentage = 0
    end
  end

  def active_in_group?(group, user)
    f = @groups[group.to_sym]
    f&.call(user)
  end

  def get(feature)
    Feature.new(
      state: @backend.fetch_feature(feature),
      rollout: self,
      options: @options,
      name: feature,
    )
  end

  def set_feature_data(feature, data)
    with_feature(feature) do |f|
      f.data.merge!(data) if data.is_a? Hash
    end
  end

  def clear_feature_data(feature)
    with_feature(feature) do |f|
      f.data = {}
    end
  end

  def multi_get(*features)
    return [] if features.empty?

    @backend.fetch_features(features).zip(features).map do |state, name|
      Feature.new(state: state, rollout: self, options: @options, name: name)
    end
  end

  def features
    @backend.feature_names.map(&:to_sym)
  end

  def feature_states(user = nil)
    multi_get(*features).each_with_object({}) do |f, hash|
      hash[f.name] = f.active?(user)
    end
  end

  def active_features(user = nil)
    multi_get(*features).select do |f|
      f.active?(user)
    end.map(&:name)
  end

  def clear!
    features.each do |feature|
      with_feature(feature, &:clear)
      @backend.delete_feature(feature)
    end
  end

  def exists?(feature)
    @backend.feature_exists?(feature)
  end

  def with_feature(feature)
    mutated = nil
    before = nil
    snapshot = count_observers > 0 || logging_capture?

    @backend.mutate_feature(feature) do |current_state|
      mutated = Feature.new(state: current_state, rollout: self, options: @options)
      before = mutated.deep_clone if snapshot
      yield mutated

      event = logging_capture? ? logging.event_for(before, mutated) : nil
      result = { state: mutated.to_feature_state, event: event }
      if event
        result[:history_length] = logging.history_length
        result[:global] = logging.global
      end
      result
    end

    if count_observers > 0
      changed
      notify_observers(:update, before, mutated)
    end

    mutated
  end

  private

  def logging_capture?
    respond_to?(:logging) && logging.logging_enabled?
  end
end
