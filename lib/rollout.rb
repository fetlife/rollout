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

  attr_reader :options, :storage

  def initialize(storage, opts = {})
    @storage = storage
    @options = opts
    @groups  = { all: ->(_user) { true } }

    extend(Logging) if opts[:logging]
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
    features = (@storage.get(features_key) || '').split(',')
    features.delete(feature.to_s)
    @storage.set(features_key, features.join(','))
    @storage.del(key(feature))

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
    string = @storage.get(key(feature))
    Feature.new(feature, state: string, rollout: self, options: @options)
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

    feature_keys = features.map { |feature| key(feature) }

    @storage
      .mget(*feature_keys)
      .map
      .with_index do |string, index|
        Feature.new(features[index], state: string, rollout: self, options: @options)
      end
  end

  def features
    (@storage.get(features_key) || '').split(',').map(&:to_sym)
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
      @storage.del(key(feature))
    end

    @storage.del(features_key)
  end

  def exists?(feature)
    # since redis-rb v4.2, `#exists?` replaces `#exists` which now returns integer value instead of boolean
    # https://github.com/redis/redis-rb/pull/918
    if @storage.respond_to?(:exists?)
      @storage.exists?(key(feature))
    else
      @storage.exists(key(feature))
    end
  end

  def with_feature(feature)
    f = get(feature)

    if count_observers > 0
      before = f.deep_clone
      yield(f)
      save(f)
      changed
      notify_observers(:update, before, f)
    else
      yield(f)
      save(f)
    end
  end

  private

  def key(name)
    "feature:#{name}"
  end

  def features_key
    'feature:__features__'
  end

  def save(feature)
    @storage.set(key(feature.name), feature.serialize)
    @storage.set(features_key, (features | [feature.name.to_sym]).join(','))
  end
end
