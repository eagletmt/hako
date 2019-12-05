# frozen_string_literal: true

require 'hako/schema'

module Hako
  module Schedulers
    class EcsDefinitionComparator
      # @param [Hash] expected_container
      def initialize(expected_container)
        @expected_container = expected_container
        @schema = definition_schema
      end

      # @param [Aws::ECS::Types::ContainerDefinition] actual_container
      # @return [Boolean]
      def different?(actual_container)
        !@schema.same?(actual_container.to_h, @expected_container)
      end

      private

      def definition_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:image, Schema::String.new)
          struct.member(:cpu, Schema::Integer.new)
          struct.member(:memory, Schema::Nullable.new(Schema::Integer.new))
          struct.member(:memory_reservation, Schema::Nullable.new(Schema::Integer.new))
          struct.member(:links, Schema::UnorderedArray.new(Schema::String.new))
          struct.member(:essential, Schema::Boolean.new)
          struct.member(:port_mappings, Schema::UnorderedArray.new(port_mapping_schema))
          struct.member(:environment, Schema::UnorderedArray.new(environment_schema))
          struct.member(:secrets, Schema::Nullable.new(Schema::UnorderedArray.new(secrets_schema)))
          struct.member(:docker_labels, Schema::Table.new(Schema::String.new, Schema::String.new))
          struct.member(:mount_points, Schema::UnorderedArray.new(mount_point_schema))
          struct.member(:entry_point, Schema::Nullable.new(Schema::OrderedArray.new(Schema::String.new)))
          struct.member(:command, Schema::Nullable.new(Schema::OrderedArray.new(Schema::String.new)))
          struct.member(:depends_on, Schema::Nullable.new(Schema::UnorderedArray.new(depends_on_schema)))
          struct.member(:volumes_from, Schema::UnorderedArray.new(volumes_from_schema))
          struct.member(:user, Schema::Nullable.new(Schema::String.new))
          struct.member(:privileged, Schema::Boolean.new)
          struct.member(:log_configuration, Schema::Nullable.new(log_configuration_schema))
          struct.member(:health_check, Schema::Nullable.new(health_check_schema))
          struct.member(:ulimits, Schema::Nullable.new(ulimits_schema))
          struct.member(:extra_hosts, Schema::Nullable.new(extra_hosts_schema))
          struct.member(:linux_parameters, Schema::Nullable.new(linux_parameters_schema))
          struct.member(:readonly_root_filesystem, Schema::Nullable.new(Schema::Boolean.new))
          struct.member(:docker_security_options, Schema::Nullable.new(Schema::UnorderedArray.new(Schema::String.new)))
          struct.member(:system_controls, Schema::Nullable.new(system_controls_schema))
          struct.member(:repository_credentials, Schema::Nullable.new(repository_credentials_schema))
          struct.member(:firelens_configuration, Schema::Nullable.new(firelens_configuration_schema))
        end
      end

      def port_mapping_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:container_port, Schema::Integer.new)
          struct.member(:host_port, Schema::Integer.new)
          struct.member(:protocol, Schema::String.new)
        end
      end

      def environment_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:name, Schema::String.new)
          struct.member(:value, Schema::String.new)
        end
      end

      def mount_point_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:source_volume, Schema::String.new)
          struct.member(:container_path, Schema::String.new)
          struct.member(:read_only, Schema::Boolean.new)
        end
      end

      def volumes_from_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:source_container, Schema::String.new)
          struct.member(:read_only, Schema::Boolean.new)
        end
      end

      def log_configuration_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:log_driver, Schema::String.new)
          struct.member(:options, Schema::Table.new(Schema::String.new, Schema::String.new))
        end
      end

      def health_check_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:command, Schema::OrderedArray.new(Schema::String.new))
          struct.member(:interval, Schema::Integer.new)
          struct.member(:timeout, Schema::Integer.new)
          struct.member(:retries, Schema::Integer.new)
          struct.member(:start_period, Schema::Integer.new)
        end
      end

      def ulimits_schema
        Schema::UnorderedArray.new(ulimit_schema)
      end

      def ulimit_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:name, Schema::String.new)
          struct.member(:hard_limit, Schema::Integer.new)
          struct.member(:soft_limit, Schema::Integer.new)
        end
      end

      def linux_parameters_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:capabilities, Schema::Nullable.new(capabilities_schema))
          struct.member(:devices, Schema::Nullable.new(devices_schema))
          struct.member(:init_process_enabled, Schema::Nullable.new(Schema::Boolean.new))
          struct.member(:shared_memory_size, Schema::Nullable.new(Schema::Integer.new))
          struct.member(:tmpfs, Schema::Nullable.new(tmpfs_schema))
        end
      end

      def capabilities_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:add, Schema::UnorderedArray.new(Schema::String.new))
          struct.member(:drop, Schema::UnorderedArray.new(Schema::String.new))
        end
      end

      def devices_schema
        Schema::UnorderedArray.new(device_schema)
      end

      def device_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:host_path, Schema::String.new)
          struct.member(:container_path, Schema::Nullable.new(Schema::String.new))
          struct.member(:permissions, Schema::UnorderedArray.new(Schema::String.new))
        end
      end

      def tmpfs_schema
        Schema::UnorderedArray.new(
          Schema::Structure.new.tap do |struct|
            struct.member(:container_path, Schema::String.new)
            struct.member(:mount_options, Schema::UnorderedArray.new(Schema::String.new))
            struct.member(:size, Schema::Integer.new)
          end
        )
      end

      def extra_hosts_schema
        Schema::UnorderedArray.new(extra_host_schema)
      end

      def extra_host_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:hostname, Schema::String.new)
          struct.member(:ip_address, Schema::String.new)
        end
      end

      def secrets_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:name, Schema::String.new)
          struct.member(:value_from, Schema::String.new)
        end
      end

      def depends_on_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:container_name, Schema::String.new)
          struct.member(:condition, Schema::String.new)
        end
      end

      def system_controls_schema
        Schema::UnorderedArray.new(system_control_schema)
      end

      def system_control_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:namespace, Schema::String.new)
          struct.member(:value, Schema::String.new)
        end
      end

      def repository_credentials_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:credentials_parameter, Schema::String.new)
        end
      end

      def firelens_configuration_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:type, Schema::String.new)
          struct.member(:options, Schema::Nullable.new(Schema::Table.new(Schema::String.new, Schema::String.new)))
        end
      end
    end
  end
end
