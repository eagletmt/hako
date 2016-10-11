# frozen_string_literal: true
require 'spec_helper'
require 'hako/schema/integer'
require 'hako/schema/ordered_array'

RSpec.describe Hako::Schema::OrderedArray do
  let(:schema) { described_class.new(subschema) }
  let(:subschema) { Hako::Schema::Integer.new }

  describe '#valid?' do
    it do
      expect(schema).to be_valid([1, 2, 3])
      expect(schema).to_not be_valid(nil)
      expect(schema).to_not be_valid([1, nil])
      expect(schema).to_not be_valid([1, '2'])
    end
  end

  describe '#same?' do
    it do
      expect(schema).to be_same([1, 2, 3], [1, 2, 3])
      expect(schema).to_not be_same([1, 2, 3], [2, 3, 1])
      expect(schema).to_not be_same([1, 2, 3], [1, 2])
      expect(schema).to_not be_same([1, 2], [1, 2, 3])
    end
  end
end
