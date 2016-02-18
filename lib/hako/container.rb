module Hako
  class Container
    DEFAULT_CONFIG = {
      'docker_labels' => {},
    }.freeze

    def initialize(definition)
      @definition = definition.merge(DEFAULT_CONFIG)
    end

    %w[
      image_tag
      docker_labels
      cpu
      memory
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

    PROVIDERS_KEY = '$providers'.freeze

    def expand_env(env)
      env = env.dup
      providers = load_providers(env.delete(PROVIDERS_KEY) || [])
      EnvExpander.new(providers).expand(env)
    end

    def load_providers(provider_configs)
      provider_configs.map do |yaml|
        Loader.new(Hako::EnvProviders, 'hako/env_providers').load(yaml.fetch('type')).new(@app.root_path, yaml)
      end
    end
  end
end
