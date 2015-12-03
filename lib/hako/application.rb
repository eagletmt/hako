require 'yaml'

module Hako
  class Application
    attr_reader :id, :root_path, :yaml

    def initialize(yaml_path)
      path = Pathname.new(yaml_path)
      @id = path.basename.sub_ext('').to_s
      @root_path = path.parent
      @yaml = load_default_yaml(@root_path).merge(YAML.load_file(yaml_path))
    end

    private

    def load_default_yaml(root_path)
      YAML.load_file(root_path.join('default.yml').to_s)
    rescue Errno::ENOENT
      {}
    end
  end
end
