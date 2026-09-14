# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

require 'bundler/setup'
require 'redis'
require 'rollout'
require 'rollout/redis'

$redis = Redis.new(
  host: ENV.fetch('REDIS_HOST', '127.0.0.1'),
  port: ENV.fetch('REDIS_PORT', '6379'),
  db: ENV.fetch('REDIS_DB', '7'),
)

def redis_backend
  Rollout::Redis::Backend.new($redis)
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do |example|
    next if example.metadata[:file_path].end_with?("codec_spec.rb")

    $redis.flushdb
  end
end
