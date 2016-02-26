# frozen_string_literal: true
require 'spec_helper'
require 'hako/env_expander'

RSpec.describe Hako::EnvExpander do
  let(:expander) { described_class.new(providers) }
  let(:env) { { 'FOO' => 'BAR' } }
  let(:providers) { [provider] }
  let(:provider) { double('EnvProvider') }

  describe '#expand' do
    it 'does nothing when no interpolation is found' do
      expect(expander.expand(env)).to eq('FOO' => 'BAR')
    end

    context 'with interploation' do
      before do
        env['MESSAGE'] = 'Hello, #{username}'
        allow(provider).to receive(:ask).with(['username']).and_return('username' => 'eagletmt')
      end

      it 'resolves interpolated variables with EnvProvider' do
        expect(expander.expand(env)).to eq('FOO' => 'BAR', 'MESSAGE' => 'Hello, eagletmt')
      end
    end

    context 'when undefined variable is interpolated' do
      before do
        env['MESSAGE'] = 'Hello, #{undefined}'
        allow(provider).to receive(:ask).with(['undefined']).and_return({})
      end

      it 'raises error' do
        expect { expander.expand(env) }.to raise_error(Hako::EnvExpander::ExpansionError)
      end
    end

    context 'when multiple provider is specified' do
      let(:another_provider) { double('Another EnvProvider') }

      before do
        providers << another_provider
        allow(provider).to receive(:ask).with(%w[foo bar]).and_return('foo' => 'hoge')
        allow(another_provider).to receive(:ask).with(['bar']).and_return('bar' => 'fuga')
        env['MESSAGE'] = '#{foo}, #{bar}'
      end

      it 'asks providers in order' do
        expect(expander.expand(env)).to eq('FOO' => 'BAR', 'MESSAGE' => 'hoge, fuga')
      end
    end
  end
end
