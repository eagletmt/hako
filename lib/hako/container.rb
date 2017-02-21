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
      memory_reservation
      links
      port_mappings
      command
      user
      privileged
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

    # @return [Hash, nil]
    def log_configuration
      if @definition.key?('log_configuration')
        conf = @definition['log_configuration']
        {
          log_driver: conf.fetch('log_driver'),
          options: conf.fetch('options'),
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
      providers = load_providers(provider_types)
      if @dry_run && providers.any? { |provider| !provider.dry_run_available? }
        env
      else
        EnvExpander.new(providers).expand(env)
      end
    end

    # @param [Array<Hash>] provider_configs
    # @return [Array<EnvProvider>]
    def load_providers(provider_configs)
      provider_configs.map do |yaml|
        provider = Loader.new(Hako::EnvProviders, 'hako/env_providers').load(yaml.fetch('type')).new(@app.root_path, yaml)
        if @dry_run && provider.dry_run_available?
          provider.dry_run!
        end
        provider
      end
    end

    # @return [Hash]
    def default_config
      {
        'cpu' => 0,
        'env' => {},
        'docker_labels' => {},
        'links' => [],
        'mount_points' => [],
        'port_mappings' => [],
        'volumes_from' => [],
        'privileged' => false,
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
