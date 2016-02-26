# frozen_string_literal: true
module Hako
  class Loader
    def initialize(base_module, base_path)
      @base_module = base_module
      @base_path = base_path
    end

    def load(name)
      require "#{@base_path}/#{name}"
      @base_module.const_get(camelize(name))
    end

    private

    def camelize(name)
      name.split('_').map(&:capitalize).join('')
    end
  end
end
