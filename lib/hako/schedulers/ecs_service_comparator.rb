# frozen_string_literal: true
require 'hako/schema'

module Hako
  module Schedulers
    class EcsServiceComparator
      def initialize(expected_service)
        @expected_service = expected_service
        @schema = service_schema
      end

      # @param [Aws::ECS::Types::Service] actual_service
      # @return [Boolean]
      def different?(actual_service)
        !@schema.same?(actual_service.to_h, @expected_service)
      end

      private

      def service_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:desired_count, Schema::Integer.new)
          struct.member(:task_definition, Schema::String.new)
          struct.member(:deployment_configuration, Schema::WithDefault.new(deployment_configuration_schema, default_configuration))
        end
      end

      def deployment_configuration_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:maximum_percent, Schema::Integer.new)
          struct.member(:minimum_healthy_percent, Schema::Integer.new)
        end
      end

      def default_configuration
        {
          maximum_percent: 200,
          minimum_healthy_percent: 100,
        }
      end
    end
  end
end
