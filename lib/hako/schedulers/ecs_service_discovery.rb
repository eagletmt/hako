# frozen_string_literal: true

require 'aws-sdk-servicediscovery'
require 'hako'
require 'hako/error'
require 'hako/schedulers/ecs_service_discovery_service_comparator'

module Hako
  module Schedulers
    class EcsServiceDiscovery
      # @param [Array<Hash>] config
      # @param [Boolean] dry_run
      # @param [String] region
      def initialize(config, region, dry_run:)
        @region = region
        @config = config
        @dry_run = dry_run
      end

      # @return [void]
      def apply
        @config.map do |service_discovery|
          service = service_discovery.fetch('service')
          namespace_id = service.fetch('namespace_id')
          namespace = get_namespace(namespace_id)
          if !namespace
            raise Error.new("Service discovery namespace #{namespace_id} not found")
          elsif namespace.type != 'DNS_PRIVATE'
            raise Error.new("ECS only supports registering a service into a private DNS namespace: #{namespace.name} (#{namespace_id})")
          end

          service_name = service.fetch('name')
          current_service = find_service(namespace_id, service_name)
          if !current_service
            if @dry_run
              Hako.logger.info("Created service discovery service #{service_name} (dry-run)")
            else
              current_service = create_service(service)
              Hako.logger.info("Created service discovery service #{service_name} (#{current_service.id})")
            end
          else
            if service_changed?(service, current_service)
              if @dry_run
                Hako.logger.info("Updated service discovery service #{service_name} (#{current_service.id}) (dry-run)")
              else
                update_service(current_service.id, service)
                Hako.logger.info("Updated service discovery service #{service_name} (#{current_service.id})")
              end
            end
            warn_disallowed_service_change(service, current_service)
          end
        end
      end

      # @return [void]
      def status(service_registries)
        service_registries.each do |service_registry|
          service_id = service_registry.registry_arn.slice(%r{service/(.+)\z}, 1)
          service = get_service(service_id)
          next unless service

          namespace = get_namespace(service.namespace_id)
          instances = service_discovery_client.list_instances(service_id: service.id).flat_map(&:instances)
          puts "  #{service.name}.#{namespace.name} instance_count=#{instances.size}"
          instances.each do |instance|
            instance_attributes = instance.attributes.map { |k, v| "#{k}=#{v}" }.join(', ')
            puts "    #{instance.id} #{instance_attributes}"
          end
        end
      end

      # @return [void]
      def remove(service_registries)
        service_registries.each do |service_registry|
          service_id = service_registry.registry_arn.slice(%r{service/(.+)\z}, 1)
          service = get_service(service_id)
          unless service
            Hako.logger.info("Service discovery service #{service_name} (#{service_id}) doesn't exist")
            next
          end
          if @dry_run
            Hako.logger.info("Deleted service discovery service #{service.name} (#{service.id}) (dry-run)")
          else
            deleted = false
            10.times do |i|
              sleep 10 unless i.zero?
              begin
                service_discovery_client.delete_service(id: service.id)
                deleted = true
                break
              rescue Aws::ServiceDiscovery::Errors::ResourceInUse => e
                Hako.logger.warn("#{e.class}: #{e.message}")
              end
            end
            unless deleted
              raise Error.new("Unable to delete service discovery service #{service.name} (#{service.id})")
            end

            Hako.logger.info("Deleted service discovery service #{service.name} (#{service.id})")
          end
        end
      end

      # @return [Hash]
      def service_registries
        @config.map do |service_discovery|
          service = service_discovery.fetch('service')
          namespace_id = service.fetch('namespace_id')
          service_name = service.fetch('name')
          current_service = find_service(namespace_id, service_name)
          unless current_service
            raise Error.new("Service discovery service #{service_name} not found")
          end

          {
            container_name: service_discovery['container_name'],
            container_port: service_discovery['container_port'],
            port: service_discovery['port'],
            registry_arn: current_service.arn,
          }.reject { |_, v| v.nil? }
        end
      end

      private

      # @param [String] namespace_id
      # @param [String] service_name
      # @return [Aws::ServiceDiscovery::Types::ServiceSummary, nil]
      def find_service(namespace_id, service_name)
        params = {
          filters: [
            name: 'NAMESPACE_ID',
            values: [namespace_id],
            condition: 'EQ',
          ],
        }
        services = service_discovery_client.list_services(params).flat_map(&:services)
        services.find { |service| service.name == service_name }
      end

      # @return [Aws::ServiceDiscovery::Client]
      def service_discovery_client
        @service_discovery_client ||= Aws::ServiceDiscovery::Client.new(region: @region)
      end

      # @param [Hash] service
      # @return [Aws::ServiceDiscovery::Types::Service]
      def create_service(service)
        service_discovery_client.create_service(create_service_params(service)).service
      end

      # @param [Hash] service
      # @return [Hash]
      def create_service_params(service)
        dns_config = service.fetch('dns_config')
        params = {
          name: service.fetch('name'),
          namespace_id: service['namespace_id'],
          description: service['description'],
          dns_config: {
            namespace_id: dns_config['namespace_id'],
            routing_policy: dns_config.fetch('routing_policy', 'MULTIVALUE'),
          },
        }
        params[:dns_config][:dns_records] = dns_config.fetch('dns_records').map do |dns_record|
          {
            type: dns_record.fetch('type'),
            ttl: dns_record.fetch('ttl'),
          }
        end
        if (health_check_custom_config = service['health_check_custom_config'])
          params[:health_check_custom_config] = {
            failure_threshold: health_check_custom_config['failure_threshold'],
          }
        end
        params
      end

      # @param [Hash] expected_service
      # @param [Aws::ServiceDiscovery::Types::ServiceSummary] actual_service
      # @return [Boolean]
      def service_changed?(expected_service, actual_service)
        EcsServiceDiscoveryServiceComparator.new(update_service_params(expected_service)).different?(actual_service)
      end

      # @param [String] service_id
      # @param [Hash] service
      def update_service(service_id, service)
        operation_id = service_discovery_client.update_service(
          id: service_id,
          service: update_service_params(service),
        ).operation_id
        operation = wait_for_operation(operation_id)
        if operation.status != 'SUCCESS'
          raise Error.new("Unable to update service discovery service (#{operation.error_code}): #{operation.error_message}")
        end
      end

      # @param [Hash] service
      # @return [Hash]
      def update_service_params(service)
        dns_config = service.fetch('dns_config')
        params = {
          description: service['description'],
          dns_config: {},
        }
        params[:dns_config][:dns_records] = dns_config.fetch('dns_records').map do |dns_record|
          {
            type: dns_record.fetch('type'),
            ttl: dns_record.fetch('ttl'),
          }
        end
        params
      end

      # @param [String] service_id
      # @return [Aws::ServiceDiscovery::Types::GetOperationResponse]
      def wait_for_operation(operation_id)
        loop do
          operation = service_discovery_client.get_operation(operation_id: operation_id).operation
          return operation if %w[SUCCESS FAIL].include?(operation.status)

          sleep 10
        end
      end

      # @param [String] service_id
      # @return [Aws::ServiceDiscovery::Types::Service, nil]
      def get_service(service_id)
        service_discovery_client.get_service(id: service_id).service
      rescue Aws::ServiceDiscovery::Errors::ServiceNotFound
        nil
      end

      # @param [String] namespace_id
      # @return [Aws::ServiceDiscovery::Types::Namespace, nil]
      def get_namespace(namespace_id)
        service_discovery_client.get_namespace(id: namespace_id).namespace
      rescue Aws::ServiceDiscovery::Errors::NamespaceNotFound
        nil
      end

      # @param [Hash] expected_service
      # @param [Aws::ServiceDiscovery::Types::ServiceSummary] actual_service
      # @return [void]
      def warn_disallowed_service_change(expected_service, actual_service)
        expected_service = create_service_params(expected_service)
        if expected_service.dig(:dns_config, :routing_policy) != actual_service.dns_config.routing_policy
          Hako.logger.warn("Ignoring updated service_discovery.dns_config.routing_policy in the configuration, because AWS doesn't allow updating it for now.")
        end
        if expected_service[:health_check_custom_config] != actual_service.health_check_custom_config&.to_h
          Hako.logger.warn("Ignoring updated service_discovery.health_check_custom_config in the configuration, because AWS doesn't allow updating it for now.")
        end
      end
    end
  end
end
