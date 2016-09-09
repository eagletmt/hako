# frozen_string_literal: true
require 'hako/version'

module Hako
  class Container
    # @!attribute [r] definition
    #   @return [Hash]
    attr_reader :definition

    # @param [Application] app
    # @param [Hash] definition
    # @param [Boolean] dry_run
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
      port_mappings
      command
      user
    ].each do |name|
      define_method(name) do
        @definition[name]
      end

      define_method("#{name}=") do |val|
        @definition[name] = val
      end
    end

    # @return [Hash<String, String>]
    def env
      @expanded_env ||= expand_env(@definition.fetch('env'))
    end

    # @return [Array<Hash>]
    def mount_points
      @definition['mount_points'].map do |mount_point|
        {
          source_volume: mount_point.fetch('source_volume'),
          container_path: mount_point.fetch('container_path'),
          read_only: mount_point.fetch('read_only', false),
        }
      end
    end

    # @return [Array<Hash>]
    def volumes_from
      @definition['volumes_from'].map do |volumes_from|
        {
          source_container: volumes_from.fetch('source_container'),
          read_only: volumes_from.fetch('read_only', false),
        }
      end
    end

    private

    PROVIDERS_KEY = '$providers'

    # @param [Hash<String, String>] env
    # @return [Hash<String, String>]
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

    # @param [Array<Hash>] provider_configs
    # @return [Array<EnvProvider>]
    def load_providers(provider_configs)
      provider_configs.map do |yaml|
        Loader.new(Hako::EnvProviders, 'hako/env_providers').load(yaml.fetch('type')).new(@app.root_path, yaml)
      end
    end

    # @return [Hash]
    def default_config
      {
        'env' => {},
        'docker_labels' => {},
        'links' => [],
        'mount_points' => [],
        'port_mappings' => [],
        'volumes_from' => [],
      }
    end

    # @return [Hash<String, String>]
    def default_labels
      {
        'cc.wanko.hako.version' => VERSION,
      }
    end
  end
end
