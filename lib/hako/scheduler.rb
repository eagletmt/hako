module Hako
  class Scheduler
    class ValidationError < Error
    end

    def initialize(_app_id, _options)
    end

    def deploy(_image_tag, _port_mappings)
      raise NotImplementedError
    end

    private

    def validation_error!(message)
      raise ValidationError.new(message)
    end
  end
end
