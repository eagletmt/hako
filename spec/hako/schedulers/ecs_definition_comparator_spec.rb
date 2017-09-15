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
  end
end
