require 'redis'
require 'logger'
require 'rollout'

class Rollout::NullContext < Rollout::Context
  def self.rollout
    Rollout::Roller.new(Redis.new, Rollout::NullContext.new(nil, logger: Logger.new(STDOUT)))
  end

  def uaid; SecureRandom.hex; end
  def user_id; 0; end
  def user_name; ""; end
  def admin?(id); false; end
  def in_group?(user_id, groups)
    false
  end
  def features; ""; end
  def internal_request; false; end
end
