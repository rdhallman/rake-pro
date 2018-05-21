require 'rake'
require 'yaml'
require 'etc'

module Rake
  class Application
    include MigrationManager

    attr_accessor :context
    attr_accessor :scopes
    attr_accessor :context
    attr_accessor :context_class
    attr_accessor :active_dir
    attr_accessor :active_task
    attr_accessor :current_task
    attr_accessor :dependent_tasks
    attr_accessor :disconnected
    attr_accessor :reverse
    attr_accessor :executing_task

    class Context
      def initialize
        @cfg_files = []
        @kvp_stack = []
        @active_scopes = []
        @kvp = KeyStore.new
      end

      def [](key)
        @kvp.fetch(key) {
          raise "Key '#{key}' is missing from toplevel application context"
        }
      end

      def values()
        @kvp
      end

      def home()
        Etc.getpwuid.dir;
      end
  
      def root()
        Rake.original_dir
      end

      def rpath(*paths)
        return File.join(paths)
      end

      def active_scopes
        @active_scopes
      end

      def push_scope scope
        puts "Promoting scope '#{scope}'." if Rake.verbose?
        @active_scopes.push(scope)
      end

      def pop_scope
        @active_scopes.pop
      end

      def push_cfg cfg_file
        puts "Loading configuration file: #{cfg_file}" if Rake.verbose?
        cfg = KeyStore.load(cfg_file)
        source = if (cfg.has_key?(:default))
                    cfg[:default]
                  elsif (cfg.has_key?(:source))
                    cfg[:source]
                  elsif (cfg.has_key?(:system))
                    cfg[:system]
                  elsif(cfg.has_key?(:target))
                    cfg[:target]
                  end

        push_scope(source.to_sym) if source
        @kvp_stack.push(cfg)
      end

      def pop_cfg
        @kvp_stack.pop
      end

      def load_once(cfg_file)
        unless @cfg_files.include?(cfg_file)
          if (File.file?(cfg_file))
            Rake.application.active_dir = File.dirname(cfg_file)
            push_cfg(cfg_file)
          end
          @cfg_files.push(cfg_file)
        end
      end

      def scope_siblings scope
        siblings = nil
        Rake.application.scopes.each { |scope_set|
          siblings = scope_set if scope_set.include?(scope)
        }
        siblings
      end
          
      def before_invoke task_details
        task_name = task_details[0]
        parts = task_name.split(':')
        push_scope(parts[0].to_sym) if parts.length == 1

        load_paths = [*0..parts.length-1].reduce([
            rpath(root, 'cfg.yml'),
            rpath(root, '.cfg.yml'),
            rpath(root, 'cfg-private.yml'),
            rpath(root, '.cfg-private.yml'),
            rpath(root, 'cfg-local.yml'),
            rpath(root, '.cfg-local.yml')
          ]) { |paths, index|
            folder = File.join(parts[0..index])
            paths.push(rpath(root, folder, 'cfg.yml'))
            paths.push(rpath(root, folder, '.cfg.yml'))
            paths.push(rpath(root, folder, 'cfg-private.yml'))
            paths.push(rpath(root, folder, '.cfg-private.yml'))
            paths.push(rpath(root, folder, 'cfg-local.yml'))
            paths.push(rpath(root, folder, '.cfg-local.yml'))
            paths
        }
        load_paths.push(rpath(home, '.cyborg.yml'))

        load_paths.each { |path|
          load_once(path)
        }

        # promote and prune the key space
        promoted = false
        pruned_stack = []
        @kvp_stack.each { |kvp| 
          @active_scopes.each { |scope|
            kvp, didpromote = kvp.promote_key(scope)

            siblings = scope_siblings(scope)
            kvp = kvp.prune_keys(siblings) if siblings
            promoted |= didpromote && scope == task_name.to_sym
          }
          pruned_stack.push(kvp)
        }

        # merge the kvp stack entries into a single map
        @kvp = pruned_stack.reduce(KeyStore.new) { |acc, kvp|
          acc.recursive_merge(kvp)
        }

        [task_name, promoted]
      end

      def after_invoke task_details
        task_name = task_details[0]
        parts = task_name.split(':')
        if parts.length > 1
          pop_scope
          pop_cfg
        end
      end

    end

    def migration_manager
      db = init_migration_manager
      yield(self, db) if block_given?
    end
  end


  module ApplicationOverrides

    def context_factory
      Rake.application.context_class.nil? ? Application::Context.new : Rake.application.context_class.new
    end

    def invoke_task *args
      task_name, pruned = (Rake.application.context ||= context_factory).before_invoke(parse_task_string args.first)
      if Rake::Task.task_defined?(task_name) || !pruned
        Rake.application.active_task = task_name
        super
      end
      Rake.application.context.after_invoke(parse_task_string args.first)
    end

    # Display the tasks and comments.
    def display_tasks_and_comments # :nodoc:
      displayable_tasks = tasks.select { |t|
        (options.show_all_tasks || t.comment) &&
          t.name =~ options.show_task_pattern
      }
      case options.show_tasks
      when :tasks
        width = displayable_tasks.map { |t| t.name_with_args.length }.max || 10
        if truncate_output?
          max_column = terminal_width - name.size - width - 7
        else
          max_column = nil
        end

        displayable_tasks.each do |t|
          if top_level_tasks.length == 1 && top_level_tasks.first == 'default'
            match = true
          else
            match = false
            top_level_tasks.each { |ns| 
              match = t.name.start_with?("#{ns}:")
            }
          end
          next if !match
          printf("#{name} %-#{width}s  # %s\n",
            t.name_with_args,
            max_column ? truncate(t.comment, max_column) : t.comment)
        end
      when :describe
        displayable_tasks.each do |t|
          puts "#{name} #{t.name_with_args}"
          comment = t.full_comment || ""
          comment.split("\n").each do |line|
            puts "    #{line}"
          end
          puts
        end
      when :lines
        displayable_tasks.each do |t|
          t.locations.each do |loc|
            printf "#{name} %-30s %s\n", t.name_with_args, loc
          end
        end
      else
        fail "Unknown show task mode: '#{options.show_tasks}'"
      end
    end

  end

  module TaskOverrides
    class AbortNormally < Exception
    end

    def flag_as_migration
      @isa_migration = true
    end

    def invoke_prerequisites(task_args, invocation_chain)
      (Rake.application.dependent_tasks ||= []).push(@name)
      super
      Rake.application.dependent_tasks.pop
    end

    def up
      puts "Calling up!"
=begin
      if @direction == :up && block_given?
        begin
            yield @db
            puts "done with migration.  Inserting..."
            @db.run "INSERT INTO public.testmitbl VALUES ('#{@mip.name}', '#{Time.now}', '#{@mip.full_comment}', 'applied', '#{whoami} as #{@dbuser}', '#{@mip.prerequisites.join(', ')}')"
        rescue => ex
            puts "EXCEPTION! #{ex}"
        end
=end
    end

    def down
      puts "Calling down!"
    end

    def execute(args=nil)
      Rake.application.current_task = @name  
      Rake.application.executing_task = true
      Rake.application.task_in_progress = self
      if (@isa_migration)
        Rake.application.init_migration_manager
      else
        super
      end
      Rake.application.executing_task = false
    rescue => ex
      puts "Error:\n => #{ex.message}"
      puts "Backtrace:\n\t#{ex.backtrace.join("\n\t")}" if Rake.verbose?
    end


    def invoke_with_call_chain(task_args, invocation_chain) # :nodoc:
      Rake.application.active_task = name
      new_chain = InvocationChain.append(self, invocation_chain)
      @lock.synchronize do
        if application.options.trace
          application.trace "** Invoke #{name} #{format_trace_flags}"
        end
        return if @already_invoked
        @already_invoked = true
        begin
          if Rake.application.reverse
            execute(task_args) if needed?
            invoke_prerequisites(task_args, new_chain)
          else
            invoke_prerequisites(task_args, new_chain)
            execute(task_args) if needed?
          end
        rescue AbortNormally => ex
        end
      end
    rescue Exception => ex
      add_chain_to(ex, new_chain)
      raise ex
    end
  end
end

Rake::Application.class_eval do
  prepend Rake::ApplicationOverrides
end

Rake::Task.class_eval do
  prepend Rake::TaskOverrides
end

def require_tasks rakefile
  rakepaths = Gem.find_latest_files("**/#{rakefile}")
  if rakepaths.length > 1
    puts "Warning! Required rake tasks found at multiple paths.  Using first of:"
    puts rakepaths.inspect
  end
  load rakepaths.first
end