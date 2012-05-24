require 'bundler'
Bundler::GemHelper.install_tasks
require 'rspec/core/rake_task'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "rollout"
    gem.summary = %Q{Conditionally roll out features with redis.}
    gem.description = %Q{Conditionally roll out features with redis.}
    gem.email = "jamesgoick@gmail.com"
    gem.homepage = "http://github.com/jamesgolick/rollout"
    gem.authors = ["James Golick"]
    gem.add_development_dependency "rspec", "~> 2.8.0"
    gem.add_development_dependency "bourne", "1.0.0"
    gem.add_development_dependency "redis", "2.2.2"
    gem.add_development_dependency "rdoc", "2.4.2"
    gem.add_development_dependency "jeweler", "1.8.3"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :default => :spec

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "rollout #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
