module Hako
  class Container
    def initialize(definition)
      @definition = definition
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
