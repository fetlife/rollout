# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

require 'bundler/setup'
require 'redis'
require 'rollout'

Redis.current = Redis.new(
  host: ENV.fetch('REDIS_HOST', '127.0.0.1'),
  port: ENV.fetch('REDIS_PORT', '6379'),
  db: ENV.fetch('REDIS_DB', '7'),
)

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  # config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before { Redis.current.flushdb }
end
