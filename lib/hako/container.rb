# frozen_string_literal: true
require 'hako/version'

module Hako
  class Container
    attr_reader :definition

    def initialize(app, definition, dry_run:)
      @app = app
      @definition = default_config.merge(definition)
      @definition['docker_labels'].merge!(default_labels)
      @dry_run = dry_run
    end

    %w[
      image_tag
      docker_labels
      cpu
      memory
      links
    ].each do |name|
      define_method(name) do
        @definition[name]
      end

      define_method("#{name}=") do |val|
        @definition[name] = val
      end
    end

    def env
      @expanded_env ||= expand_env(@definition.fetch('env', {}))
    end

    private

    PROVIDERS_KEY = '$providers'

    def expand_env(env)
      env = env.dup
      provider_types = env.delete(PROVIDERS_KEY) || []
      if @dry_run
        env
      else
        providers = load_providers(provider_types)
        EnvExpander.new(providers).expand(env)
      end
    end

    def load_providers(provider_configs)
      provider_configs.map do |yaml|
        Loader.new(Hako::EnvProviders, 'hako/env_providers').load(yaml.fetch('type')).new(@app.root_path, yaml)
      end
    end

    def default_config
      {
        'docker_labels' => {},
        'links' => [],
      }
    end

    def default_labels
      {
        'cc.wanko.hako.version' => VERSION,
      }
    end
  end
end
