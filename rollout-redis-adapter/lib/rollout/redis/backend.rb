# frozen_string_literal: true

require 'rollout/adapters/redis_adapter'

class Rollout
  module Redis
    Backend = Adapters::RedisAdapter
  end
end
