require "spec_helper"

describe "Rollout::Feature" do
  def build_feature(name: :chat, percentage: 0, users: [], groups: [], data: {}, options: {}, rollout: nil)
    rollout ||= Object.new
    Rollout::Feature.new(
      state: Rollout::FeatureState.new(
        name: name,
        percentage: percentage,
        users: users,
        groups: groups,
        data: data,
      ),
      rollout: rollout,
      options: options,
    )
  end

  describe "#add_user" do
    it "ids a user using id_user_by" do
      user = double("User", email: "test@test.com")
      feature = build_feature(options: { id_user_by: :email })
      feature.add_user(user)
      expect(user).to have_received :email
    end
  end

  describe "#initialize" do
    it "uses the state's name" do
      expect(build_feature(name: :video).name).to eq :video
    end

    it "preserves an explicit public name" do
      feature = Rollout::Feature.new(
        state: Rollout::FeatureState.new(name: :chat, percentage: 0),
        rollout: Object.new,
        name: "chat",
      )
      feature.percentage = 50
      feature.clear

      expect(feature.name).to eq "chat"
      expect(feature.to_feature_state.name).to eq "chat"
    end

    it "clears feature attributes for an empty state" do
      feature = build_feature

      expect(feature.groups).to be_empty
      expect(feature.users).to be_empty
      expect(feature.percentage).to eq 0
      expect(feature.data).to eq({})
    end
  end

  describe "percentage assignment" do
    it "keeps the same users across features when randomize_percentage is off" do
      chat = build_feature(name: :chat, percentage: 20)
      beta = build_feature(name: :beta, percentage: 20)

      expect(chat.active?(double(id: 2))).to eq true
      expect(chat.active?(double(id: 6))).to eq true
      expect(chat.active?(double(id: 1))).to eq false
      expect(beta.active?(double(id: 2))).to eq true
      expect(beta.active?(double(id: 1))).to eq false
    end

    it "changes assignment by feature name when randomize_percentage is on" do
      chat = build_feature(name: :chat, percentage: 20, options: { randomize_percentage: true })
      beta = build_feature(name: :beta, percentage: 20, options: { randomize_percentage: true })

      expect(chat.active?(double(id: 1))).to eq true
      expect(beta.active?(double(id: 1))).to eq false
      expect(chat.active?(double(id: 5))).to eq false
      expect(beta.active?(double(id: 5))).to eq true
    end
  end

  it "does not expose assign_state" do
    feature = build_feature

    expect(feature).not_to respond_to(:assign_state)
    expect(feature.private_methods).to include(:assign_state)
  end
end
