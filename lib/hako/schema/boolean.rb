# frozen_string_literal: true
module Hako
  module Schema
    class Boolean
      def valid?(object)
        object.is_a?(FalseClass) || object.is_a?(TrueClass)
      end

      def same?(x, y)
        x == y
      end
    end
  end
end
