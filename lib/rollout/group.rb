module Rollout
  class Group
    attr_reader :name

    def initialize(name, &block)
      @name = name.to_sym
      @block = block
    end
  end
end
