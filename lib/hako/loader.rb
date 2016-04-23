# frozen_string_literal: true
module Hako
  class Loader
    # @param [Module] base_module
    # @param [String] base_path
    def initialize(base_module, base_path)
      @base_module = base_module
      @base_path = base_path
    end

    # @param [String] name
    # @return [Module]
    def load(name)
      require "#{@base_path}/#{name}"
      @base_module.const_get(camelize(name))
    end

    private

    # @param [String] name
    # @return [String]
    def camelize(name)
      name.split('_').map(&:capitalize).join('')
    end
  end
end
