# frozen_string_literal: true

require 'spec_helper'
require 'hako/schedulers/ecs_definition_comparator'
require 'aws-sdk-ecs'

RSpec.describe Hako::Schedulers::EcsDefinitionComparator do
  describe '#different?' do
    let(:ecs_definition_comparator) { described_class.new(expected_container) }

    let(:default_config) do
      {
        docker_labels: {},
        environment: {},
        links: [],
        mount_points: [],
        port_mappings: [],
        volumes_from: [],
      }
    end

    describe 'compares correctly even if the definition includes LinuxParameters' do
      let(:expected_container) do
        {
          name: 'app',
          linux_parameters: {
            capabilities: {
              add: ['ALL'],
              drop: ['NET_ADMIN']
            },
            devices: [
              {
                host_path: '/dev/null',
                container_path: nil,
                permissions: ['read']
              }
            ],
            shared_memory_size: 128,
            tmpfs: [
              {
                container_path: '/tmp',
                mount_options: ['defaults'],
                size: 128
              }
            ]
          }
        }.merge(default_config)
      end

      let(:actual_container) do
        Aws::ECS::Types::ContainerDefinition.new({
          name: 'app',
          linux_parameters: Aws::ECS::Types::LinuxParameters.new(
            capabilities: {
              add: ['ALL'],
              drop: ['NET_ADMIN']
            },
            devices: [
              {
                host_path: '/dev/null',
                container_path: nil,
                permissions: ['read']
              }
            ],
            shared_memory_size: 128,
            tmpfs: [
              {
                container_path: '/tmp',
                mount_options: ['defaults'],
                size: 128
              }
            ]
          )
        }.merge(default_config))
      end

      it 'returns valid value' do
        expect(ecs_definition_comparator).to_not be_different(actual_container)
      end
    end

    describe 'compares correctly even if the definition includes LogConfiguration' do
      let(:expected_container) do
        {
          name: 'app',
          log_configuration: {
            log_driver: 'awslogs',
            options: {
              'awslogs-group' => '/loggroup',
              'awslogs-region' => 'ap-northeast-1',
              'awslogs-stream-prefix' => 'prefix'
            }
          }
        }.merge(default_config)
      end

      let(:actual_container) do
        Aws::ECS::Types::ContainerDefinition.new({
          name: 'app',
          log_configuration: Aws::ECS::Types::LogConfiguration.new(
            log_driver: 'awslogs',
            options: {
              'awslogs-group' => '/loggroup',
              'awslogs-region' => 'ap-northeast-1',
              'awslogs-stream-prefix' => 'prefix'
            }
          )
        }.merge(default_config))
      end

      it 'returns valid value' do
        expect(ecs_definition_comparator).to_not be_different(actual_container)
      end
    end

    describe 'compares correctly even if the definition includes Container healthcheck' do
      let(:expected_container) do
        {
          name: 'app',
          health_check: {
            command: [
              'ls',
              '/'
            ],
            interval: 5,
            timeout: 4,
            retries: 3,
            start_period: 1
          }
        }.merge(default_config)
      end

      let(:actual_container) do
        Aws::ECS::Types::ContainerDefinition.new({
          name: 'app',
          health_check: Aws::ECS::Types::HealthCheck.new(
            command: [
              'ls',
              '/'
            ],
            interval: 5,
            timeout: 4,
            retries: 3,
            start_period: 1
          )
        }.merge(default_config))
      end

      it 'returns valid value' do
        expect(ecs_definition_comparator).to_not be_different(actual_container)
      end
    end
  end
end
