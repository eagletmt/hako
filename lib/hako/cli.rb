require 'thor'

module Hako
  class CLI < Thor
    desc 'apply FILE', 'Run'
    def apply(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).apply
    end

    desc 'status FILE', 'Show deployment status'
    def status(yaml_path)
      require 'hako/commander'
      Commander.new(yaml_path).status
    end
  end
end
