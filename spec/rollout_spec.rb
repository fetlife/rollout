require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'rollout/test_context'

class TestRolloutContextWithUrl < Rollout::TestContext
  def features
    "background:blue,element:water"
  end
end

describe "Rollout" do
  before do
    @rollout = Rollout::TestContext.rollout
    @rollout[:chat].enable
  end

  describe "version" do
    it "should increment" do
      previous_version = @rollout.version
      @rollout.set(:key_value) do |f|
        f.type = :value
      end
      @rollout.version.should > previous_version
    end
  end

  describe "clear" do
    it "should reset the type" do
      @rollout.get(:chat).clear
      @rollout.get(:chat).gate?.should == true
      @rollout.get(:chat).value.should == nil
    end
  end

  describe "value basics" do
    before do
      @rollout.set(:key_value) do |f|
        f.type = :value
      end
    end
    it "should be a value type" do
      @rollout.get(:key_value).value?.should == true
    end
  end

  describe "multi-variant basics" do
    before do
      @rollout.set(:background) do |f|
        f.type = :variant
        f.variants = {:red => 50, :blue => 50}
        f.bucketing = :user
        f.enabled = :rollout
      end
    end
    it "should make user always enter the same bucket" do
      @rollout.should be_active(:background, stub(:id => 5))
      @rollout.get(:background).active?.should == [:red, "w"]
      @rollout.get(:background).blue?.should == false
      @rollout.get(:background).red?.should == true
    end
  end

  describe "multi-variant random bucketing" do
    before do
      @rollout.set(:background) do |f|
        f.type = :variant
        f.variants = {:red => 50, :blue => 50}
        f.bucketing = :random
        f.enabled = :rollout
      end
    end
    it "should randomly bucket" do
      (1..200).select { |id| @rollout[:background].blue? }.length.should be_within(20).of(100)
    end
  end

  describe "multi-variant coerce" do
    before do
      @rollout.set(:background) do |f|
        f.type = :variant
        f.variants = {"red" => "90", :blue => "10"} # NOTE: blue is 0 percent
        f.enabled = :rollout
      end
    end
    it "should coerce the strings to symbols" do
      @rollout[:background].variants.should == { red: 90, blue: 10 }
    end
  end

  describe "multi-variant coerce users" do
    before do
      @rollout.set(:background) do |f|
        f.users = {"red" => "1,2,3", :blue => "4,5,6"}
        f.enabled = :rollout
      end
    end
    it "should coerce the string to an array of integers" do
      @rollout[:background].users.should == { red: [1,2,3], blue: [4,5,6] }
    end
  end

  describe "multi-variant coerce groups" do
    before do
      @rollout.set(:background) do |f|
        f.groups = {:red => "1,2,3", :blue => "fred, jim, bob"}
        f.enabled = :rollout
      end
    end
    it "should coerce the string to an array of symbols or integers" do
      @rollout[:background].groups.should == { red: [1,2,3], blue: [:fred, :jim, :bob] }
    end
  end

  describe "multi-variant force user to a variant" do
    before do
      @rollout.set(:background) do |f|
        f.variants = {:red => 100, :blue => 0} # NOTE: blue is 0 percent
        f.users = { :blue => [1] }
        f.bucketing = :random
        f.enabled = :rollout
      end
    end
    it "should force user to the blue bucket" do
      (1..200).select { |id| @rollout[:background].blue? }.length.should == 200
    end
  end

  describe "multi-variant url override for a variant" do
    before do
      @rollout2 = Rollout::Roller.new(Redis.new, TestRolloutContextWithUrl.new(nil, logger: Logger.new(STDOUT)))
      @rollout2.set(:background) do |f|
        f.variants = {:red => 100, :blue => 0} # NOTE: blue is 0 percent
        f.users = { :red => [1234] } # NOTE: forcing user to red
        f.bucketing = :random
        f.enabled = :rollout
      end
      @rollout2.set(:element) do |f|
        f.variants = {:earth => 100, :wind => 0, :water => 0} # NOTE: water is 0 percent
        f.users = { :earth => [1234] } # NOTE: forcing user to red
        f.bucketing = :random
        f.enabled = :rollout
      end
    end
    it "should force user to the blue bucket with url" do
      (1..200).select { |id| @rollout2[:background].blue? }.length.should == 200
    end
    it "should force user to the water bucket with url" do
      (1..200).select { |id| @rollout2[:element].water? }.length.should == 200
    end
  end

  describe "when a group is activated" do
    before do
      @rollout[:chat].enable @rollout.group(:fivesonly)
    end

    it "the feature is active for users for which the block evaluates to true" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "is not active for users for which the block evaluates to false" do
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end

    it "is not active if a group is found in Redis but not defined in Rollout" do
      @rollout[:chat].enable @rollout.group(:fake)
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end
  end

  describe "the default all group" do
    before do
      @rollout.activate_group(:chat, :all)
    end

    it "evaluates to true no matter what" do
      @rollout.should be_active(:chat, stub(:id => 1))
    end
  end

  describe "deactivating a group" do
    before do
      @rollout.group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :some)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.deactivate_group(:chat, :all)
      @rollout.deactivate_group(:chat, "some")
    end

    it "deactivates the rules for that group" do
      # puts "deactivates the rules for that group" + @rollout[:chat].serialize
      @rollout.should_not be_active(:chat, stub(:id => 11))
    end

    it "leaves the other groups active" do
      @rollout.get(:chat).groups.should == {groups: [:fivesonly]}
    end
  end

  describe "deactivating a feature completely" do
    before do
      @rollout.group(:fivesonly) { |user| user.id == 5 }
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
      @rollout[:chat].enable
      # puts @rollout[:chat].serialize
      @rollout.activate_user(:chat, stub(:id => 42))
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
      @rollout[:chat].enable
      # puts @rollout[:chat].serialize
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
      @rollout.get(:chat).users.should == { users: [24] }
    end
  end

  describe "activating a feature globally" do
    before do
      @rollout[:chat].enable :on
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
      (1..120).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(5).of(25)
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
      @rollout.activate_percentage(:chat, 10)
    end

    it "activates the feature for that percentage of the users" do
      (1..100).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should be_within(5).of(10)
    end
  end

  describe "activating a feature for a group as a string" do
    before do
      @rollout.group(:admins) 
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
      feature.groups.should == {groups: [:caretakers, :greeters]}
      feature.percentage.should == 10
      feature.users.should == {users: [42]}
      feature.to_h.should == {
        admin: false,
        bucketing: "uaid",
        date_range: nil,
        description: nil,
        enabled: "rollout",
        groups: {groups: [:caretakers, :greeters]},
        internal: false,
        name: "chat",
        percentage: 10,
        sha: "2e9c1dc1be59401123eab422850d1ffb638198f28364d88c2a831642b8f9785b",
        type: "gate",
        url: "chat",
        users: {users: [42]}
      }

      feature = @rollout.get(:signup)
      feature.groups.should be_empty
      feature.users.should be_empty
      feature.percentage.should == 0
    end
  end

end
