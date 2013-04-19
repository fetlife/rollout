require 'singleton'

class NoFeature
  include Singleton
  
  def enabled?
    false
  end

  def method_missing(method_name, *arguments)
    if method_name.to_s[-1,1] == "?"
      false
    else
      super
    end
  end
end

