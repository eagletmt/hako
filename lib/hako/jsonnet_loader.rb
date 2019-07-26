# frozen_string_literal: true

require 'hako'
require 'hako/env_providers'
require 'hako/error'
require 'hako/loader'
require 'json'
require 'jsonnet'

module Hako
  class JsonnetLoader
    # @param [Application] application
    # @param [Boolean] expand_variables
    # @param [Boolean] ask_keys
    def initialize(application, expand_variables:, ask_keys:, ext_vars:)
      @vm = Jsonnet::VM.new
      @root_path = application.root_path
      define_provider_functions(expand_variables, ask_keys)
      @vm.ext_var('appId', application.id)
      ext_vars.each { |k, v| @vm.ext_var(k.to_s, v) }
    end

    # @param [Pathname] path
    def load(path)
      JSON.parse(@vm.evaluate_file(path.to_s))
    end

    private

    def define_provider_functions(expand_variables, ask_keys)
      Gem.loaded_specs.each do |gem_name, spec|
        spec.require_paths.each do |path|
          Dir.glob(File.join(spec.full_gem_path, path, 'hako/env_providers/*.rb')).each do |provider_path|
            provider_name = File.basename(provider_path, '.rb')
            provider_class = Loader.new(Hako::EnvProviders, 'hako/env_providers').load(provider_name)
            Hako.logger.debug("Loaded #{provider_class} from '#{gem_name}' gem")
            @vm.define_function("provide.#{provider_name}") do |options, name|
              if expand_variables
                provider_class.new(@root_path, JSON.parse(options)).ask([name]).fetch(name)
              else
                if ask_keys
                  provider = provider_class.new(@root_path, JSON.parse(options))
                  if provider.can_ask_keys?
                    if provider.ask_keys([name]).empty?
                      raise Error.new("Could not lookup #{name} from #{provider_name} provider with options=#{options}")
                    end
                  end
                end
                "${#{name}}"
              end
            end
          end
        end
      end
    end
  end
end
