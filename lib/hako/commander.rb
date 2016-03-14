# frozen_string_literal: true
require 'hako/app_container'
require 'hako/container'
require 'hako/env_expander'
require 'hako/error'
require 'hako/fronts'
require 'hako/loader'
require 'hako/schedulers'
require 'hako/scripts'
require 'set'

module Hako
  class Commander
    def initialize(app)
      @app = app
    end

    def deploy(force: false, tag: 'latest', dry_run: false)
      containers = load_containers(tag, dry_run: dry_run)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      scheduler = load_scheduler(@app.yaml['scheduler'], scripts, force: force, dry_run: dry_run)

      scripts.each { |script| script.before_deploy(containers) }
      scheduler.deploy(containers)
      scripts.each { |script| script.after_deploy(containers) }
    end

    def oneshot(commands, tag:, containers:, env: {}, dry_run: false)
      containers = load_containers(tag, dry_run: dry_run, with: containers)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      scheduler = load_scheduler(@app.yaml['scheduler'], scripts, dry_run: dry_run)

      exit_code = with_oneshot_signal_handlers(scheduler) do
        scheduler.oneshot(containers, commands, env)
      end
      exit exit_code
    end

    def status
      load_scheduler(@app.yaml['scheduler'], []).status
    end

    def remove
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      load_scheduler(@app.yaml['scheduler'], scripts).remove
      scripts.each(&:after_remove)
    end

    private

    TRAP_SIGNALS = %i[INT TERM].freeze
    class SignalTrapped < StandardError; end

    def with_oneshot_signal_handlers(scheduler, &block)
      old_handlers = {}
      trapped = false
      exit_code = nil

      begin
        TRAP_SIGNALS.each do |sig|
          old_handlers[sig] = Signal.trap(sig) { raise SignalTrapped }
        end
        exit_code = block.call
      rescue SignalTrapped
        trapped = true
      ensure
        old_handlers.each do |sig, command|
          Signal.trap(sig, command)
        end
      end

      if trapped
        exit_code = scheduler.stop_oneshot
      end

      exit_code
    end

    def load_containers(tag, dry_run:, with: nil)
      additional_containers = @app.yaml.fetch('additional_containers', {})
      container_names = ['app']
      if with
        container_names.concat(with)
      else
        if @app.yaml.key?('front')
          container_names << 'front'
        end
        container_names.concat(additional_containers.keys)
      end

      load_containers_from_name(tag, container_names, additional_containers, dry_run: dry_run)
    end

    def load_containers_from_name(tag, container_names, additional_containers, dry_run:)
      names = Set.new(container_names)
      containers = {}
      while containers.size < names.size
        names.difference(containers.keys).each do |name|
          containers[name] =
            case name
            when 'app'
              AppContainer.new(@app, @app.yaml['app'].merge('tag' => tag), dry_run: dry_run)
            when 'front'
              load_front(@app.yaml['front'], dry_run: dry_run)
            else
              Container.new(@app, additional_containers.fetch(name), dry_run: dry_run)
            end
          containers[name].links.each do |link|
            m = link.match(/\A([^:]+):([^:]+)\z/)
            if m
              names << m[1]
            else
              names << link
            end
          end
        end
      end
      containers
    end

    def load_scheduler(yaml, scripts, force: false, dry_run: false)
      Loader.new(Hako::Schedulers, 'hako/schedulers').load(yaml.fetch('type')).new(@app.id, yaml, scripts: scripts, force: force, dry_run: dry_run)
    end

    def load_front(yaml, dry_run:)
      Loader.new(Hako::Fronts, 'hako/fronts').load(yaml.fetch('type')).new(@app, yaml, dry_run: dry_run)
    end

    def load_script(yaml, dry_run:)
      Loader.new(Hako::Scripts, 'hako/scripts').load(yaml.fetch('type')).new(@app, yaml, dry_run: dry_run)
    end
  end
end
