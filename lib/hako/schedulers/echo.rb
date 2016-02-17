require 'hako/scheduler'

module Hako
  module Schedulers
    class Echo < Scheduler
      def initialize(app_id, _options)
        @app_id = app_id
      end

      def deploy(containers, env, app_port, force: false)
        puts "Deploy #{containers.fetch('app').image_tag} with app_port=#{app_port}, force=#{force}"
        puts 'Environment variables:'
        env.each do |key, val|
          puts "  #{key}=#{val.inspect}"
        end
      end

      def oneshot(app, env, commands)
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
