require 'yaml'
require 'erb'
require 'json/minify'
require 'sequel'
require 'uri'

module Rake

    class ScriptContext

        attr_accessor :host
        attr_accessor :port
        attr_accessor :login
        attr_accessor :filepath
    
        def initialize(login, flags)
            @login = login
            # Set flags
            flags.each do |flag|
                instance_variable_set("@#{flag}", true)
            end
        end

        def job
            Rake.application.context.values
        end
        
        def expand template
            template.gsub!(/#\{.+?\}/) { |match|
                cv = match.split(/#\{|\}/)
                "<%= #{cv[1]} %>"
            }
            render = ERB.new(template)
            render.result(binding)
        end
        
        def inject(filename)
            template = IO.read(File.join(Rake.application.active_dir, filename))
            renderer = ERB.new(template)
            JSON.minify(renderer.result(binding))
        rescue => ex
            raise "When ERB expanding and injecting file '#{filename}':\n ]=> " + ex.message
        end

    end

    def self.script(runner, user = :me, sqlfile = nil, &block)
        flags = []
        if block_given?
            script = yield
        elsif sqlfile
            parts = sqlfile.split('@')
            if parts.length == 2
            flags = parts[0].split(',')
            filename = parts[1]
            else
            filename = sqlfile
            end
            script = IO.read(File.join(Rake.application.active_dir, filename))
        else
            raise "You must either pass a sql file or sql string."
        end

        login = context[:users][user.to_sym]
        ctx = ScriptContext.new(login, flags)
        expScript = ctx.expand(script)
        scriptFile = File.join('/tmp/', 'tmp-psql-script.sql')
        File.open(scriptFile,  'w') { |file| file.write(expScript) }
        ctx.filepath = scriptFile
        ctx.login = login
        Rake::SSH.tunnel do |local, host, port|
            ctx.host = host
            ctx.port = port

            cmdLine = Rake.application.context.values['command-lines'][runner]
            exCmdLine = ctx.expand(cmdLine)

            if Rake.application.disconnected
                puts "\n\nWOULD RUN:"

                puts "  $ #{exCmdLine}"
                puts "    ------------------------------------------------------------- "
                contents = IO.read(scriptFile)
                contents.each_line {|line| 
                    if (line.length() > 90)
                        puts "    | %s..." % line[0..90]
                    else
                        puts "    | " + line
                    end
                }
                puts "    -------- END of FILE ------------------------------------------ "

            else
                local.sh %Q[PGPASSWORD=\"#{login[:password]}\" psql -a -h #{host} -U #{login[:username]} -d #{context[:database]} -p #{port} -f #{scriptFile}]
            end
        end
    rescue => ex
        errmsg = ""
        if !sqlfile.nil?
            errmsg = "When expanding SQL file '#{File.join(Rake.application.active_dir, filename)}'"
        elsif block_given?
            errmsg = "When expanding SQL block passed in to psql()"
        end
        puts "\n!!! PSQL Error:\n => #{errmsg}: \n => #{$!}"
        puts "Backtrace:\n\t#{ex.backtrace.join("\n\t")}"
    end

    def sequel(user = :me)
        raise "You must pass a block for this function to yield to" unless block_given?
        login = context[:users][user.to_sym]
        Rake::SSH.tunnel do |local, host, port|
            db =  if host.include?("redshift")
                    Sequel.connect("postgres://#{login[:username]}:#{URI.escape(login[:password])}@#{host}:#{port}/#{context[:database]}", {client_min_messages: false, force_standard_strings: false})
                else
                    Sequel.postgres(host: host, port: port, user: login[:username], password: login[:password], database: context[:database])
                end
            yield db
            db.disconnect
        end
    end

end


def method_missing(m, *args, &block)  
    if Rake.application.executing_task
        Rake.application.executing_task = false
        Rake.script(m, *args, &block)
        Rake.application.executing_task = true
    end
end  
