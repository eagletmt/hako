# frozen_string_literal: true
require 'set'
require 'strscan'
require 'hako/env_providers'
require 'hako/error'

module Hako
  class EnvExpander
    class ExpansionError < Error
    end

    Literal = Struct.new(:literal)
    Variable = Struct.new(:name)

    # @param [Array<EnvProvider>] providers
    def initialize(providers)
      @providers = providers
    end

    # @param [Hash<String, String>] env
    # @return [Hash<String, String>]
    def expand(env)
      parsed_env = parse_env(env)
      variables = Set.new
      parsed_env.each_value do |tokens|
        tokens.each do |t|
          if t.is_a?(Variable)
            variables << t.name
          end
        end
      end

      values = {}
      @providers.each do |provider|
        if variables.empty?
          break
        end
        provider.ask(variables.to_a).each do |var, val|
          values[var] = val
          variables.delete(var)
        end
      end
      unless variables.empty?
        raise ExpansionError.new("Could not resolve embedded variables from $providers=#{@providers}: #{variables.to_a}")
      end

      expanded_env = {}
      parsed_env.each do |key, tokens|
        expanded_env[key] = tokens.map { |t| expand_value(values, t) }.join('')
      end
      expanded_env
    end

    # @param [Hash<String, String>] env
    # @return [Boolean]
    def validate!(env)
      parsed_env = parse_env(env)
      variables = Set.new
      parsed_env.each_value do |tokens|
        tokens.each do |t|
          if t.is_a?(Variable)
            variables << t.name
          end
        end
      end

      @providers.each do |provider|
        if variables.empty?
          break
        end
        if provider.can_ask_keys?
          provider.ask_keys(variables.to_a).each do |var|
            variables.delete(var)
          end
        else
          Hako.logger.warn("EnvProvider#validate! is skipped because #{provider.class} doesn't support ask_keys method")
          return false
        end
      end
      unless variables.empty?
        raise ExpansionError.new("Could not find embedded variables from $providers=#{@providers}: #{variables.to_a}")
      end
      true
    end

    private

    # @param [Hash<String, String>] env
    # @return [Hash<String, Array<Literal, Variable>>]
    def parse_env(env)
      parsed_env = {}
      env.each do |key, val|
        parsed_env[key] = parse(val.to_s)
      end
      parsed_env
    end

    # @param [String] value
    # @return [Array]
    def parse(value)
      s = StringScanner.new(value)
      tokens = []
      pos = 0
      while s.scan_until(/#\{(.*?)\}/)
        pre = s.string.byteslice(pos...(s.pos - s.matched.size))
        var = s[1]
        unless pre.empty?
          tokens << Literal.new(pre)
        end
        if var.empty?
          raise ExpansionError.new('Empty interpolation is not allowed')
        else
          tokens << Variable.new(var)
        end
        pos = s.pos
      end
      unless s.rest.empty?
        tokens << Literal.new(s.rest)
      end
      tokens
    end

    def expand_value(values, token)
      case token
      when Literal
        token.literal
      when Variable
        values.fetch(token.name)
      else
        raise ExpansionError.new("Unknown token type: #{token.class}")
      end
    end
  end
end
