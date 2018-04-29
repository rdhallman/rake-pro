module Rake

  def self.verbose?
    Rake.verbose == true
  end

  module Pro
  end
end

require "rake/pro/version"
require "rake/pro/exceptions"
require "rake/pro/key_store"
require "rake/pro/localsh"
require "rake/pro/ssh_tunnel"
require "rake/pro/context"
require "rake/pro/migration"
require "rake/pro/script_context"
