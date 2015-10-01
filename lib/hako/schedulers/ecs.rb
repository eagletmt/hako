require 'aws-sdk'
require 'hako'
require 'hako/scheduler'

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

      def deploy(image_tag, env, port_mappings)
        task_definition = register_task_definition(image_tag, env, port_mappings)
        Hako.logger.info "Registered task-definition: #{task_definition.task_definition_arn}"
        service = create_or_update_service(task_definition.task_definition_arn)
        Hako.logger.info "Updated service: #{service.service_arn}"
        wait_for_ready(service)
        Hako.logger.info "Deployment completed"
      end

      private

      def register_task_definition(image_tag, env, port_mappings)
        @ecs.register_task_definition(
          family: @app_id,
          container_definitions: [
            front_container,
            app_container(image_tag, env, port_mappings),
          ],
        ).task_definition
      end

      def front_container
        # TODO: Read from config
        {
          name: 'front',
          image: 'nginx:1.9.5',
          cpu: 100,
          memory: 100,
          links: [],
          port_mappings: [{container_port: 80, host_port: 80, protocol: 'tcp'}],
          essential: true,
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
