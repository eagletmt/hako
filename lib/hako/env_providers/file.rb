# frozen_string_literal: true
require 'hako/env_provider'

module Hako
  module EnvProviders
    class File < EnvProvider
      # @param [Pathname] root_path
      # @param [Hash<String, Object>] options
      def initialize(root_path, options)
        unless options['path']
          validation_error!('path must be set')
        end
        @path = root_path.join(options['path'])
      end

      # @param [Array<String>] variables
      # @return [Hash<String, String>]
      def ask(variables)
        env = {}
        read_from_file do |key, val|
          if variables.include?(key)
            env[key] = val
          end
        end
        env
      end

      private

      # @yieldparam [String] key
      # @yieldparam [String] val
      # @return [nil]
      def read_from_file(&block)
        ::File.open(@path) do |f|
          f.each_line do |line|
            line.chomp!
            line.lstrip!
            if line[0] == '#'
              # line comment
              next
            end
            key, val = line.split('=', 2)
            if val
              block.call(key, val)
            end
          end
        end
      end
    end
  end
end
