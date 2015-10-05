module Hako
  module Schedulers
    class EcsDefinitionComparator
      def initialize(expected_container)
        @expected_container = expected_container
      end

      CONTAINER_KEYS = %i[image cpu memory links]
      PORT_MAPPING_KEYS = %i[container_port host_port protocol]
      ENVIRONMENT_KEYS = %i[name value]

      def different?(actual_container)
        unless actual_container
          return true
        end
        if different_members?(@expected_container, actual_container, CONTAINER_KEYS)
          return true
        end
        if @expected_container[:port_mappings].size != actual_container.port_mappings.size
          return true
        end
        @expected_container[:port_mappings].zip(actual_container.port_mappings) do |e, a|
          if different_members?(e, a, PORT_MAPPING_KEYS)
            return true
          end
        end
        if @expected_container[:environment].size != actual_container.environment.size
          return true
        end
        @expected_container[:environment].zip(actual_container.environment) do |e, a|
          if different_members?(e, a, ENVIRONMENT_KEYS)
            return true
          end
        end

        false
      end

      private

      def different_members?(expected, actual, keys)
        keys.each do |key|
          if actual.public_send(key) != expected[key]
            return true
          end
        end
        false
      end
    end
  end
end
