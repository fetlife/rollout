class Rollout
  def initialize(redis)
    @redis  = redis
    @groups = {"all" => lambda { |user| true }}
  end

  def activate_group(feature, group)
    @redis.sadd(group_key(feature), group)
  end

  def deactivate_group(feature, group)
    @redis.srem(group_key(feature), group)
  end

  def deactivate_all(feature)
    @redis.del(group_key(feature))
    @redis.del(user_key(feature))
    @redis.del(percentage_key(feature))
  end

  def activate_user(feature, user)
    @redis.sadd(user_key(feature), user.id)
  end

  def deactivate_user(feature, user)
    @redis.srem(user_key(feature), user.id)
  end

  def define_group(group, &block)
    @groups[group.to_s] = block
  end

  def active?(feature, user)
    user_in_active_group?(feature, user) ||
      user_active?(feature, user) ||
        user_within_active_percentage?(feature, user)
  end

  def activate_percentage(feature, percentage)
    @redis.set(percentage_key(feature), percentage)
  end

  def deactivate_percentage(feature)
    @redis.del(percentage_key(feature))
  end

  private
    def key(name)
      "feature:#{name}"
    end

    def group_key(name)
      "#{key(name)}:groups"
    end

    def user_key(name)
      "#{key(name)}:users"
    end

    def percentage_key(name)
      "#{key(name)}:percentage"
    end

    def user_in_active_group?(feature, user)
      @redis.smembers(group_key(feature)).any? { |group| @groups.key?(group) && @groups[group].call(user) }
    end

    def user_active?(feature, user)
      @redis.sismember(user_key(feature), user.id)
    end

    def user_within_active_percentage?(feature, user)
      percentage = @redis.get(percentage_key(feature))
      return false if percentage.nil?

      user.id % 10 < percentage.to_i / 10
    end
end
