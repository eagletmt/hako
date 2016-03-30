# frozen_string_literal: true
require 'aws-sdk'
require 'erb'
require 'hako'
require 'hako/script'

module Hako
  module Scripts
    class NginxFront < Script
      S3Config = Struct.new(:region, :bucket, :prefix) do
        def initialize(options)
          self.region = options.fetch('region')
          self.bucket = options.fetch('bucket')
          self.prefix = options.fetch('prefix', nil)
        end

        def key(app_id)
          if prefix
            "#{prefix}/#{app_id}.conf"
          else
            "#{app_id}.conf"
          end
        end
      end

      def deploy_starting(containers)
        front = containers.fetch('front')
        front.definition['env'].merge!(
          'AWS_DEFAULT_REGION' => @s3.region,
          'S3_CONFIG_BUCKET' => @s3.bucket,
          'S3_CONFIG_KEY' => @s3.key(@app.id),
        )
        front.links << link_app
      end

      def deploy_started(containers, front_port)
        app = containers.fetch('app')
        front = containers.fetch('front')
        front.definition['port_mappings'] << port_mapping(front_port)
        upload_config(generate_config(app.port))
        Hako.logger.debug "Uploaded front configuration to s3://#{@s3.bucket}/#{@s3.key(@app.id)}"
      end

      private

      def configure(options)
        super
        @options = options
        @options['locations'] ||= { '/' => {} }
        @s3 = S3Config.new(@options.fetch('s3'))
      end

      def link_app
        'app:app'
      end

      def port_mapping(front_port)
        { container_port: 80, host_port: front_port, protocol: 'tcp' }
      end

      def generate_config(app_port)
        Generator.new(@options, app_port).render
      end

      def upload_config(front_conf)
        if @dry_run
          Hako.logger.info "Generated configuration:\n#{front_conf}"
        else
          s3_client.put_object(
            body: front_conf,
            bucket: @s3.bucket,
            key: @s3.key(@app.id),
          )
        end
      end

      def s3_client
        @s3_client ||= Aws::S3::Client.new(region: @s3.region)
      end

      class Generator
        def initialize(options, app_port)
          @options = options
          @app_port = app_port
        end

        def render
          ERB.new(File.read(nginx_conf_erb), nil, '-').result(binding)
        end

        private

        def listen_spec
          "app:#{@app_port}"
        end

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
          locs = @options.fetch('locations').dup
          locs.keys.each do |k|
            locs[k] = Location.new(locs[k])
          end
          locs
        end

        def client_max_body_size
          @options.fetch('client_max_body_size', nil)
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
            allow = @config.fetch('allow_only_from', nil)
            if allow
              allow.flatten
            end
          end
        end
      end
    end
  end
end
