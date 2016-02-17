module Hako
  class Container
    DEFAULT_CONFIG = {
      'docker_labels' => {},
    }.freeze

    def initialize(definition)
      @definition = definition.merge(DEFAULT_CONFIG)
    end

    %w[
      image_tag
      docker_labels
    ].each do |name|
      define_method(name) do
        @definition[name]
      end

      define_method("#{name}=") do |val|
        @definition[name] = val
      end
    end
  end
end
