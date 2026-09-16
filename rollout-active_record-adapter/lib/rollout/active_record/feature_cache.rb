# frozen_string_literal: true

class Rollout
  module ActiveRecord
    class FeatureCache
      def initialize(ttl:, clock: nil)
        unless ttl.is_a?(Integer) && ttl > 0
          raise ArgumentError, "cache_ttl must be an Integer > 0"
        end

        @ttl = ttl
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @entries = {}
        @mutex = Mutex.new
      end

      def read(name)
        key = name.to_s
        @mutex.synchronize do
          entry = @entries[key]
          return nil unless entry
          if entry[:expires_at] <= now
            @entries.delete(key)
            return nil
          end

          entry[:state].deep_clone
        end
      end

      def write(state)
        clone = state.deep_clone
        @mutex.synchronize do
          @entries[state.name.to_s] = { state: clone, expires_at: now + @ttl }
        end
      end

      def delete(*names)
        keys = names.map(&:to_s)
        @mutex.synchronize do
          keys.each { |key| @entries.delete(key) }
        end
      end

      def clear
        @mutex.synchronize { @entries.clear }
      end

      private

      def now
        @clock.call
      end
    end
  end
end
