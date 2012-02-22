$:.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'rollout'
require 'rspec'
require 'bourne'
require 'redis'

RSpec.configure do |config|
  config.mock_with :mocha
  config.before { Redis.new.flushdb }
  config.color_enabled = true
end
