# frozen_string_literal: true

class Rollout
  module CLI
    module Response
      def self.timestamp?(value)
        return false unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/)
        Date.iso8601(value[0, 10])
        DateTime.rfc3339(value)
        Time.iso8601(value)
        true
      rescue ArgumentError
        false
      end

      def self.feature?(value)
        value.is_a?(Hash) && value['name'].is_a?(String) &&
          value['percentage'].is_a?(Numeric) && (0..100).cover?(value['percentage']) &&
          value['data'].is_a?(Hash) &&
          %w[groups users].all? { |key| value[key].is_a?(Array) && value[key].all? { |item| item.is_a?(String) } }
      end

      def self.event?(value)
        value.is_a?(Hash) && value['feature'].is_a?(String) && value['name'].is_a?(String) &&
          value['data'].is_a?(Hash) && %w[before after].all? { |key| value['data'][key].is_a?(Hash) } &&
          value['context'].is_a?(Hash) && timestamp?(value['created_at'])
      end

      def self.validate!(body, command:, feature:, limit:, since:, environment:)
        valid = body.is_a?(Hash) && body['api_version'] == 1 && body['environment'] == environment
        if valid && command == 'show'
          valid = feature?(body['feature']) && body['feature']['name'] == feature
        elsif valid
          items = body[command == 'features' ? 'features' : 'events']
          meta = body['meta']
          valid = items.is_a?(Array) && items.length <= limit && meta.is_a?(Hash) &&
            meta['limit'] == limit && [true, false].include?(meta['truncated'])
          if valid && command == 'features'
            valid = items.all? { |item| feature?(item) }
          elsif valid
            retention = meta['retention']
            valid = items.all? { |item| event?(item) && (!feature || item['feature'] == feature) && (!since || Time.iso8601(item['created_at']) >= Time.iso8601(since)) } &&
              meta.key?('since') && meta['since'] == since && meta['scope'] == (feature ? 'feature' : 'global') && meta.key?('feature') && meta['feature'] == feature &&
              retention.is_a?(Hash) && [true, false].include?(retention['enabled']) &&
              %w[max_events oldest_available_at].all? { |key| retention.key?(key) } &&
              (retention['enabled'] || items.empty?) &&
              (retention['max_events'].nil? || (retention['max_events'].is_a?(Integer) && retention['max_events'] >= 0)) &&
              (retention['oldest_available_at'].nil? || timestamp?(retention['oldest_available_at'])) &&
              retention['completeness'] == 'unknown' && retention['deletion_events'] == false
          end
        end
        raise Error.new(5, 'API response does not match v1 contract or selected environment') unless valid
        body
      end
    end
  end
end
