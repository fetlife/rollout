require "active_support/core_ext/object"
require "active_support/core_ext/hash"

module Rollout
  class Feature
    attr_reader :roller, :name, :enabled, :variants, :users, :groups
    attr_writer :enabled, :variants, :users, :groups, :url, :internal, :admin, :bucketing, :percentages, :percentage
    attr_accessor :context, :cache

    # Bucketing schemes
    # :uaid, :user, :random
    def enable(*args)
      @roller.enable(@name, *args)
    end

    def disable(*args)
      @roller.disable(@name, *args)
    end

    def initialize(roller, name, context, string = nil)
      @roller = roller
      @name = name.to_sym
      @context = context
      @cache = {}

      if not string
        clear
        return
      end

      raw = JSON.parse(string).with_indifferent_access
      @url = raw[:url]
      @variants = raw[:variants] || {}
      @users = raw[:users] || {}
      @groups = raw[:groups] || {}
      @internal = raw[:internal] || false
      @admin = raw[:admin] || false
      @bucketing = (raw[:bucketing] || :uaid).to_sym
      @percentage = raw[:percentage].to_i if raw[:percentage]
      @percentage ||= 0
      @percentages = compute_percentages

      # Can be :on, :off or :rollout
      @enabled = raw[:enabled].to_sym if raw[:enabled].is_a?(String)
      @enabled ||= :on if raw[:enabled] == true || raw[:enabled] == "true" || raw[:enabled] == "True"
      @enabled ||= :off
    end

    def serialize
      {
        enabled: enabled,
        url: @url,
        admin: @admin,
        users: @users,
        groups: @groups,
        internal: @internal,
        variants: @variants,
        percentage: @percentage,
        date_range: @date_range,
        bucketing: @bucketing,
      }.to_json
    end

    def multivariant?
      @variants.length > 0
    end

    def compute_percentages
      total = 0
      percentages = []
      @variants.each do |variant,percent|
        if !percent.is_a?(Integer) or percent < 0 or percent > 100
          throw "Bad percentage #{percent} for variant #{variant}"
        end
        if percent > 0
          total += percent
          percentages << [total, variant]
        end
        if total > 100
          throw "Total of percentages > 100 for variant #{variant}"
        end
      end
      percentages
    end

    def groups
      Hash[@groups.symbolize_keys.map{|k,v| [k, v.map{|x| x.to_sym}]}]
    end

    def users
      @users.symbolize_keys
    end

    def percentage
      @percentage
    end

    def id_from_user(user)
      id = user if user.is_a?(String) or user.is_a?(Numeric)
      id ||= user.send(@roller.user_id_method)
      id
    end

    def add_user(user, variant = :users)
      remove_user(user)
      @users[variant] ||= []
      @users[variant] << id_from_user(user)
      users
    end

    def remove_user(user)
      id = id_from_user(user)
      @users.each do |variant,items|
        @users[variant].delete(id.to_s)
        @users[variant].delete(id.to_i) if id.to_i > 0
      end
      users
    end

    def add_group(group, variant = :groups)
      group = Group.new(group) if not group.is_a?(Group)
      remove_group(group)
      @groups[variant] ||= []
      @groups[variant] << group.name
      # puts "add groups: " + @groups.inspect
      groups
    end

    def remove_group(group)
      group = Group.new(group) if not group.is_a?(Group)
      @groups.each do |variant,items|
        @groups[variant].delete(group.name.to_s)
      end
      groups
    end

    def clear
      @enabled = :off
      @variants = {}
      @groups = {}
      @users = {}
      @percentages = []
      @percentage = 0
      @bucketing = :uaid
      @internal = false
      @url = "feature_#{@name}"
    end

    def active?(user = nil)
      user_id = id_from_user(user) if user
      # puts "active? user_id: #{user_id}"
      user_id ||= context.user_id
      ret = choose_variant(user_id, false)
      # puts ret.inspect
      if ret.is_a?(Array)
        sym, selector = ret
        ret = false if sym == :off
      end
      ret
    end

    def to_hash
      {
        percentage: @percentage,
        groups: groups,
        users: users
      }
    end

    def variant
      choose_variant(nil, true)[0]
    end

    def variant?(variant, user_id = nil)
      user_id ||= context.user_id
      var, selector = choose_variant(user_id, true)
      var == variant
    end

    def method_missing(method_name, *arguments)
      if method_name.to_s[-1,1] == "?"
        variant_name_to_check = method_name.to_s[0..-2]
        #find which variant, compare to variant_name_to_check
        user_id ||= context.user_id
        variant?(variant_name_to_check.to_sym)
      else
        super
      end
    end


    # private
      def bucketing_id
        ret = nil
        case @bucketing
          when :uaid
          when :random
            uaid = context.uaid
            # In the RANDOM case we still need a bucketing id to keep
            # the assignment stable within a request.
            # Note that when being run from outside of a web request (e.g. crons),
            # there is no UAID, so we default to a static string
            ret = uaid ? uaid : "no uaid"

          when :user
            user_id = context.user_id
            # Not clear if this is right. There's an argument to be
            # made that if we're bucketing by userID and the user is
            # not logged in we should treat the feature as disabled.
            ret = (not user_id.nil?) ? user_id  : context.uaid

          else
            raise "Bad bucketing: #{@bucketing}"
        end
        ret
      end

      def variant_from_url(user_id)
        if @url or @internal or context.admin?(user_id)
          url_features = context.features
          if url_features
            url_features.split(/,/).each do |f|
              parts = f.split(/:/)
              # puts "#{url_features} = #{parts.inspect} = #{@name.to_sym}"
              if parts.first.to_sym == @name.to_sym
                return [(parts[1].nil? or parts[1].empty?) ? :on : parts[1].to_sym, 'o']
              end
            end
          end
        end
        false
      end

      def variant_for_user(id)
        if @users.length > 0
          name = context.user_name
          id ||= context.user_id
          ret = false
          # puts "users: " + @users.inspect
          @users.each do |variant, list|
            # puts "list: " + list.inspect
            if name != nil and list.include?(name)
              ret = [variant.to_sym, 'u'] 
            elsif id != nil and (list.include?(id.to_s) or (id.to_i > 0 and list.include?(id.to_i)))
              ret = [variant.to_sym, 'u'] 
            end
            return ret if ret != false
          end
        end
        false
      end

      def variant_for_group(id)
        # puts "groups are now: " + @groups.inspect
        if @groups.length > 0
          id ||= context.user_id
          @groups.each do |variant, list|
            # puts "#{variant}: " + list.inspect
            if id != nil and context.in_group?(id, list)
              ret = [variant.to_sym, 'g'] 
              return ret
            end
          end
        end
        false
      end

      def variant_for_admin(id)
        if @admin and context.admin?(id)
          return [:admin, 'a']
        end
        false
      end

      def variant_for_internal
        if @internal and context.internal_request
          return [:internal, 'i']
        end
        false
      end

      def variant_by_percentage(id, in_variant = false)
        n = 100 * randomish(id)
        @percentages.each do |percent,variant|
          if n < percent or percent == 100
            return [variant.to_sym, 'w']
          end
        end
        if not in_variant && enabled_status == :rollout
          # puts "percentage: #{@percentage} n: #{n}"
          if n < @percentage or @percentage == 100
            return [@name.to_sym, 'w']
          end
        end
        false
      end

      def randomish(id)
        @bucketing == :random ? context.random : context.hash("#{@name}-#{id}")
      end

      # status one of these [:off, :on, :rollout]
      def enabled_status
        if @enabled.is_a?(String) or @enabled.is_a?(Symbol)
          if @enabled.to_sym == :off
            return :off
          elsif @enabled.to_sym == :on
            return :on
          end
        end
        :rollout
      end

      def choose_variant(user_id, in_variant = false)
        # if in_variant and @enabled == true
        #   throw "Variant check when fully enabled"
        # end
        #
        status = enabled_status
        if status == :off
          return false
        elsif status == :on
          return true
        end

        bucket_id = bucketing_id

        if @cache.include?(bucket_id)
          # Note that this caching is not just an optimization:
          # it prevents us from double logging a single
          # feature--we only want to log each distinct checked
          # feature once.
          #
          # The caching also affects the semantics when we use
          # random bucketing (rather than hashing the id), i.e.
          # 'random' => 'true', by making the variant and
          # enabled status stable within a request.
          return @cache[bucket_id]
        end

        variant = variant_from_url(user_id)
        variant ||= variant_for_user(user_id)
        variant ||= variant_for_group(user_id)
        variant ||= variant_for_admin(user_id)
        variant ||= variant_for_internal
        variant ||= variant_by_percentage(user_id, multivariant?)
        variant ||= [:off, 'w']

        # puts variant.inspect

        @cache[bucket_id] = variant
      end

    private

      def user_in_active_users?(user)
        @users.include?(user.id.to_s)
      end

      def user_in_active_group?(user, rollout)
        @groups.any? do |g|
          active_in_group?(g, user)
        end
      end

  end
end
