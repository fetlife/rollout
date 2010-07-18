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
  end

  describe "the default all group" do
    before do
      @rollout.activate_group(:chat, :all)
    end

    it "evaluates to true no matter what" do
      @rollout.should be_active(:chat, stub(:id => nil))
    end
  end

  describe "deactivating a group" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.deactivate_group(:chat, :all)
    end

    it "deactivates the rules for that group" do
      @rollout.should_not be_active(:chat, stub(:id => 10))
    end

    it "leaves the other groups active" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end
  end

  describe "deactivating a feature completely" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.deactivate_all(:chat)
    end

    it "removes all of the groups" do
      @rollout.should_not be_active(:chat, stub(:id => nil))
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

  describe "deactivating a specific user" do
    before do
      @rollout.activate_user(:chat, stub(:id => 42))
      @rollout.activate_user(:chat, stub(:id => 24))
      @rollout.deactivate_user(:chat, stub(:id => 42))
    end

    it "that user should no longer be active" do
      @rollout.should_not be_active(:chat, stub(:id => 42))
    end

    it "remains active for other active users" do
      @rollout.should be_active(:chat, stub(:id => 24))
    end
  end
end
