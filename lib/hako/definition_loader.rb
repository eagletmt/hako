# frozen_string_literal: true

require 'set'
require 'hako/app_container'
require 'hako/container'
require 'hako/loader'

module Hako
  class DefinitionLoader
    # @param [Application] app
    # @param [Boolean] dry_run
    def initialize(app, dry_run:)
      @app = app
      @dry_run = dry_run
    end

    # @param [String] tag
    # @return [Hash<String, Container>]
    def load(tag)
      # XXX: Load additional_containers for compatibility
      sidecars = @app.definition.fetch('sidecars', @app.definition.fetch('additional_containers', {}))
      containers = {
        'app' => AppContainer.new(@app, @app.definition['app'].merge('tag' => tag), dry_run: @dry_run),
      }
      sidecars.each do |name, sidecar|
        containers[name] = Container.new(@app, sidecar, dry_run: @dry_run)
      end
      containers
    end
  end
end
