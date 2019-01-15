# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rollout/version"

Gem::Specification.new do |s|
  s.name        = "rollout"
  s.version     = Rollout::VERSION
  s.authors     = ["James Golick", "Gary Burns"]
  s.email       = ["jamesgolick@gmail.com", "gary@barkbox.com"]
  s.description = "Feature flippers with redis."
  s.summary     = "Feature flippers with redis."
  s.homepage    = "https://github.com/FetLife/rollout"
  s.license     = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "rspec"
  s.add_development_dependency "appraisal"
  s.add_development_dependency "bundler", ">= 1.0.0"
  s.add_development_dependency "redis"
  s.add_development_dependency "fakeredis"
  s.add_development_dependency "simplecov"
  s.add_development_dependency "codeclimate-test-reporter"
end
