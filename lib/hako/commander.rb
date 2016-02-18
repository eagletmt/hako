require 'hako/app_container'
require 'hako/env_expander'
require 'hako/error'
require 'hako/fronts'
require 'hako/schedulers'
require 'hako/scripts'

module Hako
  class Commander
    PROVIDERS_KEY = '$providers'.freeze

    def initialize(app)
      @app = app
    end

    def deploy(force: false, tag: 'latest')
      env = load_environment(@app.yaml['env'])
      app = AppContainer.new(@app.yaml['app'].merge('tag' => tag))
      front = load_front(@app.yaml['front'])
      scheduler = load_scheduler(@app.yaml['scheduler'])
      app_port = @app.yaml.fetch('port', nil)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config) }

      containers = { 'app' => app, 'front' => front }
      scripts.each { |script| script.before_deploy(containers) }
      scheduler.deploy(containers, env, app_port, force: force)
      scripts.each { |script| script.after_deploy(containers) }
    end

    def oneshot(commands, tag: 'latest')
      env = load_environment(@app.yaml['env'])
      app = AppContainer.new(@app.yaml['app'].merge('tag' => tag))
      scheduler = load_scheduler(@app.yaml['scheduler'])
      exit scheduler.oneshot(app, env, commands)
    end

    def status
      load_scheduler(@app.yaml['scheduler']).status
    end

    def remove
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config) }
      load_scheduler(@app.yaml['scheduler']).remove
      scripts.each(&:after_remove)
    end

    private

    def load_environment(env)
      env = env.dup
      providers = load_providers(env.delete(PROVIDERS_KEY) || [])
      EnvExpander.new(providers).expand(env)
    end

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
      type = yaml['type']
      require "hako/fronts/#{type}"
      Hako::Fronts.const_get(camelize(type)).new(@app.id, yaml)
    end

    def load_script(config)
      type = config.fetch('type')
      require "hako/scripts/#{type}"
      Hako::Scripts.const_get(camelize(type)).new(@app, config)
    end

    def camelize(name)
      name.split('_').map(&:capitalize).join('')
    end
  end
end
