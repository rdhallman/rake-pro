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
    attr_accessor :task_in_progress

    class Context
      def initialize
        @kvp_files = @rake_files = []
        @kvp_stack = []
        @active_scopes = []
        @kvp = KeyStore.new
        @scope_depth = 0
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

      def scope_depth
        @scope_depth
      end

      def push_scope scope
        puts "Promoting scope '#{scope}'." if Rake.verbose?
        @active_scopes.push(scope)
      end

      def pop_scope
        @active_scopes.pop
      end

      def push_kvp kvp_file
        puts "Loading configuration file: #{kvp_file}" if Rake.verbose?
        kvp = KeyStore.load(kvp_file)
        source = if (kvp.has_key?(:default))
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

      def pop_kvp
        @kvp_stack.pop
      end

      def path_namespace
        ns = File.basename(Rake.application.active_dir)
        File.basename(root) == ns ? nil : ns
      end

      def load_kvpfile_once(kvp_file)
        unless @kvp_files.include?(kvp_file)
          if (File.file?(kvp_file))
            # Rake.application.active_dir = File.dirname(kvp_file)
            #  loading rakefiles will set active dir more accurately
            push_kvp(kvp_file)
          end
          @kvp_files.push(kvp_file)
        end
      end

      def load_rakefile_once(rake_file, depth)
        unless @rake_files.include?(rake_file)
          if (File.file?(rake_file))
            Rake.application.active_dir = File.dirname(rake_file)
            fullpath = File.expand_path(rake_file, root)
            @scope_depth = depth
            Rake.load_rakefile(fullpath)
          end
          @rake_files.push(rake_file)
        end
      end

      def scope_siblings scope
        siblings = nil
        Rake.application.scopes.each { |scope_set|
          siblings = scope_set if scope_set.include?(scope)
        }
        siblings
      end
          
      private def kvp_files(paths)
        [
          rpath(*paths, 'cfg.yml'),
          rpath(*paths, '.cfg.yml'),
          rpath(*paths, 'cfg-private.yml'),
          rpath(*paths, '.cfg-private.yml'),
          rpath(*paths, 'cfg-local.yml'),
          rpath(*paths, '.cfg-local.yml')
        ]
      end

      private def rake_files(paths, depth)
        [
          { path: rpath(*paths, 'tasks.rake'), depth: depth },
          { path: rpath(*paths, 'migrations.rake'), depth: depth }
        ]
      end


      def before_invoke task_name, task_args
        parts = task_name.split('/')
        push_scope(parts[0].to_sym) if parts.length == 1
        ARGV.shift

        task_name = parts.last

        load_paths = [*0..parts.length-1].reduce(
          kvps: kvp_files([root]),
          rakes: rake_files([root], 0)
        ) { |paths, index|
            folder = File.join(parts[0..index])
            paths[:kvps] += kvp_files([root] + parts[0..index])
            paths[:rakes] += rake_files([root] + parts[0..index], index+1)
            paths
        }
        load_paths[:kvps].push(rpath(home, '.cyborg.yml'))

        load_paths[:kvps].each { |path|
          load_kvpfile_once(path)
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

        # Load rakefiles along the path
        load_paths[:rakes].each { |rake|
          load_rakefile_once(rake[:path], rake[:depth])
        }

        [task_name, promoted]
      end

      def after_invoke task_details
        task_name = task_details[0]
        parts = task_name.split(':')
        if parts.length > 1
          pop_scope
          pop_kvp
        end
      end

    end

    def migration_manager
      db = init_migration_manager
      yield(self, db) if block_given?
    end

  end
end


module Rake
  module ApplicationOverrides

    def context_factory
      Rake.application.context_class.nil? ? Application::Context.new : Rake.application.context_class.new
    end

    def invoke_task *args
      Rake::TaskManager.record_task_metadata = true
      task_name, task_args = parse_task_string *args
      task_name, pruned = (Rake.application.context ||= context_factory).before_invoke(task_name, task_args)
      if Rake::Task.task_defined?(task_name) || !pruned
        Rake.application.active_task = task_name
        if task_args.length > 0
          task_details = "#{task_name}[#{task_args}.join(', ')]"
        else
          task_details = task_name
        end
        super(task_details)
      end
      Rake.application.context.after_invoke(parse_task_string args.first)
    end

    def standard_rake_options # :nodoc:
      stdopts = super
      stdopts << ["--migrations", "-M [PATTERN]",
            "Display the migrations (matching optional PATTERN) " +
            "with descriptions, then exit. " +
            "-AM combination displays all of migrations contained no description.",
            lambda { |value|
              select_tasks_to_show(options, :migrations, value)
            }
      ]
      sort_options(stdopts)
    end

    # Display the tasks and comments.
    def display_tasks_and_comments # :nodoc:
      puts "DIsplaying tasks"
      displayable_tasks = tasks.select { |t|
        (options.show_all_tasks || t.comment) &&
          t.name =~ options.show_task_pattern
      }
      case options.show_tasks
      when :migrations
        width = displayable_tasks.map { |t| t.name_with_args.length }.max || 10
        if truncate_output?
          max_column = terminal_width - name.size - width - 7
        else
          max_column = nil
        end

        displayable_tasks.each do |t|
          next if !t.isa_migration?
          #puts t.name_with_args
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
      when :tasks
        width = displayable_tasks.map { |t| t.name_with_args.length }.max || 10
        if truncate_output?
          max_column = terminal_width - name.size - width - 7
        else
          max_column = nil
        end

        displayable_tasks.each do |t|
          next if t.isa_migration?
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

    def top_level
      super
      finalize_migrations
    end
  end
end

Rake::Application.class_eval do
  prepend(Rake::ApplicationOverrides)
end

module Rake
  module TaskOverrides
    attr_reader :author
    attr_reader :created
    attr_reader :revision

    class AbortNormally < Exception
    end

    def flag_as_migration
      @isa_migration = true
    end

    def isa_migration?
      return @isa_migration
    end

    def invoke_prerequisites(task_args, invocation_chain)
      (Rake.application.dependent_tasks ||= []).push(@name)
      super
      Rake.application.dependent_tasks.pop
    end

    # Enhance a task with prerequisites or actions.  Returns self.
    def enhance(deps=nil, &block)
      scope_depth = Rake.application.context.scope_depth || 0
      nt = super
      actions = nt.instance_variable_get("@actions")
      @action_depths ||= {}
      if @action_depths.has_key?(scope_depth)
        @action_depths[scope_depth] << actions.last
      else
        @action_depths[scope_depth] = [actions.last]
      end
      nt
    end

    def up(&block)
      Rake.migration_manager do |mgr, db|
        #if mgr.migrating_up? && mgr.apply_pending?(self)
        if mgr.migrate_up_pending?(self)
          if block_given?
            begin
                if block.parameters.length == 0
                  # block is not receiving the DB argument.  So, expect a SQL string
                  # to be returned that we will run
                  sql = yield db
                  db.run sql
                else
                  yield db
                end
                mgr.record_success(self)
            rescue => ex
                mgr.record_failure(self)
                raise RakeTaskError.new("Failed to apply migration '#{name}'.", ex)
            end
          else
            raise RakeTaskError.new("Migration up() called without a block argument.  You must pass a block to migrate up()")
          end
        end
      end
    end

    def down(&block)
      Rake.migration_manager do |mgr, db|
        #if mgr.migrating_down? && mgr.reverse_pending?(self)
        if mgr.migrate_down_pending?(self)
          if block_given?
            begin
                if block.parameters.length == 0
                  # block is not receiving the DB argument.  So, expect a SQL string
                  # to be returned that we will run
                  sql = yield db
                  db.run sql
                else
                  yield db
                end
                mgr.record_success(self)
            rescue => ex
                mgr.record_failure(self)
                raise RakeTaskError.new("Failed to reverse migration '#{name}'.", ex)
            end
          else
            raise RakeTaskError.new("Migration down() called without a block argument.  You must pass a block to migrate down()")
          end
        end
      end
    end

    def execute_actions(args=nil)
      args ||= EMPTY_TASK_ARGS
      if application.options.dryrun
        application.trace "** Execute (dry run) #{name}"
        return
      end
      application.trace "** Execute #{name}" if application.options.trace
      application.enhance_with_matching_rule(name) if @actions.empty?
      if @current_action.nil? 
        @current_action ||= Rake.application.context.scope_depth
      else
        @current_action -= 1
      end
      @action_depths[@current_action].each { |act| act.call(self, args) }
    end

    def execute(args=nil)
      Rake.application.current_task = @name  
      Rake.application.executing_task = true
      Rake.application.task_in_progress = self
      if (@isa_migration)
        Rake.application.init_migration_manager
        execute_actions(args)
      else
        execute_actions(args)
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

#Rake::Application.singleton_class.prepend(Rake::ApplicationOverrides)


Rake::Task.class_eval do
  prepend(Rake::TaskOverrides)
end

def require_tasks rakefile
  rakepaths = Gem.find_latest_files("**/#{rakefile}")
  if rakepaths.length > 1
    puts "Warning! Required rake tasks found at multiple paths.  Using first of:"
    puts rakepaths.inspect
  end
  load rakepaths.first
end

