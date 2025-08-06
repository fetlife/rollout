# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :version do
  desc "Bump patch version"
  task :patch do
    bump_version(:patch)
  end
  
  desc "Bump minor version"
  task :minor do
    bump_version(:minor)
  end
  
  desc "Bump major version"
  task :major do
    bump_version(:major)
  end
end

def bump_version(type)
  require 'rollout/version'
  current_version = Rollout::VERSION
  major, minor, patch = current_version.split('.').map(&:to_i)
  
  new_version = case type
  when :major
    "#{major + 1}.0.0"
  when :minor
    "#{major}.#{minor + 1}.0"
  when :patch
    "#{major}.#{minor}.#{patch + 1}"
  end
  
  puts "Bumping version from #{current_version} to #{new_version}"
  
  # Update version file
  version_file = 'lib/rollout/version.rb'
  content = File.read(version_file)
  updated_content = content.gsub(/VERSION\s*=\s*'[^']+'/, "VERSION = '#{new_version}'")
  File.write(version_file, updated_content)
  
  puts "Version bumped to #{new_version}"
end
