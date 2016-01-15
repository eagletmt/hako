require 'logger'
require 'hako/version'

module Hako
  def self.logger
    @logger ||=
      begin
        $stdout.sync = true
        Logger.new($stdout)
      end
  end
end
