$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require "rollout"
require "rspec"
require(p(ENV["TRAVIS_CI"] ? "redis" : "fakeredis"))
require "codeclimate-test-reporter"

SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    CodeClimate::TestReporter::Formatter,
  ])
end

RSpec.configure do |config|
  config.before { Redis.new.flushdb }
end
