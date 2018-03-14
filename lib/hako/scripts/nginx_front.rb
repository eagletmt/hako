# frozen_string_literal: true

require 'aws-sdk-s3'
require 'erb'
require 'hako'
require 'hako/script'

module Hako
  module Scripts
    class NginxFront < Script
      S3Config = Struct.new(:region, :bucket, :prefix) do
        # @param [Hash] options
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

      # @param [Hash<String, Container>] containers
      # @return [nil]
      def deploy_starting(containers)
        front = containers.fetch('front')
        front.definition['env'].merge!(
          'AWS_DEFAULT_REGION' => @s3.region,
          'S3_CONFIG_BUCKET' => @s3.bucket,
          'S3_CONFIG_KEY' => @s3.key(@app.id),
        )
      end

      # @param [Hash<String, Container>] containers
      # @param [Fixnum] front_port
      # @return [nil]
      def deploy_started(containers, front_port)
        front = containers.fetch('front')
        if front_port.nil?
          # Links and extraHosts are not supported when networkMode=awsvpc (i.e., --network=container).
        else
          front.links << link_app
        end
        front.definition['port_mappings'] << port_mapping(front_port)
        upload_config(generate_config(backend_host: front_port.nil? ? 'localhost' : 'backend'))
        Hako.logger.info "Uploaded front configuration to s3://#{@s3.bucket}/#{@s3.key(@app.id)}"
      end

      private

      # @param [Hash] options
      # @return [nil]
      def configure(options)
        super
        @options = options
        @options['locations'] ||= { '/' => {} }
        @backend = options.fetch('backend', 'app')
        @s3 = S3Config.new(options.fetch('s3'))
      end

      # @return [String]
      def link_app
        "#{@backend}:backend"
      end

      # @param [Fixnum] front_port
      # @return [Hash]
      def port_mapping(front_port)
        { 'container_port' => 80, 'host_port' => front_port || 80, 'protocol' => 'tcp' }
      end

      # @return [String]
      def generate_config(backend_host:)
        Generator.new(@options, backend_host: backend_host).render
      end

      # @return [Hash]
      def upload_config(front_conf)
        if @dry_run
          puts "#{self.class} will upload this configuration:\n#{front_conf}"
        else
          s3_client.put_object(
            body: front_conf,
            bucket: @s3.bucket,
            key: @s3.key(@app.id),
          )
        end
      end

      # @return [Aws::S3::Client]
      def s3_client
        @s3_client ||= Aws::S3::Client.new(region: @s3.region)
      end

      class Generator
        # @param [Hash] options
        def initialize(options, backend_host:)
          @options = options
          @backend_host = backend_host
          @backend_port = options.fetch('backend_port')
        end

        # @return [String]
        def render
          ERB.new(File.read(nginx_conf_erb), nil, '-').result(binding)
        end

        private

        # @return [String]
        def listen_spec
          "#{@backend_host}:#{@backend_port}"
        end

        # @return [String]
        def templates_directory
          File.expand_path('../templates', __dir__)
        end

        # @return [String]
        def nginx_conf_erb
          File.join(templates_directory, 'nginx.conf.erb')
        end

        # @return [String]
        def nginx_location_conf_erb
          File.join(templates_directory, 'nginx.location.conf.erb')
        end

        # @return [Hash<String, Location>]
        def locations
          locs = {}
          @options.fetch('locations').each do |k, v|
            locs[k] = Location.new(v)
          end
          locs
        end

        # @return [String, nil]
        def client_max_body_size
          @options.fetch('client_max_body_size', nil)
        end

        # @param [String] listen_spec
        # @param [Location] location
        # @return [String]
        def render_location(listen_spec, location)
          ERB.new(File.read(nginx_location_conf_erb), nil, '-').result(binding).each_line.map do |line|
            "    #{line}"
          end.join('')
        end

        class Location
          # @param [Hash] config
          def initialize(config)
            @config = config
          end

          # @return [Array<String>, nil]
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
