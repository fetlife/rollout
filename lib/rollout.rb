class Rollout
  def initialize(redis)
    @redis  = redis
    @groups = {"all" => lambda { |user| true }}
  end

  def activate(feature, group)
    @redis.sadd(key(feature), group)
  end

  def deactivate(feature, group)
    @redis.srem(key(feature), group)
  end

  def deactivate_all(feature)
    @redis.del(key(feature))
  end

  def define_group(group, &block)
    @groups[group.to_s] = block
  end

  def active?(feature, user)
    @redis.smembers(key(feature)).any? { |group| @groups[group].call(user) }
  end

  private
    def key(name)
      "feature:#{name}"
    end
end
