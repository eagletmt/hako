# frozen_string_literal: true

require 'aws-sdk-cloudwatchlogs'
require 'hako'
require 'hako/script'

module Hako
  module Scripts
    class CreateAwsCloudWatchLogsLogGroup < Script
      # @param [Hash<String, Container>] containers
      # @return [nil]
      def deploy_starting(containers)
        containers.each_value do |container|
          log_configuration = container.log_configuration
          unless log_configuration
            next
          end

          if log_configuration[:log_driver] == 'awslogs'
            create_log_group_if_not_exist(log_configuration.fetch(:options))
          end
        end
      end

      alias_method :oneshot_starting, :deploy_starting

      private

      # @param [Hash] options
      # @return [nil]
      def create_log_group_if_not_exist(options)
        group = options.fetch('awslogs-group')
        region = options.fetch('awslogs-region')

        unless log_group_exist?(group, region: region)
          cloudwatch_logs(region).create_log_group(log_group_name: group)
          Hako.logger.info "Created CloudWatch log group #{group} in #{region}"
        end
      end

      # @param [String] region
      # @return [Aws::CloudWatchLogs::Client]
      def cloudwatch_logs(region)
        @cloudwatch_logs ||= {}
        @cloudwatch_logs[region] ||= Aws::CloudWatchLogs::Client.new(region: region)
      end

      # @param [String] group
      # @param [String] region
      # @return [Boolean]
      def log_group_exist?(group, region:)
        cloudwatch_logs(region).describe_log_groups(log_group_name_prefix: group).any? do |page|
          page.log_groups.any? { |log_group| log_group.log_group_name == group }
        end
      end
    end
  end
end
