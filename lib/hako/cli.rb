require 'thor'

module Hako
  class CLI < Thor
    desc 'deploy FILE', 'Run deployment'
    def deploy(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).deploy
    end

    desc 'status FILE', 'Show deployment status'
    def status(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).status
    end
  end
end
