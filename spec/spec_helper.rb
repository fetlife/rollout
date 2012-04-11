$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rollout'
require 'rspec'
require 'rspec/autorun'
require 'bourne'
require 'redis'

RSpec.configure do |config|
  config.mock_with :mocha
  config.before(:each) { Redis.new.flushdb }
end