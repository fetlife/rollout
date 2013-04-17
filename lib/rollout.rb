require "rollout/legacy"
require "rollout/feature"
require "rollout/world"
require "digest"
require "zlib"

class Rollout
  def initialize(storage, opts = {})
    @storage  = storage
    @groups = {:all => lambda { |user| true }}
    @legacy = Legacy.new(@storage) if opts[:migrate]
  end

  def activate(feature)
    with_feature(feature) do |f|
      f.enabled = true
    end
  end
  alias :enable :activate

  def deactivate(feature)
    with_feature(feature) do |f|
      f.enabled = false
    end
  end
  alias :disable :deactivate

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
    @groups[group.to_sym] = block
  end

  def active?(feature, user = nil)
    feature = get(feature)
    feature.active?(self, user)
  end
  alias :enabled? :active?

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
    f = @groups[group.to_sym]
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
      @storage.set(features_key, (features | [feature.name]).join(","))
    end

    def migrate?
      @legacy
    end

end
