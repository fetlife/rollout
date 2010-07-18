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
  end

  def activate_user(feature, user)
    @redis.sadd(user_key(feature), user.id)
  end

  def define_group(group, &block)
    @groups[group.to_s] = block
  end

  def active?(feature, user)
    user_in_active_group?(feature, user) || user_active?(feature, user)
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

    def user_in_active_group?(feature, user)
      @redis.smembers(group_key(feature)).any? { |group| @groups[group].call(user) }
    end

    def user_active?(feature, user)
      @redis.sismember(user_key(feature), user.id)
    end
end
