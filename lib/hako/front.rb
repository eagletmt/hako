require 'hako/container'

module Hako
  class Front < Container
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

    attr_reader :s3

    def initialize(app, config)
      super(app, config)
      @s3 = S3Config.new(@definition.fetch('s3'))
    end

    def env
      super.merge(
        'AWS_DEFAULT_REGION' => @s3.region,
        'S3_CONFIG_BUCKET' => @s3.bucket,
        'S3_CONFIG_KEY' => @s3.key(@app.id),
      )
    end

    DEFAULT_LINK = ['app:app'].freeze

    def links
      DEFAULT_LINK + super
    end

    def extra
      @definition.fetch('extra', {})
    end

    def generate_config(_app_port)
      raise NotImplementedError
    end
  end
end
