# frozen_string_literal: true
require 'psych'

module Hako
  module YamlLoader
    class << self
      def load(path)
        class_loader = Psych::ClassLoader.new
        scanner = Psych::ScalarScanner.new(class_loader)
        prev_path = @current_path
        @current_path = path
        visitor = Visitor.new(scanner, class_loader) do |_, val|
          load(@current_path.parent.join(val))
        end
        path.open do |f|
          visitor.accept(Psych.parse(f))
        end
      ensure
        @current_path = prev_path
      end
    end

    class Visitor < Psych::Visitors::ToRuby
      INCLUDE_TAG = 'tag:include'
      SHOVEL = '<<'

      def initialize(scanner, class_loader, &block)
        super(scanner, class_loader)
        @domain_types[INCLUDE_TAG] = [INCLUDE_TAG, block]
      end

      def revive_hash(hash, o)
        super(hash, o).tap do |r|
          if r[SHOVEL].is_a?(Hash)
            h = r.delete(SHOVEL)
            r.merge!(h)
          end
        end
      end
    end
  end
end
