require 'active_support/concern'

module Rollout
  module ContextProvider
    extend ActiveSupport::Concern

    def rollout_context_class
      self.class.rollout_context_class
    end

    def rollout
      raise 'No rollout context available' unless rollout_context_class
      @rollout = rollout_context_class.new(self)
    end

    included do
      helper_method :rollout
    end

    module ClassMethods
      def rollout_context_class
        @rollout_context_class
      end

      def has_rollout_context(klazz)
        raise 'Need a context class' unless klazz
        @rollout_context_class = klazz
      end
    end
  end
end