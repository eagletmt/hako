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
      scripts = @app.definition.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      volumes = @app.definition.fetch('volumes', {})
      scheduler = load_scheduler(@app.definition['scheduler'], scripts, volumes: volumes, force: force, dry_run: dry_run, timeout: timeout)

      scripts.each { |script| script.deploy_starting(containers) }
      scheduler.deploy(containers)
      scripts.each { |script| script.deploy_finished(containers) }
      nil
    end

    # @param [Boolean] dry_run
    # @return [nil]
    def rollback(dry_run: false)
      scripts = @app.definition.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      scheduler = load_scheduler(@app.definition['scheduler'], scripts, dry_run: dry_run)

      scripts.each(&:rollback_starting)
      scheduler.rollback
      scripts.each(&:rollback_finished)
    end

    # @param [Array<String>] commands
    # @param [String] tag
    # @param [Hash<String, String>] env
    # @param [Boolean] dry_run
    # @param [Boolean] no_wait
    # @return [nil]
    def oneshot(commands, tag:, containers:, env: {}, dry_run: false, no_wait: false)
      containers = load_containers(tag, dry_run: dry_run, with: containers)
      scripts = @app.definition.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      volumes = @app.definition.fetch('volumes', {})
      scheduler = load_scheduler(@app.definition['scheduler'], scripts, volumes: volumes, dry_run: dry_run)

      scripts.each { |script| script.oneshot_starting(containers) }
      exit_code = with_oneshot_signal_handlers(scheduler) do
        scheduler.oneshot(containers, commands, env, no_wait: no_wait)
      end
      scripts.each { |script| script.oneshot_finished(containers) }
      exit exit_code
    end

    # @return [nil]
    def status
      load_scheduler(@app.definition['scheduler'], [], dry_run: false).status
    end

    # @param [Boolean] dry_run
    # @return [nil]
    def remove(dry_run:)
      scripts = @app.definition.fetch('scripts', []).map { |config| load_script(config, dry_run: dry_run) }
      load_scheduler(@app.definition['scheduler'], scripts, dry_run: dry_run).remove
      scripts.each(&:after_remove)
    end

    def stop(dry_run:)
      load_scheduler(@app.definition['scheduler'], [], dry_run: dry_run).stop
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

    # @param [Hash] scheduler_definition
    # @param [Hash] volumes
    # @param [Boolean] force
    # @param [Boolean] dry_run
    # @param [Integer] timeout
    # @return [Scheduler]
    def load_scheduler(scheduler_definition, scripts, volumes: {}, force: false, dry_run:, timeout: nil)
      Loader.new(Hako::Schedulers, 'hako/schedulers').load(scheduler_definition.fetch('type')).new(@app.id, scheduler_definition, volumes: volumes, scripts: scripts, force: force, dry_run: dry_run, timeout: timeout)
    end

    # @param [Hash] script_definition
    # @param [Boolean] dry_run
    # @return [Script]
    def load_script(script_definition, dry_run:)
      Loader.new(Hako::Scripts, 'hako/scripts').load(script_definition.fetch('type')).new(@app, script_definition, dry_run: dry_run)
    end
  end
end
