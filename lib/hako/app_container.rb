require 'hako/container'

module Hako
  class AppContainer < Container
    def image_tag
      "#{@definition['image']}:#{@definition['tag']}"
    end

    def port
      @definition['port']
    end
  end
end
