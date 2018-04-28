require 'openssl'
require 'net/ssh/gateway'
require 'open4'

module Rake

  class Local

    def sh command_line, opts = {}
      native_output_only = command_line.include?('--terse') || opts[:terse]
      if native_output_only
        command_line.sub!(' --terse', '')
        opts[:echo] = true
        opts[:echo_cmd] = false
      end
      echo_command_output = opts[:echo] || true
      command_line = "#{command_line}"
      puts "$ #{command_line}"
      command_output = ""
      status = Open4::popen4(command_line) do |pid, stdin, stdout, stderr|
        command_output = capture_output(stdout, stderr, echo_command_output, native_output_only)
      end
      if status.exitstatus != 0
        raise AbnormalExitStatus.new(status.exitstatus, command_output) if opts[:raise_on_error]
      end
      command_output.strip
    rescue AbnormalExitStatus
      raise
    rescue Errno::ENOENT
      raise CommandNotFound, "Bash Error.  Command or file arguments not found." if opts[:raise_on_error]
    end

    def capture_output stdout, stderr, echo_command_output, native_output_only
      stdout_lines = ""
      stderr_lines = ""
      command_output = ""
      loop do
        begin
          # check whether stdout, stderr or both are
          #  ready to be read from without blocking
          IO.select([stdout,stderr]).flatten.compact.each { |io|
            # stdout, if ready, goes to stdout_lines
            stdout_lines += io.readpartial(1024) if io.fileno == stdout.fileno
            # stderr, if ready, goes to stdout_lines
            stderr_lines += io.readpartial(1024) if io.fileno == stderr.fileno
          }
          break if stdout.closed? && stderr.closed?
        rescue EOFError
          # Note, readpartial triggers the EOFError too soon.  Continue to flush the
          # pending io (via readpartial) until we have received all characters
          # out from the IO socket.
          break if stdout_lines.length == 0  &&  stderr_lines.length == 0
        ensure
          # if we acumulated any complete lines (\n-terminated)
          #  in either stdout/err_lines, output them now
          stdout_lines.sub!(/.*\n/) {
            command_output << $&
            if echo_command_output
              if native_output_only
                puts $&.strip
              else
                puts $&.strip
              end
            end
          }
          stderr_lines.sub!(/.*\n/) {
            command_output << $&
            if echo_command_output
              if native_output_only
                puts $&.strip
              else
                puts $&.strip
              end
            end
          }
        end
      end
      command_output
    end
  end
    
  class SSH
    class << self
      def tunnel
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
          else 
            host = cfg[:host]
            port = cfg[:port]
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
