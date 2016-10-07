# frozen_string_literal: true
module Hako
  module Schema
    class Table
      def initialize(key_schema, val_schema)
        @key_schema = key_schema
        @val_schema = val_schema
      end

      def valid?(object)
        object.is_a?(::Hash) && object.all? { |k, v| @key_schema.valid?(k) && @val_schema.valid?(v) }
      end

      def same?(xs, ys)
        if xs.size != ys.size
          return false
        end

        t = xs.dup
        ys.each do |yk, yv|
          xk, = xs.find { |k, v| @key_schema.same?(k, yk) && @val_schema.same?(v, yv) }
          if xk
            t.delete(xk)
          else
            return false
          end
        end

        t.empty?
      end
    end
  end
end
