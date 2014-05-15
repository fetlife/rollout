# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rollout/version"

Gem::Specification.new do |s|
  s.name = "rollout"
  s.version = Rollout::VERSION
  s.authors = ["James Golick"]
  s.email       = ["jamesgolick@gmail.com"]
  s.description = "Feature flippers with redis."
  s.summary = "Feature flippers with redis."
  s.homepage = "https://github.com/jamesgolick/rollout"

  s.rubyforge_project = "rollout"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "rspec", "~> 2.10.0"
  s.add_development_dependency "bundler", ">= 1.0.0"
  s.add_development_dependency "jeweler", "~> 1.6.4"
  s.add_development_dependency "bourne", "1.0"
  s.add_development_dependency "mocha", "0.9.8"
  s.add_development_dependency "redis"
end
