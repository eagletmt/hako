require 'aws-sdk'
require 'hako'
require 'hako/scheduler'
require 'hako/schedulers/ecs_definition_comparator'

module Hako
  module Schedulers
    class Ecs < Scheduler
      DEFAULT_CLUSTER = 'default'

      def initialize(app_id, options)
        @app_id = app_id
        @cluster = options.fetch('cluster', DEFAULT_CLUSTER)
        @desired_count = options.fetch('desired_count') { validation_error!('desired_count must be set') }
        @cpu = options.fetch('cpu') { validation_error!('cpu must be set') }
        @memory = options.fetch('memory') { validation_error!('memory must be set') }
        region = options.fetch('region') { validation_error!('region must be set') }
        @ecs = Aws::ECS::Client.new(region: region)
      end

      def deploy(image_tag, env, port_mappings, front_config)
        unless deploy_needed?(image_tag, env, port_mappings, front_config)
          Hako.logger.info "Deployment isn't needed"
          return
        end
        task_definition = register_task_definition(image_tag, env, port_mappings, front_config)
        Hako.logger.info "Registered task-definition: #{task_definition.task_definition_arn}"
        service = create_or_update_service(task_definition.task_definition_arn)
        Hako.logger.info "Updated service: #{service.service_arn}"
        wait_for_ready(service)
        Hako.logger.info "Deployment completed"
      end

      private

      def deploy_needed?(image_tag, env, port_mappings, front_config)
        task_definition = @ecs.describe_task_definition(task_definition: @app_id).task_definition
        container_definitions = {}
        task_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end
        different_definition?(front_container(front_config), container_definitions['front']) || different_definition?(app_container(image_tag, env, port_mappings), container_definitions['app'])
      rescue Aws::ECS::Errors::ClientException
        # Task definition does not exist
        true
      end

      def different_definition?(expected_container, actual_container)
        EcsDefinitionComparator.new(expected_container).different?(actual_container)
      end

      def register_task_definition(image_tag, env, port_mappings, front_config)
        @ecs.register_task_definition(
          family: @app_id,
          container_definitions: [
            front_container(front_config),
            app_container(image_tag, env, port_mappings),
          ],
        ).task_definition
      end

      def front_container(front_config)
        {
          name: 'front',
          image: front_config.image_tag,
          cpu: 1,
          memory: 1,
          links: ['app:app'],
          port_mappings: [{container_port: 80, host_port: 80, protocol: 'tcp'}],
          essential: true,
          environment: [],
        }
      end

      def app_container(image_tag, env, port_mappings)
        environment = env.map { |k, v| { name: k, value: v } }
        {
          name: 'app',
          image: image_tag,
          cpu: @cpu,
          memory: @memory,
          links: [],
          port_mappings: port_mappings,
          essential: true,
          environment: environment,
        }
      end

      def create_or_update_service(task_definition_arn)
        services = @ecs.describe_services(cluster: @cluster, services: [@app_id]).services
        if services.empty?
          @ecs.create_service(
            cluster: @cluster,
            service_name: @app_id,
            task_definition: task_definition_arn,
            # TODO: load_balancers
            desired_count: @desired_count,
          ).service
        else
          @ecs.update_service(
            cluster: @cluster,
            service: @app_id,
            desired_count: @desired_count,
            task_definition: task_definition_arn,
          ).service
        end
      end

      def wait_for_ready(service)
        loop do
          s = @ecs.describe_services(cluster: service.cluster_arn, services: [service.service_arn]).services[0]
          finished = s.deployments.all? { |d| d.status != 'ACTIVE' }
          if finished
            return
          else
            sleep 1
          end
        end
      end
    end
  end
end
