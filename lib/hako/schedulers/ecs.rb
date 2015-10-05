require 'aws-sdk'
require 'hako'
require 'hako/error'
require 'hako/scheduler'
require 'hako/schedulers/ecs_definition_comparator'

module Hako
  module Schedulers
    class Ecs < Scheduler
      DEFAULT_CLUSTER = 'default'
      DEFAULT_FRONT_PORT = 10000

      def initialize(app_id, options)
        @app_id = app_id
        @cluster = options.fetch('cluster', DEFAULT_CLUSTER)
        @desired_count = options.fetch('desired_count') { validation_error!('desired_count must be set') }
        @cpu = options.fetch('cpu') { validation_error!('cpu must be set') }
        @memory = options.fetch('memory') { validation_error!('memory must be set') }
        region = options.fetch('region') { validation_error!('region must be set') }
        @ecs = Aws::ECS::Client.new(region: region)
        @elb = Aws::ElasticLoadBalancing::Client.new(region: region)
        @elb_config = options.fetch('elb', nil)
      end

      def deploy(image_tag, env, port_mapping, front)
        front_env = {
          'AWS_DEFAULT_REGION' => front.config.s3.region,
          'S3_CONFIG_BUCKET' => front.config.s3.bucket,
          'S3_CONFIG_KEY' => front.config.s3.key(@app_id),
        }
        front_port = determine_front_port(front)
        task_definition = register_task_definition(image_tag, env, port_mapping, front.config, front_env, front_port)
        if task_definition == :noop
          Hako.logger.info "Task definition isn't changed"
          task_definition = @ecs.describe_task_definition(task_definition: @app_id).task_definition
        else
          Hako.logger.info "Registered task definition: #{task_definition.task_definition_arn}"
          upload_front_config(@app_id, front, port_mapping[:container_port])
          Hako.logger.info "Uploaded front configuration to s3://#{front.config.s3.bucket}/#{front.config.s3.key(@app_id)}"
        end
        service = create_or_update_service(task_definition.task_definition_arn, front_port)
        if service == :noop
          Hako.logger.info "Service isn't changed"
        else
          Hako.logger.info "Updated service: #{service.service_arn}"
          wait_for_ready(service)
        end
        Hako.logger.info "Deployment completed"
      end

      private

      def determine_front_port(front)
        service = @ecs.describe_services(cluster: @cluster, services: [@app_id]).services[0]
        if service
          find_front_port(service)
        else
          max_port = -1
          @ecs.list_services(cluster: @cluster).each do |page|
            unless page.service_arns.empty?
              @ecs.describe_services(cluster: @cluster, services: page.service_arns).services.each do |service|
                max_port = [max_port, find_front_port(service)].max
              end
            end
          end
          if max_port == -1
            DEFAULT_FRONT_PORT
          else
            max_port+1
          end
        end
      end

      def find_front_port(service)
        task_definition = @ecs.describe_task_definition(task_definition: service.task_definition).task_definition
        container_definitions = {}
        task_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end
        container_definitions['front'].port_mappings[0].host_port
      end

      def task_definition_changed?(front, app)
        task_definition = @ecs.describe_task_definition(task_definition: @app_id).task_definition
        container_definitions = {}
        task_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end
        different_definition?(front, container_definitions['front']) || different_definition?(app, container_definitions['app'])
      rescue Aws::ECS::Errors::ClientException
        # Task definition does not exist
        true
      end

      def different_definition?(expected_container, actual_container)
        EcsDefinitionComparator.new(expected_container).different?(actual_container)
      end

      def register_task_definition(image_tag, env, port_mapping, front_config, front_env, front_port)
        front = front_container(front_config, front_env, front_port)
        app = app_container(image_tag, env, port_mapping)
        if task_definition_changed?(front, app)
          @ecs.register_task_definition(
            family: @app_id,
            container_definitions: [front, app],
          ).task_definition
        else
          :noop
        end
      end

      def front_container(front_config, env, front_port)
        environment = env.map { |k, v| { name: k, value: v } }
        {
          name: 'front',
          image: front_config.image_tag,
          cpu: 100,
          memory: 100,
          links: ['app:app'],
          port_mappings: [{container_port: 80, host_port: front_port, protocol: 'tcp'}],
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

      def create_or_update_service(task_definition_arn, front_port)
        services = @ecs.describe_services(cluster: @cluster, services: [@app_id]).services
        if services.empty?
          params = {
            cluster: @cluster,
            service_name: @app_id,
            task_definition: task_definition_arn,
            desired_count: @desired_count,
          }
          if @elb_config
            name = find_or_create_load_balancer(front_port)
            params.merge!(
              load_balancers: [
                {
                  load_balancer_name: name,
                  container_name: 'front',
                  container_port: 80,
                },
              ],
              role: @elb_config.fetch('role'),
            )
          end
          @ecs.create_service(params).service
        else
          service = services[0]
          if service.status != 'ACTIVE'
            raise Error.new("Service #{service.service_arn} is already exist but the status is #{service.status}")
          end
          params = {
            cluster: @cluster,
            service: @app_id,
            desired_count: @desired_count,
            task_definition: task_definition_arn,
          }
          if service_changed?(service, params)
            @ecs.update_service(params).service
          else
            :noop
          end
        end
      end

      SERVICE_KEYS = %i[desired_count task_definition]

      def service_changed?(service, params)
        SERVICE_KEYS.each do |key|
          if service.public_send(key) != params[key]
            return true
          end
        end
        false
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

      def find_or_create_load_balancer(front_port)
        unless load_balancer_exist?(elb_name)
          listeners = @elb_config.fetch('listeners').map do |l|
            {
              protocol: 'tcp',
              load_balancer_port: l.fetch('load_balancer_port'),
              instance_port: front_port,
              ssl_certificate_id: l.fetch('ssl_certificate_id', nil),
            }
          end
          lb = @elb.create_load_balancer(
            load_balancer_name: elb_name,
            listeners: listeners,
            subnets: @elb_config.fetch('subnets'),
            security_groups: @elb_config.fetch('security_groups'),
            tags: @elb_config.fetch('tags', {}).map { |k, v| { key: k, value: v.to_s } },
          )
          Hako.logger.info "Created ELB #{lb.dns_name} with instance_port=#{front_port}"
        end
        elb_name
      end

      def load_balancer_exist?(name)
        @elb.describe_load_balancers(load_balancer_names: [elb_name])
        true
      rescue Aws::ElasticLoadBalancing::Errors::LoadBalancerNotFound
        false
      end

      def elb_name
        "hako-#{@app_id}"
      end
    end
  end
end
