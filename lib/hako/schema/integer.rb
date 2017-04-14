# frozen_string_literal: true

module Hako
  module Schema
    class Integer
      def valid?(object)
        object.is_a?(::Integer)
      end

      def same?(x, y)
        x == y
      end
    end
  end
end
