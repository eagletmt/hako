require 'thor'

module Hako
  class CLI < Thor
    desc 'deploy FILE', 'Run deployment'
    option :force, aliases: %w[-f], type: :boolean, default: false, desc: 'Run deployment even if nothing is changed'
    def deploy(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).deploy(force: options[:force])
    end

    desc 'status FILE', 'Show deployment status'
    def status(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).status
    end
  end
end
