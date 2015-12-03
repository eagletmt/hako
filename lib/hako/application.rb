require 'yaml'

module Hako
  class Application
    attr_reader :id, :root_path, :yaml

    def initialize(yaml_path)
      path = Pathname.new(yaml_path)
      @id = path.basename.sub_ext('').to_s
      @root_path = path.parent
      @yaml = YAML.load(load_default_yaml(@root_path) + path.read)
    end

    private

    def load_default_yaml(root_path)
      root_path.join('default.yml').read
    rescue Errno::ENOENT
      ''
    end
  end
end
