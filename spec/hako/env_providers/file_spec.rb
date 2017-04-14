# frozen_string_literal: true

require 'spec_helper'
require 'hako/env_providers/file'

RSpec.describe Hako::EnvProviders::File do
  let(:provider) { described_class.new(fixture_root, options) }
  let(:options) { { 'path' => 'hello.env' } }

  describe '#ask' do
    it 'returns known variables' do
      expect(provider.ask(['username'])).to eq('username' => 'eagletmt')
    end

    it 'returns empty to unknown variables' do
      expect(provider.ask(['undefined'])).to eq({})
    end
  end

  describe '#ask_keys' do
    it 'returns known variables' do
      expect(provider.ask_keys(%w[username undefined])).to match_array(['username'])
    end
  end
end
