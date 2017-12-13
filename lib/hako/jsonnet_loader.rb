# frozen_string_literal: true

require 'hako'
require 'hako/env_providers'
require 'hako/loader'
require 'json'
require 'jsonnet'

module Hako
  class JsonnetLoader
    # @param [Application] application
    # @param [Boolean] expand_variables
    def initialize(application, expand_variables)
      @vm = Jsonnet::VM.new
      @root_path = application.root_path
      define_provider_functions(expand_variables)
      @vm.ext_var('appId', application.id)
    end

    # @param [Pathname] path
    def load(path)
      JSON.parse(@vm.evaluate_file(path.to_s))
    end

    private

    def define_provider_functions(expand_variables)
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
                "\#{#{name}}"
              end
            end
          end
        end
      end
    end
  end
end
