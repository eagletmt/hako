# frozen_string_literal: true
require 'hako/definition_loader'
require 'hako/env_expander'
require 'hako/error'
require 'hako/loader'
require 'hako/schedulers'
require 'hako/scripts'

module Hako
  class Commander
    # @param [Application] app
    def initialize(app)
      @app = app
    end

    # @param [Boolean] force
    # @param [String] tag
    # @param [Boolean] dry_run
    # @return [nil]
    def deploy(force: false, tag: 'latest', dry_run: false, timeout:)
      containers = load_containers(tag, dry_run: dry_run)
      if dry_run
        print_expanded_yaml(containers)
      end
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      volumes = @app.yaml.fetch('volumes', [])
      scheduler = load_scheduler(@app.yaml['scheduler'], scripts, volumes: volumes, force: force, dry_run: dry_run, timeout: timeout)

      scripts.each { |script| script.deploy_starting(containers) }
      scheduler.deploy(containers)
      scripts.each { |script| script.deploy_finished(containers) }
      nil
    end

    # @param [Boolean] dry_run
    # @return [nil]
    def rollback(dry_run: false)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      scheduler = load_scheduler(@app.yaml['scheduler'], scripts, dry_run: dry_run)

      scheduler.rollback
    end

    # @param [Array<String>] commands
    # @param [String] tag
    # @param [Hash<String, String>] env
    # @param [Boolean] dry_run
    # @return [nil]
    def oneshot(commands, tag:, containers:, env: {}, dry_run: false)
      containers = load_containers(tag, dry_run: dry_run, with: containers)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      volumes = @app.yaml.fetch('volumes', [])
      scheduler = load_scheduler(@app.yaml['scheduler'], scripts, volumes: volumes, dry_run: dry_run)

      scripts.each { |script| script.oneshot_starting(containers) }
      exit_code = with_oneshot_signal_handlers(scheduler) do
        scheduler.oneshot(containers, commands, env)
      end
      scripts.each { |script| script.oneshot_finished(containers) }
      exit exit_code
    end

    # @return [nil]
    def status
      load_scheduler(@app.yaml['scheduler'], [], dry_run: false).status
    end

    # @param [Boolean] dry_run
    # @return [nil]
    def remove(dry_run:)
      scripts = @app.yaml.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      load_scheduler(@app.yaml['scheduler'], scripts, dry_run: dry_run).remove
      scripts.each(&:after_remove)
    end

    def stop(dry_run:)
      load_scheduler(@app.yaml['scheduler'], [], dry_run: dry_run).stop
    end

    private

    TRAP_SIGNALS = %i[INT TERM].freeze
    class SignalTrapped < StandardError; end

    # @param [Scheduler] scheduler
    # @yieldreturn [Fixnum]
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

    # @param [String] tag
    # @param [Boolean] dry_run
    # @param [Array<String>, nil] with
    # @return [Hash<String, Container>]
    def load_containers(tag, dry_run:, with: nil)
      DefinitionLoader.new(@app, dry_run: dry_run).load(tag, with: with)
    end

    # @param [Hash] yaml
    # @param [Hash] volumes
    # @param [Boolean] force
    # @param [Boolean] dry_run
    # @param [Integer] timeout
    # @return [Scheduler]
    def load_scheduler(yaml, scripts, volumes: [], force: false, dry_run:, timeout: nil)
      Loader.new(Hako::Schedulers, 'hako/schedulers').load(yaml.fetch('type')).new(@app.id, yaml, volumes: volumes, scripts: scripts, force: force, dry_run: dry_run, timeout: timeout)
    end

    # @param [Hash] yaml
    # @param [Boolean] dry_run
    # @return [Script]
    def load_script(yaml, dry_run:)
      Loader.new(Hako::Scripts, 'hako/scripts').load(yaml.fetch('type')).new(@app, yaml, dry_run: dry_run)
    end

    # @param [Hash<String, Container>] containers
    # @return [nil]
    def print_expanded_yaml(containers)
      yaml = @app.yaml.dup
      containers.each do |name, container|
        if yaml.dig('additional_containers', name, 'env')
          yaml.dig('additional_containers', name, 'env').merge!(container.env)
        elsif yaml.dig(name, 'env')
          yaml.dig(name, 'env').merge!(container.env)
        end
      end
      puts yaml.to_yaml
    end
  end
end
