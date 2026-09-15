# frozen_string_literal: true

require 'redis'
require 'rollout'
require 'rollout/logging'
require 'rollout/redis/codec'
require 'rollout/redis/feature_export'

class Rollout
  module Adapters
    class Redis
      FEATURES_KEY = 'feature:__features__'

      def initialize(client)
        @client = client
      end

      def fetch_feature(name)
        ::Rollout::Redis::Codec.decode(name, @client.get(key(name)))
      end

      def fetch_features(names)
        return [] if names.empty?

        payloads = @client.mget(*names.map { |name| key(name) })
        names.zip(payloads).map { |name, payload| ::Rollout::Redis::Codec.decode(name, payload) }
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
        @client.set(key(state.name), ::Rollout::Redis::Codec.encode(state))
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

      def export_features(include_history: false)
        registered = feature_names.map(&:to_s).reject { |name| name.empty? }.uniq
        stored = stored_feature_names
        missing_names = (registered - stored).sort
        unregistered_names = (stored - registered).sort
        present = registered - missing_names

        ::Rollout::Redis::FeatureExport.new(
          states: fetch_features(present),
          missing_names: missing_names,
          unregistered_names: unregistered_names,
          history: include_history ? export_history : [],
        )
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

      def stored_feature_names
        names = []
        @client.scan_each(match: 'feature:*') do |raw_key|
          key = raw_key.to_s
          next if key == FEATURES_KEY
          next if key.end_with?(':logging:events')

          names << key.sub(/\Afeature:/, '')
        end
        names.uniq
      end

      def export_history
        feature_members = []
        global_members = {}

        @client.scan_each(match: 'feature:*:logging:events') do |raw_key|
          key = raw_key.to_s
          if key == global_events_key
            zrange_pairs(key).each do |member, score|
              global_members[member] = score
            end
          else
            name = history_feature_name(key)
            next if name.nil? || name == '_global_'

            zrange_pairs(key).each do |member, score|
              feature_members << [member, score]
            end
          end
        end

        seen = {}
        rows = []
        feature_members.each do |member, score|
          seen[member] = true
          rows << [member, score, true, !global_members[member].nil?]
        end
        global_members.each do |member, score|
          next if seen[member]

          rows << [member, score, false, true]
        end

        sort_history_rows(rows).map do |member, score, feature_visible, global_visible|
          history_entry(member, score, feature_visible, global_visible)
        end
      end

      def history_feature_name(key)
        return nil unless key.start_with?('feature:') && key.end_with?(':logging:events')

        key.sub(/\Afeature:/, '').sub(/:logging:events\z/, '')
      end

      def zrange_pairs(key)
        pairs = @client.zrange(key, 0, -1, with_scores: true)
        return [] if pairs.nil? || pairs.empty?
        return pairs if pairs.first.is_a?(Array)

        pairs.each_slice(2).to_a
      end

      def history_entry(member, score, feature_visible, global_visible)
        ::Rollout::Redis::FeatureExport::HistoryEntry.new(
          event: ::Rollout::Redis::Codec.decode_event(member, score),
          feature_visible: feature_visible,
          global_visible: global_visible,
        )
      end

      def sort_history_rows(rows)
        rows.sort_by { |member, score, _feature_visible, _global_visible| [score, member] }.reverse
      end

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
          .map { |value| ::Rollout::Redis::Codec.decode_event(*value) }
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
