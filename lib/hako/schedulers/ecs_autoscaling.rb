# frozen_string_literal: true

require 'aws-sdk-applicationautoscaling'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-elasticloadbalancingv2'
require 'hako'
require 'hako/error'

module Hako
  module Schedulers
    class EcsAutoscaling
      def initialize(options, region, ecs_elb_client, dry_run:)
        @region = region
        @ecs_elb_client = ecs_elb_client
        @dry_run = dry_run
        @role_arn = required_option(options, 'role_arn')
        @min_capacity = required_option(options, 'min_capacity')
        @max_capacity = required_option(options, 'max_capacity')
        @policies = required_option(options, 'policies').map { |r| Policy.new(r) }
      end

      PUT_METRIC_ALARM_OPTIONS = %i[
        alarm_name alarm_description actions_enabled ok_actions alarm_actions
        insufficient_data_actions metric_name namespace statistic dimensions
        period unit evaluation_periods threshold comparison_operator
      ].freeze

      # @param [Aws::ECS::Types::Service] service
      # @return [nil]
      def apply(service)
        resource_id = service_resource_id(service)
        service_namespace = 'ecs'
        scalable_dimension = 'ecs:service:DesiredCount'

        Hako.logger.info("Registering scalable target to #{resource_id}")
        unless @dry_run
          autoscaling_client.register_scalable_target(
            service_namespace: service_namespace,
            resource_id: resource_id,
            scalable_dimension: scalable_dimension,
            min_capacity: @min_capacity,
            max_capacity: @max_capacity,
            role_arn: @role_arn,
          )
        end
        @policies.each do |policy|
          Hako.logger.info("Configuring scaling policy #{policy.name}")
          if @dry_run
            if policy.policy_type == 'StepScaling'
              policy.alarms.each do |alarm_name|
                Hako.logger.info("Configuring #{alarm_name}'s alarm_action")
              end
            end
          else
            policy_params = {
              policy_name: policy.name,
              service_namespace: service_namespace,
              resource_id: resource_id,
              scalable_dimension: scalable_dimension,
              policy_type: policy.policy_type,
            }
            if policy.policy_type == 'StepScaling'
              policy_params[:step_scaling_policy_configuration] = {
                adjustment_type: policy.adjustment_type,
                step_adjustments: [
                  {
                    scaling_adjustment: policy.scaling_adjustment,
                    metric_interval_lower_bound: policy.metric_interval_lower_bound,
                    metric_interval_upper_bound: policy.metric_interval_upper_bound,
                  },
                ],
                cooldown: policy.cooldown,
                metric_aggregation_type: policy.metric_aggregation_type,
              }
            else
              predefined_metric_specification = {
                predefined_metric_type: policy.predefined_metric_type,
              }
              if policy.predefined_metric_type == 'ALBRequestCountPerTarget'
                if service.load_balancers.empty? || service.load_balancers[0].target_group_arn.nil?
                  raise Error.new('Target group must be attached to the ECS service for predefined metric type ALBRequestCountPerTarget')
                end
                resource_label = target_group_resource_label
                unless resource_label.start_with?('app/')
                  raise Error.new("Load balancer type must be 'application' for predefined metric type ALBRequestCountPerTarget")
                end
                predefined_metric_specification[:resource_label] = resource_label
              end
              policy_params[:target_tracking_scaling_policy_configuration] = {
                target_value: policy.target_value,
                predefined_metric_specification: predefined_metric_specification,
                scale_out_cooldown: policy.scale_out_cooldown,
                scale_in_cooldown: policy.scale_in_cooldown,
                disable_scale_in: policy.disable_scale_in,
              }
            end
            policy_arn = autoscaling_client.put_scaling_policy(policy_params).policy_arn

            if policy.policy_type == 'StepScaling'
              alarms = cw_client.describe_alarms(alarm_names: policy.alarms).flat_map(&:metric_alarms).map { |a| [a.alarm_name, a] }.to_h
              policy.alarms.each do |alarm_name|
                alarm = alarms.fetch(alarm_name) { raise Error.new("Alarm #{alarm_name} does not exist") }
                Hako.logger.info("Updating #{alarm_name}'s alarm_actions from #{alarm.alarm_actions} to #{[policy_arn]}")
                params = PUT_METRIC_ALARM_OPTIONS.map { |key| [key, alarm.public_send(key)] }.to_h
                params[:alarm_actions] = [policy_arn]
                cw_client.put_metric_alarm(params)
              end
            end
          end
        end
        nil
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [nil]
      def remove(service)
        resource_id = service_resource_id(service)
        service_namespace = 'ecs'
        scalable_dimension = 'ecs:service:DesiredCount'

        Hako.logger.info("Deregister scalable target #{resource_id} and its policies")
        unless @dry_run
          begin
            autoscaling_client.deregister_scalable_target(service_namespace: service_namespace, resource_id: resource_id, scalable_dimension: scalable_dimension)
          rescue Aws::ApplicationAutoScaling::Errors::ObjectNotFoundException => e
            Hako.logger.warn(e)
          end
        end
        nil
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [nil]
      def status(service)
        resource_id = service_resource_id(service)
        service_namespace = 'ecs'
        scalable_dimension = 'ecs:service:DesiredCount'

        autoscaling_client.describe_scaling_activities(service_namespace: service_namespace, resource_id: resource_id, scalable_dimension: scalable_dimension, max_results: 50).scaling_activities.each do |activity|
          puts "  [#{activity.start_time} - #{activity.end_time}] #{activity.status_message}"
          puts "    description: #{activity.description}"
          puts "    cause: #{activity.cause}"
          puts "    details: #{activity.details}"
        end
      end

      private

      # @param [Hash] options
      # @param [String] key
      # @return [Object]
      def required_option(options, key)
        options.fetch(key) { raise Error.new("scheduler.autoscaling.#{key} must be set") }
      end

      # @return [Aws::ApplicationAutoScaling]
      def autoscaling_client
        @autoscaling_client ||= Aws::ApplicationAutoScaling::Client.new(region: @region)
      end

      # @return [Aws::CloudWatch::Client]
      def cw_client
        @cw_client ||= Aws::CloudWatch::Client.new(region: @region)
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [String]
      def service_resource_id(service)
        "service/#{service.cluster_arn.slice(%r{[^/]+\z}, 0)}/#{service.service_name}"
      end

      # @return [String]
      def target_group_resource_label
        target_group = @ecs_elb_client.describe_target_group
        load_balancer_arn = target_group.load_balancer_arns[0]
        target_group_arn = target_group.target_group_arn
        "#{load_balancer_arn.slice(%r{:loadbalancer/(.+)\z}, 1)}/#{target_group_arn.slice(/[^:]+\z/)}"
      end

      class Policy
        attr_reader :policy_type
        attr_reader :alarms, :cooldown, :adjustment_type, :scaling_adjustment, :metric_interval_lower_bound, :metric_interval_upper_bound, :metric_aggregation_type
        attr_reader :target_value, :predefined_metric_type, :scale_out_cooldown, :scale_in_cooldown, :disable_scale_in

        # @param [Hash] options
        def initialize(options)
          @policy_type = options.fetch('policy_type', 'StepScaling')
          case @policy_type
          when 'StepScaling'
            @alarms = required_option(options, 'alarms')
            @cooldown = required_option(options, 'cooldown')
            @adjustment_type = required_option(options, 'adjustment_type')
            @scaling_adjustment = required_option(options, 'scaling_adjustment')
            @metric_interval_lower_bound = options.fetch('metric_interval_lower_bound', nil)
            @metric_interval_upper_bound = options.fetch('metric_interval_upper_bound', nil)
            @metric_aggregation_type = required_option(options, 'metric_aggregation_type')
          when 'TargetTrackingScaling'
            @name = required_option(options, 'name')
            @target_value = required_option(options, 'target_value')
            @predefined_metric_type = required_option(options, 'predefined_metric_type')
            @scale_out_cooldown = options.fetch('scale_out_cooldown', nil)
            @scale_in_cooldown = options.fetch('scale_in_cooldown', nil)
            @disable_scale_in = options.fetch('disable_scale_in', nil)
          else
            raise Error.new("scheduler.autoscaling.policies.#{policy_type} must be either 'StepScaling' or 'TargetTrackingScaling'")
          end
        end

        # @return [String]
        def name
          if policy_type == 'StepScaling'
            alarms.join('-and-')
          else
            @name
          end
        end

        private

        # @param [Hash] options
        # @param [String] key
        # @return [Object]
        def required_option(options, key)
          options.fetch(key) { raise Error.new("scheduler.autoscaling.policies.#{key} must be set") }
        end
      end
    end
  end
end
