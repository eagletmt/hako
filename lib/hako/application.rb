# frozen_string_literal: true

require 'hako/error'
require 'hako/jsonnet_loader'
require 'hako/yaml_loader'
require 'pathname'

module Hako
  class Application
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] root_path
    #   @return [Pathname]
    # @!attribute [r] definition
    #   @return [Hash]
    attr_reader :id, :root_path, :definition

    def initialize(definition_path, expand_variables: true, ask_keys: false)
      path = Pathname.new(definition_path)
      @id = path.basename.sub_ext('').to_s
      @root_path = path.parent
      @definition =
        case path.extname
        when '.yml', '.yaml'
          YamlLoader.new.load(path)
        when '.jsonnet', '.json'
          JsonnetLoader.new(self, expand_variables: expand_variables, ask_keys: ask_keys).load(path)
        else
          raise Error.new("Unknown extension: #{path}")
        end
    end
  end
end
