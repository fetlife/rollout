# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'rollout-redis'
  spec.version     = '0.1.0'
  spec.authors     = ['FetLife']
  spec.email       = ['dev@fetlife.com']
  spec.description = 'Redis adapter for the rollout gem.'
  spec.summary     = 'Redis adapter for the rollout gem.'
  spec.homepage    = 'https://github.com/FetLife/rollout'
  spec.license     = 'MIT'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*.rb']
  end
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.3'

  spec.add_dependency 'redis', '>= 4.0', '< 6'
  spec.add_dependency 'rollout', '>= 3.0', '< 4'
end
