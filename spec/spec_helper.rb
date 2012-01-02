require 'simplecov'
SimpleCov.start
require 'rollout'
require 'rspec'
require 'redis'

RSpec.configure do |config|
  config.mock_with :mocha
  config.before { Redis.new.flushdb }
end
