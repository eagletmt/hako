# frozen_string_literal: true

require 'hako/schema'

module Hako
  module Schedulers
    class EcsVolumeComparator
      # @param [Hash] expected_volume
      def initialize(expected_volume)
        @expected_volume = expected_volume
        @schema = volume_schema
      end

      # @param [Aws::ECS::Types::Volume] actual_volume
      # @return [Boolean]
      def different?(actual_volume)
        !@schema.same?(actual_volume.to_h, @expected_volume)
      end

      private

      def volume_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:docker_volume_configuration, Schema::Nullable.new(docker_volume_configuration_schema))
          struct.member(:efs_volume_configuration, Schema::Nullable.new(efs_volume_configuration_schema))
          struct.member(:host, Schema::Nullable.new(host_schema))
          struct.member(:name, Schema::String.new)
        end
      end

      def docker_volume_configuration_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:autoprovision, Schema::Nullable.new(Schema::Boolean.new))
          struct.member(:driver, Schema::WithDefault.new(Schema::String.new, 'local'))
          struct.member(:driver_opts, Schema::Nullable.new(Schema::Table.new(Schema::String.new, Schema::String.new)))
          struct.member(:labels, Schema::Nullable.new(Schema::Table.new(Schema::String.new, Schema::String.new)))
          struct.member(:scope, Schema::WithDefault.new(Schema::String.new, 'task'))
        end
      end

      def efs_volume_configuration_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:file_system_id, Schema::String.new)
          struct.member(:root_directory, Schema::WithDefault.new(Schema::String.new, '/'))
          struct.member(:transit_encryption, Schema::Nullable.new(Schema::String.new))
          struct.member(:transit_encryption_port, Schema::Nullable.new(Schema::Integer.new))
          struct.member(:authorization_config, Schema::Nullable.new(efs_authorization_config_schema))
        end
      end

      def efs_authorization_config_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:access_point_id, Schema::Nullable.new(Schema::String.new))
          struct.member(:iam, Schema::Nullable.new(Schema::String.new))
        end
      end

      def host_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:source_path, Schema::Nullable.new(Schema::String.new))
        end
      end
    end
  end
end
