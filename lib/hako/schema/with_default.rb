# frozen_string_literal: true

module Hako
  module Schema
    class WithDefault
      def initialize(schema, default)
        @schema = schema
        @default = default
      end

      def valid?(object)
        object.nil? || @schema.valid?(object)
      end

      def same?(x, y)
        @schema.same?(wrap(x), wrap(y))
      end

      private

      def wrap(x)
        x.nil? ? @default : x
      end
    end
  end
end
