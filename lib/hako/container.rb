# frozen_string_literal: true

require 'hako/env_expander'
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
      essential
      entry_point
      command
      user
      privileged
      readonly_root_filesystem
      docker_security_options
      system_controls
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

    # @return [Array<Hash>, nil]
    def secrets
      if @definition['secrets']
        @definition['secrets'].map do |secret|
          {
            name: secret.fetch('name'),
            value_from: secret.fetch('value_from'),
          }
        end
      end
    end

    # @return [Array<Hash>]
    def port_mappings
      @definition['port_mappings'].map do |port_mapping|
        {
          container_port: port_mapping.fetch('container_port'),
          host_port: port_mapping.fetch('host_port'),
          protocol: port_mapping.fetch('protocol', 'tcp'),
        }
      end
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

    # @return[Hash, nil]
    def health_check
      if @definition.key?('health_check')
        conf = @definition['health_check']
        ret = {
          command: conf.fetch('command'),
          interval: conf.fetch('interval', 30),
          retries: conf.fetch('retries', 3),
          timeout: conf.fetch('timeout', 5),
        }

        if conf.key?('start_period')
          ret[:start_period] = conf.fetch('start_period')
        end

        ret
      end
    end

    # @return [Array<Hash>, nil]
    def ulimits
      if @definition.key?('ulimits')
        @definition['ulimits'].map do |ulimit|
          {
            name: ulimit.fetch('name'),
            soft_limit: ulimit.fetch('soft_limit'),
            hard_limit: ulimit.fetch('hard_limit'),
          }
        end
      end
    end

    # @return [Array<Hash>, nil]
    def extra_hosts
      if @definition.key?('extra_hosts')
        @definition['extra_hosts'].map do |extra_host|
          {
            hostname: extra_host.fetch('hostname'),
            ip_address: extra_host.fetch('ip_address'),
          }
        end
      end
    end

    # @return [Hash, nil]
    def linux_parameters
      if @definition.key?('linux_parameters')
        ret = {}
        conf = @definition['linux_parameters']

        if conf.key?('capabilities')
          cap = conf['capabilities']
          ret[:capabilities] = {
            add: cap.fetch('add', []),
            drop: cap.fetch('drop', [])
          }
        end

        if conf.key?('devices')
          ret[:devices] = conf['devices'].map do |d|
            {
              host_path: d.fetch('host_path'),
              container_path: d.fetch('container_path', nil),
              permissions: d.fetch('permissions', [])
            }
          end
        end

        ret[:init_process_enabled] = conf.fetch('init_process_enabled', nil)

        ret[:shared_memory_size] = conf.fetch('shared_memory_size', nil)

        if conf.key?('tmpfs')
          ret[:tmpfs] = conf['tmpfs'].map do |t|
            {
              container_path: t.fetch('container_path'),
              mount_options: t.fetch('mount_options', []),
              size: t.fetch('size')
            }
          end
        end

        ret
      end
    end

    # @return [Array<Hash>, nil]
    def system_controls
      if @definition.key?('system_controls')
        @definition['system_controls'].map do |system_control|
          {
            namespace: system_control.fetch('namespace'),
            value: system_control.fetch('value'),
          }
        end
      end
    end

    def depends_on
      if @definition.key?('depends_on')
        @definition['depends_on'].map do |depends_on|
          {
            container_name: depends_on.fetch('container_name'),
            condition: depends_on.fetch('condition'),
          }
        end
      end
    end

    # @return [Hash, nil]
    def repository_credentials
      if @definition.key?('repository_credentials')
        {
          credentials_parameter: @definition['repository_credentials'].fetch('credentials_parameter'),
        }
      end
    end

    # @return [Array, nil]
    def resource_requirements
      if @definition.key?('resource_requirements')
        @definition['resource_requirements'].map do |rr|
          {
            type: rr.fetch('type'),
            value: rr.fetch('value'),
          }
        end
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
      expander = EnvExpander.new(providers)
      if @dry_run
        expander.validate!(env)
        env
      else
        expander.expand(env)
      end
    end

    # @param [Array<Hash>] provider_configs
    # @return [Array<EnvProvider>]
    def load_providers(provider_configs)
      provider_configs.map do |provider_config|
        Loader.new(Hako::EnvProviders, 'hako/env_providers').load(provider_config.fetch('type')).new(@app.root_path, provider_config)
      end
    end

    # @return [Hash]
    def default_config
      {
        'cpu' => 0,
        'env' => {},
        'docker_labels' => {},
        'links' => [],
        'essential' => true,
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
