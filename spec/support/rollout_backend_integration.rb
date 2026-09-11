RSpec.shared_examples "a rollout backend integration" do
  let(:rollout) { Rollout.new(backend: backend) }

  it "persists combined feature state" do
    rollout.with_feature(:chat) do |feature|
      feature.percentage = 10.5
      feature.groups = [:employees]
      feature.users = ["123"]
      feature.data.update(description: "New navigation", label: :beta)
    end

    feature = rollout.get(:chat)
    expect(feature.percentage).to eq 10.5
    expect(feature.groups).to eq [:employees]
    expect(feature.users).to eq %w[123]
    expect(feature.data).to eq("description" => "New navigation", "label" => "beta")
    expect(rollout.exists?(:chat)).to eq true
    expect(rollout.features).to eq [:chat]
  end

  it "persists metadata that contains pipes" do
    rollout.activate_user(:chat, 8)
    rollout.set_feature_data(:chat, "|call||text|" => "a|bunch|of|stuff")

    expect(rollout.get(:chat).data).to include("|call||text|" => "a|bunch|of|stuff")
    expect(rollout.get(:chat).users).to eq %w[8]
  end

  it "clears users, groups, percentage, and data on deactivate" do
    rollout.activate_user(:chat, 42)
    rollout.activate_group(:chat, :employees)
    rollout.activate_percentage(:chat, 50)
    rollout.set_feature_data(:chat, description: "foo")

    rollout.deactivate(:chat)

    expect(rollout.features).to eq [:chat]
    expect(rollout.get(:chat).to_hash).to eq(
      percentage: 0,
      users: [],
      groups: [],
      data: {},
    )
  end

  it "keeps users, groups, and data on deactivate_percentage" do
    rollout.activate_user(:chat, 42)
    rollout.activate_group(:chat, :employees)
    rollout.activate_percentage(:chat, 50)
    rollout.set_feature_data(:chat, description: "foo")

    rollout.deactivate_percentage(:chat)

    expect(rollout.get(:chat).percentage).to eq 0
    expect(rollout.get(:chat).users).to eq %w[42]
    expect(rollout.get(:chat).groups).to eq [:employees]
    expect(rollout.get(:chat).data).to eq("description" => "foo")
  end

  it "removes the feature on delete" do
    rollout.activate(:chat)
    rollout.delete(:chat)

    expect(rollout.features).to eq []
    expect(rollout.exists?(:chat)).to eq false
    expect(rollout.get(:chat).percentage).to eq 0
  end

  it "clears persisted features" do
    rollout.activate(:signup)
    rollout.activate(:chat)
    rollout.clear!

    expect(rollout.features).to eq []
    expect(rollout.exists?(:chat)).to eq false
  end
end
