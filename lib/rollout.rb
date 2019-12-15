# frozen_string_literal: true

require 'rollout/version'
require 'zlib'
require 'set'
require 'json'

class Rollout
  RAND_BASE = (2**32 - 1) / 100.0
  PERCENTAGE_INDEX_SCALE = 10

  class Feature
    attr_accessor :groups, :users, :percentage, :data
    attr_reader :name, :options

    def initialize(name, string = nil, opts = {})
      @options = opts
      @name    = name

      if string
        raw_percentage, raw_users, raw_groups, raw_data = string.split('|', 4)
        @percentage = raw_percentage.to_f
        @users = users_from_string(raw_users)
        @groups = groups_from_string(raw_groups)
        @data = raw_data.nil? || raw_data.strip.empty? ? {} : JSON.parse(raw_data)
      else
        clear
      end
    end

    def serialize
      "#{@percentage}|#{@users.to_a.join(',')}|#{@groups.to_a.join(',')}|#{serialize_data}"
    end

    def add_user(user)
      id = user_id(user)
      @users << id unless @users.include?(id)
    end

    def remove_user(user)
      @users.delete(user_id(user))
    end

    def add_group(group)
      @groups << group.to_sym unless @groups.include?(group.to_sym)
    end

    def remove_group(group)
      @groups.delete(group.to_sym)
    end

    def clear
      @groups = groups_from_string('')
      @users = users_from_string('')
      @percentage = 0
      @data = {}
    end

    def active?(rollout, user)
      if user
        id = user_id(user)
        user_in_percentage?(id) ||
          user_in_active_users?(id) ||
          user_in_active_group?(user, rollout)
      else
        @percentage == 100
      end
    end

    def user_in_active_users?(user)
      @users.include?(user_id(user))
    end

    def to_hash
      {
        percentage: @percentage,
        groups: @groups,
        users: @users
      }
    end

    private

    def user_id(user)
      if user.is_a?(Integer) || user.is_a?(String)
        user.to_s
      else
        user.send(id_user_by).to_s
      end
    end

    def id_user_by
      @options[:id_user_by] || :id
    end

    def user_in_percentage?(user)
      Zlib.crc32(user_id_for_percentage(user)) < RAND_BASE * @percentage
    end

    def user_id_for_percentage(user)
      if @options[:randomize_percentage]
        user_id(user).to_s + @name.to_s
      else
        user_id(user)
      end
    end

    def user_in_active_group?(user, rollout)
      @groups.any? do |g|
        rollout.active_in_group?(g, user)
      end
    end

    def serialize_data
      return '' unless @data.is_a? Hash

      @data.to_json
    end

    def users_from_string(raw_users)
      users = (raw_users || '').split(',').map(&:to_s)
      if @options[:use_sets]
        users.to_set
      else
        users
      end
    end

    def groups_from_string(raw_groups)
      groups = (raw_groups || '').split(',').map(&:to_sym)
      if @options[:use_sets]
        groups.to_set
      else
        groups
      end
    end
  end

  def initialize(storage, opts = {})
    @storage = storage
    @options = opts
    @groups  = { all: ->(_user) { true } }
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
    feature.active?(self, user)
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
    Feature.new(feature, string, @options)
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
    @storage.mget(*feature_keys).map.with_index { |string, index| Feature.new(features[index], string, @options) }
  end

  def features
    (@storage.get(features_key) || '').split(',').map(&:to_sym)
  end

  def feature_states(user = nil)
    multi_get(*features).each_with_object({}) do |f, hash|
      hash[f.name] = f.active?(self, user)
    end
  end

  def active_features(user = nil)
    multi_get(*features).select do |f|
      f.active?(self, user)
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
    @storage.exists(key(feature))
  end

  private

  def key(name)
    "feature:#{name}"
  end

  def field_index(name)
    "rollout:indices:#{name}"
  end

  def features_key
    'feature:__features__'
  end

  def with_feature(feature)
    f = get(feature)
    yield(f)
    save(f)
  end

  def percentage_scale(percentage)
    (percentage / PERCENTAGE_INDEX_SCALE).to_i
  end

  def reindex_percentage(origin_feature, changed_feature)
    return if origin_feature.percentage == 0 && changed_feature.percentage == 0 

    origin_percentage = percentage_scale(origin_feature.percentage)
    changed_percentage = percentage_scale(changed_feature.percentage)
    return if origin_percentage == changed_percentage 

    @storage.sadd(field_index("percentage:#{changed_percentage}"), changed_feature.name) unless changed_feature.percentage == 0
    @storage.srem(field_index("percentage:#{origin_percentage}"), changed_feature.name) unless origin_feature.percentage == 0
  end

  def reindex_field(origin_feature, changed_feature, name) 
    activated_keys = changed_feature.send(name) - origin_feature.send(name)
    deactivated_keys = origin_feature.send(name) - changed_feature.send(name) 

    activated_keys.each do |key|
      @storage.sadd(field_index("#{name}:#{key}"), changed_feature.name)
    end
    deactivated_keys.each do |key|
      @storage.srem(field_index("#{name}:#{key}"), changed_feature.name)
    end
  end

  def save(feature)
    origin_feature  = get(feature.name)
    origin_features = features

    @storage.multi do
      reindex_field(origin_feature, feature, "users")
      reindex_field(origin_feature, feature, "groups")
      reindex_percentage(origin_feature, feature)
      @storage.set(key(feature.name), feature.serialize)
      @storage.set(features_key, (origin_features | [feature.name.to_sym]).join(','))
    end
  end
end
