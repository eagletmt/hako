require 'logger'
require 'hako/version'

module Hako
  def self.logger
    @logger ||= Logger.new($stdout)
  end
end
