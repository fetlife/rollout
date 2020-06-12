# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'rollout/version'

Gem::Specification.new do |spec|
  spec.name        = 'rollout'
  spec.version     = Rollout::VERSION
  spec.authors     = ['James Golick']
  spec.email       = ['jamesgolick@gmail.com']
  spec.description = 'Feature flippers with redis.'
  spec.summary     = 'Feature flippers with redis.'
  spec.homepage    = 'https://github.com/FetLife/rollout'
  spec.license     = 'MIT'

  spec.files         = `git ls-files`.split("\n")
  spec.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  spec.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.3'

  spec.add_dependency 'redis', '~> 4.0'

  spec.add_development_dependency 'bundler', '>= 1.17'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec_junit_formatter', '~> 0.4'
  spec.add_development_dependency 'rubocop', '~> 0.71'
  spec.add_development_dependency 'simplecov', '0.17'
end
