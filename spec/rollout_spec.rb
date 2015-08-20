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
      expect(@rollout).to be_active(:chat, stub(:id => 5))
    end

    it "is not active for users for which the block evaluates to false" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 1))
    end

    it "is not active if a group is found in Redis but not defined in Rollout" do
      @rollout.activate_group(:chat, :fake)
      expect(@rollout).not_to be_active(:chat, stub(:id => 1))
    end
  end

  describe "when a locale is activated" do
    before do
      @rollout.define_locale("zh-CN") do |user|
        user.language == "zh-CN"
      end
    end
    it "the feature is deactive for users whose language is not released to" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 4, :language => 'zh-CN'))
      expect(@rollout).not_to be_active(:chat, stub(:id => 4, :language => 'zh-TW'))
      expect(@rollout).not_to be_active(:chat, stub(:id => 5, :language => 'zh-CN'))
    end
    it "the feature is active for users whose language is released to" do
      @rollout.activate_locale(:chat, "zh-CN", 10)
      expect(@rollout).to be_active(:chat, stub(:id => 4, :language => 'zh-CN'))
      expect(@rollout).not_to be_active(:chat, stub(:id => 4, :language => "dummy"))
      expect(@rollout).not_to be_active(:chat, stub(:id => 5, :language => "dummy"))
      expect(@rollout).not_to be_active(:chat, stub(:id => 5, :language => "zh-CN"))
    end
  end

  describe "the default all group" do
    before do
      @rollout.activate_group(:chat, :all)
    end
    
    it "evaluates to true no matter what" do
      expect(@rollout).to be_active(:chat, stub(:id => 0))
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
      expect(@rollout).not_to be_active(:chat, stub(:id => 10))
    end
    
    it "leaves the other groups active" do
      expect(@rollout.get(:chat).groups).to eq([:fivesonly])
    end
  end
  
  describe "deactivating a feature completely" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.define_locale("zh-CN") do |user|
        user.language == "zh-CN"
      end
      @rollout.activate_locale(:chat, "zh-CN", 10)
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.activate_user(:chat, stub(:id => 51))
      @rollout.activate_percentage(:chat, 100)
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
    end

    it "removes all of the groups" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 0))
    end

    it "removes all of the users" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 51))
    end

    it "removes the percentage" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 24))
    end

    it "removes all languages" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 4, :language => "zh-CN"))
    end

    it "removes globally" do
      expect(@rollout).not_to be_active(:chat)
    end
  end

  describe "activating a specific user" do
    before do
      @rollout.activate_user(:chat, stub(:id => 42))
    end

    it "is active for that user" do
      expect(@rollout).to be_active(:chat, stub(:id => 42))
    end

    it "remains inactive for other users" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 24))
    end
  end

  describe "activating a specific user by ID" do
    before do
      @rollout.activate_user(:chat, 42)
    end
    
    it "is active for that user" do
      expect(@rollout).to be_active(:chat, stub(:id => 42))
    end
    
    it "remains inactive for other users" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 24))
    end
  end
  
  describe "activating a specific user with a string id" do
    before do
      @rollout.activate_user(:chat, stub(:id => 'user-72'))
    end
    
    it "is active for that user" do
      expect(@rollout).to be_active(:chat, stub(:id => 'user-72'))
    end
    
    it "remains inactive for other users" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 'user-12'))
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
      expect(@rollout).not_to be_active(:chat, stub(:id => 42))
    end
    
    it "remains active for other active users" do
      expect(@rollout.get(:chat).users).to eq(%w(24))
    end
  end
  
  describe "activating a feature globally" do
    before do
      @rollout.activate(:chat)
    end
    
    it "activates the feature" do
      expect(@rollout).to be_active(:chat)
    end
  end
  
  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end
    
    it "activates the feature for that percentage of the users" do
      expect((1..120).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length).to be_within(1).of(20)
    end
  end
  
  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end
    
    it "activates the feature for that percentage of the users" do
      expect((1..200).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length).to be_within(5).of(40)
    end
  end
  
  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 5)
    end
    
    it "activates the feature for that percentage of the users" do
      expect((1..100).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length).to be_within(2).of(5)
    end
  end
  
  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
      @rollout.activate_percentage(:beta, 20)
      @options = @rollout.instance_variable_get('@options')
    end
    
    it "activates the feature for a random set of users when opt is set" do
      @options[:randomize_percentage] = true
      chat_users = (1..100).select { |id| @rollout.active?(:chat, stub(:id => id)) }
      beta_users = (1..100).select { |id| @rollout.active?(:beta, stub(:id => id)) }
      expect(chat_users).not_to eq beta_users
    end
    it "activates the feature for the same set of users when opt is not set" do
      @options[:randomize_percentage] = false
      chat_users = (1..100).select { |id| @rollout.active?(:chat, stub(:id => id)) }
      beta_users = (1..100).select { |id| @rollout.active?(:beta, stub(:id => id)) }
      expect(chat_users).to eq beta_users
    end
  end
  
  describe "activating a feature for a group as a string" do
    before do
      @rollout.define_group(:admins) { |user| user.id == 5 }
      @rollout.activate_group(:chat, 'admins')
    end
    
    it "the feature is active for users for which the block evaluates to true" do
      expect(@rollout).to be_active(:chat, stub(:id => 5))
    end
    
    it "is not active for users for which the block evaluates to false" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 1))
    end
  end
  
  describe "deactivating the percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 100)
      @rollout.deactivate_percentage(:chat)
    end
    
    it "becomes inactivate for all users" do
      expect(@rollout).not_to be_active(:chat, stub(:id => 24))
    end
  end
  
  describe "deactivating the feature globally" do
    before do
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
    end
    
    it "becomes inactivate" do
      expect(@rollout).not_to be_active(:chat)
    end
  end
  
  describe "setting a feature on" do
    before do
      @rollout.set(:chat, true)
    end
    
    it "becomes activated" do
      expect(@rollout).to be_active(:chat)
    end
  end
  
  describe "setting a feature off" do
    before do
      @rollout.set(:chat, false)
    end
    
    it "becomes activated" do
      expect(@rollout).not_to be_active(:chat)
    end
  end
  
  describe "keeps a list of features" do
    it "saves the feature" do
      @rollout.activate(:chat)
      expect(@rollout.features).to be_include(:chat)
    end
    
    it "does not contain doubles" do
      @rollout.activate(:chat)
      @rollout.activate(:chat)
      expect(@rollout.features.size).to eq(1)
    end
    
    it "does not contain doubles when using string" do
      @rollout.activate(:chat)
      @rollout.activate("chat")
      expect(@rollout.features.size).to eq(1)
    end
  end
  
  describe "#get" do
    before do
      @rollout.activate_percentage(:chat, 10)
      @rollout.activate_group(:chat, :caretakers)
      @rollout.activate_group(:chat, :greeters)
      @rollout.activate_locale(:chat, "zh-CN", 10)
      @rollout.activate_locale(:chat, "zh-TW")
      @rollout.activate(:signup)
      @rollout.activate_user(:chat, stub(:id => 42))
    end
    
    it "returns the feature object" do
      feature = @rollout.get(:chat)
      expect(feature.groups).to eq([:caretakers, :greeters])
      expect(feature.percentage).to eq(10)
      expect(feature.users).to eq(%w(42))
      expect(feature.locales).to eq(["zh-CN:10", "zh-TW:0"])
      expect(feature.to_hash).to eq({
        :groups => [:caretakers, :greeters],
        :percentage => 10,
        :users => %w(42),
        :locales => ["zh-CN:10", "zh-TW:0"]
      })
      
      feature = @rollout.get(:signup)
      expect(feature.groups).to be_empty
      expect(feature.users).to be_empty
      expect(feature.locales).to be_empty
      expect(feature.percentage).to eq(100)
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
        expect(@rollout.get(feature).to_hash).to eq({
          :percentage => 0,
          :users => [],
          :groups => [],
          :locales => []
        })
      end
    end
    
    it "removes all features" do
      expect(@rollout.features).to be_empty
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
      expect(@rollout.get(:chat).to_hash).to eq({
        :percentage => 12,
        :users => %w(24 42),
        :groups => [:dope_people],
        :locales => []
      })
      @legacy.deactivate_all(:chat)
      expect(@rollout.get(:chat).to_hash).to eq({
        :percentage => 12,
        :users => %w(24 42),
        :groups => [:dope_people],
        :locales => []
      })
      expect(@redis.get("feature:chat")).not_to be_nil
    end
    
    it "imports settings that were globally activated" do
      @legacy.activate_globally(:video_chat)
      expect(@rollout.get(:video_chat).to_hash[:percentage]).to eq(100)
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
      expect(@user).to have_received :email
    end
  end
end
