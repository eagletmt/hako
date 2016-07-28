# frozen_string_literal: true
require 'hako'
require 'hako/error'

module Hako
  module Schedulers
    class EcsAutoscaling
      def initialize(options, dry_run:)
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
            policy.alarms.each do |alarm_name|
              Hako.logger.info("Configuring #{alarm_name}'s alarm_action")
            end
          else
            policy_arn = autoscaling_client.put_scaling_policy(
              policy_name: policy.name,
              service_namespace: service_namespace,
              resource_id: resource_id,
              scalable_dimension: scalable_dimension,
              policy_type: 'StepScaling',
              step_scaling_policy_configuration: {
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
              },
            ).policy_arn

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

      private

      # @param [Hash] options
      # @param [String] key
      # @return [Object]
      def required_option(options, key)
        options.fetch(key) { raise Error.new("scheduler.autoscaling.#{key} must be set") }
      end

      # @return [Aws::ApplicationAutoScaling]
      def autoscaling_client
        @autoscaling_client ||= Aws::ApplicationAutoScaling::Client.new
      end

      # @return [Aws::CloudWatch::Client]
      def cw_client
        @cw_client ||= Aws::CloudWatch::Client.new
      end

      # @param [Aws::ECS::Types::Service] service
      # @return [String]
      def service_resource_id(service)
        "service/#{service.cluster_arn.slice(%r{[^/]+\z}, 0)}/#{service.service_name}"
      end

      class Policy
        attr_reader :alarms, :cooldown, :adjustment_type, :scaling_adjustment, :metric_interval_lower_bound, :metric_interval_upper_bound, :metric_aggregation_type

        # @param [Hash] options
        def initialize(options)
          @alarms = required_option(options, 'alarms')
          @cooldown = required_option(options, 'cooldown')
          @adjustment_type = required_option(options, 'adjustment_type')
          @scaling_adjustment = required_option(options, 'scaling_adjustment')
          @metric_interval_lower_bound = options.fetch('metric_interval_lower_bound', nil)
          @metric_interval_upper_bound = options.fetch('metric_interval_upper_bound', nil)
          @metric_aggregation_type = required_option(options, 'metric_aggregation_type')
        end

        # @return [String]
        def name
          alarms.join('-and-')
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
