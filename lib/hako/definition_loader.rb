# frozen_string_literal: true
require 'set'
require 'hako/app_container'
require 'hako/container'
require 'hako/fronts'
require 'hako/loader'

module Hako
  class DefinitionLoader
    def initialize(app, dry_run:)
      @app = app
      @dry_run = dry_run
    end

    def load(tag, with: nil)
      additional_containers = @app.yaml.fetch('additional_containers', {})
      container_names = ['app']
      if with
        container_names.concat(with)
      else
        if @app.yaml.key?('front')
          container_names << 'front'
        end
        container_names.concat(additional_containers.keys)
      end

      load_containers_from_name(tag, container_names, additional_containers)
    end

    private

    def load_containers_from_name(tag, container_names, additional_containers)
      names = Set.new(container_names)
      containers = {}
      while containers.size < names.size
        names.difference(containers.keys).each do |name|
          containers[name] =
            case name
            when 'app'
              AppContainer.new(@app, @app.yaml['app'].merge('tag' => tag), dry_run: @dry_run)
            when 'front'
              load_front(@app.yaml['front'], dry_run: @dry_run)
            else
              Container.new(@app, additional_containers.fetch(name), dry_run: @dry_run)
            end

          containers[name].links.each do |link|
            m = link.match(/\A([^:]+):([^:]+)\z/)
            names << (m ? m[1] : link)
          end
        end
      end
      containers
    end

    def load_front(yaml, dry_run:)
      Loader.new(Hako::Fronts, 'hako/fronts').load(yaml.fetch('type')).new(@app, yaml, dry_run: dry_run)
    end
  end
end
