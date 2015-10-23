require 'aws-sdk'
require 'hako'
require 'hako/scheduler'
require 'hako/schedulers/ecs_definition_comparator'
require 'hako/schedulers/ecs_elb'

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
        @role = options.fetch('role', nil)
        @ecs = Aws::ECS::Client.new(region: region)
        @elb = EcsElb.new(app_id, Aws::ElasticLoadBalancing::Client.new(region: region), options.fetch('elb', nil))
        @ec2 = Aws::EC2::Client.new(region: region)
      end

      def deploy(image_tag, env, app_port, front, force: false)
        @force_mode = force
        front_env = {
          'AWS_DEFAULT_REGION' => front.config.s3.region,
          'S3_CONFIG_BUCKET' => front.config.s3.bucket,
          'S3_CONFIG_KEY' => front.config.s3.key(@app_id),
        }
        front_port = determine_front_port
        task_definition = register_task_definition(image_tag, env, front.config, front_env, front_port)
        if task_definition == :noop
          Hako.logger.info "Task definition isn't changed"
          task_definition = @ecs.describe_task_definition(task_definition: @app_id).task_definition
        else
          Hako.logger.info "Registered task definition: #{task_definition.task_definition_arn}"
          upload_front_config(@app_id, front, app_port)
          Hako.logger.info "Uploaded front configuration to s3://#{front.config.s3.bucket}/#{front.config.s3.key(@app_id)}"
        end
        service = create_or_update_service(task_definition.task_definition_arn, front_port)
        if service == :noop
          Hako.logger.info "Service isn't changed"
        else
          Hako.logger.info "Updated service: #{service.service_arn}"
          wait_for_ready(service)
        end
        Hako.logger.info 'Deployment completed'
      end

      def status
        service = get_service
        unless service
          puts 'Unavailable'
          exit 1
        end

        unless service.load_balancers.empty?
          lb = service.load_balancers[0]
          lb_detail = @elb.describe_load_balancer
          puts 'Load balancer:'
          lb_detail.listener_descriptions.each do |ld|
            l = ld.listener
            puts "  #{lb_detail.dns_name}:#{l.load_balancer_port} -> #{lb.container_name}:#{lb.container_port}"
          end
        end

        puts 'Deployments:'
        service.deployments.each do |d|
          abbrev_task_definition = d.task_definition.slice(%r{task-definition/(.+)\z}, 1)
          puts "  [#{d.status}] #{abbrev_task_definition} desired_count=#{d.desired_count}, pending_count=#{d.pending_count}, running_count=#{d.running_count}"
        end

        puts 'Tasks:'
        @ecs.list_tasks(cluster: @cluster, service_name: @app_id).each do |page|
          unless page.task_arns.empty?
            tasks = @ecs.describe_tasks(cluster: @cluster, tasks: page.task_arns).tasks
            container_instances = {}
            @ecs.describe_container_instances(cluster: @cluster, container_instances: tasks.map(&:container_instance_arn)).container_instances.each do |ci|
              container_instances[ci.container_instance_arn] = ci
            end
            ec2_instances = {}
            @ec2.describe_instances(instance_ids: container_instances.values.map(&:ec2_instance_id)).reservations.each do |r|
              r.instances.each do |i|
                ec2_instances[i.instance_id] = i
              end
            end
            tasks.each do |task|
              ci = container_instances[task.container_instance_arn]
              instance = ec2_instances[ci.ec2_instance_id]
              print "  [#{task.last_status}]: #{ci.ec2_instance_id}"
              if instance
                name_tag = instance.tags.find { |t| t.key == 'Name' }
                if name_tag
                  print " (#{name_tag.value})"
                end
              end
              puts
            end
          end
        end

        puts 'Events:'
        service.events.first(10).each do |e|
          puts "  #{e.created_at}: #{e.message}"
        end
      end

      def remove
        service = get_service
        if service
          @ecs.delete_service(cluster: @cluster, service: @app_id)
          Hako.logger.info "#{service.service_arn} is deleted"
        else
          puts "Service #{@app_id} doesn't exist"
        end

        @elb.destroy
      end

      private

      def get_service
        service = @ecs.describe_services(cluster: @cluster, services: [@app_id]).services[0]
        if service && service.status != 'INACTIVE'
          service
        else
          nil
        end
      end

      def determine_front_port
        service = get_service
        if service
          find_front_port(service)
        else
          max_port = -1
          @ecs.list_services(cluster: @cluster).each do |page|
            unless page.service_arns.empty?
              @ecs.describe_services(cluster: @cluster, services: page.service_arns).services.each do |s|
                if s.status != 'INACTIVE'
                  max_port = [max_port, find_front_port(s)].max
                end
              end
            end
          end
          if max_port == -1
            DEFAULT_FRONT_PORT
          else
            max_port + 1
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
        if @force_mode
          return true
        end
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

      def register_task_definition(image_tag, env, front_config, front_env, front_port)
        front = front_container(front_config, front_env, front_port)
        app = app_container(image_tag, env)
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
          port_mappings: [{ container_port: 80, host_port: front_port, protocol: 'tcp' }],
          essential: true,
          environment: environment,
        }
      end

      def app_container(image_tag, env)
        environment = env.map { |k, v| { name: k, value: v } }
        {
          name: 'app',
          image: image_tag,
          cpu: @cpu,
          memory: @memory,
          links: [],
          port_mappings: [],
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
            role: @role,
          }
          name = @elb.find_or_create_load_balancer(front_port)
          if name
            params.merge!(
              load_balancers: [
                {
                  load_balancer_name: name,
                  container_name: 'front',
                  container_port: 80,
                },
              ],
            )
          end
          @ecs.create_service(params).service
        else
          params = {
            cluster: @cluster,
            service: @app_id,
            desired_count: @desired_count,
            task_definition: task_definition_arn,
          }
          if service_changed?(services[0], params)
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
        latest_event_id = service.events[0].id
        loop do
          s = @ecs.describe_services(cluster: service.cluster_arn, services: [service.service_arn]).services[0]
          s.events.each do |e|
            if e.id == latest_event_id
              break
            end
            Hako.logger.info "#{e.created_at}: #{e.message}"
          end
          latest_event_id = s.events[0].id
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
