$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rollout'
require 'spec'
require 'spec/autorun'
require 'bourne'
require 'redis'

Spec::Runner.configure do |config|
  config.mock_with :mocha
  config.before { Redis.new.flushdb }
end
