# frozen_string_literal: true

require 'spec_helper'
require 'hako/schema/integer'
require 'hako/schema/string'
require 'hako/schema/table'

RSpec.describe Hako::Schema::Table do
  let(:schema) { described_class.new(key_schema, val_schema) }
  let(:key_schema) { Hako::Schema::String.new }
  let(:val_schema) { Hako::Schema::Integer.new }

  describe '#valid?' do
    it do
      expect(schema).to be_valid('foo' => 1, 'bar' => 2)
      expect(schema).to_not be_valid('foo' => 1, 'bar' => '2')
      expect(schema).to_not be_valid('foo' => 1, bar: 2)
      expect(schema).to be_valid({})
    end
  end

  describe '#same?' do
    it do
      expect(schema).to be_same({ 'foo' => 1, 'bar' => 2 }, { 'foo' => 1, 'bar' => 2 }) # rubocop:disable Style/BracesAroundHashParameters
      expect(schema).to_not be_same({ 'foo' => 1, 'bar' => 2 }, { 'foo' => 1, 'bar' => 2, 'baz' => 3 }) # rubocop:disable Style/BracesAroundHashParameters
    end
  end
end
