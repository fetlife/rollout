# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'rollout-active_record'
  spec.version     = '0.1.0'
  spec.authors     = ['FetLife']
  spec.email       = ['dev@fetlife.com']
  spec.description = 'Active Record adapter for the rollout gem.'
  spec.summary     = 'Active Record adapter for the rollout gem.'
  spec.homepage    = 'https://github.com/FetLife/rollout'
  spec.license     = 'MIT'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'README.md'].select { |path| File.file?(path) }
  end
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.7'

  spec.add_dependency 'activerecord', '>= 7.1', '< 9'
  spec.add_dependency 'rollout', '>= 3.0', '< 4'
end
