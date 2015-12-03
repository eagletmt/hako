require 'hako/after_scripts'
require 'hako/env_expander'
require 'hako/error'
require 'hako/front_config'
require 'hako/fronts'
require 'hako/schedulers'

module Hako
  class Commander
    PROVIDERS_KEY = '$providers'

    def initialize(app)
      @app = app
      $LOAD_PATH << @app.root_path.join('lib')
    end

    def deploy(force: false, tag: 'latest')
      env = @app.yaml['env'].dup
      providers = load_providers(env.delete(PROVIDERS_KEY) || [])
      env = EnvExpander.new(providers).expand(env)

      front = load_front(@app.yaml['front'])

      scheduler = load_scheduler(@app.yaml['scheduler'])
      app_port = @app.yaml.fetch('port', nil)
      image = @app.yaml.fetch('image') { raise Error.new('image must be set') }
      image_tag = "#{image}:#{tag}"
      after_scripts = @app.yaml.fetch('after_scripts', []).map { |config| load_after_script(config) }

      scheduler.deploy(image_tag, env, app_port, front, force: force)

      after_scripts.each(&:run)
    end

    def status
      load_scheduler(@app.yaml['scheduler']).status
    end

    def remove
      load_scheduler(@app.yaml['scheduler']).remove
    end

    private

    def load_providers(provider_configs)
      provider_configs.map do |config|
        type = config['type']
        unless type
          raise Error.new("type must be set in each #{PROVIDERS_KEY} element")
        end
        require "hako/env_providers/#{type}"
        Hako::EnvProviders.const_get(camelize(type)).new(@app.root_path, config)
      end
    end

    def load_scheduler(scheduler_config)
      type = scheduler_config['type']
      unless type
        raise Error.new('type must be set in scheduler')
      end
      require "hako/schedulers/#{type}"
      Hako::Schedulers.const_get(camelize(type)).new(@app.id, scheduler_config)
    end

    def load_front(yaml)
      front_config = FrontConfig.new(yaml)
      require "hako/fronts/#{front_config.type}"
      Hako::Fronts.const_get(camelize(front_config.type)).new(front_config)
    end

    def load_after_script(config)
      type = config.fetch('type')
      require "hako/after_scripts/#{type}"
      Hako::AfterScripts.const_get(camelize(type)).new(config)
    end

    def camelize(name)
      name.split('_').map(&:capitalize).join('')
    end
  end
end
