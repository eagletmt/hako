# frozen_string_literal: true

require 'hako/schema'

module Hako
  module Schedulers
    class EcsRuntimePlatformComparator
      # @param [Hash] expected_runtime_platform
      def initialize(expected_runtime_platform)
        @expected_runtime_platform = expected_runtime_platform
        @schema = runtime_platform_schema
      end

      # @param [Aws::ECS::Types::RuntimePlatform] actual_runtime_platform
      # @return [Boolean]
      def different?(actual_runtime_platform)
        !@schema.same?(actual_runtime_platform.to_h, @expected_runtime_platform)
      end

      private

      def runtime_platform_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:cpu_architecture, Schema::Nullable.new(Schema::String.new))
          struct.member(:operating_system_family, Schema::Nullable.new(Schema::String.new))
        end
      end
    end
  end
end
