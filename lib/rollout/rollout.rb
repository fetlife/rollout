module Rollout
  class Roller
    attr_accessor :storage
    attr_accessor :context
    attr_accessor :user_id_method

    def initialize(storage, context, opts = {})
      @storage  = storage
      @context  = context
      @groups = {:all => lambda { |user| true }}
      @user_id_method = opts[:user_id_method] || :id
    end

    def feature(feature)
      f = get(feature)
      if f.enabled?
        f.tap do |f|
          if block_given?
            yield f
          end
        end
      else
        # Worst case, a blank feature
        f
      end
    end

    def set(feature)
      f = get(feature)
      r = f
      if block_given?
        r = yield(f)
        save(f)
      end
      r
    end

    alias_method :[], :feature
    alias_method :with_feature, :set

    def enable(feature, *args)
      if args.last.is_a?(Group)
        group = args.pop
      end
      value = args.pop || :rollout
      set(feature) do |f|
        f.enabled = value
        f.add_group(group) if group
      end
    end
    alias :activate :enable

    def disable(feature)
      set(feature) do |f|
        f.enabled = :off
      end
    end
    alias :deactivate :disable

    def activate_group(feature, group)
      set(feature) do |f|
        f.add_group(group)
      end
    end

    def deactivate_group(feature, group)
      set(feature) do |f|
        f.remove_group(group)
      end
    end

    def activate_user(feature, user)
      set(feature) do |f|
        f.add_user(user)
      end
    end

    def deactivate_user(feature, user)
      set(feature) do |f|
        f.remove_user(user)
      end
    end

    def group(group, &block)
      group = Group.new(group, &block)
      @groups[group.name] = group
      group
    end

    def active?(feature, user = nil)
      set(feature) do |f|
        f.active?(user)
      end
    end
    alias :enabled? :active?

    def activate_percentage(feature, percentage)
      set(feature) do |f|
        f.percentage = percentage
      end
    end

    def deactivate_percentage(feature)
      set(feature) do |f|
        f.percentage = 0
      end
    end

    def active_in_group?(group, user)
      f = @groups[group.to_sym]
      f && f.block.call(user)
    end

    def get(feature)
      string = @storage.get(key(feature))
      Feature.new(self, context, feature, string)
    end

    def new_feature
      Feature.new(self, context)
    end

    def features
      @storage.smembers(features_key).map(&:to_sym)
    end

    def delete(feature)
      @storage.del(key(feature))
      @storage.srem(features_key, feature)
    end

    private
      def key(name)
        "rollout:feature:#{name}"
      end

      def features_key
        "rollout:features"
      end

      def save(feature)
        @storage.set(key(feature.name), feature.serialize)
        @storage.sadd(features_key, feature.name)
      end

  end
end
