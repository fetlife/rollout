# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

require 'bundler/setup'
require ENV["USE_REAL_REDIS"] == "true" ? "redis" : "fakeredis"
require "rollout"

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  # config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before { Redis.new.flushdb }
end
