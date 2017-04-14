# frozen_string_literal: true

require 'spec_helper'
require 'hako/schema/integer'
require 'hako/schema/with_default'

RSpec.describe Hako::Schema::WithDefault do
  let(:schema) { described_class.new(subschema, default_value) }
  let(:default_value) { 100 }
  let(:subschema) { Hako::Schema::Integer.new }

  describe '#valid?' do
    it do
      expect(schema).to be_valid(nil)
      expect(schema).to be_valid(50)
      expect(schema).to_not be_valid('50')
    end
  end

  describe '#same?' do
    context 'when both sides satisfy subschema' do
      it do
        expect(schema).to be_same(50, 50)
        expect(schema).to_not be_same(70, 50)
      end
    end

    context 'when one side is nil' do
      it do
        expect(schema).to be_same(nil, default_value)
        expect(schema).to be_same(default_value, nil)
        expect(schema).to_not be_same(nil, 123)
        expect(schema).to_not be_same(123, nil)
      end
    end

    context 'when side sides are nil' do
      it do
        expect(schema).to be_same(nil, nil)
      end
    end
  end
end
