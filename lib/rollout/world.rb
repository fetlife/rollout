class World
  def initialize()
    @digester = Digest::SHA256.new
    @selections = []
    @logger ||= Rails.logger 
  end

  def uaid
    # seesion cookie id
  end

  def user_id
    current_user.id
  end

  def user_name
  end

  def admin?
  end

  def in_group?(user_id, group)
  end

  # Produce a random number in [0, 1] for RANDOM bucketing.
  def random
    rand
  end

  def log(name, variant, selector)
      @selections << [name, variant, selector]
      @logger.info(name, variant, selector)
  end

  def hash(id)
    hex_digest = @digester.hexdigest(@digester.digest(id.to_s))
    puts hex_digest
    map_hex(hex_digest)
  end


  def map_hex(hex)
    len = [40, hex.length].min
    max = 1 << len
    v = 0
    (0...len).each do |i|
      bit = hex[i].hex < 8 ? 0 : 1
      v = (v << 1) + bit
    end
    w = v.to_f / max
    w
  end

end
