# frozen_string_literal: true
module Hako
  module Schema
    class Structure
      def initialize
        @members = {}
      end

      def valid?(object)
        unless object.is_a?(::Hash)
          return false
        end
        @members.each do |key, val_schema|
          unless val_schema.valid?(object[key])
            return false
          end
        end
        true
      end

      def same?(x, y)
        @members.each do |key, val_schema|
          unless val_schema.same?(x[key], y[key])
            return false
          end
        end
        true
      end

      def member(key, schema)
        @members[key] = schema
      end
    end
  end
end
