# frozen_string_literal: true

require 'spec_helper'
require 'hako/schedulers/ecs_service_comparator'
require 'aws-sdk-ecs'

RSpec.describe Hako::Schedulers::EcsServiceComparator do
  let(:comparator) { described_class.new(expected_service) }
  let(:expected_service) do
    {
      cluster: 'cl1',
      service: 'svc1',
      desired_count: 4,
      task_definition: 'td1',
      deployment_configuration: {
        maximum_percent: 100,
        minimum_healthy_percent: 0,
      },
      service_registries: [],
      placement_constraints: [],
      placement_strategy: [],
    }
  end
  let(:actual_service) do
    Aws::ECS::Types::Service.new(
      desired_count: 4,
      task_definition: 'td1',
      deployment_configuration: Aws::ECS::Types::DeploymentConfiguration.new(
        maximum_percent: 100,
        minimum_healthy_percent: 0,
      ),
      service_registries: [],
      placement_constraints: [],
      placement_strategy: [],
    )
  end

  describe '#different?' do
    context 'when same' do
      it 'returns false' do
        expect(comparator).to_not be_different(actual_service)
      end
    end

    context 'when some parameters differ' do
      before do
        actual_service.desired_count = 1
      end

      it 'returns true' do
        expect(comparator).to be_different(actual_service)
      end
    end

    context 'when placement_constraints changes' do
      it 'detects memberOf changes' do
        expected_service[:placement_constraints] = [{ type: 'memberOf', expression: 'ecs.cpu-architecture == arm64' }]
        expect(comparator).to be_different(actual_service)
      end

      it 'detects distinctInstances changes' do
        expected_service[:placement_constraints] = [{ type: 'distinctInstances' }]
        expect(comparator).to be_different(actual_service)
      end
    end

    context 'when deployment_configuration is missing' do
      before do
        expected_service[:deployment_configuration] = nil
      end

      it 'returns true' do
        expect(comparator).to be_different(actual_service)
      end

      context 'and actual deployment_configuration is default' do
        before do
          actual_service.deployment_configuration.maximum_percent = 200
          actual_service.deployment_configuration.minimum_healthy_percent = 100
        end

        it 'returns false' do
          expect(comparator).to_not be_different(actual_service)
        end
      end
    end
  end
end
