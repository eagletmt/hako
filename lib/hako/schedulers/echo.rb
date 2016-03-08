# frozen_string_literal: true
require 'hako/scheduler'

module Hako
  module Schedulers
    class Echo < Scheduler
      def deploy(containers)
        app = containers.fetch('app')
        puts "Deploy #{app.image_tag} with app_port=#{app.port}, force=#{@force}, dry_run=#{@dry_run}"
        puts 'Environment variables:'
        app.env.each do |key, val|
          puts "  #{key}=#{val.inspect}"
        end
      end

      def oneshot(containers, commands, env)
        app = containers.fetch('app')
        puts "Run #{app.image_tag} with oneshot commands=#{commands.inspect}"
        puts 'Environment variables:'
        env.each do |key, val|
          puts "  #{key}=#{val.inspect}"
        end
        0
      end
    end
  end
end
