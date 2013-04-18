require 'active_support/concern'

module Rollout
  module ContextProvider
    extend ActiveSupport::Concern

    def rollout_context_class
      self.class.rollout_context_class
    end

    def rollout_context
      raise 'No rollout context available' unless rollout_context_class
      @rollout_context ||= rollout_context_class.new(self)
    end

    def rollout
      redis = Redis.new
      @rollout ||= RolloutClass.new(redis, rollout_context)
      @rollout
    end

    included do
      class_attribute :rollout_context_class
      helper_method :rollout_context
      helper_method :rollout
    end
  end
end
