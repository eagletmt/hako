require 'spec_helper'
require 'hako/env_providers/file'

RSpec.describe Hako::EnvProviders::File do
  let(:provider) { described_class.new(options) }
  let(:options) { { 'path' => fixture_path('hello.env') } }

  describe '#ask' do
    it 'returns known variables' do
      expect(provider.ask(['username'])).to eq('username' => 'eagletmt')
    end

    it 'returns empty to unknown variables' do
      expect(provider.ask(['undefined'])).to eq({})
    end
  end
end
