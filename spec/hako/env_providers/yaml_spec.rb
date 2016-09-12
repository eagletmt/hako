# frozen_string_literal: true
require 'spec_helper'
require 'hako/env_providers/yaml'

RSpec.describe Hako::EnvProviders::Yaml do
  let(:provider) { described_class.new(fixture_root, options) }
  let(:options) { { 'path' => 'env.yml' } }

  describe '#ask' do
    it 'returns known variables' do
      expect(provider.ask(['username'])).to eq('username' => 'eagletmt')
      expect(provider.ask(['host'])).to eq('host' => 'app-001,app-002')
      expect(provider.ask(['app.db.host'])).to eq('app.db.host' => 'db-001')
      expect(provider.ask(['app.db.port'])).to eq('app.db.port' => '3306')
      expect(provider.ask(['app.cache.host'])).to eq('app.cache.host' => 'cache-001')
      expect(provider.ask(['app.cache.port'])).to eq('app.cache.port' => '11211')
    end

    it 'returns empty to unknown variables' do
      expect(provider.ask(['undefined'])).to eq({})
    end

    context 'when key_sep=_ ary_sep=/' do
      let(:options) { { 'path' => 'env.yml', 'key_sep' => '_', 'ary_sep' => '/' } }

      it 'returns known variables' do
        expect(provider.ask(['username'])).to eq('username' => 'eagletmt')
        expect(provider.ask(['host'])).to eq('host' => 'app-001/app-002')
        expect(provider.ask(['app_db_host'])).to eq('app_db_host' => 'db-001')
        expect(provider.ask(['app_db_port'])).to eq('app_db_port' => '3306')
        expect(provider.ask(['app_cache_host'])).to eq('app_cache_host' => 'cache-001')
        expect(provider.ask(['app_cache_port'])).to eq('app_cache_port' => '11211')
      end
    end
  end
end
