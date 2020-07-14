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
      attr_reader :name, :data, :context, :created_at

      def self.from_raw(value, score)
        hash = JSON.parse(value, symbolize_names: true)
        name = hash.fetch(:name)
        data = hash.fetch(:data)
        context = hash[:context]
        created_at = Time.at(-score.to_f / 1_000_000)

        new(name: name, data: data, context: context, created_at: created_at)
      end

      def initialize(name:, data:, context:, created_at:)
        @name = name
        @data = data
        @context = context
        @created_at = created_at
      end

      def timestamp
        (@created_at.to_f * 1_000_000).to_i
      end

      def serialize
        JSON.dump(name: @name, data: @data, context: @context)
      end

      def ==(other)
        name == other.name && data == other.data && created_at == other.created_at
      end
    end

    class Logger
      def initialize(storage: nil, history_length: 50)
        @history_length = history_length
        @storage = storage
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

      def update(before, after)
        before_hash = before.to_hash
        after_hash = after.to_hash

        keys = before_hash.keys & after_hash.keys
        change = { before: {}, after: {} }

        keys.each do |key|
          next if before_hash[key] == after_hash[key]

          change[:before][key] = before_hash[key]
          change[:after][key] = after_hash[key]
        end
        event = Event.new(name: :update, data: change, context: current_context, created_at: Time.now)

        storage_key = events_storage_key(after.name)

        @storage.zadd(storage_key, -event.timestamp, event.serialize)
        @storage.zremrangebyrank(storage_key, @history_length, -1)
      end

      def log(event, *args)
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

      def with_context(context)
        raise ArgumentError, "block is required" unless block_given?
        Thread.current[:rollout_logging_context] = context
        yield
      ensure
        Thread.current[:rollout_logging_context] = nil
      end

      def current_context
        Thread.current[:rollout_logging_context]
      end

      private

      def events_storage_key(feature_name)
        "feature:#{feature_name}:logging:events"
      end

      def current_timestamp
        (Time.now.to_f * 1_000_000).to_i
      end
    end
  end
end
