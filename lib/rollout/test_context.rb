require 'redis'
require 'logger'
require 'rollout'

class Rollout::TestContext < Rollout::Context
  def self.rollout
    Rollout::Roller.new(Redis.new, Rollout::TestContext.new(nil, logger: Logger.new(STDOUT)))
  end

  def uaid; SecureRandom.hex; end
  def user_id; 1; end
  def user_name; "test@tester.com"; end
  def admin?(id); false; end
  def in_group?(user_id, groups)
    # puts "in_group? #{user_id}," + groups.inspect
    ret = false
    groups.each do |group|
      if group == :fivesonly
        ret = user_id % 5 == 0
      elsif group == :admins
        ret = user_id == 5
      elsif group == :fake
        ret = false
      elsif group == :all
        ret = true
      end
    end
    ret
  end
  def features; ""; end
  def internal_request; false; end
end
