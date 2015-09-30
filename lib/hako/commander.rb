require 'yaml'
require 'hako/env_expander'
require 'hako/error'

module Hako
  class Commander
    PROVIDERS_KEY = '$providers'

    def initialize(yaml_path)
      @yaml = YAML.load_file(yaml_path)
    end

    def apply
      env = @yaml['env'].dup
      providers = load_providers(env.delete(PROVIDERS_KEY) || [])
      env = EnvExpander.new(providers).expand(env)
      p env
    end

    private

    def load_providers(provider_configs)
      provider_configs.map do |config|
        type = config['type']
        unless type
          raise Error.new("type must be set in each #{PROVIDERS_KEY} element")
        end
        require "hako/env_providers/#{type}"
        Hako::EnvProviders.const_get(camelize(type)).new(config)
      end
    end

    def camelize(name)
      name.split('_').map(&:capitalize).join('')
    end
  end
end
