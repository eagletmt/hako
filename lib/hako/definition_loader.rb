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
    # @param [Array<String>, nil] with
    # @return [Hash<String, Container>]
    def load(tag, with: nil)
      # XXX: Load additional_containers for compatibility
      sidecars = @app.definition.fetch('sidecars', @app.definition.fetch('additional_containers', {}))
      container_names = ['app']
      if with
        container_names.concat(with)
      else
        container_names.concat(sidecars.keys)
      end

      load_containers_from_name(tag, container_names, sidecars)
    end

    private

    # @param [String] tag
    # @param [Array<String>] container_names
    # @param [Hash<String, Hash>] sidecars
    # @return [Hash<String, Container>]
    def load_containers_from_name(tag, container_names, sidecars)
      names = Set.new(container_names)
      containers = {}
      while containers.size < names.size
        names.difference(containers.keys).each do |name|
          containers[name] =
            case name
            when 'app'
              AppContainer.new(@app, @app.definition['app'].merge('tag' => tag), dry_run: @dry_run)
            else
              Container.new(@app, sidecars.fetch(name), dry_run: @dry_run)
            end

          containers[name].links.each do |link|
            m = link.match(/\A([^:]+):([^:]+)\z/)
            names << (m ? m[1] : link)
          end

          containers[name].volumes_from.each do |volumes_from|
            names << volumes_from[:source_container]
          end
        end
      end
      containers
    end
  end
end
