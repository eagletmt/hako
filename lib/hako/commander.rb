require 'hako/app_container'
require 'hako/env_expander'
require 'hako/error'
require 'hako/fronts'
require 'hako/loader'
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
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config) }

      containers = { 'app' => app, 'front' => front }
      scripts.each { |script| script.before_deploy(containers) }
      scheduler.deploy(containers, env, force: force)
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
      provider_configs.map do |yaml|
        Loader.new(Hako::EnvProviders, 'hako/env_providers').load(yaml.fetch('type')).new(@app.root_path, yaml)
      end
    end

    def load_scheduler(yaml)
      Loader.new(Hako::Schedulers, 'hako/schedulers').load(yaml.fetch('type')).new(@app.id, yaml)
    end

    def load_front(yaml)
      Loader.new(Hako::Fronts, 'hako/fronts').load(yaml.fetch('type')).new(@app.id, yaml)
    end

    def load_script(yaml)
      Loader.new(Hako::Scripts, 'hako/scripts').load(yaml.fetch('type')).new(@app, yaml)
    end
  end
end
