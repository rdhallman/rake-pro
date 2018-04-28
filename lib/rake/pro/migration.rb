
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

class Migration

    def initialize #(up)
        #@direction = up ? :up : :down
        @loaded = false
    end

    def direction
        Rake.application.reverse ? :down : :up
    end

    def current()
        if @loaded
            #load current migration
        end
    end

    def alreadyApplied?()
        ### !! This can check the history of migrations
        ### applied in the migrations table, and if the
        ### next task name isn't matching/aligning with
        ### what is listed in the database table, it can
        ### warn of concurrent migrations with another
        ### team member.  Oh, and each migration could
        ### include the team member name that did the
        ### migration.
        Rake.application.current_task == "spartan:m0"
    end

    def up
        if @direction == :up && block_given?
            yield
        end
    end

    def down
        if @direction == :down && block_given?
            yield
        end
    end

end

module Rake

    def self.migrate
        puts "current_task: #{Rake.application.current_task}"
        puts "dependent-tasks: #{Rake.application.dependent_tasks.inspect}"

        migration = Migration.new

        #memo.loadMigrationHistory()

        if false #thisMigration.alreadyApplied?
            puts "Skipping..."
            puts "----"
            #raise Rake::Task::Skip
            raise Rake::Task::AbortNormally
        else
            puts "running  #{Rake.application.current_task}..."
            puts "----"
            yield migration if block_given?
            puts "done running!"
        end
    end

end