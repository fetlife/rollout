# frozen_string_literal: true

class Rollout
  module ActiveRecord
    class FeatureCache
      DEFAULT_MAX_SIZE = 4096

      def initialize(ttl:, clock: nil, max_size: DEFAULT_MAX_SIZE)
        unless ttl.is_a?(Integer) && ttl > 0
          raise ArgumentError, "cache_ttl must be an Integer > 0"
        end
        unless max_size.is_a?(Integer) && max_size > 0
          raise ArgumentError, "max_size must be an Integer > 0"
        end

        @ttl = ttl
        @max_size = max_size
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @entries = {}
        @generation = 0
        @mutex = Mutex.new
      end

      def generation
        @mutex.synchronize { @generation }
      end

      def read(name, context: nil)
        key = entry_key(name, context)
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

      def fill(generation, states, context: nil)
        clones = states.map { |state| [state.name.to_s, state.deep_clone] }
        @mutex.synchronize do
          return if generation != @generation

          clones.each do |name, clone|
            store_locked(name, clone, context)
          end
        end
      end

      def delete(*names, context: nil)
        keys = names.map { |name| entry_key(name, context) }
        @mutex.synchronize do
          @generation += 1
          keys.each { |key| @entries.delete(key) }
        end
      end

      def clear
        @mutex.synchronize do
          @generation += 1
          @entries.clear
        end
      end

      private

      def store_locked(name, clone, context)
        key = entry_key(name, context)
        @entries.delete(key)
        if @entries.size >= @max_size
          prune_expired_locked
          @entries.shift while @entries.size >= @max_size
        end
        @entries[key] = { state: clone, expires_at: now + @ttl }
      end

      def prune_expired_locked
        t = now
        @entries.delete_if { |_key, entry| entry[:expires_at] <= t }
      end

      def entry_key(name, context)
        [context, name.to_s]
      end

      def now
        @clock.call
      end
    end
  end
end
