# frozen_string_literal: true

class Rollout
  module ActiveRecord
    class Migration
      class Difference
        attr_reader :name, :kind, :field, :source, :destination

        def initialize(name:, kind:, field: nil, source: nil, destination: nil)
          @name = name
          @kind = kind
          @field = field
          @source = source
          @destination = destination
        end

        def ==(other)
          other.is_a?(self.class) &&
            name == other.name &&
            kind == other.kind &&
            field == other.field &&
            source == other.source &&
            destination == other.destination
        end
      end

      class Result
        attr_reader :status, :feature_count, :history_count, :missing_names, :unregistered_names, :differences

        def initialize(
          status:,
          feature_count: 0,
          history_count: 0,
          missing_names: [],
          unregistered_names: [],
          differences: []
        )
          @status = status
          @feature_count = feature_count
          @history_count = history_count
          @missing_names = missing_names
          @unregistered_names = unregistered_names
          @differences = differences
        end

        def success?
          status == :ok || status == :ready
        end

        def summary
          case status
          when :ready
            ready_summary("Ready to import")
          when :ok
            ready_summary("Imported")
          when :source_invalid
            "Source invalid: missing=#{missing_names.inspect} unregistered=#{unregistered_names.inspect}"
          when :destination_conflict
            "Destination already has rollout data"
          when :verification_failed
            verification_failed_summary
          else
            "Migration failed (#{status})"
          end
        end

        private

        def ready_summary(prefix)
          features = "#{feature_count} feature#{'s' unless feature_count == 1}"
          if history_count > 0
            events = "#{history_count} history event#{'s' unless history_count == 1}"
            "#{prefix} #{features} and #{events}"
          else
            "#{prefix} #{features}"
          end
        end

        def verification_failed_summary
          message = "Imported data did not match the source"
          difference = differences.first
          return message unless difference

          details = [difference.kind, difference.name, difference.field].compact.join(" ")
          "#{message}: #{details}"
        end
      end

      def initialize(source:, destination:, include_history: false)
        @source = source
        @destination = destination
        @include_history = include_history
      end

      def dry_run
        execute(write: false)
      end

      def run
        execute(write: true)
      end

      private

      def execute(write:)
        export = @source.export_features(include_history: @include_history)
        history = @include_history ? Array(export.history) : []
        counts = { feature_count: export.states.size, history_count: history.size }

        unless export.valid?
          return Result.new(
            status: :source_invalid,
            missing_names: export.missing_names,
            unregistered_names: export.unregistered_names,
            **counts,
          )
        end

        if @destination.occupied?
          return Result.new(status: :destination_conflict, **counts)
        end

        return Result.new(status: :ready, **counts) unless write

        failed = nil
        begin
          @destination.import_features(export.states, history: history) do
            differences = compare_states(export.states, imported_states) +
              compare_history(history)
            next if differences.empty?

            failed = Result.new(status: :verification_failed, differences: differences, **counts)
            raise ::ActiveRecord::Rollback
          end
        rescue ::Rollout::Adapters::ActiveRecord::DestinationNotEmpty
          return Result.new(status: :destination_conflict, **counts)
        end

        failed || Result.new(status: :ok, **counts)
      end

      def imported_states
        @destination.fetch_features(@destination.feature_names)
      end

      def compare_states(source_states, destination_states)
        source_by_name = source_states.to_h { |state| [state.name, state] }
        destination_by_name = destination_states.to_h { |state| [state.name, state] }
        names = (source_by_name.keys | destination_by_name.keys).sort
        differences = []

        names.each do |name|
          source = source_by_name[name]
          destination = destination_by_name[name]

          if source.nil?
            differences << Difference.new(name: name, kind: :extra)
            next
          end

          if destination.nil?
            differences << Difference.new(name: name, kind: :missing)
            next
          end

          next if source == destination

          %i[percentage users groups data].each do |field|
            source_value = source.public_send(field)
            destination_value = destination.public_send(field)
            next if source_value == destination_value

            differences << Difference.new(
              name: name,
              kind: :changed,
              field: field,
              source: source_value,
              destination: destination_value,
            )
          end
        end

        differences
      end

      def compare_history(source_entries)
        source_by_feature = Hash.new { |hash, name| hash[name] = [] }
        source_global = []

        source_entries.each do |entry|
          event = entry.event
          source_by_feature[event.feature.to_s] << event if entry.feature_visible
          source_global << event if entry.global_visible
        end

        names = (source_by_feature.keys | history_feature_names).sort
        differences = []

        names.each do |name|
          differences.concat(
            event_differences(
              name,
              source_by_feature[name],
              @destination.feature_events(name),
            ),
          )
        end
        differences.concat(event_differences("_global_", source_global, @destination.global_events))
        differences
      end

      def history_feature_names
        @destination.global_events.map { |event| event.feature.to_s } |
          @destination.feature_names.map(&:to_s)
      end

      def event_differences(name, source_events, destination_events)
        source_signatures = source_events.map { |event| event_signature(event) }
        destination_signatures = destination_events.map { |event| event_signature(event) }
        return [] if source_signatures == destination_signatures

        [Difference.new(
          name: name,
          kind: :history,
          field: :events,
          source: source_signatures,
          destination: destination_signatures,
        )]
      end

      def event_signature(event)
        {
          feature: event.feature.to_s,
          name: event.name.to_s,
          data: event.data,
          context: event.context,
          timestamp: (event.created_at.to_r * 1_000_000).round,
        }
      end
    end
  end
end
