require 'hako/scheduler'

module Hako
  module Schedulers
    class Echo < Scheduler
      def initialize(app_id, _options)
        @app_id = app_id
      end

      def deploy(image_tag, env, app_port, _front, force: false)
        puts "Deploy #{image_tag} with app_port=#{app_port}, force=#{force}"
        puts 'Environment variables:'
        env.each do |key, val|
          puts "  #{key}=#{val.inspect}"
        end
      end
    end
  end
end
