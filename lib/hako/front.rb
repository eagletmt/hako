module Hako
  class Front
    attr_reader :config

    def initialize(front_config)
      @config = front_config
    end

    def generate_config(_app_port)
      raise NotImplementedError
    end
  end
end
