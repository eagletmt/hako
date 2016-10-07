# frozen_string_literal: true
module Hako
  module Schema
    class Nullable
      def initialize(schema)
        @schema = schema
      end

      def valid?(object)
        object.nil? || @schema.valid?(object)
      end

      def same?(x, y)
        if x.nil? && y.nil?
          true
        elsif x.nil? || y.nil?
          false
        else
          @schema.same?(x, y)
        end
      end
    end
  end
end
