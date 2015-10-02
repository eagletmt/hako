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

      def deploy(image_tag, env, port_mapping, front)
        front_env = {
          'AWS_DEFAULT_REGION' => front.config.s3.region,
          'S3_CONFIG_BUCKET' => front.config.s3.bucket,
          'S3_CONFIG_KEY' => front.config.s3.key(@app_id),
        }
        unless deploy_needed?(image_tag, env, port_mapping, front.config, front_env)
          Hako.logger.info "Deployment isn't needed"
          return
        end
        task_definition = register_task_definition(image_tag, env, port_mapping, front.config, front_env)
        Hako.logger.info "Registered task-definition: #{task_definition.task_definition_arn}"
        upload_front_config(@app_id, front, port_mapping[:host_port])
        Hako.logger.info "Uploaded front configuration to s3://#{front.config.s3.bucket}/#{front.config.s3.key(@app_id)}"
        service = create_or_update_service(task_definition.task_definition_arn)
        Hako.logger.info "Updated service: #{service.service_arn}"
        wait_for_ready(service)
        Hako.logger.info "Deployment completed"
      end

      private

      def deploy_needed?(image_tag, env, port_mapping, front_config, front_env)
        task_definition = @ecs.describe_task_definition(task_definition: @app_id).task_definition
        container_definitions = {}
        task_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end
        different_definition?(front_container(front_config, front_env), container_definitions['front']) || different_definition?(app_container(image_tag, env, port_mapping), container_definitions['app'])
      rescue Aws::ECS::Errors::ClientException
        # Task definition does not exist
        true
      end

      def different_definition?(expected_container, actual_container)
        EcsDefinitionComparator.new(expected_container).different?(actual_container)
      end

      def register_task_definition(image_tag, env, port_mapping, front_config, front_env)
        @ecs.register_task_definition(
          family: @app_id,
          container_definitions: [
            front_container(front_config, front_env),
            app_container(image_tag, env, port_mapping),
          ],
        ).task_definition
      end

      def front_container(front_config, env)
        environment = env.map { |k, v| { name: k, value: v } }
        {
          name: 'front',
          image: front_config.image_tag,
          cpu: 100,
          memory: 100,
          links: ['app:app'],
          port_mappings: [{container_port: 80, host_port: 80, protocol: 'tcp'}],
          essential: true,
          environment: environment,
        }
      end

      def app_container(image_tag, env, port_mapping)
        environment = env.map { |k, v| { name: k, value: v } }
        {
          name: 'app',
          image: image_tag,
          cpu: @cpu,
          memory: @memory,
          links: [],
          port_mappings: [port_mapping].compact,
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
