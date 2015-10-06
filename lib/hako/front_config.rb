require 'erb'

module Hako
  class FrontConfig < Struct.new(:type, :image_tag, :s3, :extra)
    class S3Config < Struct.new(:region, :bucket, :prefix)
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

    def initialize(options)
      self.type = options.fetch('type')
      self.image_tag = options.fetch('image_tag')
      self.s3 = S3Config.new(options.fetch('s3'))
      self.extra = options.fetch('extra', {})
    end
  end
end
