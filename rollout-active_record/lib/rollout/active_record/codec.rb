# frozen_string_literal: true

require 'json'
require 'rollout/feature_state'
require 'rollout/logging'

class Rollout
  module ActiveRecord
    class Codec
      def self.dump(value)
        JSON.generate(value)
      end

      def self.load_array(payload)
        JSON.parse(payload)
      end

      def self.load_hash(payload)
        JSON.parse(payload)
      end

      def self.load_event_hash(payload)
        JSON.parse(payload, symbolize_names: true)
      end

      def self.feature_state(name, record)
        if record.nil?
          return FeatureState.new(
            name: name,
            percentage: 0.0,
            users: [],
            groups: [],
            data: {},
          )
        end

        FeatureState.new(
          name: name,
          percentage: record.percentage,
          users: load_array(record.users),
          groups: load_array(record.groups),
          data: load_hash(record.data),
        )
      end

      def self.event(record)
        Logging::Event.new(
          feature: record.feature_name,
          name: record.event_name,
          data: load_event_hash(record.data),
          context: load_event_hash(record.context),
          created_at: record.occurred_at,
        )
      end
    end
  end
end
