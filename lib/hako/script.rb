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

    def before_deploy(_containers)
    end

    def after_deploy(_containers)
    end

    def oneshot_started(_scheduler)
    end
  end
end
