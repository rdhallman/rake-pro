require 'etc'

module Rake

  def self.verbose?
    Rake.verbose == true
  end

  module Pro
  end

  class << self
    def context
      Rake.application.context.values
    end

    def next_arg
      ARGV.shift
    end

    def migration_manager(&block)
      Rake.application.migration_manager(&block)
    end

    def whoami
        Etc.getpwuid(Process.uid).name
    end
  end

end


require "rake/pro/version"
require "rake/pro/exceptions"
require "rake/pro/key_store"
require "rake/pro/localsh"
require "rake/pro/ssh_tunnel"
require "rake/pro/migration_manager"
require "rake/pro/context"
require "rake/pro/migration"
require "rake/pro/script_context"
require "rake/pro/sequel"
require "rake/pro/migration"
require "rake/pro/dsl_extensions"
