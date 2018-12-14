# frozen_string_literal: true

require 'hako/schema'

module Hako
  module Schedulers
    class EcsServiceDiscoveryServiceComparator
      # @param [Hash] expected_service
      def initialize(expected_service)
        @expected_service = expected_service
        @schema = service_schema
      end

      # @param [Aws::ServiceDiscovery::Types::ServiceSummary] actual_service
      # @return [Boolean]
      def different?(actual_service)
        !@schema.same?(actual_service.to_h, @expected_service)
      end

      private

      def service_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:description, Schema::Nullable.new(Schema::String.new))
          struct.member(:dns_config, dns_config_schema)
        end
      end

      def dns_config_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:dns_records, Schema::UnorderedArray.new(dns_records_schema))
        end
      end

      def dns_records_schema
        Schema::Structure.new.tap do |struct|
          struct.member(:ttl, Schema::Integer.new)
          struct.member(:type, Schema::String.new)
        end
      end
    end
  end
end
