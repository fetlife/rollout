module Rollout
  class Feature
    attr_reader :name, :enabled, :variants, :users, :groups
    attr_writer :enabled, :variants, :users, :groups, :url, :internal, :admin, :bucketing, :percentages
    attr_accessor :rollout, :cache

    # Bucketing schemes
    # :uaid, :user, :random

    def initialize(name, string = nil)
      @name = name
      @cache = {}
      if string
        raw_enabled,raw_variants,raw_users,raw_groups,raw_url,raw_internal,raw_admin,raw_bucketing = string.split("|")


        @variants = {}
        (raw_variants || "").split(",").each do |kv|
          key, value = kv.split(":")
          @variants[key.to_sym] = value.to_i
        end

        @enabled = raw_enabled == "true"
        @enabled ||= raw_enabled if raw_enabled != "false"

        @users = (raw_users || "").split(",").map(&:to_s)
        @groups = (raw_groups || "").split(",").map(&:to_sym)

        @url = raw_url if not (raw_url || "").empty?
        @internal = raw_internal == "true"
        @admin = raw_admin == "true"
        @bucketing = raw_bucketing.to_sym if not (raw_bucketing || "").empty?
        @bucketing ||= :uaid
        @percentages = compute_percentages
      else
        clear
      end
    end

    def serialize
      # "#{@percentage}|#{@users.join(",")}|#{@groups.join(",")}"
      parts = []
      parts << @enabled ? 'true' : 'false'
      parts << @variants.map{|k,v| "#{k}:#{v}" }.join(",")
      parts << @users.join(",")
      parts << @groups.join(",")
      parts << @url
      parts << @internal ? 'true' : 'false'
      parts << @admin ? 'true' : 'false'
      parts << @bucketing
      parts.join("|")
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

    def add_user(user)
      @users << user.id.to_s unless @users.include?(user.id.to_s)
    end

    def remove_user(user)
      @users.delete(user.id.to_s)
    end

    def add_group(group)
      @groups << group.to_sym unless @groups.include?(group.to_sym)
    end

    def remove_group(group)
      @groups.delete(group.to_sym)
    end

    def clear
      @enabled = false
      @variants = {}
      @groups = []
      @users = []
      @percentage = 0
      @bucketing = :uaid
      @internal = false
      @url = "feature_#{@name}"
    end

    def active?(user = nil)
      user_id = user.id if user
      user_id ||= rollout.context.user_id
      ret = choose_variant(user_id, false)
      if ret.is_a?(Array)
        sym, selector = ret
        ret = false if sym == :off
      end
      ret
    end

    def to_hash
      {:percentage => @percentage,
        :groups     => @groups,
        :users      => @users}
    end

    def variant?(variant, user_id = nil)
      user_id ||= rollout.context.user_id
      var, selector = choose_variant(user_id, true)
      var == variant
    end


    # private
      def bucketing_id
        ret = nil
        case @bucketing
          when :uaid
          when :random
            uaid = rollout.context.uaid
            # In the RANDOM case we still need a bucketing id to keep
            # the assignment stable within a request.
            # Note that when being run from outside of a web request (e.g. crons),
            # there is no UAID, so we default to a static string
            ret = uaid ? uaid : "no uaid"

          when :user
            user_id = rollout.context.user_id
            # Not clear if this is right. There's an argument to be
            # made that if we're bucketing by userID and the user is
            # not logged in we should treat the feature as disabled.
            ret = (not user_id.nil?) ? user_id  : rollout.context.uaid

          else
            raise "Bad bucketing: #{@bucketing}"
        end
        ret
      end

      def variant_from_url(user_id)
        if @url or @internal or rollout.context.admin?(user_id)
          url_features = rollout.context.features
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
          name = rollout.context.user_name(id)
          if name != nil and @names.include?(name)
            return [:user, 'u']
          end
        end
        false
      end

      def variant_for_group(id)
      end

      def variant_for_admin(id)
        if @admin and rollout.context.admin?(id)
          return [:admin, 'a']
        end
        false
      end

      def variant_for_internal
        if @internal and rollout.context.internal_request
          return [:internal, 'i']
        end
        false
      end

      def variant_by_percentage(id)
        n = 100 * randomish(id)
        @percentages.each do |percent,variant|
          if n < percent or percent == 100
            return [variant.to_sym, 'w']
          end
        end
        false
      end

      def randomish(id)
        @bucketing == :random ? rollout.context.random : rollout.context.hash("#{@name}-#{id}")
      end

      def choose_variant(user_id, in_variant = false)
        # if in_variant and @enabled == true
        #   throw "Variant check when fully enabled"
        # end
        #
        if @enabled.is_a?(String) or @enabled.is_a?(Symbol)
          if @enabled.to_sym == :off
            return false
          elsif @enabled.to_sym == :on
            return true
          end
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
        variant ||= variant_by_percentage(user_id)
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
          rollout.active_in_group?(g, user)
        end
      end

  end
end
