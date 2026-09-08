# frozen_string_literal: true

class Rollout
  module Logging
    def self.extended(rollout)
      options = rollout.options[:logging]
      options = options.is_a?(Hash) ? options.dup : {}

      logger = Logger.new(backend: rollout.backend, **options)
      rollout.define_singleton_method(:logging) do
        logger
      end
    end

    class Event
      attr_reader :feature, :name, :data, :context, :created_at

      def self.from_raw(value, score)
        hash = JSON.parse(value, symbolize_names: true)

        new(**hash.merge(created_at: Time.at(-score.to_f / 1_000_000)))
      end

      def initialize(feature: nil, name:, data:, context: {}, created_at:)
        @feature = feature
        @name = name
        @data = data
        @context = context
        @created_at = created_at
      end

      def timestamp
        (@created_at.to_f * 1_000_000).to_i
      end

      def serialize
        JSON.dump(
          feature: @feature,
          name: @name,
          data: @data,
          context: @context,
          created_at: @created_at,
        )
      end

      def ==(other)
        feature == other.feature \
          && name == other.name \
          && data == other.data \
          && created_at == other.created_at
      end
    end

    class Logger
      attr_reader :history_length, :global

      def initialize(backend:, history_length: 50, global: false)
        @backend = backend
        @history_length = history_length
        @global = global
      end

      def updated_at(feature_name)
        @backend.feature_updated_at(feature_name)
      end

      def last_event(feature_name)
        events(feature_name).last
      end

      def events(feature_name)
        @backend.feature_events(feature_name)
      end

      def global_events
        @backend.global_events
      end

      def delete(feature_name)
        @backend.delete_feature_events(feature_name)
      end

      def event_for(before, after)
        return unless logging_enabled?

        before_hash = before.to_hash
        before_hash.delete(:data).each do |k, v|
          before_hash["data.#{k}"] = v
        end
        after_hash = after.to_hash
        after_hash.delete(:data).each do |k, v|
          after_hash["data.#{k}"] = v
        end

        keys = before_hash.keys | after_hash.keys
        change = { before: {}, after: {} }
        changed_count = 0

        keys.each do |key|
          next if before_hash[key] == after_hash[key]

          change[:before][key] = before_hash[key]
          change[:after][key] = after_hash[key]

          changed_count += 1
        end

        return if changed_count == 0

        Event.new(
          feature: after.name,
          name: :update,
          data: change,
          context: current_context,
          created_at: Time.now,
        )
      end

      CONTEXT_THREAD_KEY = :rollout_logging_context
      WITHOUT_THREAD_KEY = :rollout_logging_disabled

      def with_context(context)
        raise ArgumentError, "context must be a Hash" unless context.is_a?(Hash)
        raise ArgumentError, "block is required" unless block_given?

        Thread.current[CONTEXT_THREAD_KEY] = context
        yield
      ensure
        Thread.current[CONTEXT_THREAD_KEY] = nil
      end

      def current_context
        Thread.current[CONTEXT_THREAD_KEY] || {}
      end

      def without
        Thread.current[WITHOUT_THREAD_KEY] = true
        yield
      ensure
        Thread.current[WITHOUT_THREAD_KEY] = nil
      end

      def logging_enabled?
        !Thread.current[WITHOUT_THREAD_KEY]
      end
    end
  end
end
