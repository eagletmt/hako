# frozen_string_literal: true
module Hako
  module Schedulers
    class EcsDefinitionComparator
      # @param [Hash] expected_container
      def initialize(expected_container)
        @expected_container = expected_container
      end

      CONTAINER_KEYS = %i[image cpu memory links docker_labels user].freeze
      PORT_MAPPING_KEYS = %i[container_port host_port protocol].freeze
      ENVIRONMENT_KEYS = %i[name value].freeze
      MOUNT_POINT_KEYS = %i[source_volume container_path read_only].freeze
      VOLUMES_FROM_KEYS = %i[source_container read_only].freeze

      # @param [Aws::ECS::Types::ContainerDefinition] actual_container
      # @return [Boolean]
      def different?(actual_container)
        unless actual_container
          return true
        end
        if different_members?(@expected_container, actual_container, CONTAINER_KEYS)
          return true
        end
        if different_array?(@expected_container, actual_container, :port_mappings, PORT_MAPPING_KEYS)
          return true
        end
        if different_array?(@expected_container, actual_container, :environment, ENVIRONMENT_KEYS)
          return true
        end
        if different_array?(@expected_container, actual_container, :mount_points, MOUNT_POINT_KEYS)
          return true
        end
        if different_array?(@expected_container, actual_container, :volumes_from, VOLUMES_FROM_KEYS)
          return true
        end

        false
      end

      private

      # @param [Hash<String, Object>] expected
      # @param [Hash<String, Object>] actual
      # @param [Array<String>] keys
      # @return [Boolean]
      def different_members?(expected, actual, keys)
        keys.each do |key|
          if actual.public_send(key) != expected[key]
            return true
          end
        end
        false
      end

      # @param [Hash<String, Array<Object>>] expected
      # @param [Hash<String, Array<Object>>] actual
      # @param [Array<String>] keys
      # @return [Boolean]
      def different_array?(expected, actual, key, keys)
        if expected[key].size != actual.public_send(key).size
          return true
        end
        sorted_expected = expected[key].sort_by { |e| keys.map { |k| e[k] }.join('') }
        sorted_actual = actual.public_send(key).sort_by { |a| keys.map { |k| a.public_send(k) }.join('') }
        sorted_expected.zip(sorted_actual) do |e, a|
          if different_members?(e, a, keys)
            return true
          end
        end
        false
      end
    end
  end
end
