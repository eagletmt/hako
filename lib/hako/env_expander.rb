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
      parsed_env = {}
      variables = Set.new
      env.each do |key, val|
        tokens = parse(val.to_s)
        tokens.each do |t|
          if t.is_a?(Variable)
            variables << t.name
          end
        end
        parsed_env[key] = tokens
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

    private

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
