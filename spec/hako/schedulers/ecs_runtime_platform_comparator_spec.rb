# frozen_string_literal: true

require 'spec_helper'
require 'hako/schedulers/ecs_runtime_platform_comparator'
require 'aws-sdk-ecs'

RSpec.describe Hako::Schedulers::EcsRuntimePlatformComparator do
  let(:comparator) { described_class.new(expected_runtime_platform) }
  let(:expected_runtime_platform) do
    {
      cpu_architecture: 'ARM64',
      operating_system_family: 'LINUX',
    }
  end
  let(:actual_runtime_platform) do
    Aws::ECS::Types::RuntimePlatform.new(
      cpu_architecture: 'ARM64',
      operating_system_family: 'LINUX',
    )
  end

  describe '#different?' do
    context 'when same' do
      it 'returns false' do
        expect(comparator).to_not be_different(actual_runtime_platform)
      end
    end

    context 'when some parameters differ' do
      before do
        actual_runtime_platform.cpu_architecture = 'X86_64'
      end

      it 'returns true' do
        expect(comparator).to be_different(actual_runtime_platform)
      end
    end

    context 'when some parameters are omitted' do
      let(:expected_runtime_platform) do
        {
          cpu_architecture: nil,
          operating_system_family: 'LINUX',
        }
      end
      let(:actual_runtime_platform) do
        Aws::ECS::Types::RuntimePlatform.new(
          operating_system_family: 'LINUX',
        )
      end

      it 'returns false' do
        expect(comparator).to_not be_different(actual_runtime_platform)
      end
    end
  end
end
