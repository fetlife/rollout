require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Rollout" do
  before do
    @redis   = Redis.new
    @rollout = Rollout.new(@redis)
  end

  # activate
  describe "when a feature is activated" do
    it "should be accessible to every user" do
      @rollout.should_not be_active(:chat, stub(:id => 0))
      @rollout.activate(:chat)
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "should be active" do
      @rollout.activate(:chat)
      @rollout.should be_active(:chat)
    end
  end

  # deactivate
  describe "when a feature is deactivate" do
    it "should not be accessible by any user" do
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
      @rollout.should_not be_active(:chat, stub(:id => 0))
    end

    it "should not be active" do
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
      @rollout.should_not be_active(:chat)
    end
  end

  # active?
  describe "when checking if feature is active" do
    describe "when the feature is accessible to all" do
      before do
        @rollout.activate_percentage(:chat, 100)
      end

      it "should be active" do
        @rollout.should be_active(:chat, stub(:id => 0))
      end
    end

    describe "when the user is part of the percentage" do
      before do
        @rollout.activate_percentage(:chat, 20)
        Zlib.stubs(:crc32).returns(19)
      end

      it "should be active" do
        @rollout.should be_active(:chat, stub(:id => 19))
      end
    end

    describe "when the user is not part of the percentage" do
      before do
        @rollout.activate_percentage(:chat, 20)
        Zlib.stubs(:crc32).returns(30)
      end

      describe "but was specifically activated" do
        before do
          @rollout.activate_user(:chat, stub(:id => 42))
        end

        it "should be active" do
          @rollout.should be_active(:chat, stub(:id => 42))
        end
      end

      describe "and was not specifically activated" do
        describe "but is part of an active group" do
          before do
            @rollout.define_group(:fortyniners) { |user| user.id == 49 }
            @rollout.activate_group(:chat, :fortyniners)
          end

          it "should be active" do
            @rollout.should be_active(:chat, stub(:id => 49))
          end
        end

        describe "and is not part of an active group" do
          it "should not be active" do
            @rollout.should_not be_active(:chat, stub(:id => 50))
          end
        end
      end
    end
  end

  # activate_group
  describe "when activating a group" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :fivesonly)
    end

    it "should allow access to any users in this group" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "should deny access to users outside of this group" do
      @rollout.should_not be_active(:chat, stub(:id => 4))
    end

    describe "when a string is passed" do
      before do
        @rollout.define_group(:admins) { |user| user.id == 5 }
        @rollout.activate_group(:chat, 'admins')
      end

      it "should also work" do
        @rollout.should be_active(:chat, stub(:id => 5))
      end
    end
  end

  describe "when multiple group are activated" do
    before do
      @rollout.define_group(:foursonly) { |user| user.id == 4 }
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :foursonly)
      @rollout.activate_group(:chat, :fivesonly)
    end

    it "should allow access to any users in these groups" do
      @rollout.should be_active(:chat, stub(:id => 4))
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "should deny access to users outside of these groups" do
      @rollout.should_not be_active(:chat, stub(:id => 3))
    end
  end

  # deactivate_group
  describe "when deactivating a group" do
    before do
      @rollout.define_group(:foursonly) { |user| user.id == 4 }
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :foursonly)
      @rollout.activate_group(:chat, :fivesonly)

      @rollout.deactivate_group(:chat, :foursonly)
    end

    it "should deny access to users in this group" do
      @rollout.should_not be_active(:chat, stub(:id => 4))
    end

    it "should still allow access in other active groups" do
      @rollout.should be_active(:chat, stub(:id => 5))
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

  # active_in_group?
  describe "when checking if active in group" do
    before do
      @rollout.define_group(:even) { |user| user.id % 2 == 0}
    end

    it "should return true if the user meets the criteria" do
      @rollout.should be_active_in_group(:even, stub(:id => 2))
      @rollout.should be_active_in_group(:even, stub(:id => 4))
      @rollout.should be_active_in_group(:even, stub(:id => 6))
    end

    it "should return false if the user meets the criteria" do
      @rollout.should_not be_active_in_group(:even, stub(:id => 1))
      @rollout.should_not be_active_in_group(:even, stub(:id => 3))
      @rollout.should_not be_active_in_group(:even, stub(:id => 5))
    end
  end

  # activate_user
  describe "activating a specific user" do
    describe "with a numeric id" do
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

    describe "with a string id" do
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
  end

  # deactivate_user
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

  # activate_percentage
  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:commenting, 5)
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      (1..100).select { |id| @rollout.active?(:commenting, stub(:id => id)) }.length.should be_within(2).of(5)
      (1..120).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(2).of(20)
      (1..200).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(5).of(40)
    end
  end

  # deactivate_percentage
  describe "deactivating the percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 100)
      @rollout.deactivate_percentage(:chat)
    end

    it "becomes inactivate for all users" do
      100.times do |i|
        @rollout.should_not be_active(:chat, stub(:id => i))
      end
    end
  end

  # get
  describe "#get" do
    describe "when asking for 'shell feature'" do
      before do
        @rollout.activate(:signup)
      end

      it "returns the feature object" do
        feature = @rollout.get(:signup)
        feature.groups.should be_empty
        feature.users.should be_empty
        feature.percentage.should == 100
      end
    end

    describe "when asking for an active feature" do
      before do
        @rollout.activate_percentage(:chat, 10)
        @rollout.activate_group(:chat, :caretakers)
        @rollout.activate_group(:chat, :greeters)
        @rollout.activate_user(:chat, stub(:id => 42))
      end

      it "returns the feature object" do
        feature = @rollout.get(:chat)
        feature.groups.should == [:caretakers, :greeters]
        feature.percentage.should == 10
        feature.users.should == %w(42)
        feature.to_hash.should == {
          :groups     => [:caretakers, :greeters],
          :percentage => 10,
          :users      => %w(42)
        }
      end
    end
  end

  # features
  describe "keeps a list of features" do
    it "saves the feature" do
      @rollout.activate(:chat)
      @rollout.features.should eq([:chat])
    end

    it "does not contain doubles" do
      @rollout.activate(:chat)
      @rollout.activate(:chat)
      @rollout.features.should eq([:chat])
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
  end

  describe "active_in_groups?" do
    before(:each) do
      @rollout.define_group(:a) { |user| user.a }
      @rollout.define_group(:b) { |user| user.b }
      @rollout.define_group(:c) { |user| user.c }
    end

    it "should work for the unique group" do
      user = stub(:a => true)
      @rollout.active_in_groups?("a", user).should be_true
    end

    it "should work for one intersection" do
      user = stub(:a => true, :b => true)
      @rollout.active_in_groups?("a&b", user).should be_true
      @rollout.active_in_groups?("b&a", user).should be_true
    end

    it "should work for multiple intersections" do
      user = stub(:a => true, :b => true, :c => false)
      @rollout.active_in_groups?("a&b&c", user).should be_false
      @rollout.active_in_groups?("b&a&c", user).should be_false
      @rollout.active_in_groups?("b&c&a", user).should be_false

      user = stub(:a => true, :b => true, :c => true)
      @rollout.active_in_groups?("a&b&c", user).should be_true
    end

    it "should work with rejections" do
      user = stub(:a => true, :b => false)
      @rollout.active_in_groups?("!a", user).should be_false
      @rollout.active_in_groups?("!b", user).should be_true
    end

    it "should work with rejections and intersections" do
      user = stub(:a => true, :b => true, :c => false)
      @rollout.active_in_groups?("a&b&!c", user).should be_true
      @rollout.active_in_groups?("a&!c", user).should be_true
      @rollout.active_in_groups?("a&!c&b", user).should be_true
      @rollout.active_in_groups?("a&!c&!b", user).should be_false

      user = stub(:a => true, :b => false, :c => false)
      @rollout.active_in_groups?("a&!c&!b", user).should be_true
    end
  end
end
