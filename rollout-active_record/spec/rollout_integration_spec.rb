require "spec_helper"
require_relative "../../spec/support/rollout_backend_integration"

RSpec.describe "Rollout ActiveRecord integration" do
  it_behaves_like "a rollout backend integration" do
    let(:backend) { active_record_backend }
  end
end
