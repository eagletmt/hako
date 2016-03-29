# frozen_string_literal: true
require 'aws-sdk'

module Hako
  class Scheduler
    class ValidationError < Error
    end

    def initialize(app_id, options, volumes:, scripts:, dry_run:, force:)
      @app_id = app_id
      @volumes = volumes
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

    private

    def validation_error!(message)
      raise ValidationError.new(message)
    end
  end
end
