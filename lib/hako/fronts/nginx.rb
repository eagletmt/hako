require 'erb'
require 'hako/front'

module Hako
  module Fronts
    class Nginx < Front
      def generate_config(app_port)
        listen_spec = "app:#{app_port}"
        ERB.new(File.read(nginx_conf_erb), nil, '-').result(binding)
      end

      private

      def templates_directory
        File.expand_path('../../templates', __FILE__)
      end

      def nginx_conf_erb
        File.join(templates_directory, 'nginx.conf.erb')
      end

      def nginx_location_conf_erb
        File.join(templates_directory, 'nginx.location.conf.erb')
      end

      def locations
        locs = @config.extra.fetch('locations', {}).dup
        locs['/'] ||= {}
        locs.keys.each do |k|
          locs[k] = Location.new(locs[k])
        end
        locs
      end

      def client_max_body_size
        @config.extra.fetch('client_max_body_size', nil)
      end

      def render_location(listen_spec, location)
        ERB.new(File.read(nginx_location_conf_erb), nil, '-').result(binding).each_line.map do |line|
          "    #{line}"
        end.join('')
      end

      class Location
        def initialize(config)
          @config = config
        end

        def allow_only_from
          @config.fetch('allow_only_from', nil)
        end
      end
    end
  end
end
