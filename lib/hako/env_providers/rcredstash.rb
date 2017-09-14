# frozen_string_literal: true

require 'hako/env_provider'
require 'rcredstash'

module Hako
  module EnvProviders
    class Rcredstash < EnvProvider
      # @param [Pathname] root_path
      # @param [Hash<String, Object>] options
      def initialize(root_path, options)
        @client = options['client'] || CredStash
      end

      # @param [Array<String>] variables
      # @return [Hash<String, String>]
      def ask(variables)
        env = {}
        variables.each do |key|
          val = get_value_from_credstash(key)
          if val
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
        read_keys_from_credstash.each do |key, _|
          if variables.include?(key)
            keys << key
          end
        end
        keys
      end

      private

      # @return [Hash<String, Integer>]
      def read_keys_from_credstash()
        @client.list
      end

      # @param [String] key
      # @return [String]
      def get_value_from_credstash(key)
        @client.get(key)
      end
    end
  end
end
