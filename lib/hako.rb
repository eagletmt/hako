# frozen_string_literal: true

require 'logger'
require 'hako/version'

module Hako
  def self.logger
    @logger ||=
      begin
        $stdout.sync = true
        Logger.new($stdout).tap do |l|
          l.level = Logger::INFO
        end
      end
  end
end
