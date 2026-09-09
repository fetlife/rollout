# frozen_string_literal: true

require 'rollout/logging'
require 'rollout/redis/codec'

class Rollout
  module Redis
    class Backend
      FEATURES_KEY = 'feature:__features__'

      def initialize(client)
        @client = client
      end

      def fetch_feature(name)
        Codec.decode(name, @client.get(key(name)))
      end

      def fetch_features(names)
        return [] if names.empty?

        payloads = @client.mget(*names.map { |name| key(name) })
        names.zip(payloads).map { |name, payload| Codec.decode(name, payload) }
      end

      def feature_names
        (@client.get(FEATURES_KEY) || '').split(',')
      end

      def feature_exists?(name)
        if @client.respond_to?(:exists?)
          @client.exists?(key(name))
        else
          @client.exists(key(name))
        end
      end

      def save_feature(state)
        @client.set(key(state.name), Codec.encode(state))
        names = feature_names.map(&:to_s) | [state.name.to_s]
        @client.set(FEATURES_KEY, names.join(','))
      end

      def delete_feature(name)
        names = feature_names
        names.delete(name.to_s)
        @client.set(FEATURES_KEY, names.join(','))
        @client.del(key(name))
      end

      def clear_features
        @client.del(FEATURES_KEY)
      end

      def mutate_feature(name)
        mutation = yield fetch_feature(name)
        save_feature(mutation.fetch(:state))
        event = mutation[:event]
        if event
          record_event(
            event,
            history_length: mutation.fetch(:history_length),
            global: mutation[:global],
          )
        end
        mutation
      end

      def record_event(event, history_length:, global: false)
        storage_key = events_key(event.feature)
        @client.zadd(storage_key, -event.timestamp, event.serialize)
        @client.zremrangebyrank(storage_key, history_length, -1)

        return unless global

        @client.zadd(global_events_key, -event.timestamp, event.serialize)
        @client.zremrangebyrank(global_events_key, history_length, -1)
      end

      def feature_events(name, limit: nil)
        events_from(events_key(name), limit: limit)
      end

      def global_events(limit: nil)
        events_from(global_events_key, limit: limit)
      end

      def feature_updated_at(name)
        _, score = @client.zrange(events_key(name), 0, 0, with_scores: true).first
        Time.at(-score.to_f / 1_000_000) if score
      end

      def delete_feature_events(name)
        @client.del(events_key(name))
      end

      private

      def key(name)
        "feature:#{name}"
      end

      def events_key(name)
        "feature:#{name}:logging:events"
      end

      def global_events_key
        'feature:_global_:logging:events'
      end

      def events_from(storage_key, limit: nil)
        stop = event_range_stop(limit)
        return [] if stop == :empty

        @client
          .zrange(storage_key, 0, stop, with_scores: true)
          .map { |value| Codec.decode_event(*value) }
          .reverse
      end

      def event_range_stop(limit)
        return -1 if limit.nil?
        raise ArgumentError, "limit must be an Integer" unless limit.is_a?(Integer)
        raise ArgumentError, "limit must be >= 0" if limit < 0
        return :empty if limit.zero?

        limit - 1
      end
    end
  end
end
