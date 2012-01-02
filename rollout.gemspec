# encoding: utf-8

Gem::Specification.new do |gem|
  gem.name = "rollout"
  gem.version = "1.0.0"

  gem.required_rubygems_version = Gem::Requirement.new(">= 1.3.6") if gem.respond_to? :required_rubygems_version=
  gem.authors = ["James Golick"]
  gem.date = "2011-10-06"
  gem.description = "Conditionally roll out features with redis."
  gem.email = "jamesgoick@gmail.com"
  gem.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  gem.files = [
    ".document",
    "LICENSE",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "lib/rollout.rb",
    "rollout.gemspec",
    "spec/rollout_spec.rb",
    "spec/spec.opts",
    "spec/spec_helper.rb"
  ]
  gem.homepage = "http://github.com/jamesgolick/rollout"
  gem.require_paths = ["lib"]
  gem.summary = "Conditionally roll out features with redis."

  if gem.respond_to? :specification_version then
    gem.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      gem.add_runtime_dependency(%q<redis>, ["= 0.1"])
      gem.add_development_dependency(%q<rspec>, ["= 1.2.9"])
      gem.add_development_dependency(%q<bourne>, ["= 1.0.0"])
    else
      gem.add_dependency(%q<rspec>, ["= 1.2.9"])
      gem.add_dependency(%q<bourne>, ["= 1.0.0"])
      gem.add_dependency(%q<redis>, ["= 0.1"])
    end
  else
    gem.add_dependency(%q<rspec>, ["= 1.2.9"])
    gem.add_dependency(%q<bourne>, ["= 1.0.0"])
    gem.add_dependency(%q<redis>, ["= 0.1"])
  end
end

