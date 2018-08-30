# frozen_string_literal: true

require 'spec_helper'
require 'hako/application'
require 'hako/definition_loader'

RSpec.describe Hako::DefinitionLoader do
  let(:definition_loader) { described_class.new(app, dry_run: dry_run) }
  let(:fixture_name) { 'default.jsonnet' }
  let(:app) { Hako::Application.new(fixture_root.join('jsonnet', fixture_name)) }
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
  end
end
