# frozen_string_literal: true
require 'hako/app_container'
require 'hako/container'
require 'hako/env_expander'
require 'hako/error'
require 'hako/fronts'
require 'hako/loader'
require 'hako/schedulers'
require 'hako/scripts'

module Hako
  class Commander
    def initialize(app)
      @app = app
    end

    def deploy(force: false, tag: 'latest', dry_run: false)
      containers = load_containers(tag, dry_run: dry_run)
      scheduler = load_scheduler(@app.yaml['scheduler'], force: force, dry_run: dry_run)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }

      scripts.each { |script| script.before_deploy(containers) }
      scheduler.deploy(containers)
      scripts.each { |script| script.after_deploy(containers) }
    end

    def oneshot(commands, tag: 'latest')
      app = AppContainer.new(@app, @app.yaml['app'].merge('tag' => tag), dry_run: false)
      scheduler = load_scheduler(@app.yaml['scheduler'])
      exit scheduler.oneshot(app, commands)
    end

    def status
      load_scheduler(@app.yaml['scheduler']).status
    end

    def remove
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      load_scheduler(@app.yaml['scheduler']).remove
      scripts.each(&:after_remove)
    end

    private

    def load_containers(tag, dry_run:)
      app = AppContainer.new(@app, @app.yaml['app'].merge('tag' => tag), dry_run: dry_run)
      front = load_front(@app.yaml['front'], dry_run: dry_run)

      containers = { 'app' => app, 'front' => front }
      @app.yaml.fetch('additional_containers', {}).each do |name, container|
        containers[name] = Container.new(@app, container, dry_run: dry_run)
      end
      containers
    end

    def load_scheduler(yaml, force: false, dry_run: false)
      Loader.new(Hako::Schedulers, 'hako/schedulers').load(yaml.fetch('type')).new(@app.id, yaml, force: force, dry_run: dry_run)
    end

    def load_front(yaml, dry_run:)
      Loader.new(Hako::Fronts, 'hako/fronts').load(yaml.fetch('type')).new(@app, yaml, dry_run: dry_run)
    end

    def load_script(yaml, dry_run:)
      Loader.new(Hako::Scripts, 'hako/scripts').load(yaml.fetch('type')).new(@app, yaml, dry_run: dry_run)
    end
  end
end
