class Rollout
  module Logging
    def self.extended(rollout)
      options = rollout.options[:logging]
      options = options.is_a?(Hash) ? options.dup : {}
      options[:storage] ||= rollout.storage

      logger = Logger.new(**options)

      rollout.add_observer(logger, :log)
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
      def initialize(storage: nil, history_length: 50, global: false)
        @history_length = history_length
        @storage = storage
        @global = global
      end

      def updated_at(feature_name)
        storage_key = events_storage_key(feature_name)
        _, score = @storage.zrange(storage_key, 0, 0, with_scores: true).first
        Time.at(-score.to_f / 1_000_000) if score
      end

      def last_event(feature_name)
        storage_key = events_storage_key(feature_name)
        value = @storage.zrange(storage_key, 0, 0, with_scores: true).first
        Event.from_raw(*value) if value
      end

      def events(feature_name)
        storage_key = events_storage_key(feature_name)
        @storage
          .zrange(storage_key, 0, -1, with_scores: true)
          .map { |v| Event.from_raw(*v) }
          .reverse
      end

      def global_events
        @storage
          .zrange(global_events_storage_key, 0, -1, with_scores: true)
          .map { |v| Event.from_raw(*v) }
          .reverse
      end

      def delete(feature_name)
        storage_key = events_storage_key(feature_name)
        @storage.del(storage_key)
      end

      def update(before, after)
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

        event = Event.new(
          feature: after.name,
          name: :update,
          data: change,
          context: current_context,
          created_at: Time.now,
        )

        storage_key = events_storage_key(after.name)

        @storage.zadd(storage_key, -event.timestamp, event.serialize)
        @storage.zremrangebyrank(storage_key, @history_length, -1)

        if @global
          @storage.zadd(global_events_storage_key, -event.timestamp, event.serialize)
          @storage.zremrangebyrank(global_events_storage_key, @history_length, -1)
        end
      end

      def log(event, *args)
        return unless logging_enabled?

        unless respond_to?(event)
          raise ArgumentError, "Invalid log event: #{event}"
        end

        expected_arity = method(event).arity
        unless args.count == expected_arity
          raise(
            ArgumentError,
            "Invalid number of arguments for event '#{event}': expected #{expected_arity} but got #{args.count}",
          )
        end

        public_send(event, *args)
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

      private

      def global_events_storage_key
        "feature:_global_:logging:events"
      end

      def events_storage_key(feature_name)
        "feature:#{feature_name}:logging:events"
      end

      def current_timestamp
        (Time.now.to_f * 1_000_000).to_i
      end
    end
  end
end
