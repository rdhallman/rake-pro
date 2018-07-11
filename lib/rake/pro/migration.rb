
#migrations table
#task  |  Description  | Status  | Time  | Author? |  Deployer
# m0
# m1
#  well, the description could include the author
#  the deployer would be the name of the db user writing
#  the record.
#
#  the status could be ["APPLIED", "REVERSED"]
#
# How could I make this server-side?
#
# How to prevent some users in prod? 
#   their sql user simply doesn't allow write access

require "singleton"
require "etc"

module Rake

    class Migration < Rake::Task

        def initialize(task_name, app)
            puts "INITIALIZING Migration:  #{task_name}"
            super
        end

        class << self

            def define_migration(*args, &block)
                Rake.application.define_migration(self, *args, &block)
            end
  
        end
    end

    class MigrationManagerEx
        include Singleton

        def initialize
            @initialized = false
        end

        def init()
            if !@initialized
                begin
                    @dbuser = Rake.context[:migrations][:user]
                    @gateway, @host, @port = Rake::SSH.open_tunnel
                    @db = sequel_connect(@host, @port, @dbuser)
                    @db.loggers << Logger.new($stdout)
                    @migration_history = @db["SELECT * FROM public.testmitbl"].all
                    @initialized = true
                rescue Sequel::DatabaseError => ex
                    raise RakeTaskError.new("Migration table not yet provisioned.  You need to run migrate:init task.", ex)
                end
            end
        end

        def whoami
            Etc.getpwuid(Process.uid).name
        end

        def destroy
            if @initialized
                @db.disconnect unless @db.nil?
                @gateway.close(@port) unless @gateway.nil?
            end
        end

        def migrate_to_latest
            @direction = :up
            init
        end

        def migrate_up
            @direction = :up
            init()
        end

        def set_mode(direction, count = 0)
            @direction = direction
            @count = count
            Rake.application.reverse = direction == :down
            init()
        end

        def direction
            Rake.application.reverse ? :down : :up
        end

        def current()
            if @loaded
                #load current migration
            end
        end

        def migration_in_progress(mip)
            @mip = mip
        end

        def alreadyApplied?(name)

            #puts "task in progress -------------"
            #puts Rake.application.task_in_progress.comment

            #tip =  Rake.application.task_in_progress
            #puts "IN PROGRESS TASK:"
            #puts ""
            #puts tip.investigation
            #puts tip.inspect
            #puts "Desc: #{tip.comment}"
            #puts "Name: #{tip.name}"
            #puts "Name with args: #{tip.name_with_args}"
            #puts "Prereq: #{tip.prerequisites}"
            #puts "Actions: #{tip.actions}"
            #puts "Comments: #{tip.comments}"
            #puts "scope: #{tip.scope}"
            #puts "arg names: #{tip.arg_names}"
            #puts "locations: #{tip.locations}"
            #puts "all prereqs: #{all_prerequisite_tasks.inspect}"


            puts "Checking is applied: #{name}"


            ### !! This can check the history of migrations
            ### applied in the migrations table, and if the
            ### next task name isn't matching/aligning with
            ### what is listed in the database table, it can
            ### warn of concurrent migrations with another
            ### team member.  Oh, and each migration could
            ### include the team member name that did the
            ### migration.
            #Rake.application.current_task == "spartan:m0"
            false
        end

        def onMigrationApplied
        end

        def up
            if @direction == :up && block_given?
                begin
                    yield @db
                    puts "done with migration.  Inserting..."
                    @db.run "INSERT INTO public.testmitbl VALUES ('#{@mip.name}', '#{Time.now}', '#{@mip.full_comment}', 'applied', '#{whoami} as #{@dbuser}', '#{@mip.prerequisites.join(', ')}')"
                rescue => ex
                    puts "EXCEPTION! #{ex}"
                end
            end
        end

        def down
            if @direction == :down && block_given?
                begin
                    yield @db
                    @db.run "INSERT INTO public.testmitbl VALUES ('#{@mip.name}', '#{Time.now}', '#{@mip.full_comment}', 'reversed', '#{whoami} as #{@dbuser}', '#{@mip.prerequisites.join(', ')}')"
                rescue => ex
                end
            end
        end
    end

    def self.migrate
        puts "current_task: #{Rake.application.current_task}"
        puts "dependent-tasks: #{Rake.application.dependent_tasks.inspect}"

        manager = MigrationManager.instance
        manager.migration_in_progress(Rake.application.task_in_progress)

        if manager.alreadyApplied?(Rake.application.current_task)
            puts "Skipping..."
            puts "----"
            #raise Rake::Task::Skip
            raise Rake::Task::AbortNormally
        else
            puts "running  #{Rake.application.current_task}..."
            puts "----"
            yield manager if block_given?
            puts "done running!"
        end
    end

end