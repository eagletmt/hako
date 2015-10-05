require 'thor'

module Hako
  class CLI < Thor
    desc 'deploy FILE', 'Run deployment'
    option :force, aliases: %w[-f], type: :boolean, default: false, desc: 'Run deployment even if nothing is changed'
    option :tag, aliases: %w[-t], type: :string, default: 'latest', desc: 'Specify tag (default: latest)'
    def deploy(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).deploy(force: options[:force], tag: options[:tag])
    end

    desc 'status FILE', 'Show deployment status'
    def status(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).status
    end

    desc 'remove FILE', 'Destroy the application'
    def remove(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).remove
    end
  end
end
