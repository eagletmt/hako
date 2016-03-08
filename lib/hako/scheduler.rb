# frozen_string_literal: true
require 'aws-sdk'

module Hako
  class Scheduler
    class ValidationError < Error
    end

    def initialize(app_id, options, scripts:, dry_run:, force:)
      @app_id = app_id
      @scripts = scripts
      @dry_run = dry_run
      @force = force
      configure(options)
    end

    def configure(_options)
    end

    def deploy(_containers, _options)
      raise NotImplementedError
    end

    def status
      raise NotImplementedError
    end

    def remove
      raise NotImplementedError
    end

    def upload_front_config(app_id, front, app_port)
      front_conf = front.generate_config(app_port)
      s3_config = front.s3
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
