require 'active_support/concern'

module Rollout
  module ContextProvider
    extend ActiveSupport::Concern

    def rollout_context_class
      self.class.rollout_context_class
    end


    def rollout
      raise 'No rollout context available' unless rollout_context_class
      @rollout ||= RolloutClass.new(Rollout.redis, rollout_context_class.new(self))
      @rollout
    end
    
    included do
      class_attribute :rollout_context_class
      delegate :enabled?, :feature, to: :rollout
      helper_method :enabled?, :feature
      helper_method :rollout
    end
  end
end
