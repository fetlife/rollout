# frozen_string_literal: true

class Rollout
  module Redis
    class FeatureExport
      class HistoryEntry
        attr_reader :event, :feature_visible, :global_visible

        def initialize(event:, feature_visible:, global_visible:)
          @event = event
          @feature_visible = feature_visible
          @global_visible = global_visible
        end
      end

      attr_reader :states, :missing_names, :unregistered_names, :history

      def initialize(states:, missing_names:, unregistered_names:, history: [])
        @states = states
        @missing_names = missing_names
        @unregistered_names = unregistered_names
        @history = history
      end

      def valid?
        missing_names.empty? && unregistered_names.empty?
      end
    end
  end
end
