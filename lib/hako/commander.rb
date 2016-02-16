require 'hako/container'
require 'hako/env_expander'
require 'hako/error'
require 'hako/front_config'
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
      front = load_front(@app.yaml['front'])
      scheduler = load_scheduler(@app.yaml['scheduler'])
      app_port = @app.yaml.fetch('port', nil)
      image = @app.yaml.fetch('image') { raise Error.new('image must be set') }
      app = Container.new(
        'image_tag' => "#{image}:#{tag}",
        'docker_labels' => @app.yaml.fetch('docker_labels', {}),
      )
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config) }

      scripts.each { |script| script.before_deploy(app) }
      scheduler.deploy(app, env, app_port, front, force: force)
      scripts.each { |script| script.after_deploy(app) }
    end

    def oneshot(commands, tag: 'latest')
      env = load_environment(@app.yaml['env'])
      scheduler = load_scheduler(@app.yaml['scheduler'])
      image = @app.yaml.fetch('image') { raise Error.new('image must be set') }
      image_tag = "#{image}:#{tag}"
      exit scheduler.oneshot(Container.new('image_tag' => image_tag), env, commands)
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
      front_config = FrontConfig.new(yaml)
      require "hako/fronts/#{front_config.type}"
      Hako::Fronts.const_get(camelize(front_config.type)).new(front_config)
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
