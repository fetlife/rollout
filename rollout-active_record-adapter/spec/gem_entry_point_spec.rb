require "spec_helper"
require "rubygems/package"

RSpec.describe "rollout-active_record-adapter" do
  it "can be required by gem name" do
    expect { require "rollout-active_record-adapter" }.not_to raise_error
    expect(Rollout::Adapters::ActiveRecord).to be_a(Class)
  end

  it "packages the gem-name entry point" do
    adapter_root = File.expand_path("..", __dir__)
    Dir.chdir(adapter_root) do
      spec = Gem::Specification.load("rollout-active_record-adapter.gemspec")
      gem_path = File.expand_path(Gem::Package.build(spec))
      files = Gem::Package.new(gem_path).contents
      expect(files).to include("lib/rollout-active_record-adapter.rb")
    ensure
      File.delete(gem_path) if gem_path && File.exist?(gem_path)
    end
  end
end
