# frozen_string_literal: true

class Rollout
  class FeatureState
    attr_reader :name, :percentage, :users, :groups, :data

    def initialize(name:, percentage:, users: [], groups: [], data: {})
      @name = name.to_s
      @percentage = percentage.to_f
      @users = Array(users).map(&:to_s)
      @groups = Array(groups).map(&:to_s)
      @data = stringify_keys(data)
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

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_s] = dup_value(value)
      end
    end

    def dup_value(value)
      case value
      when Hash
        stringify_keys(value)
      when Array
        value.map { |item| dup_value(item) }
      when String
        value.dup
      else
        value
      end
    end
  end
end
