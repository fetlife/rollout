# frozen_string_literal: true

require 'rollout/feature_state'

class Rollout
  class Feature
    attr_accessor :groups, :users, :percentage, :data
    attr_reader :name, :options

    def initialize(state:, rollout:, options: {})
      @rollout = rollout
      @options = options
      @name = state.name
      assign_state(state)
    end

    def to_feature_state
      FeatureState.new(
        name: @name,
        percentage: @percentage,
        users: Array(@users),
        groups: Array(@groups),
        data: @data,
      )
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
      assign_state(
        FeatureState.new(
          name: @name,
          percentage: 0,
          users: [],
          groups: [],
          data: {},
        ),
      )
    end

    def active?(user)
      if user
        id = user_id(user)
        user_in_percentage?(id) ||
          user_in_active_users?(id) ||
          user_in_active_group?(user)
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
        users: @users,
        data: @data,
      }
    end

    def deep_clone
      c = self.clone
      c.instance_variable_set('@rollout', nil)
      c = Marshal.load(Marshal.dump(c))
      c.instance_variable_set('@rollout', @rollout)
      c
    end

    private

    def assign_state(state)
      state = state.deep_clone

      @name = state.name
      @percentage = state.percentage
      @users = users_from_array(state.users)
      @groups = groups_from_array(state.groups)
      @data = state.data
    end

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

    def user_in_active_group?(user)
      @groups.any? do |g|
        @rollout.active_in_group?(g, user)
      end
    end

    def users_from_array(users)
      users = Array(users).map(&:to_s)
      if @options[:use_sets]
        users.to_set
      else
        users
      end
    end

    def groups_from_array(groups)
      groups = Array(groups).map(&:to_sym)
      if @options[:use_sets]
        groups.to_set
      else
        groups
      end
    end
  end
end
