# frozen_string_literal: true
module Hako
  module Schema
    class UnorderedArray
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

        t = xs.dup
        ys.each do |y|
          i = t.index { |x| @schema.same?(x, y) }
          if i
            t.delete_at(i)
          else
            return false
          end
        end

        true
      end
    end
  end
end
