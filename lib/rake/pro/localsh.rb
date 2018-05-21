require 'open4'

module Rake

  class CommandNotFound < StandardError
  end
  
  class AbnormalExitStatus  < StandardError
    attr_reader :exit_status
    def initialize(exit_status, error_lines)
      @exit_status = exit_status
      super error_lines
    end
  end
  
  class Local

    class << self

      def sh command_line = nil, opts = {}
        if command_line.nil?
          if block_given?
            sh yield(), opts
          else
            raise ArgumentError, "Command line not specified"
          end
        elsif command_line.is_a? Array
          command_line.each { |cmdline|
            sh cmdline, opts
          }
        else
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
        end
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
  end
end