class Rollout
  class PersistentGroups
    PERSISTENT_GROUPS_KEY = 'feature:__persistent_groups__'.freeze
    STORAGE_SEPARATOR_CHAR = ','.freeze

    def initialize(storage, cache_age = 60)
      @storage = storage
      @cache_age = cache_age
    end

    def include_in_groups?(groups, user_identifier)
      groups.any? do |group|
        include_in_group?(group, user_identifier)
      end
    end

    def include_in_group?(group, user_identifier)
      group = group.to_s
      user_identifier = user_identifier.to_s
      refresh_persistent_groups
      @groups[group] && @groups[group].include?(user_identifier)
    end

    def set_persistent_group(group, user_identifiers)
      raise 'user_identifiers must be an Array' unless user_identifiers.is_a?(Array)

      @groups[group] = user_identifiers
      save_persistent_group(group)
    end

    def remove_persistent_group(group)
      @groups[group].delete(group)
      save_persistent_group(group)
    end

    private

    def refresh_persistent_groups
      current_time = Time.now.to_i
      if !@last_query_time || @last_query_time + @cache_age < current_time
        @groups = get_persistent_groups
        @last_query_time = current_time
      end
    end

    def get_persistent_groups
      raw_groups = @storage.hgetall(PERSISTENT_GROUPS_KEY)
      return {} if raw_groups.nil?

      raw_groups.each {|key, val| raw_groups[key] = val.split(STORAGE_SEPARATOR_CHAR) }
    end

    def save_persistent_group(group_name)
      group = @groups[group_name]
      @storage.hset(PERSISTENT_GROUPS_KEY, group_name, group.join(STORAGE_SEPARATOR_CHAR))
    end
  end
end
