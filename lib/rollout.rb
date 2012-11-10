require "rollout/legacy"

class Rollout
  class Feature
    attr_reader :name, :groups, :users, :percentage
    attr_writer :percentage, :groups, :users

    def initialize(name, string = nil)
      @name = name
      if string
        raw_percentage,raw_users,raw_groups = string.split("|")
        @percentage = raw_percentage.to_i
        @users = (raw_users || "").split(",").map(&:to_i)
        @groups = (raw_groups || "").split(",").map(&:to_sym)
      else
        clear
      end
    end

    def serialize
      "#{@percentage}|#{@users.join(",")}|#{@groups.join(",")}"
    end

    def add_user(user)
      @users << user.id unless @users.include?(user.id)
    end

    def remove_user(user)
      @users.delete(user.id)
    end

    def add_group(group)
      @groups << group unless @groups.include?(group)
    end

    def remove_group(group)
      @groups.delete(group)
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
        user.id % 100 < @percentage
      end

      def user_in_active_users?(user)
        @users.include?(user.id)
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
    @legacy = Legacy.new(@storage) if opts[:migrate]
  end

  def activate(feature)
    with_feature(feature) do |f|
      f.percentage = 100
    end
  end

  def deactivate(feature)
    with_feature(feature) do |f|
      f.clear
    end
  end

  def activate_group(feature, group)
    with_feature(feature) do |f|
      f.add_group(group)
    end
  end

  def deactivate_group(feature, group)
    with_feature(feature) do |f|
      f.remove_group(group)
    end
  end

  def deactivate_all(feature)
    with_feature(feature) do |f|
      f.clear
    end
  end

  def activate_user(feature, user)
    with_feature(feature) do |f|
      f.add_user(user)
    end
  end

  def deactivate_user(feature, user)
    with_feature(feature) do |f|
      f.remove_user(user)
    end
  end

  def define_group(group, &block)
    @groups[group] = block
  end

  def active?(feature, user = nil)
    feature = get(feature)
    feature.active?(self, user)
  end

  def activate_percentage(feature, percentage)
    with_feature(feature) do |f|
      f.percentage = percentage
    end
  end

  def deactivate_percentage(feature)
    with_feature(feature) do |f|
      f.percentage = 0
    end
  end

  def active_in_group?(group, user)
    f = @groups[group]
    f && f.call(user)
  end

  def get(feature)
    string = @storage.get(key(feature))
    if string || !migrate?
      Feature.new(feature, string)
    else
      info = @legacy.info(feature)
      f = Feature.new(feature)
      f.percentage = info[:percentage]
      f.groups = info[:groups]
      f.users = info[:users]
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
      @storage.set(features_key, (features + [feature.name]).join(","))
    end

    def migrate?
      @legacy
    end
end
