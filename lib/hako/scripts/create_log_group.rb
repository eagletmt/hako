# frozen_string_literal: true
require 'aws-sdk'
require 'hako'
require 'hako/script'

module Hako
  module Scripts
    class CreateLogGroup < Script
      # @param [Hash<String, Container>] containers
      # @return [nil]
      def deploy_starting(containers)
        containers.each do |_, container|
          next unless container.definition.key?('log_configuration')
          log_configuration = container.definition['log_configuration']
          if log_configuration['log_driver'] == 'awslogs'
            create_log_group_if_not_exist(log_configuration.fetch('options'))
          end
        end
      end

      private

      # @param [Hash] options
      # @return [nil]
      def create_log_group_if_not_exist(options)
        group = options.fetch('awslogs-group')
        @region = options.fetch('awslogs-region')

        unless log_group_exist?(group)
          cloudwatch_logs.create_log_group(log_group_name: group)
          Hako.logger.info "Created CloudWatch log group #{group} in #{@region}"
        end
      end

      # @return [Aws::CloudWatchLogs::Client]
      def cloudwatch_logs
        @cloudwatch_logs ||= {}
        @cloudwatch_logs[@region] ||= Aws::CloudWatchLogs::Client.new(region: @region)
      end

      # @return [Boolean]
      def log_group_exist?(group)
        cloudwatch_logs.describe_log_groups(log_group_name_prefix: group).log_groups.empty? == false
      end
    end
  end
end
