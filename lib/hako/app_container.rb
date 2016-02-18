require 'hako/container'

module Hako
  class AppContainer < Container
    def image_tag
      "#{@definition['image']}:#{@definition['tag']}"
    end
  end
end
