# frozen_string_literal: true
require 'thor'

module Hako
  class CLI < Thor
    desc 'deploy FILE', 'Run deployment'
    option :force, aliases: %w[-f], type: :boolean, default: false, desc: 'Run deployment even if nothing is changed'
    option :tag, aliases: %w[-t], type: :string, default: 'latest', desc: 'Specify tag (default: latest)'
    option :dry_run, aliases: %w[-n], type: :boolean, default: false, desc: 'Enable dry-run mode'
    def deploy(yaml_path)
      require 'hako/application'
      require 'hako/commander'
      Commander.new(Application.new(yaml_path)).deploy(force: options[:force], tag: options[:tag], dry_run: options[:dry_run])
    end

    desc 'oneshot FILE COMMAND ARG...', 'Run oneshot task'
    option :tag, aliases: %w[-t], type: :string, default: 'latest', desc: 'Specify tag (default: latest)'
    option :containers, aliases: %w[-c], type: :string, default: '', banner: 'NAME1,NAME2', desc: 'Comma-separated additional container names to start with the app container (default: "")'
    def oneshot(yaml_path, command, *args)
      require 'hako/application'
      require 'hako/commander'
      Commander.new(Application.new(yaml_path)).oneshot([command, *args], tag: options[:tag], containers: options[:containers].split(','))
    end

    desc 'show-yaml FILE', 'Show expanded YAML'
    def show_yaml(yaml_path)
      require 'hako/yaml_loader'
      puts YamlLoader.new.load(Pathname.new(yaml_path)).to_yaml
    end

    desc 'status FILE', 'Show deployment status'
    def status(yaml_path)
      require 'hako/application'
      require 'hako/commander'
      Commander.new(Application.new(yaml_path)).status
    end

    desc 'remove FILE', 'Destroy the application'
    def remove(yaml_path)
      require 'hako/application'
      require 'hako/commander'
      Commander.new(Application.new(yaml_path)).remove
    end
  end
end
