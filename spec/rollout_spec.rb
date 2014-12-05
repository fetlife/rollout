require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Rollout" do
  before do
    @redis   = Redis.new
    @rollout = Rollout.new(@redis)
  end

  describe "when a group is activated" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :fivesonly)
    end

    it "the feature is active for users for which the block evaluates to true" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "is not active for users for which the block evaluates to false" do
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end

    it "is not active if a group is found in Redis but not defined in Rollout" do
      @rollout.activate_group(:chat, :fake)
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end
  end

  describe "the default all group" do
    before do
      @rollout.activate_group(:chat, :all)
    end

    it "evaluates to true no matter what" do
      @rollout.should be_active(:chat, stub(:id => 0))
    end
  end

  describe "deactivating a group" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :some)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.deactivate_group(:chat, :all)
      @rollout.deactivate_group(:chat, "some")
    end

    it "deactivates the rules for that group" do
      @rollout.should_not be_active(:chat, stub(:id => 10))
    end

    it "leaves the other groups active" do
      @rollout.get(:chat).groups.should == [:fivesonly]
    end
  end

  describe "deactivating a feature completely" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.activate_user(:chat, stub(:id => 51))
      @rollout.activate_percentage(:chat, 100)
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
    end

    it "removes all of the groups" do
      @rollout.should_not be_active(:chat, stub(:id => 0))
    end

    it "removes all of the users" do
      @rollout.should_not be_active(:chat, stub(:id => 51))
    end

    it "removes the percentage" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end

    it "removes globally" do
      @rollout.should_not be_active(:chat)
    end
  end

  describe "activating a specific user" do
    before do
      @rollout.activate_user(:chat, stub(:id => 42))
    end

    it "is active for that user" do
      @rollout.should be_active(:chat, stub(:id => 42))
    end

    it "remains inactive for other users" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end
  end

  describe "activating a specific user by ID" do
    before do
      @rollout.activate_user(:chat, 42)
    end

    it "is active for that user" do
      @rollout.should be_active(:chat, stub(:id => 42))
    end

    it "remains inactive for other users" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end
  end

  describe "activating a specific user with a string id" do
    before do
      @rollout.activate_user(:chat, stub(:id => 'user-72'))
    end

    it "is active for that user" do
      @rollout.should be_active(:chat, stub(:id => 'user-72'))
    end

    it "remains inactive for other users" do
      @rollout.should_not be_active(:chat, stub(:id => 'user-12'))
    end
  end

  describe "deactivating a specific user" do
    before do
      @rollout.activate_user(:chat, stub(:id => 42))
      @rollout.activate_user(:chat, stub(:id => 4242))
      @rollout.activate_user(:chat, stub(:id => 24))
      @rollout.deactivate_user(:chat, stub(:id => 42))
      @rollout.deactivate_user(:chat, stub(:id => "4242"))
    end

    it "that user should no longer be active" do
      @rollout.should_not be_active(:chat, stub(:id => 42))
    end

    it "remains active for other active users" do
      @rollout.get(:chat).users.should == %w(24)
    end
  end

  describe "activating a feature globally" do
    before do
      @rollout.activate(:chat)
    end

    it "activates the feature" do
      @rollout.should be_active(:chat)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      (1..120).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(1).of(20)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      (1..200).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(5).of(40)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 5)
    end

    it "activates the feature for that percentage of the users" do
      (1..100).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(2).of(5)
    end
  end

  describe "activating a feature for a group as a string" do
    before do
      @rollout.define_group(:admins) { |user| user.id == 5 }
      @rollout.activate_group(:chat, 'admins')
    end

    it "the feature is active for users for which the block evaluates to true" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "is not active for users for which the block evaluates to false" do
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end
  end

  describe "deactivating the percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 100)
      @rollout.deactivate_percentage(:chat)
    end

    it "becomes inactivate for all users" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end
  end

  describe "deactivating the feature globally" do
    before do
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
    end

    it "becomes inactivate" do
      @rollout.should_not be_active(:chat)
    end
  end

  describe "setting a feature on" do
    before do
      @rollout.set(:chat, true)
    end

    it "becomes activated" do
      @rollout.should be_active(:chat)
    end
  end

  describe "setting a feature off" do
    before do
      @rollout.set(:chat, false)
    end

    it "becomes activated" do
      @rollout.should_not be_active(:chat)
    end
  end

  describe "keeps a list of features" do
    it "saves the feature" do
      @rollout.activate(:chat)
      @rollout.features.should be_include(:chat)
    end

    it "does not contain doubles" do
      @rollout.activate(:chat)
      @rollout.activate(:chat)
      @rollout.features.size.should == 1
    end

    it "does not contain doubles when using string" do
      @rollout.activate(:chat)
      @rollout.activate("chat")
      @rollout.features.size.should == 1
    end
  end

  describe "#get" do
    before do
      @rollout.activate_percentage(:chat, 10)
      @rollout.activate_group(:chat, :caretakers)
      @rollout.activate_group(:chat, :greeters)
      @rollout.activate(:signup)
      @rollout.activate_user(:chat, stub(:id => 42))
    end

    it "returns the feature object" do
      feature = @rollout.get(:chat)
      feature.groups.should == [:caretakers, :greeters]
      feature.percentage.should == 10
      feature.users.should == %w(42)
      feature.to_hash.should == {
        :groups => [:caretakers, :greeters],
        :percentage => 10,
        :users => %w(42)
      }

      feature = @rollout.get(:signup)
      feature.groups.should be_empty
      feature.users.should be_empty
      feature.percentage.should == 100
    end
  end

  describe "#clear" do
    let(:features) { %w(signup beta alpha gm) }

    before do
      features.each { |f| @rollout.activate(f) }

      @rollout.clear!
    end

    it "each feature is cleared" do
      features.each do |feature|
        @rollout.get(feature).to_hash.should == {
          :percentage => 0,
          :users => [],
          :groups => []
        }
      end
    end

    it "removes all features" do
      @rollout.features.should be_empty
    end
  end

  describe "migration mode" do
    before do
      @legacy = Rollout::Legacy.new(@redis)
      @legacy.activate_percentage(:chat, 12)
      @legacy.activate_user(:chat, stub(:id => 42))
      @legacy.activate_user(:chat, stub(:id => 24))
      @legacy.activate_group(:chat, :dope_people)
      @rollout = Rollout.new(@redis, :migrate => true)
    end

    it "imports the settings from the legacy rollout once" do
      @rollout.get(:chat).to_hash.should == {
        :percentage => 12,
        :users => %w(24 42),
        :groups => [:dope_people]
      }
      @legacy.deactivate_all(:chat)
      @rollout.get(:chat).to_hash.should == {
        :percentage => 12,
        :users => %w(24 42),
        :groups => [:dope_people]
      }
      @redis.get("feature:chat").should_not be_nil
    end

    it "imports settings that were globally activated" do
      @legacy.activate_globally(:video_chat)
      @rollout.get(:video_chat).to_hash[:percentage].should == 100
    end
  end
end

describe "Rollout::Feature" do
  before do
    @user    = stub("User", :email => "test@test.com")
    @feature = Rollout::Feature.new(:chat, nil, :id_user_by => :email)
  end

  describe "#add_user" do
    it "ids a user using id_user_by" do
      @feature.add_user(@user)
      @user.should have_received :email
    end
  end
end
