require "spec_helper"
require "support/backend_contract"

RSpec.describe RolloutMemoryBackend do
  it_behaves_like "a rollout feature backend" do
    let(:backend) { described_class.new }
  end
end
