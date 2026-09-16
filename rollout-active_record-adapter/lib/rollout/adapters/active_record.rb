# frozen_string_literal: true

require 'active_record'
require 'rollout'
require 'rollout/active_record/schema'
require 'rollout/active_record/codec'
require 'rollout/active_record/migration'
require 'rollout/active_record/feature_cache'

class Rollout
  module Adapters
    class ActiveRecord
      class DestinationNotEmpty < ArgumentError
      end

      def initialize(
        base_record_class: ::ActiveRecord::Base,
        features_table_name: "rollout_features",
        events_table_name: "rollout_events",
        cache_ttl: nil
      )
        @base_record_class = base_record_class
        @features_table_name = features_table_name
        @events_table_name = events_table_name
        @feature_record = build_record_class(@features_table_name)
        @event_record = build_record_class(@events_table_name)
        @feature_cache = cache_ttl.nil? ? nil : ::Rollout::ActiveRecord::FeatureCache.new(ttl: cache_ttl)
      end

      def fetch_feature(name)
        if feature_cache_enabled?
          cached = @feature_cache.read(name)
          return cached if cached
        end

        state = ::Rollout::ActiveRecord::Codec.feature_state(name, find_feature(name))
        @feature_cache.write(state) if feature_cache_enabled?
        state
      end

      def fetch_features(names)
        return [] if names.empty?
        return fetch_features_uncached(names) unless feature_cache_enabled?

        hits = {}
        misses = []
        names.map(&:to_s).uniq.each do |name|
          cached = @feature_cache.read(name)
          if cached
            hits[name] = cached
          else
            misses << name
          end
        end

        unless misses.empty?
          fetch_features_uncached(misses).each do |state|
            @feature_cache.write(state)
            hits[state.name] = state
          end
        end

        names.map { |name| hits[name.to_s].deep_clone }
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
          invalidate_features_after_commit(state.name)
        end
      end

      def delete_feature(name)
        @feature_record.where(name: name.to_s).delete_all
        invalidate_features_after_commit(name)
      end

      def clear_features
        @feature_record.delete_all
        invalidate_all_features_after_commit
      end

      def occupied?
        @feature_record.uncached do
          @feature_record.exists? || @event_record.exists?
        end
      end

      def import_features(states, history: [])
        raise ArgumentError, "states must be an Array" unless states.is_a?(Array)
        raise ArgumentError, "history must be an Array" unless history.is_a?(Array)

        states.each do |state|
          next if state.is_a?(::Rollout::FeatureState)

          raise ArgumentError, "states must contain FeatureState objects"
        end

        @feature_record.transaction(requires_new: true) do
          if occupied?
            raise DestinationNotEmpty, "destination already has rollout data"
          end

          states.each { |state| persist_state(nil, state) }
          history.each { |entry| insert_imported_event(entry) }
          yield if block_given?
          invalidate_all_features_after_commit
        end
      end

      def mutate_feature(name)
        rollback_error = nil
        mutation = nil

        @feature_record.transaction(requires_new: true) do
          record = locked_feature(name)
          begin
            mutation = yield ::Rollout::ActiveRecord::Codec.feature_state(name, record)
          rescue ::ActiveRecord::Rollback => error
            rollback_error = error
            raise
          end
          persist_mutation(record, mutation)
          invalidate_features_after_commit(name)
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

      def fetch_features_uncached(names)
        return [] if names.empty?

        records = @feature_record.where(name: names.map(&:to_s).uniq).index_by(&:name)
        names.map { |name| ::Rollout::ActiveRecord::Codec.feature_state(name, records[name.to_s]) }
      end

      def feature_cache_enabled?
        @feature_cache && !@feature_record.connection.transaction_open?
      end

      def invalidate_features_after_commit(*names)
        return unless @feature_cache

        after_outer_commit { @feature_cache.delete(*names) }
      end

      def invalidate_all_features_after_commit
        return unless @feature_cache

        after_outer_commit { @feature_cache.clear }
      end

      def after_outer_commit(&block)
        txn = root_joinable_transaction
        if txn
          txn.add_record(AfterCommitCallback.new(&block))
        else
          block.call
        end
      end

      def root_joinable_transaction
        txn = @feature_record.connection.current_transaction
        return nil unless txn.joinable?

        while txn.respond_to?(:parent) && txn.parent&.joinable?
          txn = txn.parent
        end
        txn
      end

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
          users: ::Rollout::ActiveRecord::Codec.dump(state.users),
          groups: ::Rollout::ActiveRecord::Codec.dump(state.groups),
          data: ::Rollout::ActiveRecord::Codec.dump(state.data),
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
          data: ::Rollout::ActiveRecord::Codec.dump(event.data),
          context: ::Rollout::ActiveRecord::Codec.dump(event.context),
          feature_visible: true,
          global_visible: global ? true : false,
          occurred_at: event.created_at,
        )
      end

      def insert_imported_event(entry)
        event = entry.event
        @event_record.create!(
          feature_name: event.feature.to_s,
          event_name: event.name.to_s,
          data: ::Rollout::ActiveRecord::Codec.dump(event.data),
          context: ::Rollout::ActiveRecord::Codec.dump(event.context),
          feature_visible: !!entry.feature_visible,
          global_visible: !!entry.global_visible,
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
        unless limit.nil?
          raise ArgumentError, "limit must be an Integer" unless limit.is_a?(Integer)
          raise ArgumentError, "limit must be >= 0" if limit < 0
          return [] if limit.zero?
        end

        records = scope.order(occurred_at: :desc, id: :desc)
        records = records.limit(limit) unless limit.nil?
        records.to_a.reverse.map { |record| ::Rollout::ActiveRecord::Codec.event(record) }
      end

      def validate_history_length!(history_length)
        unless history_length.is_a?(Integer) && history_length >= 0
          raise ArgumentError, "history_length must be an Integer >= 0"
        end
      end

      class AfterCommitCallback
        def initialize(&block)
          @block = block
        end

        def committed!(*)
          @block.call
        end

        def before_committed!
        end

        def rolledback!(*)
        end

        def trigger_transactional_callbacks?
          true
        end
      end
    end
  end
end
