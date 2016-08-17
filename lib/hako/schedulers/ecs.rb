# frozen_string_literal: true
require 'aws-sdk'
require 'hako'
require 'hako/error'
require 'hako/scheduler'
require 'hako/schedulers/ecs_definition_comparator'
require 'hako/schedulers/ecs_elb'
require 'hako/schedulers/ecs_autoscaling'

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
        if options.key?('autoscaling')
          @autoscaling = EcsAutoscaling.new(options.fetch('autoscaling'), dry_run: @dry_run)
        end
        @started_at = nil
        @container_instance_arn = nil
        @autoscaling_group_for_oneshot = options.fetch('autoscaling_group_for_oneshot', nil)
      end

      # @param [Hash<String, Container>] containers
      # @return [nil]
      def deploy(containers)
        unless @desired_count
          validation_error!('desired_count must be set')
        end
        front_port = determine_front_port
        @scripts.each { |script| script.deploy_started(containers, front_port) }
        definitions = create_definitions(containers)

        if @dry_run
          definitions.each do |d|
            Hako.logger.info "Add container #{d}"
          end
          if @autoscaling
            @autoscaling.apply(Aws::ECS::Types::Service.new(cluster_arn: @cluster, service_name: @app_id))
          end
        else
          task_definition = register_task_definition(definitions)
          if task_definition == :noop
            Hako.logger.info "Task definition isn't changed"
            task_definition = ecs_client.describe_task_definition(task_definition: @app_id).task_definition
          else
            Hako.logger.info "Registered task definition: #{task_definition.task_definition_arn}"
          end
          service = create_or_update_service(task_definition.task_definition_arn, front_port)
          if service == :noop
            Hako.logger.info "Service isn't changed"
            if @autoscaling
              @autoscaling.apply(describe_service)
            end
          else
            Hako.logger.info "Updated service: #{service.service_arn}"
            if @autoscaling
              @autoscaling.apply(service)
            end
            wait_for_ready(service)
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
        Hako.logger.info "Current task defintion is #{current_definition}. Rolling back to #{target_definition}"

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
      # @return [nil]
      def oneshot(containers, commands, env)
        definitions = create_definitions(containers)
        definitions.each do |definition|
          definition.delete(:essential)
        end

        if @dry_run
          definitions.each do |d|
            Hako.logger.info "Add container #{d}"
          end
          env.each do |k, v|
            Hako.logger.info "Add environment #{k}=#{v}"
          end
          Hako.logger.info "Execute command #{commands}"
          0
        else
          task_definition = register_task_definition_for_oneshot(definitions)
          if task_definition == :noop
            Hako.logger.info "Task definition isn't changed"
            task_definition = ecs_client.describe_task_definition(task_definition: "#{@app_id}-oneshot").task_definition
          else
            Hako.logger.info "Registered task definition: #{task_definition.task_definition_arn}"
          end
          @task = run_task(task_definition, commands, env)
          Hako.logger.info "Started task: #{@task.task_arn}"
          @scripts.each { |script| script.oneshot_started(self) }
          wait_for_oneshot_finish
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
          lb = service.load_balancers[0]
          lb_detail = ecs_elb_client.describe_load_balancer
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
        ecs_client.list_tasks(cluster: @cluster, service_name: service.service_arn).each do |page|
          unless page.task_arns.empty?
            tasks = ecs_client.describe_tasks(cluster: @cluster, tasks: page.task_arns).tasks
            container_instances = {}
            ecs_client.describe_container_instances(cluster: @cluster, container_instances: tasks.map(&:container_instance_arn)).container_instances.each do |ci|
              container_instances[ci.container_instance_arn] = ci
            end
            ec2_instances = {}
            ec2_client.describe_instances(instance_ids: container_instances.values.map(&:ec2_instance_id)).reservations.each do |r|
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

        if @autoscaling
          puts 'Autoscaling:'
          @autoscaling.status(service)
        else
          puts 'Autoscaling: No'
        end
      end

      # @return [nil]
      def remove
        service = describe_service
        if service
          if @dry_run
            Hako.logger.info "ecs_client.update_service(cluster: #{@cluster}, service: #{@app_id}, desired_count: 0)"
            Hako.logger.info "ecs_client.delete_service(cluster: #{@cluster}, service: #{@app_id})"
          else
            ecs_client.update_service(cluster: @cluster, service: @app_id, desired_count: 0)
            ecs_client.delete_service(cluster: @cluster, service: @app_id)
            Hako.logger.info "#{service.service_arn} is deleted"
          end
          if @autoscaling
            @autoscaling.remove(service)
          end
        else
          puts "Service #{@app_id} doesn't exist"
        end

        ecs_elb_client.destroy
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

      # @return [EcsElb]
      def ecs_elb_client
        @ecs_elb_client ||= EcsElb.new(@app_id, Aws::ElasticLoadBalancing::Client.new(region: @region), @ecs_elb_options, dry_run: @dry_run)
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

      # @param [String] family
      # @param [Array<Hash>] definitions
      # @return [Boolean]
      def task_definition_changed?(family, definitions)
        if @force
          return true
        end
        task_definition = ecs_client.describe_task_definition(task_definition: family).task_definition
        container_definitions = {}
        task_definition.container_definitions.each do |c|
          container_definitions[c.name] = c
        end

        if task_definition.task_role_arn != @task_role_arn
          return true
        end
        if different_volumes?(task_definition.volumes)
          return true
        end
        if definitions.any? { |definition| different_definition?(definition, container_definitions.delete(definition[:name])) }
          return true
        end
        !container_definitions.empty?
      rescue Aws::ECS::Errors::ClientException
        # Task definition does not exist
        true
      end

      # @param [Hash<String, Hash<String, String>>] actual_volumes
      # @return [Boolean]
      def different_volumes?(actual_volumes)
        if @volumes.size != actual_volumes.size
          return true
        end
        actual_volumes.each do |actual_volume|
          expected_volume = @volumes[actual_volume.name]
          if expected_volume.nil?
            return true
          end
          if expected_volume['source_path'] != actual_volume.host.source_path
            return true
          end
        end

        false
      end

      # @param [Hash] expected_container
      # @param [Aws::ECS::Types::ContainerDefinition] actual_container
      # @return [Boolean]
      def different_definition?(expected_container, actual_container)
        EcsDefinitionComparator.new(expected_container).different?(actual_container)
      end

      # @param [Array<Hash>] definitions
      # @return [Aws::ECS::Types::TaskDefinition, Symbol]
      def register_task_definition(definitions)
        if task_definition_changed?(@app_id, definitions)
          ecs_client.register_task_definition(
            family: @app_id,
            task_role_arn: @task_role_arn,
            container_definitions: definitions,
            volumes: volumes_definition,
          ).task_definition
        else
          :noop
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
      # @return [Aws::ECS::Types::TaskDefinition, Symbol]
      def register_task_definition_for_oneshot(definitions)
        family = "#{@app_id}-oneshot"
        if task_definition_changed?(family, definitions)
          ecs_client.register_task_definition(
            family: "#{@app_id}-oneshot",
            task_role_arn: @task_role_arn,
            container_definitions: definitions,
            volumes: volumes_definition,
          ).task_definition
        else
          :noop
        end
      end

      # @return [Hash]
      def volumes_definition
        @volumes.map do |name, volume|
          {
            name: name,
            host: { source_path: volume['source_path'] },
          }
        end
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
          links: container.links,
          port_mappings: container.port_mappings,
          essential: true,
          environment: environment,
          docker_labels: container.docker_labels,
          mount_points: container.mount_points,
          command: container.command,
          volumes_from: container.volumes_from,
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
          started_by: 'hako oneshot',
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
      # @return [nil]
      def wait_for_task(task)
        task_arn = task.task_arn
        loop do
          task = ecs_client.describe_tasks(cluster: @cluster, tasks: [task_arn]).tasks[0]
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
          sleep 1
        end
      end

      # @param [String] container_instance_arn
      # @return [nil]
      def report_container_instance(container_instance_arn)
        container_instance = ecs_client.describe_container_instances(cluster: @cluster, container_instances: [container_instance_arn]).container_instances[0]
        ec2_client.describe_tags(filters: [{ name: 'resource-id', values: [container_instance.ec2_instance_id] }]).each do |page|
          tag = page.tags.find { |t| t.key == 'Name' }
          if tag
            Hako.logger.info "Container instance is #{container_instance_arn} (#{tag.value} #{container_instance.ec2_instance_id})"
          else
            Hako.logger.info "Container instance is #{container_instance_arn} (#{container_instance.ec2_instance_id})"
          end
        end
      end

      # @param [String] task_definition_arn
      # @param [Fixnum] front_port
      # @return [Aws::ECS::Types::Service, Symbol]
      def create_or_update_service(task_definition_arn, front_port)
        service = describe_service
        if service.nil?
          params = {
            cluster: @cluster,
            service_name: @app_id,
            task_definition: task_definition_arn,
            desired_count: @desired_count,
            role: @role,
          }
          name = ecs_elb_client.find_or_create_load_balancer(front_port)
          if name
            params[:load_balancers] = [
              {
                load_balancer_name: name,
                container_name: 'front',
                container_port: 80,
              },
            ]
          end
          ecs_client.create_service(params).service
        else
          params = {
            cluster: @cluster,
            service: @app_id,
            desired_count: @desired_count,
            task_definition: task_definition_arn,
          }
          if @autoscaling
            # Keep current desired_count if autoscaling is enabled
            params[:desired_count] = service.desired_count
          end
          if service_changed?(service, params)
            ecs_client.update_service(params).service
          else
            :noop
          end
        end
      end

      SERVICE_KEYS = %i[desired_count task_definition].freeze

      # @param [Aws::ECS::Types::Service] service
      # @param [Hash] params
      # @return [Boolean]
      def service_changed?(service, params)
        SERVICE_KEYS.each do |key|
          if service.public_send(key) != params[key]
            return true
          end
        end
        false
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [nil]
      def wait_for_ready(service)
        latest_event_id = find_latest_event_id(service.events)
        Hako.logger.debug "  latest_event_id=#{latest_event_id}"
        loop do
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
          end
          latest_event_id = find_latest_event_id(s.events)
          Hako.logger.debug "  latest_event_id=#{latest_event_id}, deployments=#{s.deployments}"
          no_active = s.deployments.all? { |d| d.status != 'ACTIVE' }
          primary = s.deployments.find { |d| d.status == 'PRIMARY' }
          primary_ready = primary && primary.running_count == primary.desired_count
          if no_active && primary_ready
            return
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

        autoscaling = Aws::AutoScaling::Client.new
        loop do
          asg = autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: [@autoscaling_group_for_oneshot]).auto_scaling_groups[0]
          unless asg
            raise Error.new("AutoScaling Group '#{@autoscaling_group_for_oneshot}' does not exist")
          end

          container_instances = ecs_client.list_container_instances(cluster: @cluster).flat_map { |c| ecs_client.describe_container_instances(cluster: @cluster, container_instances: c.container_instance_arns).container_instances }
          if has_capacity?(task_definition, container_instances)
            Hako.logger.info("There's remaining capacity. Start retrying...")
            return true
          end

          # Check autoscaling group health
          current = asg.instances.count { |i| i.lifecycle_state == 'InService' }
          if asg.desired_capacity != current
            Hako.logger.debug("#{asg.auto_scaling_group_name} isn't in desired state. desired_capacity=#{asg.desired_capacity} in-service instances=#{current}")
            sleep 1
            next
          end

          # Check out-of-service instances
          out_instances = asg.instances.map(&:instance_id)
          container_instances.each do |ci|
            out_instances.delete(ci.ec2_instance_id)
          end
          unless out_instances.empty?
            Hako.logger.debug("There's instances that is running but not registered as container instances: #{out_instances}")
            sleep 1
            next
          end

          # Scale out
          desired = current + 1
          Hako.logger.info("Increment desired_capacity of #{asg.auto_scaling_group_name} from #{current} to #{desired}")
          autoscaling.set_desired_capacity(auto_scaling_group_name: asg.auto_scaling_group_name, desired_capacity: desired)
        end
      end

      # @param [Aws::ECS::Types::TaskDefinition] task_definition
      # @param [Array<Aws::ECS::Types::ContainerInstance>] container_instances
      # @return [Boolean]
      def has_capacity?(task_definition, container_instances)
        required_cpu, required_memory = task_definition.container_definitions.inject([0, 0]) { |(cpu, memory), d| [cpu + d.cpu, memory + d.memory] }
        container_instances.any? do |ci|
          cpu = ci.remaining_resources.find { |r| r.name == 'CPU' }.integer_value
          memory = ci.remaining_resources.find { |r| r.name == 'MEMORY' }.integer_value
          required_cpu < cpu && required_memory < memory
        end
      end
    end
  end
end
