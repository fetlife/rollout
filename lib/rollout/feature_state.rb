# frozen_string_literal: true

require 'json'

class Rollout
  class FeatureState
    attr_reader :name, :percentage, :users, :groups, :data

    def initialize(name:, percentage:, users: [], groups: [], data: {})
      raise ArgumentError, "data must be a Hash" unless data.is_a?(Hash)

      @name = name.to_s.dup
      @percentage = percentage.to_f
      @users = Array(users).map { |user| user.to_s.dup }
      @groups = Array(groups).map { |group| group.to_s.dup }
      @data = canonicalize_data(data)
    end

    def ==(other)
      other.is_a?(FeatureState) &&
        name == other.name &&
        percentage == other.percentage &&
        users == other.users &&
        groups == other.groups &&
        data == other.data
    end

    def deep_clone
      self.class.new(
        name: name,
        percentage: percentage,
        users: users,
        groups: groups,
        data: data,
      )
    end

    private

    def canonicalize_data(data)
      JSON.parse(data.to_json)
    end
  end
end
