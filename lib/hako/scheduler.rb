require 'aws-sdk'

module Hako
  class Scheduler
    class ValidationError < Error
    end

    def initialize(_app_id, _options)
    end

    def deploy(_image_tag, _env, _port_mapping, _front_config)
      raise NotImplementedError
    end

    def upload_front_config(app_id, front, app_port)
      front_conf = front.generate_config(app_port)
      s3_config = front.config.s3
      s3 = Aws::S3::Client.new(region: s3_config.region)
      s3.put_object(
        body: front_conf,
        bucket: s3_config.bucket,
        key: s3_config.key(app_id),
      )
    end

    private

    def validation_error!(message)
      raise ValidationError.new(message)
    end
  end
end
