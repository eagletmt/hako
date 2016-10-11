# frozen_string_literal: true
require 'spec_helper'
require 'hako/schema/nullable'
require 'hako/schema/integer'

RSpec.describe Hako::Schema::Nullable do
  let(:schema) { described_class.new(subschema) }
  let(:subschema) { Hako::Schema::Integer.new }

  describe '#valid?' do
    it do
      expect(schema).to be_valid(100)
      expect(schema).to be_valid(nil)
      expect(schema).to_not be_valid('100')
    end
  end

  describe '#same?' do
    context 'when both sides are non-null' do
      it do
        expect(schema).to be_same(100, 100)
        expect(schema).to_not be_same(100, 200)
      end
    end

    context 'when one side is null' do
      it do
        expect(schema).to_not be_same(nil, 100)
        expect(schema).to_not be_same(100, nil)
      end
    end

    context 'when both sides are null' do
      it do
        expect(schema).to be_same(nil, nil)
      end
    end
  end
end
