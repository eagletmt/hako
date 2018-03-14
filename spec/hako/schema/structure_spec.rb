# frozen_string_literal: true

require 'spec_helper'
require 'hako/schema/integer'
require 'hako/schema/structure'

RSpec.describe Hako::Schema::Structure do
  let(:schema) { described_class.new }

  before do
    schema.member(:foo, Hako::Schema::Integer.new)
    schema.member(:bar, Hako::Schema::Integer.new)
  end

  describe '#valid?' do
    it do
      expect(schema).to be_valid(foo: 1, bar: 2)
      expect(schema).to_not be_valid(foo: 1)
      expect(schema).to_not be_valid([bar: 2])
      expect(schema).to_not be_valid(foo: '1', bar: 2)
      expect(schema).to be_valid(foo: 1, bar: 2, baz: '3')
    end
  end

  describe '#same?' do
    it do
      expect(schema).to be_same({ foo: 1, bar: 2 }, { foo: 1, bar: 2 }) # rubocop:disable Style/BracesAroundHashParameters
      expect(schema).to_not be_same({ foo: 1, bar: 2 }, { foo: 1, bar: 3 }) # rubocop:disable Style/BracesAroundHashParameters
      expect(schema).to be_same({ foo: 1, bar: 2, baz: 3 }, { foo: 1, bar: 2, baz: 300 }) # rubocop:disable Style/BracesAroundHashParameters
      expect(schema).to be_same({ foo: 1, bar: 2, baz: 300 }, { foo: 1, bar: 2 }) # rubocop:disable Style/BracesAroundHashParameters
    end
  end
end
