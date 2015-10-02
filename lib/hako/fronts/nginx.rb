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

      def nginx_conf_erb
        File.expand_path('../../templates/nginx.conf.erb', __FILE__)
      end
    end
  end
end
