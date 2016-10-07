# frozen_string_literal: true
module Hako
  module Schema
    class String
      def valid?(object)
        object.is_a?(::String)
      end

      def same?(x, y)
        x == y
      end
    end
  end
end
