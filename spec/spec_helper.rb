# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

require 'bundler/setup'
require 'rollout'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
