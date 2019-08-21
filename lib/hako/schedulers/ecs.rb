# frozen_string_literal: true

require 'aws-sdk-autoscaling'
require 'aws-sdk-ec2'
require 'aws-sdk-ecs'
require 'aws-sdk-s3'
require 'aws-sdk-sns'
require 'aws-sdk-ssm'
require 'hako'
require 'hako/error'
require 'hako/scheduler'
require 'hako/schedulers/ecs_autoscaling'
require 'hako/schedulers/ecs_definition_comparator'
require 'hako/schedulers/ecs_elb'
require 'hako/schedulers/ecs_elb_v2'
require 'hako/schedulers/ecs_service_comparator'
require 'hako/schedulers/ecs_service_discovery'
require 'hako/schedulers/ecs_volume_comparator'

module Hako
  module Schedulers
    class Ecs < Scheduler
      class NoTasksStarted < Error
      end

      DEFAULT_CLUSTER = 'default'
      DEFAULT_FRONT_PORT = 10000

      attr_reader :task

      # @param [Hash<String, Object>] options
      def configure(options)
        @cluster = options.fetch('cluster', DEFAULT_CLUSTER)
        @desired_count = options.fetch('desired_count', nil)
        @region = options.fetch('region') { validation_error!('region must be set') }
        @role = options.fetch('role', nil)
        @task_role_arn = options.fetch('task_role_arn', nil)
        @ecs_elb_options = options.fetch('elb', nil)
        @ecs_elb_v2_options = options.fetch('elb_v2', nil)
        @ecs_elb_v2s_options = options.fetch('elb_v2s', nil)
        if @ecs_elb_options && @ecs_elb_v2_options && @ecs_elb_v2s_options
          validation_error!('Cannot specify both elb and elb_v2')
        end
        @network_mode = options.fetch('network_mode', nil)
        if @network_mode == 'awsvpc' && @ecs_elb_v2_options
          # awsvpc network mode requires ELB target group with target_type=ip
          @ecs_elb_v2_options['target_type'] = 'ip'
        end
        @dynamic_port_mapping = options.fetch('dynamic_port_mapping', @ecs_elb_options.nil?)
        @health_check_grace_period_seconds = options.fetch('health_check_grace_period_seconds') do
          @ecs_elb_options || @ecs_elb_v2_options || @ecs_elb_v2s_options ? 0 : nil
        end
        if options.key?('autoscaling')
          @autoscaling = EcsAutoscaling.new(options.fetch('autoscaling'), @region, ecs_elb_client, dry_run: @dry_run)
        end
        @autoscaling_group_for_oneshot = options.fetch('autoscaling_group_for_oneshot', nil)
        @autoscaling_topic_for_oneshot = options.fetch('autoscaling_topic_for_oneshot', nil)
        if @autoscaling_topic_for_oneshot && !@autoscaling_group_for_oneshot
          validation_error!('autoscaling_group_for_oneshot must be set when autoscaling_topic_for_oneshot is set')
        end
        @oneshot_notification_prefix = options.fetch('oneshot_notification_prefix', nil)
        if options.key?('deployment_configuration')
          @deployment_configuration = {}
          %i[maximum_percent minimum_healthy_percent].each do |key|
            @deployment_configuration[key] = options.fetch('deployment_configuration')[key.to_s]
          end
        else
          @deployment_configuration = nil
        end
        @placement_constraints = options.fetch('placement_constraints', [])
        @placement_strategy = options.fetch('placement_strategy', [])
        @scheduling_strategy = options.fetch('scheduling_strategy', nil)
        @execution_role_arn = options.fetch('execution_role_arn', nil)
        @cpu = options.fetch('cpu', nil)
        @memory = options.fetch('memory', nil)
        @requires_compatibilities = options.fetch('requires_compatibilities', nil)
        @launch_type = options.fetch('launch_type', nil)
        @platform_version = options.fetch('platform_version', nil)
        if options.key?('network_configuration')
          network_configuration = options.fetch('network_configuration')
          if network_configuration.key?('awsvpc_configuration')
            awsvpc_configuration = network_configuration.fetch('awsvpc_configuration')
            @network_configuration = {
              awsvpc_configuration: {
                subnets: awsvpc_configuration.fetch('subnets'),
                security_groups: awsvpc_configuration.fetch('security_groups', nil),
                assign_public_ip: awsvpc_configuration.fetch('assign_public_ip', nil),
              },
            }
          end
        end
        if options['service_discovery']
          @service_discovery = EcsServiceDiscovery.new(options.fetch('service_discovery'), @region, dry_run: @dry_run)
        end

        @started_at = nil
        @container_instance_arn = nil
      end

      # @param [Hash<String, Container>] containers
      # @return [nil]
      def deploy(containers)
        if @desired_count.nil? && @scheduling_strategy != 'DAEMON'
          validation_error!('desired_count must be set')
        end
        front_port = determine_front_port
        unless @dry_run
          ecs_elb_client.find_or_create_load_balancer(front_port)
        end
        @scripts.each { |script| script.deploy_started(containers, front_port) }
        definitions = create_definitions(containers)

        if @dry_run
          volumes_definition.each do |d|
            print_volume_definition_in_cli_format(d)
          end
          definitions.each do |d|
            print_definition_in_cli_format(d)
            check_secrets(d)
          end
          if @autoscaling
            @autoscaling.apply(Aws::ECS::Types::Service.new(cluster_arn: @cluster, service_name: @app_id))
          end
          ecs_elb_client.modify_attributes
          if @service_discovery
            @service_discovery.apply
          end
        else
          current_service = describe_service
          task_definition_changed, task_definition = register_task_definition(definitions)
          if task_definition_changed
            Hako.logger.info "Registered task definition: #{task_definition.task_definition_arn}"
          else
            Hako.logger.info "Task definition isn't changed: #{task_definition.task_definition_arn}"
          end
          current_service ||= create_initial_service(task_definition.task_definition_arn, front_port)
          service = update_service(current_service, task_definition.task_definition_arn)
          if service == :noop
            Hako.logger.info "Service isn't changed"
            if @autoscaling
              @autoscaling.apply(current_service)
            end
            ecs_elb_client.modify_attributes
            if @service_discovery
              @service_discovery.apply
            end
          else
            Hako.logger.info "Updated service: #{service.service_arn}"
            if @autoscaling
              @autoscaling.apply(service)
            end
            ecs_elb_client.modify_attributes
            if @service_discovery
              @service_discovery.apply
            end
            unless wait_for_ready(service)
              @scripts.each { |script| script.deploy_failed(containers, task_ids: @started_task_ids) }
              if task_definition_changed
                Hako.logger.error("Rolling back to #{current_service.task_definition}")
                update_service(service, current_service.task_definition)
                ecs_client.deregister_task_definition(task_definition: service.task_definition)
                Hako.logger.debug "Deregistered #{service.task_definition}"
              end
              raise Error.new('Deployment cancelled')
            end
          end
          Hako.logger.info 'Deployment completed'
        end
      end

      def rollback
        current_service = describe_service
        unless current_service
          Hako.logger.error 'Unable to find service'
          exit 1
        end

        task_definition = ecs_client.describe_task_definition(task_definition: current_service.task_definition).task_definition
        current_definition = "#{task_definition.family}:#{task_definition.revision}"
        target_definition = find_rollback_target(task_definition)
        Hako.logger.info "Current task definition is #{current_definition}. Rolling back to #{target_definition}"
        call_rollback_started(task_definition, target_definition)

        if @dry_run
          Hako.logger.info 'Deployment completed (dry-run)'
        else
          service = ecs_client.update_service(cluster: current_service.cluster_arn, service: current_service.service_arn, task_definition: target_definition).service
          Hako.logger.info "Updated service: #{service.service_arn}"

          deregistered_definition = ecs_client.deregister_task_definition(task_definition: current_definition).task_definition
          Hako.logger.debug "Deregistered #{deregistered_definition.task_definition_arn}"

          wait_for_ready(service)
          Hako.logger.info 'Deployment completed'
        end
      end

      # @param [Hash<String, Container>] containers
      # @param [Array<String>] commands
      # @param [Hash<String, String>] env
      # @param [Boolean] no_wait
      # @return [Integer] Returns exit code
      def oneshot(containers, commands, env, no_wait: false)
        definitions = create_definitions(containers)

        if @dry_run
          volumes_definition.each do |d|
            print_volume_definition_in_cli_format(d)
          end
          definitions.each do |d|
            if d[:name] == 'app'
              d[:command] = commands
            end
            print_definition_in_cli_format(d, additional_env: env)
            check_secrets(d)
          end
          0
        else
          updated, task_definition = register_task_definition_for_oneshot(definitions)
          if updated
            Hako.logger.info "Registered task definition: #{task_definition.task_definition_arn}"
          else
            Hako.logger.info "Task definition isn't changed: #{task_definition.task_definition_arn}"
          end
          @task = run_task(task_definition, commands, env)
          Hako.logger.info "Started task: #{@task.task_arn}"
          @scripts.each { |script| script.oneshot_started(self) }
          if no_wait
            info = { cluster: @cluster, task_arn: @task.task_arn }
            puts JSON.dump(info)
            0
          else
            wait_for_oneshot_finish
          end
        end
      end

      # @return [nil]
      def stop_oneshot
        if @task
          Hako.logger.warn "Stopping #{@task.task_arn}"
          ecs_client.stop_task(cluster: @cluster, task: @task.task_arn, reason: 'Stopped by hako stop_oneshot')
          wait_for_oneshot_finish
        end
      end

      # @return [nil]
      def status
        service = describe_service
        unless service
          puts 'Unavailable'
          exit 1
        end

        unless service.load_balancers.empty?
          puts 'Load balancer:'
          ecs_elb_client.show_status(service.load_balancers[0])
        end

        puts 'Deployments:'
        service.deployments.each do |d|
          abbrev_task_definition = d.task_definition.slice(%r{task-definition/(.+)\z}, 1)
          puts "  [#{d.status}] #{abbrev_task_definition} desired_count=#{d.desired_count}, pending_count=#{d.pending_count}, running_count=#{d.running_count}"
        end

        puts 'Tasks:'
        ecs_client.list_tasks(cluster: @cluster, service_name: service.service_arn).each do |page|
          unless page.task_arns.empty?
            tasks = ecs_client.describe_tasks(cluster: @cluster, tasks: page.task_arns).tasks
            container_instance_arns = tasks.map(&:container_instance_arn).compact
            container_instances = {}
            unless container_instance_arns.empty?
              ecs_client.describe_container_instances(cluster: @cluster, container_instances: container_instance_arns).container_instances.each do |ci|
                container_instances[ci.container_instance_arn] = ci
              end
            end
            ec2_instances = {}
            unless container_instances.empty?
              ec2_client.describe_instances(instance_ids: container_instances.values.map(&:ec2_instance_id)).reservations.each do |r|
                r.instances.each do |i|
                  ec2_instances[i.instance_id] = i
                end
              end
            end
            tasks.each do |task|
              task_id = task.task_arn.slice(%r{task/(.+)\z}, 1)
              task_definition = task.task_definition_arn.slice(%r{task-definition/(.+)\z}, 1)
              print "  [#{task.last_status}] #{task_id} task_definition=#{task_definition}, desired_status=#{task.desired_status}"
              ci = container_instances[task.container_instance_arn]
              if ci
                print ", instance_id=#{ci.ec2_instance_id}"
                instance = ec2_instances[ci.ec2_instance_id]
                if instance
                  name_tag = instance.tags.find { |t| t.key == 'Name' }
                  if name_tag
                    print " (#{name_tag.value})"
                  end
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

        if @autoscaling
          puts 'Autoscaling:'
          @autoscaling.status(service)
        else
          puts 'Autoscaling: No'
        end

        if service.service_registries.empty?
          puts 'Service Discovery: No'
        else
          puts 'Service Discovery:'
          @service_discovery.status(service.service_registries)
        end
      end

      # @return [nil]
      def remove
        service = describe_service
        if service
          if @dry_run
            unless service.scheduling_strategy == 'DAEMON'
              Hako.logger.info "ecs_client.update_service(cluster: #{service.cluster_arn}, service: #{service.service_arn}, desired_count: 0)"
            end
            Hako.logger.info "ecs_client.delete_service(cluster: #{service.cluster_arn}, service: #{service.service_arn})"
          else
            unless service.scheduling_strategy == 'DAEMON'
              ecs_client.update_service(cluster: service.cluster_arn, service: service.service_arn, desired_count: 0)
            end
            ecs_client.delete_service(cluster: service.cluster_arn, service: service.service_arn)
            Hako.logger.info "#{service.service_arn} is deleted"
          end
          unless service.service_registries.empty?
            @service_discovery.remove(service.service_registries)
          end
        else
          puts "Service #{@app_id} doesn't exist"
        end

        ecs_elb_client.destroy
      end

      # @return [nil]
      def stop
        service = describe_service
        if service
          if @dry_run
            Hako.logger.info("ecs_client.update_service(cluster: #{service.cluster_arn}, service: #{service.service_arn}, desired_count: 0)")
          else
            ecs_client.update_service(cluster: service.cluster_arn, service: service.service_arn, desired_count: 0)
            Hako.logger.info("#{service.service_arn} is stopped")
          end
        else
          puts "Service #{@app_id} doesn't exist"
        end
      end

      private

      # @return [Aws::ECS::Client]
      def ecs_client
        @ecs_client ||= Aws::ECS::Client.new(region: @region)
      end

      # @return [Aws::EC2::Client]
      def ec2_client
        @ec2_client ||= Aws::EC2::Client.new(region: @region)
      end

      # @return [Aws::SSM::Client]
      def ssm_client
        @ssm_client ||= Aws::SSM::Client.new(region: @region)
      end

      # @return [EcsElb, EcsElbV2, EcsElbV2s]
      def ecs_elb_client
        @ecs_elb_client ||=
          if @ecs_elb_options
            EcsElb.new(@app_id, @region, @ecs_elb_options, dry_run: @dry_run)
          elsif @ecs_elb_v2_options
            EcsElbV2.new(@app_id, @region, @ecs_elb_v2_options, dry_run: @dry_run)
          else
            EcsElbV2s.new(@app_id, @region, @ecs_elb_v2s_options, dry_run: @dry_run)
          end
      end

      # @return [Aws::ECS::Types::Service, nil]
      def describe_service
        service = ecs_client.describe_services(cluster: @cluster, services: [@app_id]).services[0]
        if service && service.status != 'INACTIVE'
          service
        end
      end

      # @return [Fixnum]
      def determine_front_port
        if @network_mode == 'awsvpc'
          # When networkMode=awsvpc, the host ports and container ports in port mappings must match
          return nil
        elsif @dynamic_port_mapping
          return 0
        end
        if @dry_run
          return DEFAULT_FRONT_PORT
        end

        service = describe_service
        if service
          find_front_port(service)
        else
          new_front_port
        end
      end

      # @return [Fixnum]
      def new_front_port
        max_port = -1
        ecs_client.list_services(cluster: @cluster).each do |page|
          unless page.service_arns.empty?
            ecs_client.describe_services(cluster: @cluster, services: page.service_arns).services.each do |s|
              if s.status != 'INACTIVE'
                port = find_front_port(s)
                if port
                  max_port = [max_port, port].max
                end
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

      # @param [Aws::ECS::Types::Service] service
      # @return [Fixnum, nil]
      def find_front_port(service)
        task_definition = ecs_client.describe_task_definition(task_definition: service.task_definition).task_definition
        container_definitions = {}
        task_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end
        if container_definitions['front']
          container_definitions['front'].port_mappings[0].host_port
        end
      end

      # @param [Array<Hash>] desired_definitions
      # @param [Aws::ECS::Types::TaskDefinition] actual_definition
      # @return [Array<Boolean]
      def task_definition_changed?(desired_definitions, actual_definition)
        if @force
          return true
        end
        unless actual_definition
          # Initial deployment
          return true
        end

        actual_volume_definitions = {}
        actual_definition.volumes.each do |v|
          actual_volume_definitions[v.name] = v
        end
        container_definitions = {}
        actual_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end

        if actual_definition.task_role_arn != @task_role_arn
          return true
        end
        if volumes_definition.any? { |definition| different_volume?(definition, actual_volume_definitions.delete(definition[:name])) }
          return true
        end
        unless actual_volume_definitions.empty?
          return true
        end
        if desired_definitions.any? { |definition| different_definition?(definition, container_definitions.delete(definition[:name])) }
          return true
        end
        unless container_definitions.empty?
          return true
        end
        if actual_definition.cpu != @cpu
          return true
        end
        if actual_definition.memory != @memory
          return true
        end
        if actual_definition.network_mode != @network_mode
          return true
        end
        if actual_definition.execution_role_arn != @execution_role_arn
          return true
        end
        if actual_definition.requires_compatibilities != @requires_compatibilities
          return true
        end

        false
      end

      # @param [Hash] expected_volume
      # @param [Aws::ECS::Types::Volume] actual_volume
      # @return [Boolean]
      def different_volume?(expected_volume, actual_volume)
        EcsVolumeComparator.new(expected_volume).different?(actual_volume)
      end

      # @param [Hash] expected_container
      # @param [Aws::ECS::Types::ContainerDefinition] actual_container
      # @return [Boolean]
      def different_definition?(expected_container, actual_container)
        EcsDefinitionComparator.new(expected_container).different?(actual_container)
      end

      # @param [Array<Hash>] definitions
      # @return [Array<Boolean, Aws::ECS::Types::TaskDefinition>]
      def register_task_definition(definitions)
        current_task_definition = describe_task_definition(@app_id)
        if task_definition_changed?(definitions, current_task_definition)
          new_task_definition = ecs_client.register_task_definition(
            family: @app_id,
            task_role_arn: @task_role_arn,
            execution_role_arn: @execution_role_arn,
            network_mode: @network_mode,
            container_definitions: definitions,
            volumes: volumes_definition,
            requires_compatibilities: @requires_compatibilities,
            cpu: @cpu,
            memory: @memory,
          ).task_definition
          [true, new_task_definition]
        else
          [false, current_task_definition]
        end
      end

      # @param [Hash<String, Container>] containers
      # @return [nil]
      def create_definitions(containers)
        containers.map do |name, container|
          create_definition(name, container)
        end
      end

      # @param [Array<Hash>] definitions
      # @return [Array<Boolean, Aws::ECS::Types::TaskDefinition]
      def register_task_definition_for_oneshot(definitions)
        10.times do |i|
          begin
            family = "#{@app_id}-oneshot"
            current_task_definition = describe_task_definition(family)
            if task_definition_changed?(definitions, current_task_definition)
              new_task_definition = ecs_client.register_task_definition(
                family: family,
                task_role_arn: @task_role_arn,
                execution_role_arn: @execution_role_arn,
                network_mode: @network_mode,
                container_definitions: definitions,
                volumes: volumes_definition,
                requires_compatibilities: @requires_compatibilities,
                cpu: @cpu,
                memory: @memory,
              ).task_definition
              return [true, new_task_definition]
            else
              return [false, current_task_definition]
            end
          rescue Aws::ECS::Errors::ClientException => e
            if e.message.include?('Too many concurrent attempts to create a new revision of the specified family')
              Hako.logger.error(e.message)
              interval = 2**i + rand(0.0..10.0)
              Hako.logger.error("Retrying register_task_definition_for_oneshot after #{interval} seconds")
              sleep(interval)
            else
              raise e
            end
          end
        end
        raise Error.new('Unable to register task definition for oneshot due to too many client errors')
      end

      # @return [Array<Hash>]
      def volumes_definition
        @volumes_definition ||= @volumes.map do |name, volume|
          definition = { name: name }
          if volume.key?('docker_volume_configuration')
            configuration = volume['docker_volume_configuration']
            definition[:docker_volume_configuration] = {
              autoprovision: configuration['autoprovision'],
              driver: configuration['driver'],
              # ECS API doesn't allow 'driver_opts' to be an empty hash.
              driver_opts: configuration['driver_opts'],
              # ECS API doesn't allow 'labels' to be an empty hash.
              labels: configuration['labels'],
              scope: configuration['scope'],
            }
          else
            # When neither 'host' nor 'docker_volume_configuration' is
            # specified, ECS API treats it as if 'host' is specified without
            # 'source_path'.
            definition[:host] = { source_path: volume['source_path'] }
          end
          definition
        end
      end

      def describe_task_definition(family)
        ecs_client.describe_task_definition(task_definition: family).task_definition
      rescue Aws::ECS::Errors::ClientException
        # Task definition does not exist
        nil
      end

      # @param [String] name
      # @param [Container] container
      # @return [Hash]
      def create_definition(name, container)
        environment = container.env.map { |k, v| { name: k, value: v } }
        {
          name: name,
          image: container.image_tag,
          cpu: container.cpu,
          memory: container.memory,
          memory_reservation: container.memory_reservation,
          links: container.links,
          port_mappings: container.port_mappings,
          essential: container.essential,
          environment: environment,
          secrets: container.secrets,
          docker_labels: container.docker_labels,
          mount_points: container.mount_points,
          entry_point: container.entry_point,
          command: container.command,
          privileged: container.privileged,
          linux_parameters: container.linux_parameters,
          depends_on: container.depends_on,
          volumes_from: container.volumes_from,
          user: container.user,
          log_configuration: container.log_configuration,
          health_check: container.health_check,
          ulimits: container.ulimits,
          extra_hosts: container.extra_hosts,
          readonly_root_filesystem: container.readonly_root_filesystem,
          docker_security_options: container.docker_security_options,
          system_controls: container.system_controls,
        }
      end

      # @param [Aws::ECS::Types::TaskDefinition] task_definition
      # @param [Array<String>] commands
      # @param [Hash<String, String>] env
      # @return [Aws::ECS::Types::Task]
      def run_task(task_definition, commands, env)
        environment = env.map { |k, v| { name: k, value: v } }
        result = ecs_client.run_task(
          cluster: @cluster,
          task_definition: task_definition.task_definition_arn,
          overrides: {
            container_overrides: [
              {
                name: 'app',
                command: commands,
                environment: environment,
              },
            ],
          },
          count: 1,
          placement_constraints: @placement_constraints,
          started_by: 'hako oneshot',
          launch_type: @launch_type,
          platform_version: @platform_version,
          network_configuration: @network_configuration,
        )
        result.failures.each do |failure|
          Hako.logger.error("#{failure.arn} #{failure.reason}")
        end
        if result.tasks.empty?
          raise NoTasksStarted.new('No tasks started')
        end

        result.tasks[0]
      rescue Aws::ECS::Errors::InvalidParameterException => e
        if e.message == 'No Container Instances were found in your cluster.' && on_no_tasks_started(task_definition)
          retry
        else
          raise e
        end
      rescue NoTasksStarted => e
        if on_no_tasks_started(task_definition)
          retry
        else
          raise e
        end
      end

      # @return [Fixnum]
      def wait_for_oneshot_finish
        containers = wait_for_task(@task)
        @task = nil
        Hako.logger.info 'Oneshot task finished'
        exit_code = 127
        containers.each do |name, container|
          if container.exit_code.nil?
            Hako.logger.info "#{name} has stopped without exit_code: reason=#{container.reason}"
          else
            Hako.logger.info "#{name} has stopped with exit_code=#{container.exit_code}"
            if name == 'app'
              exit_code = container.exit_code
            end
          end
        end
        exit_code
      end

      # @param [Aws::ECS::Types::Task] task
      # @return [Hash<String, Aws::ECS::Types::Container>]
      def wait_for_task(task)
        if @oneshot_notification_prefix
          poll_task_status_from_s3(task)
        else
          poll_task_status_from_ecs(task)
        end
      end

      MIN_WAIT_TASK_INTERVAL = 1
      MAX_WAIT_TASK_INTERVAL = 120
      # @param [Aws::ECS::Types::Task] task
      # @return [Hash<String, Aws::ECS::Types::Container>]
      def poll_task_status_from_ecs(task)
        task_arn = task.task_arn
        interval = 1
        loop do
          begin
            task = ecs_client.describe_tasks(cluster: @cluster, tasks: [task_arn]).tasks[0]
          rescue Aws::ECS::Errors::ThrottlingException => e
            Hako.logger.error(e)
            interval = [interval * 2, MAX_WAIT_TASK_INTERVAL].min
            Hako.logger.info("Retrying after #{interval} seconds...")
            sleep interval
            next
          end
          if task.nil?
            Hako.logger.debug "Task #{task_arn} could not be described"
            sleep 1
            next
          end

          if @container_instance_arn != task.container_instance_arn
            @container_instance_arn = task.container_instance_arn
            report_container_instance(@container_instance_arn)
          end
          unless @started_at
            @started_at = task.started_at
            if @started_at
              Hako.logger.info "Started at #{@started_at}"
            end
          end

          Hako.logger.debug "  status #{task.last_status}"

          if task.last_status == 'STOPPED'
            Hako.logger.info "Stopped at #{task.stopped_at} (reason: #{task.stopped_reason})"
            containers = {}
            task.containers.each do |c|
              containers[c.name] = c
            end
            return containers
          end
          interval = [interval / 2, MIN_WAIT_TASK_INTERVAL].max
          Hako.logger.debug("Waiting task with interval=#{interval}")
          sleep interval
        end
      end

      # @param [Aws::ECS::Types::Task] task
      # @return [Hash<String, Aws::ECS::Types::Container>]
      # Get stopped container status from S3.
      # The advantage is scalability; ecs:DescribeTasks is heavily
      # rate-limited, but s3:GetObject is much more scalable.
      # The JSON is supposed to be stored from Amazon ECS Event Stream.
      # http://docs.aws.amazon.com/AmazonECS/latest/developerguide/cloudwatch_event_stream.html
      def poll_task_status_from_s3(task)
        s3 = Aws::S3::Client.new(region: @region)
        task_arn = task.task_arn
        uri = URI.parse(@oneshot_notification_prefix)
        prefix = uri.path.sub(%r{\A/}, '')
        started_key = "#{prefix}/#{task_arn}/started.json"
        stopped_key = "#{prefix}/#{task_arn}/stopped.json"

        loop do
          unless @started_at
            begin
              object = s3.get_object(bucket: uri.host, key: started_key)
            rescue Aws::S3::Errors::NoSuchKey
              Hako.logger.debug("  s3://#{uri.host}/#{started_key} doesn't exist")
            else
              json = JSON.parse(object.body.read)
              arn = json['detail']['containerInstanceArn']
              if @container_instance_arn != arn
                @container_instance_arn = arn
                report_container_instance(@container_instance_arn)
              end
              @started_at = Time.parse(json['detail']['startedAt'])
              if @started_at
                Hako.logger.info "Started at #{@started_at}"
              end
            end
          end

          begin
            object = s3.get_object(bucket: uri.host, key: stopped_key)
          rescue Aws::S3::Errors::NoSuchKey
            Hako.logger.debug("  s3://#{uri.host}/#{stopped_key} doesn't exist")
          else
            json = JSON.parse(object.body.read)
            task = Aws::Json::Parser.new(Aws::ECS::Client.api.operation('describe_tasks').output.shape.member(:tasks).shape.member).parse(json['detail'].to_json)
            Hako.logger.info "Stopped at #{task.stopped_at} (reason: #{task.stopped_reason})"
            containers = {}
            task.containers.each do |c|
              containers[c.name] = c
            end
            return containers
          end

          sleep 1
        end
      end

      # @param [String] container_instance_arn
      # @return [nil]
      def report_container_instance(container_instance_arn)
        container_instance = ecs_client.describe_container_instances(cluster: @cluster, container_instances: [container_instance_arn]).container_instances[0]
        Hako.logger.info "Container instance is #{container_instance_arn} (#{container_instance.ec2_instance_id})"
      end

      # @param [Aws::ECS::Types::Service] task_definition_arn
      # @param [String] task_definition_arn
      # @return [Aws::ECS::Types::Service, Symbol]
      def update_service(current_service, task_definition_arn)
        params = {
          cluster: @cluster,
          service: @app_id,
          desired_count: @desired_count,
          task_definition: task_definition_arn,
          deployment_configuration: @deployment_configuration,
          platform_version: @platform_version,
          network_configuration: @network_configuration,
          health_check_grace_period_seconds: @health_check_grace_period_seconds,
        }
        if @autoscaling
          # Keep current desired_count if autoscaling is enabled
          params[:desired_count] = current_service.desired_count
        end
        warn_placement_policy_change(current_service)
        warn_service_registries_change(current_service)
        if service_changed?(current_service, params)
          ecs_client.update_service(params).service
        else
          :noop
        end
      end

      # @param [String] task_definition_arn
      # @param [Fixnum] front_port
      # @return [Aws::ECS::Types::Service]
      def create_initial_service(task_definition_arn, front_port)
        params = {
          cluster: @cluster,
          service_name: @app_id,
          task_definition: task_definition_arn,
          role: @role,
          deployment_configuration: @deployment_configuration,
          placement_constraints: @placement_constraints,
          placement_strategy: @placement_strategy,
          scheduling_strategy: @scheduling_strategy,
          launch_type: @launch_type,
          platform_version: @platform_version,
          network_configuration: @network_configuration,
          health_check_grace_period_seconds: @health_check_grace_period_seconds,
        }
        if @scheduling_strategy != 'DAEMON'
          params[:desired_count] = 0
        end
        if ecs_elb_client.find_or_create_load_balancer(front_port)
          params[:load_balancers] = [ecs_elb_client.load_balancer_params_for_service]
        end
        if @service_discovery
          @service_discovery.apply
          params[:service_registries] = @service_discovery.service_registries
        end
        ecs_client.create_service(params).service
      end

      # @param [Aws::ECS::Types::Service] service
      # @param [Hash] params
      # @return [Boolean]
      def service_changed?(service, params)
        EcsServiceComparator.new(params).different?(service)
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [Boolean]
      def wait_for_ready(service)
        latest_event_id = find_latest_event_id(service.events)
        Hako.logger.debug "  latest_event_id=#{latest_event_id}"
        started_at =
          if @timeout
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

        @started_task_ids = []

        loop do
          if started_at
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at > @timeout
              Hako.logger.error('Timed out')
              return false
            end
          end

          s = ecs_client.describe_services(cluster: service.cluster_arn, services: [service.service_arn]).services[0]
          if s.nil?
            Hako.logger.debug "Service #{service.service_arn} could not be described"
            sleep 1
            next
          end
          s.events.each do |e|
            if e.id == latest_event_id
              break
            end

            Hako.logger.info "#{e.created_at}: #{e.message}"
            task_id = extract_task_id(e.message)
            if task_id && e.message.include?(' has started ')
              @started_task_ids << task_id
            end
          end
          latest_event_id = find_latest_event_id(s.events)
          Hako.logger.debug "  latest_event_id=#{latest_event_id}, deployments=#{s.deployments}"
          no_active = s.deployments.all? { |d| d.status != 'ACTIVE' }
          primary = s.deployments.find { |d| d.status == 'PRIMARY' }
          if primary.desired_count * 2 < @started_task_ids.size
            Hako.logger.error('Some started tasks are stopped. It seems new deployment is failing to start')
            @started_task_ids.each_slice(100) do |task_ids|
              ecs_client.describe_tasks(cluster: service.cluster_arn, tasks: task_ids).tasks.each do |task|
                report_task_diagnostics(task)
              end
            end
            return false
          end
          primary_ready = primary && primary.running_count == primary.desired_count
          if no_active && primary_ready
            return true
          else
            sleep 1
          end
        end
      end

      # @param [Array<Aws::ECS::Types::ServiceEvent>] events
      # @return [String, nil]
      def find_latest_event_id(events)
        if events.empty?
          nil
        else
          events[0].id
        end
      end

      TASK_ID_RE = /\(task ([\h-]+)\)\.\z/.freeze
      # @param [String] message
      # @return [String, nil]
      def extract_task_id(message)
        message.slice(TASK_ID_RE, 1)
      end

      # @param [Aws::ECS::Types::Task] task
      # @return [nil]
      def report_task_diagnostics(task)
        Hako.logger.error("task_definition_arn=#{task.task_definition_arn} last_status=#{task.last_status}")
        Hako.logger.error("  stopped_reason: #{task.stopped_reason}")
        task.containers.sort_by(&:name).each do |container|
          Hako.logger.error("    Container #{container.name}: last_status=#{container.last_status} exit_code=#{container.exit_code.inspect} reason=#{container.reason.inspect}")
        end
      end

      # @param [Aws::ECS::Types::TaskDefinition]
      # @return [String]
      def find_rollback_target(task_definition)
        if task_definition.status != 'ACTIVE'
          raise 'Cannot find rollback target from INACTIVE task_definition!'
        end

        arn_found = false
        ecs_client.list_task_definitions(family_prefix: task_definition.family, status: 'ACTIVE', sort: 'DESC').each do |page|
          page.task_definition_arns.each do |arn|
            if arn_found
              return arn
            elsif arn == task_definition.task_definition_arn
              arn_found = true
            end
          end
        end

        raise "Unable to find rollback target. #{task_definition.task_definition_arn} is INACTIVE?"
      end

      # @param [Aws::ECS::Types::TaskDefinition] task_definition
      # @return [Boolean] true if the capacity is reserved
      def on_no_tasks_started(task_definition)
        unless @autoscaling_group_for_oneshot
          return false
        end

        if @autoscaling_topic_for_oneshot
          try_scale_out_with_sns(task_definition)
        else
          try_scale_out_with_as(task_definition)
        end
      end

      RUN_TASK_INTERVAL = 10
      def try_scale_out_with_sns(task_definition)
        required_cpu = task_definition.cpu && task_definition.cpu.to_i
        required_cpu ||= task_definition.container_definitions.inject(0) { |cpu, d| cpu + d.cpu }
        required_memory = task_definition.memory && task_definition.memory.to_i
        required_memory ||= task_definition.container_definitions.inject(0) { |memory, d| memory + (d.memory_reservation || d.memory) }
        @hako_task_id ||= SecureRandom.uuid
        message = JSON.dump(
          group_name: @autoscaling_group_for_oneshot,
          cluster: @cluster,
          cpu: required_cpu,
          memory: required_memory,
          hako_task_id: @hako_task_id,
        )
        Hako.logger.info("Unable to start tasks. Publish message to #{@autoscaling_topic_for_oneshot}: #{message}")
        sns_client = Aws::SNS::Client.new(region: @region)
        resp = sns_client.publish(topic_arn: @autoscaling_topic_for_oneshot, message: message)
        Hako.logger.info("Sent message_id=#{resp.message_id}")
        sleep(RUN_TASK_INTERVAL)
        true
      end

      MIN_ASG_INTERVAL = 1
      MAX_ASG_INTERVAL = 120
      def try_scale_out_with_as(task_definition)
        autoscaling = Aws::AutoScaling::Client.new(region: @region)
        interval = MIN_ASG_INTERVAL
        Hako.logger.info("Unable to start tasks. Start trying scaling out '#{@autoscaling_group_for_oneshot}'")
        loop do
          begin
            asg = autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: [@autoscaling_group_for_oneshot]).auto_scaling_groups[0]
          rescue Aws::AutoScaling::Errors::Throttling => e
            Hako.logger.error(e)
            interval = [interval * 2, MAX_ASG_INTERVAL].min
            Hako.logger.info("Retrying after #{interval} seconds...")
            sleep interval
            next
          end
          unless asg
            raise Error.new("AutoScaling Group '#{@autoscaling_group_for_oneshot}' does not exist")
          end

          container_instances = ecs_client.list_container_instances(cluster: @cluster).flat_map do |c|
            if c.container_instance_arns.empty?
              []
            else
              ecs_client.describe_container_instances(cluster: @cluster, container_instances: c.container_instance_arns).container_instances.select do |container_instance|
                container_instance.agent_connected && container_instance.status == 'ACTIVE'
              end
            end
          end
          if has_capacity?(task_definition, container_instances)
            Hako.logger.info("There's remaining capacity. Start retrying...")
            return true
          end

          interval = [interval / 2, MIN_ASG_INTERVAL].max
          # Check autoscaling group health
          current = asg.instances.count { |i| i.lifecycle_state == 'InService' }
          if asg.desired_capacity != current
            Hako.logger.debug("#{asg.auto_scaling_group_name} isn't in desired state. desired_capacity=#{asg.desired_capacity} in-service instances=#{current}. Retry after #{interval} seconds")
            sleep interval
            next
          end

          # Check out-of-service instances
          out_instances = asg.instances.map(&:instance_id)
          container_instances.each do |ci|
            out_instances.delete(ci.ec2_instance_id)
          end
          unless out_instances.empty?
            Hako.logger.debug("There's instances that is running but not registered as container instances: #{out_instances}. Retry after #{interval} seconds")
            sleep interval
            next
          end

          # Scale out
          desired = current + 1
          Hako.logger.info("Increment desired_capacity of #{asg.auto_scaling_group_name} from #{current} to #{desired}")
          autoscaling.set_desired_capacity(auto_scaling_group_name: asg.auto_scaling_group_name, desired_capacity: desired)
          sleep interval
        end
      end

      # @param [Aws::ECS::Types::TaskDefinition] task_definition
      # @param [Array<Aws::ECS::Types::ContainerInstance>] container_instances
      # @return [Boolean]
      def has_capacity?(task_definition, container_instances)
        required_cpu = task_definition.cpu && task_definition.cpu.to_i
        required_cpu ||= task_definition.container_definitions.inject(0) { |cpu, d| cpu + d.cpu }
        required_memory = task_definition.memory && task_definition.memory.to_i
        required_memory ||= task_definition.container_definitions.inject(0) { |memory, d| memory + (d.memory_reservation || d.memory) }
        container_instances.any? do |ci|
          cpu = ci.remaining_resources.find { |r| r.name == 'CPU' }.integer_value
          memory = ci.remaining_resources.find { |r| r.name == 'MEMORY' }.integer_value
          required_cpu <= cpu && required_memory <= memory
        end
      end

      # @param [Hash] definition
      # @return [nil]
      def print_volume_definition_in_cli_format(definition)
        return if definition.dig(:docker_volume_configuration, :autoprovision)
        # From version 1.20.0 of ECS agent, a local volume is provisioned when
        # 'host' is specified without 'source_path'.
        return if definition.dig(:host, :source_path)

        cmd = %w[docker volume create]
        if (configuration = definition[:docker_volume_configuration])
          if configuration[:driver]
            cmd << '--driver' << configuration[:driver]
          end
          (configuration[:driver_opts] || {}).each do |k, v|
            cmd << '--opt' << "#{k}=#{v}"
          end
          (configuration[:labels] || {}).each do |k, v|
            cmd << '--label' << "#{k}=#{v}"
          end
        end
        cmd << definition[:name]
        puts cmd.join(' ')
        nil
      end

      # @param [Hash] definition
      # @param [Hash<String, String>] additional_env
      # @return [nil]
      def print_definition_in_cli_format(definition, additional_env: {})
        cmd = %w[docker run]
        cmd << '--name' << definition.fetch(:name)
        cmd << '--cpu-shares' << definition.fetch(:cpu)
        if definition[:memory]
          cmd << '--memory' << "#{definition[:memory]}M"
        end
        if definition[:memory_reservation]
          cmd << '--memory-reservation' << "#{definition[:memory_reservation]}M"
        end
        definition.fetch(:links).each do |link|
          cmd << '--link' << link
        end
        definition.fetch(:port_mappings).each do |port_mapping|
          cmd << '--publish' << "#{port_mapping.fetch(:host_port)}:#{port_mapping.fetch(:container_port)}"
        end
        definition.fetch(:docker_labels).each do |key, val|
          if key != 'cc.wanko.hako.version'
            cmd << '--label' << "#{key}=#{val}"
          end
        end
        definition.fetch(:mount_points).each do |mount_point|
          source_volume = mount_point.fetch(:source_volume)
          v = volumes_definition.find { |d| d[:name] == source_volume }
          raise "Could not find volume #{source_volume}" unless v

          source = v.dig(:host, :source_path) || source_volume
          cmd << '--volume' << "#{source}:#{mount_point.fetch(:container_path)}#{mount_point[:read_only] ? ':ro' : ''}"
        end
        definition.fetch(:volumes_from).each do |volumes_from|
          cmd << '--volumes-from' << "#{volumes_from.fetch(:source_container)}#{volumes_from[:read_only] ? ':ro' : ''}"
        end
        if definition[:privileged]
          cmd << '--privileged'
        end
        if definition[:linux_parameters]
          if definition[:linux_parameters][:capabilities]
            cp = definition[:linux_parameters][:capabilities]
            %i[add drop].each do |a_or_d|
              cp[a_or_d]&.each do |c|
                cmd << "--cap-#{a_or_d}=#{c}"
              end
            end
          end

          if definition[:linux_parameters][:devices]
            devs = definition[:linux_parameters][:devices]
            devs.each do |dev|
              opts = dev[:host_path]
              opts += ":#{dev[:container_path]}" if dev[:container_path]
              if dev[:permissions]
                dev[:permissions].each do |permission|
                  opts += permission[0] if %w[read write mknod].include?(permission)
                end
              end
              cmd << "--device=#{opts}"
            end
          end

          if definition[:linux_parameters][:init_process_enabled]
            cmd << '--init'
          end

          if definition[:linux_parameters][:shared_memory_size]
            cmd << '--shm-size' << "#{definition[:linux_parameters][:shared_memory_size]}m"
          end

          definition[:linux_parameters].fetch(:tmpfs, []).each do |tmpfs|
            options = ["size=#{tmpfs[:size]}m"].concat(tmpfs[:mount_options])
            cmd << '--tmpfs' << "#{tmpfs[:container_path]}:#{options.join(',')}"
          end
        end
        definition.fetch(:volumes_from).each do |volumes_from|
          p volumes_from
        end
        if definition[:user]
          cmd << '--user' << definition[:user]
        end
        if definition[:readonly_root_filesystem]
          cmd << '--read-only'
        end
        (definition[:docker_security_options] || []).each do |docker_security_option|
          cmd << '--security-opt' << docker_security_option
        end
        if definition[:entry_point]
          cmd << '--entrypoint' << definition[:entry_point]
        end
        if definition[:system_controls]
          definition.fetch(:system_controls).each do |system_control|
            cmd << '--sysctl' << "#{system_control.fetch(:namespace)}=#{system_control.fetch(:value)}"
          end
        end
        if definition[:health_check]
          if definition[:health_check][:command]
            health_check_command_type = definition[:health_check][:command][0]
            case health_check_command_type
            when 'NONE'
              cmd << '--no-healthcheck'
            when 'CMD', 'CMD-SHELL'
              health_check_command = definition[:health_check][:command][1..-1].join(' ')
              cmd << '--health-cmd' << health_check_command.inspect
            else
              raise "Health check command type #{health_check_command_type} is not supported. CMD, CMD-SHELL and NONE are supported."
            end
          end
          if definition[:health_check][:retries]
            cmd << '--health-retries' << definition[:health_check][:retries]
          end
          %i[interval timeout start_period].each do |property|
            if definition[:health_check][property]
              cmd << "--health-#{property}" << "#{definition[:health_check][property]}s"
            end
          end
        end

        cmd << "\\\n  "
        definition.fetch(:environment).each do |env|
          name = env.fetch(:name)
          value = env.fetch(:value)
          # additional_env (given in command line) has priority over env (declared in definition file)
          unless additional_env.key?(name)
            cmd << '--env' << "#{name}=#{value}"
            cmd << "\\\n  "
          end
        end
        (definition[:secrets] || []).each do |secret|
          name = secret.fetch(:name)
          # additional_env (given in command line) has priority over secrets (declared in definition file)
          unless additional_env.key?(name)
            cmd << '--env' << "#{name}=secret:#{secret.fetch(:value_from)}"
            cmd << "\\\n  "
          end
        end
        additional_env.each do |name, value|
          cmd << '--env' << "#{name}=#{value}"
          cmd << "\\\n  "
        end

        cmd << definition.fetch(:image)
        if definition[:command]
          cmd << "\\\n  "
          cmd += definition[:command]
        end
        puts cmd.join(' ')
        nil
      end

      # @param [Hash] container_definition
      # @return [nil]
      def check_secrets(container_definition)
        parameter_names = (container_definition[:secrets] || []).map { |secret| secret.fetch(:value_from) }
        invalid_parameter_names = parameter_names.each_slice(10).flat_map do |names|
          names = names.map do |name|
            if name.start_with?('arn:')
              name.slice(%r{:parameter(/.+)\z}, 1)
            else
              name
            end
          end
          ssm_client.get_parameters(names: names).invalid_parameters
        end
        unless invalid_parameter_names.empty?
          raise Error.new("Invalid parameters for secrets: #{invalid_parameter_names}")
        end

        nil
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [nil]
      def warn_placement_policy_change(service)
        placement_constraints = service.placement_constraints.map do |c|
          h = { 'type' => c.type }
          unless c.expression.nil?
            h['expression'] = c.expression
          end
          h
        end
        if @placement_constraints != placement_constraints
          Hako.logger.warn "Ignoring updated placement_constraints in the configuration, because AWS doesn't allow updating them for now."
        end

        placement_strategy = service.placement_strategy.map do |s|
          h = { 'type' => s.type }
          unless s.field.nil?
            h['field'] = s.field.downcase
          end
          h
        end
        if @placement_strategy != placement_strategy
          Hako.logger.warn "Ignoring updated placement_strategy in the configuration, because AWS doesn't allow updating them for now."
        end
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [void]
      def warn_service_registries_change(service)
        actual_service_registries = service.service_registries.sort_by(&:registry_arn).map(&:to_h)
        expected_service_registries = @service_discovery&.service_registries&.sort_by { |s| s[:registry_arn] } || []
        if actual_service_registries != expected_service_registries
          Hako.logger.warn "Ignoring updated service_registries in the configuration, because AWS doesn't allow updating them for now."
        end
      end

      # @param [Aws::ECS::Types::TaskDefinition] task_definition
      # @param [String] target_definition
      # @return [nil]
      def call_rollback_started(task_definition, target_definition)
        current_app = task_definition.container_definitions.find { |c| c.name == 'app' }
        target_app = ecs_client.describe_task_definition(task_definition: target_definition).task_definition.container_definitions.find { |c| c.name == 'app' }
        if current_app && target_app
          @scripts.each { |script| script.rollback_started(current_app.image, target_app.image) }
        else
          Hako.logger.warn("Cannot find image_tag. current_app=#{current_app.inspect} target_app=#{target_app.inspect}. Skip calling Script#rollback_started")
        end
        nil
      end
    end
  end
end
