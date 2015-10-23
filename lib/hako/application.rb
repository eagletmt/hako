module Hako
  class Application
    attr_reader :id, :yaml

    def initialize(yaml_path)
      @id = Pathname.new(yaml_path).basename.sub_ext('').to_s
      @yaml = YAML.load_file(yaml_path)
    end
  end
end
