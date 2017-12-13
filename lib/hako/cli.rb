# frozen_string_literal: true

require 'hako'
require 'optparse'
require 'pathname'

module Hako
  class CLI
    SUB_COMMANDS = %w[
      deploy
      rollback
      oneshot
      show-definition
      status
      remove
      stop
    ].freeze

    def self.start(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @help = false
      parser.order!(@argv)
    end

    def run
      if @help || @argv.empty?
        puts parser.help
        SUB_COMMANDS.each do |subcommand|
          puts create_subcommand(subcommand).new.parser.help
        end
      else
        create_subcommand(@argv.shift).new.run(@argv)
      end
    end

    private

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = 'hako'
        opts.version = VERSION
        opts.on('-h', '--help', 'Show help') { @help = true }
      end
    end

    def create_subcommand(sub)
      if SUB_COMMANDS.include?(sub)
        CLI.const_get(sub.split('-').map(&:capitalize).join(''))
      else
        $stderr.puts "No such subcommand: #{sub}"
        exit 1
      end
    end

    class Deploy
      def run(argv)
        parse!(argv)
        require 'hako/application'
        require 'hako/commander'

        if @verbose
          Hako.logger.level = Logger::DEBUG
        end

        Commander.new(Application.new(@yaml_path)).deploy(force: @force, tag: @tag, dry_run: @dry_run, timeout: @timeout)
      end

      DEFAULT_TIMEOUT = 1200 # 20 minutes

      def parse!(argv)
        @force = false
        @tag = 'latest'
        @dry_run = false
        @verbose = false
        @timeout = DEFAULT_TIMEOUT
        parser.parse!(argv)
        @yaml_path = argv.first

        if @yaml_path.nil?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako deploy [OPTIONS] FILE'
          opts.version = VERSION
          opts.on('-f', '--force', 'Run deployment even if nothing is changed') { @force = true }
          opts.on('-t', '--tag=TAG', 'Specify tag (default: latest)') { |v| @tag = v }
          opts.on('-n', '--dry-run', 'Enable dry-run mode') { @dry_run = true }
          opts.on('-v', '--verbose', 'Enable verbose logging') { @verbose = true }
          opts.on('--timeout=TIMEOUT_SEC', "Timeout deployment after TIMEOUT_SEC seconds (default: #{DEFAULT_TIMEOUT})") { |v| @timeout = v.to_i }
        end
      end
    end

    class Rollback
      def run(argv)
        parse!(argv)
        require 'hako/application'
        require 'hako/commander'

        if @verbose
          Hako.logger.level = Logger::DEBUG
        end

        Commander.new(Application.new(@yaml_path)).rollback(dry_run: @dry_run)
      end

      def parse!(argv)
        @dry_run = false
        @verbose = false
        parser.parse!(argv)
        @yaml_path = argv.first

        if @yaml_path.nil?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako rollback [OPTIONS] FILE'
          opts.version = VERSION
          opts.on('-n', '--dry-run', 'Enable dry-run mode') { @dry_run = true }
          opts.on('-v', '--verbose', 'Enable verbose logging') { @verbose = true }
        end
      end
    end

    class Oneshot
      def run(argv)
        parse!(argv)
        require 'hako/application'
        require 'hako/commander'

        if @verbose
          Hako.logger.level = Logger::DEBUG
        end

        Commander.new(Application.new(@yaml_path)).oneshot(@argv, tag: @tag, containers: @containers, env: @env, dry_run: @dry_run, no_wait: @no_wait)
      end

      def parse!(argv)
        @tag = 'latest'
        @dry_run = false
        @containers = []
        @env = {}
        @verbose = false
        @no_wait = false
        parser.parse!(argv)
        @yaml_path = argv.shift
        @argv = argv

        if @yaml_path.nil? || @argv.empty?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako oneshot [OPTIONS] FILE COMMAND ARG...'
          opts.version = VERSION
          opts.on('-t', '--tag=TAG', 'Specify tag (default: latest)') { |v| @tag = v }
          opts.on('-n', '--dry-run', 'Enable dry-run mode') { @dry_run = true }
          opts.on('-c', '--container=NAME', 'Additional container name to start with the app container') { |v| @containers << v }
          opts.on('-v', '--verbose', 'Enable verbose logging') { @verbose = true }
          opts.on('--no-wait', 'Run Docker container in background and return task information depending on scheduler (experimental)') { @no_wait = true }
          opts.on('-e', '--env=NAME=VAL', 'Add environment variable') do |arg|
            k, v = arg.split('=', 2)
            @env[k] = v
          end
        end
      end
    end

    class ShowDefinition
      def run(argv)
        parse!(argv)
        require 'hako/application'
        app = Application.new(@path, expand_variables: false)
        puts app.definition.to_yaml
      end

      def parse!(argv)
        parser.parse!(argv)
        @path = argv.first
        if @path.nil?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako show-definition FILE'
          opts.version = VERSION
        end
      end
    end

    class Status
      def run(argv)
        parse!(argv)
        require 'hako/application'
        require 'hako/commander'
        Commander.new(Application.new(@yaml_path)).status
      end

      def parse!(argv)
        parser.parse!(argv)
        @yaml_path = argv.first

        if @yaml_path.nil?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako status FILE'
          opts.version = VERSION
        end
      end
    end

    class Remove
      def run(argv)
        parse!(argv)
        require 'hako/application'
        require 'hako/commander'
        Commander.new(Application.new(@yaml_path)).remove(dry_run: @dry_run)
      end

      def parse!(argv)
        @dry_run = false
        parser.parse!(argv)
        @yaml_path = argv.first

        if @yaml_path.nil?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako remove FILE'
          opts.version = VERSION
          opts.on('-n', '--dry-run', 'Enable dry-run mode') { @dry_run = true }
        end
      end
    end

    class Stop
      def run(argv)
        parse!(argv)
        require 'hako/application'
        require 'hako/commander'
        Commander.new(Application.new(@yaml_path)).stop(dry_run: @dry_run)
      end

      def parse!(argv)
        @dry_run = false
        parser.parse!(argv)
        @yaml_path = argv.first

        if @yaml_path.nil?
          puts parser.help
          exit 1
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = 'hako stop FILE'
          opts.version = VERSION
          opts.on('-n', '--dry-run', 'Enable dry-run mode') { @dry_run = true }
        end
      end
    end
  end
end
