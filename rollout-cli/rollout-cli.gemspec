# frozen_string_literal: true

require_relative 'lib/rollout/cli/version'

Gem::Specification.new do |spec|
  spec.name = 'rollout-cli'
  spec.version = Rollout::CLI::VERSION
  spec.authors = ['FetLife']
  spec.email = ['dev@fetlife.com']
  spec.summary = 'Read-only HTTP client for Rollout feature flags and retained history.'
  spec.homepage = 'https://github.com/FetLife/rollout'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'
  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*.rb', 'bin/*', '*.md', 'LICENSE'] }
  spec.bindir = 'bin'
  spec.executables = ['rollout']
  spec.require_paths = ['lib']
  spec.add_dependency 'json', '>= 2.6', '< 3'
  spec.add_dependency 'net-http', '>= 0.2', '< 1'
  spec.add_dependency 'optparse', '>= 0.2', '< 1'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 13.0'
end
