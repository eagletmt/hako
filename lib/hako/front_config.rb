module Hako
  class FrontConfig < Struct.new(:image_tag)
    def initialize(options)
      self.image_tag = options.fetch('image_tag')
    end
  end
end
