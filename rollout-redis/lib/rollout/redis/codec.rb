# frozen_string_literal: true

require 'json'
require 'rollout/feature_state'

class Rollout
  module Redis
    class Codec
      def self.decode(name, payload)
        if payload.nil? || payload.empty?
          return FeatureState.new(
            name: name,
            percentage: 0,
            users: [],
            groups: [],
            data: {},
          )
        end

        raw_percentage, raw_users, raw_groups, raw_data = payload.split('|', 4)
        data = raw_data.nil? || raw_data.strip.empty? ? {} : JSON.parse(raw_data)

        FeatureState.new(
          name: name,
          percentage: raw_percentage.to_f,
          users: (raw_users || '').split(','),
          groups: (raw_groups || '').split(','),
          data: data,
        )
      end

      def self.encode(feature_state)
        "#{feature_state.percentage}|#{feature_state.users.join(',')}|#{feature_state.groups.join(',')}|#{feature_state.data.to_json}"
      end
    end
  end
end
