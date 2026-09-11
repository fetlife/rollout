require "spec_helper"
require_relative "../../spec/support/backend_contract"

RSpec.describe Rollout::ActiveRecord::Backend do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { active_record_backend }
  end
end
