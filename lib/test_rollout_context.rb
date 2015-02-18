class TestRolloutContext < Rollout::Context
  def self.rollout
    Rollout::Roller.new(Redis.new, TestRolloutContext.new(nil, logger: Logger.new(STDOUT)))
  end

  def uaid; SecureRandom.hex; end
  def user_id; 1234; end
  def user_name; "test@tester.com"; end
  def admin?; false; end
  def in_group?(user_id, groups)
    # puts "in_group? #{user_id}," + groups.inspect
    ret = false
    groups.each do |group|
      if group.to_sym == :fivesonly
        ret = user_id % 5 == 0
      elsif group.to_sym == :admins
        ret = user_id == 5
      elsif group.to_sym == :fake
        ret = false
      elsif group.to_sym == :all
        ret = true
      end
    end
    ret
  end
  def features; ""; end
end
