# frozen_string_literal: true
require 'aws-sdk'

module Hako
  class Scheduler
    class ValidationError < Error
    end

    # @param [String] app_id
    # @param [Hash] options
    # @param [Hash] volumes
    # @param [Array<Script>] scripts
    # @param [Boolean] dry_run
    # @param [Boolean] force
    # @param [Integer] timeout in seconds
    def initialize(app_id, options, volumes:, scripts:, dry_run:, force:, timeout:)
      @app_id = app_id
      @volumes = volumes
      @scripts = scripts
      @dry_run = dry_run
      @force = force
      @timeout = timeout
      configure(options)
    end

    # @param [Hash] _options
    def configure(_options); end

    # @param [Hash<String, Container>] _containers
    def deploy(_containers)
      raise NotImplementedError
    end

    def rollback
      raise NotImplementedError
    end

    def status
      raise NotImplementedError
    end

    def remove
      raise NotImplementedError
    end

    def stop
      raise NotImplementedError
    end

    private

    # @param [String] message
    def validation_error!(message)
      raise ValidationError.new(message)
    end
  end
end
