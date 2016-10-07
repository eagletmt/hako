# frozen_string_literal: true
module Hako
  module Schema
    class OrderedArray
      def initialize(schema)
        @schema = schema
      end

      def valid?(object)
        object.is_a?(Array) && object.all? { |e| @schema.valid?(e) }
      end

      def same?(xs, ys)
        if xs.size != ys.size
          return false
        end

        xs.zip(ys) do |x, y|
          unless @schema.same?(x, y)
            return false
          end
        end
        true
      end
    end
  end
end
