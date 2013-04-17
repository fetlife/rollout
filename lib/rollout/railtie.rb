require 'rollout/context_provider'

module Rollout
  class Railtie < Rails::Railtie
    initializer 'rollout.controller_extension' do
      ActionController::Base.send(:include, Rollout::ContextProvider)
    end
  end
end