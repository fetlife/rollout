$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require "codeclimate-test-reporter"
require "rspec"
require ENV["USE_REAL_REDIS"] == "true" ? "redis" : "fakeredis"

if ENV["CODECLIMATE_REPO_TOKEN"]
  CodeClimate::TestReporter.start
else
  SimpleCov.start do
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      CodeClimate::TestReporter::Formatter,
    ])
  end
end


require "rollout"

RSpec.configure do |config|
  config.before { Redis.new.flushdb }
end
