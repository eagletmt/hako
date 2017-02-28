# frozen_string_literal: true
require 'hako/env_provider'
require 'yaml'

module Hako
  module EnvProviders
    class Yaml < EnvProvider
      # @param [Pathname] root_path
      # @param [Hash<String, Object>] options
      def initialize(root_path, options)
        unless options['path']
          validation_error!('path must be set')
        end

        @yaml = YAML.load_file root_path.join(options['path'])

        unless @yaml.is_a?(Hash)
          validation_error!('Env yaml root must be Hash')
        end

        @options = options
      end

      # @param [Array<String>] variables
      # @return [Hash<String, String>]
      def ask(variables)
        env = {}
        read_from_yaml do |key, val|
          if variables.include?(key)
            env[key] = val
          end
        end
        env
      end

      # @return [Boolean]
      def can_ask_keys?
        true
      end

      # @param [Array<String>] variables
      # @return [Array<String>]
      def ask_keys(variables)
        keys = []
        read_from_yaml do |key, _|
          if variables.include?(key)
            keys << key
          end
        end
        keys
      end

      private

      # @yieldparam [String] key
      # @yieldparam [String] val
      def read_from_yaml(&block)
        flatten(@yaml).each(&block)
      end

      # @param [Object] obj
      # @param [String] root
      # @param [Hash<String,String>] acc
      # @return [Hash<String, String>]
      def flatten(obj, root = nil, acc = {})
        case obj
        when Array
          ary_sep = @options.fetch('ary_sep', ',')
          acc[root] = obj.join(ary_sep)
        when Hash
          obj.each do |key, value|
            key_sep = @options.fetch('key_sep', '.')
            new_root = [root, key].reject(&:nil?).join(key_sep)
            flatten(value, new_root, acc)
          end
        else
          acc[root] = obj.to_s
        end

        acc
      end
    end
  end
end
