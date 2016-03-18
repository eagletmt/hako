# frozen_string_literal: true
require 'hako/scripts'

module Hako
  class Script
    def initialize(app, options, dry_run:)
      @app = app
      @dry_run = dry_run
      configure(options)
    end

    def configure(_options)
    end

    def deploy_starting(_containers)
    end

    def deploy_started(_containers, _front_port)
    end

    def deploy_finished(_containers)
    end

    def oneshot_started(_scheduler)
    end
  end
end
