# frozen_string_literal: true

require 'hako/container'

module Hako
  class AppContainer < Container
    # @return [String]
    def image_tag
      "#{@definition['image']}:#{@definition['tag']}"
    end
  end
end
