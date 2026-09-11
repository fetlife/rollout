# frozen_string_literal: true

require 'rollout/active_record/codec'

class Rollout
  module ActiveRecord
    class Backend
      def initialize(
        base_record_class: ::ActiveRecord::Base,
        features_table_name: "rollout_features",
        events_table_name: "rollout_events"
      )
        @base_record_class = base_record_class
        @features_table_name = features_table_name
        @events_table_name = events_table_name
        @feature_record = build_record_class(@features_table_name)
        @event_record = build_record_class(@events_table_name)
      end

      def fetch_feature(name)
        Codec.feature_state(name, find_feature(name))
      end

      def fetch_features(names)
        return [] if names.empty?

        records = @feature_record.where(name: names.map(&:to_s).uniq).index_by(&:name)
        names.map { |name| Codec.feature_state(name, records[name.to_s]) }
      end

      def feature_names
        @feature_record.order(:id).pluck(:name)
      end

      def feature_exists?(name)
        @feature_record.exists?(name: name.to_s)
      end

      def save_feature(state)
        @feature_record.transaction do
          persist_state(locked_feature(state.name), state)
        end
      end

      def delete_feature(name)
        @feature_record.where(name: name.to_s).delete_all
      end

      def clear_features
        @feature_record.delete_all
      end

      def mutate_feature(name)
        rollback_error = nil
        mutation = nil

        @feature_record.transaction do
          record = locked_feature(name)
          begin
            mutation = yield Codec.feature_state(name, record)
          rescue ::ActiveRecord::Rollback => error
            rollback_error = error
            raise
          end
          persist_mutation(record, mutation)
        end

        raise rollback_error if rollback_error

        mutation
      end

      def feature_events(name, limit: nil)
        events_from(
          @event_record.where(feature_name: name.to_s, feature_visible: true),
          limit: limit,
        )
      end

      def global_events(limit: nil)
        events_from(
          @event_record.where(global_visible: true),
          limit: limit,
        )
      end

      def feature_updated_at(name)
        @event_record
          .where(feature_name: name.to_s, feature_visible: true)
          .order(occurred_at: :desc, id: :desc)
          .limit(1)
          .pick(:occurred_at)
      end

      def delete_feature_events(name)
        @feature_record.transaction do
          @event_record.where(feature_name: name.to_s, feature_visible: true)
            .update_all(feature_visible: false)
          delete_hidden_events
        end
      end

      private

      def build_record_class(table_name)
        Class.new(@base_record_class) do
          self.table_name = table_name
          self.inheritance_column = :_type_disabled
        end
      end

      def find_feature(name)
        @feature_record.find_by(name: name.to_s)
      end

      def locked_feature(name)
        @feature_record.uncached do
          @feature_record.lock.find_by(name: name.to_s)
        end
      end

      def persist_mutation(record, mutation)
        persist_state(record, mutation.fetch(:state))
        event = mutation[:event]
        return unless event

        history_length = mutation.fetch(:history_length)
        validate_history_length!(history_length)
        insert_event(event, global: mutation[:global])
        prune_feature_events(event.feature, history_length)
        prune_global_events(history_length) if mutation[:global]
      end

      def persist_state(record, state)
        attributes = {
          percentage: state.percentage,
          users: Codec.dump(state.users),
          groups: Codec.dump(state.groups),
          data: Codec.dump(state.data),
        }

        if record
          record.update!(attributes)
        else
          @feature_record.create!(attributes.merge(name: state.name.to_s))
        end
      end

      def insert_event(event, global:)
        @event_record.create!(
          feature_name: event.feature.to_s,
          event_name: event.name.to_s,
          data: Codec.dump(event.data),
          context: Codec.dump(event.context),
          feature_visible: true,
          global_visible: global ? true : false,
          occurred_at: event.created_at,
        )
      end

      def prune_feature_events(name, history_length)
        hide_excess(
          @event_record.where(feature_name: name.to_s, feature_visible: true),
          :feature_visible,
          history_length,
        )
        delete_hidden_events
      end

      def prune_global_events(history_length)
        hide_excess(
          @event_record.where(global_visible: true),
          :global_visible,
          history_length,
        )
        delete_hidden_events
      end

      def hide_excess(scope, column, history_length)
        if history_length == 0
          scope.update_all(column => false)
          return
        end

        keep_ids = scope.order(occurred_at: :desc, id: :desc).limit(history_length).pluck(:id)
        return if keep_ids.empty?

        scope.where.not(id: keep_ids).update_all(column => false)
      end

      def delete_hidden_events
        @event_record.where(feature_visible: false, global_visible: false).delete_all
      end

      def events_from(scope, limit:)
        stop = event_range_stop(limit)
        return [] if stop == :empty

        records = scope.order(occurred_at: :desc, id: :desc)
        records = records.limit(limit) unless limit.nil?
        records.to_a.reverse.map { |record| Codec.event(record) }
      end

      def event_range_stop(limit)
        return -1 if limit.nil?
        raise ArgumentError, "limit must be an Integer" unless limit.is_a?(Integer)
        raise ArgumentError, "limit must be >= 0" if limit < 0
        return :empty if limit.zero?

        limit - 1
      end

      def validate_history_length!(history_length)
        unless history_length.is_a?(Integer) && history_length >= 0
          raise ArgumentError, "history_length must be an Integer >= 0"
        end
      end
    end
  end
end
