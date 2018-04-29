require 'openssl'
require 'net/ssh/gateway'

module Rake
    
  class SSH
    class << self
      def tunnel(local_shell_allowed = false)
          host = gateway = port = jump = nil
          cfg = Rake.application.context.values
          if cfg.has_key?(:jumpbox)
            jump = cfg[:jumpbox]
            host = "127.0.0.1"
            if !Rake.application.disconnected
              gateway = Net::SSH::Gateway.new(
                jump[:host], jump[:user],
                :keys => [jump[:keyfile]] #, :verbose => :debug
              )
              port = gateway.open(cfg[:host], cfg[:port], jump[:port])
            end
          elsif cfg.has_key?(:host) 
            host = cfg[:host]
            port = cfg[:port]
          elsif !local_shell_allowed
            raise RakeTaskError.new("Remote shell requested, but no remote host was configured.")
          end
          local = Rake::Local.new
          yield(local, host, port) if block_given?
      rescue Net::SSH::AuthenticationFailed => ex
          puts "\nError: SSH Failed to Authenticate. You may need to run\n   $ ssh-add ~/.ssh/#{jump[:keyfile]}  # key file\n     ** or add this line to your .bashrc.\n\n"
      ensure
          gateway.close(port) unless gateway.nil?
      end
    end
  end

end
