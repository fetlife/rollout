require "spec_helper"

describe "Rollout::Feature" do
  let(:rollout) { Rollout.new(Redis.current) }

  describe "#add_user" do
    it "ids a user using id_user_by" do
      user    = double("User", email: "test@test.com")
      feature = Rollout::Feature.new(:chat, state: nil, rollout: rollout, options: { id_user_by: :email })
      feature.add_user(user)
      expect(user).to have_received :email
    end
  end

  describe "#initialize" do
    describe "when string does not exist" do
      it 'clears feature attributes when string is not given' do
        feature = Rollout::Feature.new(:chat, rollout: rollout)
        expect(feature.groups).to be_empty
        expect(feature.users).to be_empty
        expect(feature.percentage).to eq 0
        expect(feature.data).to eq({})
      end

      it 'clears feature attributes when string is nil' do
        feature = Rollout::Feature.new(:chat, state: nil, rollout: rollout)
        expect(feature.groups).to be_empty
        expect(feature.users).to be_empty
        expect(feature.percentage).to eq 0
        expect(feature.data).to eq({})
      end

      it 'clears feature attributes when string is empty string' do
        feature = Rollout::Feature.new(:chat, state: "", rollout: rollout)
        expect(feature.groups).to be_empty
        expect(feature.users).to be_empty
        expect(feature.percentage).to eq 0
        expect(feature.data).to eq({})
      end

      describe "when there is no data" do
        it 'sets @data to empty hash' do
          feature = Rollout::Feature.new(:chat, state: "0||", rollout: rollout)
          expect(feature.data).to eq({})
        end

        it 'sets @data to empty hash' do
          feature = Rollout::Feature.new(:chat, state: "|||   ", rollout: rollout)
          expect(feature.data).to eq({})
        end
      end
    end
  end
end
