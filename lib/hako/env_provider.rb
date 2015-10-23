require 'hako/error'

module Hako
  class EnvProvider
    class ValidationError < Error
    end

    def initialize(_root_path, _options)
      raise NotImplementedError
    end

    def ask(_variables)
      raise NotImplementedError
    end

    private

    def validation_error!(message)
      raise ValidationError.new(message)
    end
  end
end
