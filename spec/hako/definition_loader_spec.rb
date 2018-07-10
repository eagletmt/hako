# frozen_string_literal: true

require 'spec_helper'
require 'hako/application'
require 'hako/definition_loader'

RSpec.describe Hako::DefinitionLoader do
  let(:definition_loader) { described_class.new(app, dry_run: dry_run) }
  let(:fixture_name) { 'default.yml' }
  let(:app) { Hako::Application.new(fixture_root.join('yaml', fixture_name)) }
  let(:dry_run) { false }

  describe '#load' do
    it 'loads all containers' do
      containers = definition_loader.load('latest')
      expect(containers.keys).to match_array(%w[app front])
      expect(containers.values).to all(be_a(Hako::Container))
      expect(containers['app'].image_tag).to eq('app-image:latest')
      expect(containers['app'].links).to eq([])
      expect(containers['front'].image_tag).to eq('front-image')
      expect(containers['front'].links).to eq([])
    end

    context 'with `with`' do
      it 'loads only specified definition' do
        containers = definition_loader.load('latest', with: [])
        expect(containers.keys).to match_array(['app'])
        expect(containers['app'].image_tag).to eq('app-image:latest')
        expect(containers['app'].links).to eq([])
      end
    end

    context 'with links' do
      let(:fixture_name) { 'default_with_links.yml' }

      it 'loads all containers' do
        containers = definition_loader.load('latest')
        expect(containers.keys).to match_array(%w[app redis memcached fluentd])
        expect(containers.values).to all(be_a(Hako::Container))
      end

      context 'with `with`' do
        it 'loads specified definition and linked containers' do
          containers = definition_loader.load('latest', with: [])
          expect(containers.keys).to match_array(%w[app redis memcached])
        end
      end
    end

    context 'with volumes_from' do
      let(:fixture_name) { 'default_with_volumes_from.yml' }

      it 'loads all containers' do
        containers = definition_loader.load('latest')
        expect(containers.keys).to match_array(%w[app redis memcached fluentd])
        expect(containers.values).to all(be_a(Hako::Container))
      end

      context 'with `with`' do
        it 'loads specified definition and referenced containers' do
          containers = definition_loader.load('latest', with: [])
          expect(containers.keys).to match_array(%w[app redis memcached])
        end
      end
    end
  end
end
