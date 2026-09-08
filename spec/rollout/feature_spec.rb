require "spec_helper"

describe "Rollout::Feature" do
  let(:rollout) { Rollout.new($redis) }

  def feature_for(state, options: {})
    Rollout::Feature.new(state: state, rollout: rollout, options: options)
  end

  describe "#add_user" do
    it "ids a user using id_user_by" do
      user = double("User", email: "test@test.com")
      feature = feature_for(
        Rollout::RedisCodec.decode(:chat, nil),
        options: { id_user_by: :email },
      )
      feature.add_user(user)
      expect(user).to have_received :email
    end
  end

  describe "#initialize" do
    it "uses the state's name" do
      feature = feature_for(Rollout::FeatureState.new(name: :video, percentage: 0))

      expect(feature.name).to eq :video
    end

    it "clears feature attributes for an empty state" do
      feature = feature_for(Rollout::RedisCodec.decode(:chat, nil))

      expect(feature.groups).to be_empty
      expect(feature.users).to be_empty
      expect(feature.percentage).to eq 0
      expect(feature.data).to eq({})
    end
  end
end
