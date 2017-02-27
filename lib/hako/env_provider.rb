# frozen_string_literal: true
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

    # override this method and return true if validation is available in dry-run mode
    # @return [Boolean]
    def validatable?
      false
    end

    # This method is called when dry-run mode.
    # override this method if validation is available in dry-run mode
    # @return [nil]
    def validate!
      raise NotImplementError.new('Must implement `validate!` method by child class')
    end

    private

    def validation_error!(message)
      raise ValidationError.new(message)
    end
  end
end
