# frozen_string_literal: true

require 'spec_helper'
require 'hako/schedulers/ecs_volume_comparator'
require 'aws-sdk-ecs'

RSpec.describe Hako::Schedulers::EcsVolumeComparator do
  let(:comparator) { described_class.new(expected_volume) }
  let(:expected_volume) do
    {
      docker_volume_configuration: {
        autoprovision: false,
        driver_opts: {
          'type' => 'tmpfs',
          'device' => 'tmpfs',
        },
        labels: {
          'foo' => 'bar',
        },
      },
      efs_volume_configuration: {
        authorization_config: {
          access_point_id: 'foo',
          iam: 'foo',
        },
        file_system_id: 'foo',
        root_directory: '/foo',
        transit_encryption: 'DISABLED',
        transit_encryption_port: 1234,
      },
      host: {
        source_path: '/tmp',
      },
      name: 'foo',
    }
  end
  let(:actual_volume) do
    Aws::ECS::Types::Volume.new(
      docker_volume_configuration: Aws::ECS::Types::DockerVolumeConfiguration.new(
        autoprovision: false,
        driver: 'local',
        driver_opts: {
          'type' => 'tmpfs',
          'device' => 'tmpfs',
        },
        labels: {
          'foo' => 'bar',
        },
        scope: 'task',
      ),
      efs_volume_configuration: Aws::ECS::Types::EFSVolumeConfiguration.new(
        authorization_config: Aws::ECS::Types::EFSAuthorizationConfig.new(
          access_point_id: 'foo',
          iam: 'foo',
        ),
        file_system_id: 'foo',
        root_directory: '/foo',
        transit_encryption: 'DISABLED',
        transit_encryption_port: 1234,
      ),
      host: Aws::ECS::Types::HostVolumeProperties.new(
        source_path: '/tmp',
      ),
      name: 'foo',
    )
  end

  describe '#different?' do
    context 'when same' do
      it 'returns false' do
        expect(comparator).to_not be_different(actual_volume)
      end
    end

    context 'when some parameters differ' do
      before do
        actual_volume.docker_volume_configuration.labels['foo'] = 'baz'
      end

      it 'returns true' do
        expect(comparator).to be_different(actual_volume)
      end
    end
  end
end
