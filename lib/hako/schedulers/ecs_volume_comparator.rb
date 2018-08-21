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

      def host_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:source_path, Schema::Nullable.new(Schema::String.new))
        end
      end
    end
  end
end
