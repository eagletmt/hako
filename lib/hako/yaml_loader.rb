# frozen_string_literal: true

require 'psych'

module Hako
  class YamlLoader
    def initialize
      @current_path = nil
    end

    # @param [String] path
    # @return [Hash]
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
            h2 = Hash.new {|h, k| h[k] = Hash.new }
            r.each do |k, v|
              if k == SHOVEL
                h2.merge!(v)
              else
                h2[k].merge!(v)
              end
            end
            r.replace(h2)
          end
        end
      end
    end
  end
end
