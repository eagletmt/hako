# frozen_string_literal: true

require 'spec_helper'
require 'hako/app_container'
require 'hako/scripts/create_aws_cloud_watch_logs_log_group'

RSpec.describe Hako::Scripts::CreateAwsCloudWatchLogsLogGroup do
  let(:script) { described_class.new(app, options, dry_run: false) }
  let(:app) { double('Hako::Application', id: 'nanika') }
  let(:options) do
    {
      'log_configuration' => {
        'log_driver' => 'awslogs',
        'options' => {
          'awslogs-group' => 'group',
          'awslogs-region' => 'ap-northeast-1',
        }
      }
    }
  end
  let(:app_container) { Hako::AppContainer.new(app, options, dry_run: false) }
  let(:backend_port) { 3000 }
  let(:front_container) { Hako::Container.new(app, {}, dry_run: false) }
  let(:containers) { { 'app' => app_container, 'front' => front_container } }
  let(:cloudwatch_logs) { double('Aws::CloudWatchLogs::Client') }

  before do
    allow(script).to receive(:cloudwatch_logs).and_return(cloudwatch_logs)
    allow(cloudwatch_logs).to receive(:describe_log_groups).and_return(describe_response)
  end

  describe '#deploy_starting' do
    context 'log group does not exist' do
      let(:describe_response) { [] }

      it 'creates log group' do
        expect(cloudwatch_logs).to receive(:create_log_group).with(log_group_name: 'group')
        script.deploy_starting(containers)
      end
    end

    context 'log group exist' do
      let(:describe_response) do
        [
          double(
            'Aws::CloudWatchLogs::Types::DescribeLogGroupsResponse',
            log_groups: [double('Aws::CloudWatchLogs::Types::LogGroup', log_group_name: 'group')]
          )
        ]
      end

      it 'does not create log group' do
        expect(cloudwatch_logs).to_not receive(:create_log_group)
        script.deploy_starting(containers)
      end
    end
  end
end
