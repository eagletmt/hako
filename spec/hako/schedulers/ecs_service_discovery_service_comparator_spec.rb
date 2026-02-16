# frozen_string_literal: true

require 'spec_helper'
require 'hako/schedulers/ecs_service_discovery_service_comparator'
require 'aws-sdk-servicediscovery'

RSpec.describe Hako::Schedulers::EcsServiceDiscoveryServiceComparator do
  let(:comparator) { described_class.new(expected_service) }
  let(:expected_service) do
    {
      description: 'foo',
      dns_config: {
        dns_records: [{
          ttl: 60,
          type: 'A',
        }],
      },
    }
  end
  let(:actual_service) do
    Aws::ServiceDiscovery::Types::ServiceSummary.new(
      description: 'foo',
      dns_config: Aws::ServiceDiscovery::Types::DnsConfig.new(
        dns_records: [
          Aws::ServiceDiscovery::Types::DnsRecord.new(
            ttl: 60,
            type: 'A',
          ),
        ],
      ),
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
        actual_service.dns_config.dns_records[0].ttl = 30
      end

      it 'returns true' do
        expect(comparator).to be_different(actual_service)
      end
    end
  end
end
