require "rollout/version"
require "rollout/legacy"
require "zlib"

class Rollout
  class Feature
    attr_reader :name, :groups, :users, :percentage
    attr_writer :percentage, :groups, :users

    def initialize(name, string = nil, auditor = nil)
      @name = name
      if string
        raw_percentage,raw_users,raw_groups = string.split("|")
        @percentage = raw_percentage.to_i
        @users = (raw_users || "").split(",").map(&:to_s)
        @groups = (raw_groups || "").split(",").map(&:to_sym)
      else
        clear
      end
      @auditor = auditor
    end

    def serialize
      "#{@percentage}|#{@users.join(",")}|#{@groups.join(",")}"
    end

    def add_user(user)
      @auditor.log("adding user #{user}") unless @auditor.nil?
      @users << user.id.to_s unless @users.include?(user.id.to_s)
    end

    def remove_user(user)
      @auditor.log("removing user #{user}") unless @auditor.nil?
      @users.delete(user.id.to_s)
    end

    def add_group(group)
      @auditor.log("adding group #{group}") unless @auditor.nil?
      @groups << group.to_sym unless @groups.include?(group.to_sym)
    end

    def remove_group(group)
      @auditor.log("removing group #{group}") unless @auditor.nil?
      @groups.delete(group.to_sym)
    end

    def clear
      @groups = []
      @users = []
      @percentage = 0
    end

    def active?(rollout, user)
      if user.nil?
        @percentage == 100
      else
        user_in_percentage?(user) ||
            user_in_active_users?(user) ||
            user_in_active_group?(user, rollout)
      end
    end

    def to_hash
      {:percentage => @percentage,
       :groups     => @groups,
       :users      => @users}
    end

    private
    def user_in_percentage?(user)
      Zlib.crc32(user.id.to_s) % 100 < @percentage
    end

    def user_in_active_users?(user)
      @users.include?(user.id.to_s)
    end

    def user_in_active_group?(user, rollout)
      @groups.any? do |g|
        rollout.active_in_group?(g, user)
      end
    end
  end

  def initialize(storage, opts = {})
    @storage  = storage
    @groups = {:all => lambda { |user| true }}
    @legacy = Legacy.new(opts[:legacy_storage] || @storage) if opts[:migrate]
  end

  def activate(feature)
    @auditor.log("activating feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.percentage = 100
    end
  end

  def deactivate(feature)
    @auditor.log("deactivating feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.clear
    end
  end

  def activate_group(feature, group)
    @auditor.log("activating group #{group} for feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.add_group(group)
    end
  end

  def deactivate_group(feature, group)
    @auditor.log("deactivating group #{group} for feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.remove_group(group)
    end
  end

  def activate_user(feature, user)
    @auditor.log("activating user #{user} for feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.add_user(user)
    end
  end

  def deactivate_user(feature, user)
    @auditor.log("deactivating user #{user} for feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.remove_user(user)
    end
  end

  def define_group(group, &block)
    @auditor.log("defining group #{group}") unless @auditor.nil?
    @groups[group.to_sym] = block
  end

  def active?(feature, user = nil)
    feature = get(feature)
    feature.active?(self, user)
  end

  def activate_percentage(feature, percentage)
    @auditor.log("activating percentage #{percentage} for feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.percentage = percentage
    end
  end

  def deactivate_percentage(feature)
    @auditor.log("deactivating percentage for feature #{feature}") unless @auditor.nil?
    with_feature(feature) do |f|
      f.percentage = 0
    end
  end

  def active_in_group?(group, user)
    f = @groups[group.to_sym]
    f && f.call(user)
  end

  def get(feature)
    string = @storage.get(key(feature))
    if string || !migrate?
      Feature.new(feature, string)
    else
      @auditor.log("creating new feature #{feature}") unless @auditor.nil?
      info = @legacy.info(feature)
      f = Feature.new(feature)
      f.percentage = info[:percentage]
      f.percentage = 100 if info[:global].include? feature
      f.groups = info[:groups].map { |g| g.to_sym }
      f.users = info[:users].map { |u| u.to_s }
      save(f)
      f
    end
  end

  def features
    (@storage.get(features_key) || "").split(",").map(&:to_sym)
  end

  private
  def key(name)
    "feature:#{name}"
  end

  def features_key
    "feature:__features__"
  end

  def with_feature(feature)
    f = get(feature)
    yield(f)
    save(f)
  end

  def save(feature)
    @storage.set(key(feature.name), feature.serialize)
    @storage.set(features_key, (features | [feature.name.to_sym]).join(","))
  end

  def migrate?
    @legacy
  end
end
