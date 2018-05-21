require 'stringio'
require 'logger'

module Rake

    module MigrationManager 

      def initialize # :nodoc:
        puts "Initializing task manager!!!"
        super
      end

      def init_migration_manager
        unless @migration_manager_initialized
            puts "Initing migration manager!!!" if Rake.verbose?
            @dbuser = Rake.context[:migrations][:user]
            @gateway, @host, @port = Rake::SSH.open_tunnel
            @mdb, @dbuser = sequel_connect(@host, @port, @dbuser)
            @console = StringIO.new
            @mdb.loggers << Logger.new(@console)
            @mdb.loggers << Logger.new($stdout) if Rake.verbose?
            @migration_manager_initialized = true
        end
        @mdb
      rescue Sequel::DatabaseError => ex
        raise RakeTaskError.new("Migration table not yet provisioned.  You need to run migrate:init task.", ex)
      end

      def migration_history
        @migration_history = @mdb[Rake.context[:migrations][:table].to_sym].all unless @migration_history
        @migration_history
      end

      def migrations
        @mdb[Rake.context[:migrations][:table].to_sym]
      end


      #migrations table
      #task  |  Description  | Status  | Time  | Author? |  Deployer
      # m0
      def setup
        @mdb.create_table(Rake.context[:migrations][:table]) do
            primary_key :id
            Time :commit_time
            String :name
            String :action
            String :status
            String :whoami
            String :dbuser
            String :console
        end
      end

      def teardown
        @mdb.drop_table(Rake.context[:migrations][:table].to_sym);
      end

      def action?
        migrating_up? ? "APPLY" : "REVERSE"
      end

      def record_success(migration)
        migrations.insert(
            commit_time: Time.now,
            name: migration.name,
            action: action?,
            status: "SUCCEEDED",
            whoami: Rake.whoami,
            dbuser:  @dbuser,
            console: @console.string
        )
      rescue => ex
        raise RakeTaskError.new("Failed to record information about a migration that succeeded.", ex)
      end

      def record_failure(migration)
        migrations.insert(
            commit_time: Time.now,
            name: migration.name,
            action: action?,
            status: "FAILED",
            whoami: Rake.whoami,
            dbuser: @dbuser,
            console: @console.string
        )
      rescue => ex
        raise RakeTaskError.new("Failed to record information about a migration that failed.", ex)
      end

      def finalize_migrations
        @mdb.disconnect if @migration_manager_initialized
      end

      def migrating_up?
        Rake.application.reverse.nil? || Rake.application.reverse == false
      end

      def migrating_down?
        !migrating_up?
      end

    end
  
  end
  