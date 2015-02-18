require "rollout/group"
require "rollout/feature"
require "rollout/no_feature"
require "rollout/context"
require 'rollout/rollout'
require "digest"
require "zlib"

require 'rollout/railtie' if defined?(Rails)

module Rollout
  def self.redis
    @redis
  end

  def self.redis=(redis)
    @redis = redis
  end

end
