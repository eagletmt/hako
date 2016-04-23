# frozen_string_literal: true
require 'hako/yaml_loader'

module Hako
  class Application
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] root_path
    #   @return [Pathname]
    # @!attribute [r] yaml
    #   @return [Hash]
    attr_reader :id, :root_path, :yaml

    def initialize(yaml_path)
      path = Pathname.new(yaml_path)
      @id = path.basename.sub_ext('').to_s
      @root_path = path.parent
      @yaml = YamlLoader.new.load(path)
    end
  end
end
