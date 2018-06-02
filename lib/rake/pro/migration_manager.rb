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

=begin
      def latest_migrations
        ml = migration_history.reduce({}) { |acc, mig|
          key = mig.name.to_sym
          if acc.has_key?(key)
            acc[key] = [mig]
          else
            acc[key] += mig
        }
        ml.each { |key, value|
          ml[key] = value.sort_by { |item|
            item.id
          }
        }
      end
=end

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
            String :scopes, size: 128
            String :name, size: 64
            String :action, size: 32
            String :status, size: 32
            String :whoami, size: 64
            String :dbuser, size: 64
            String :console, text: true
        end
      end

      def teardown
        @mdb.drop_table(Rake.context[:migrations][:table].to_sym);
      end

      def pack  #compress, comsolidate, rehash, squash, purge_history, compact, defrag
        # remove history, only showing the latest status for each migration
      end

      def action?
        migrating_up? ? "APPLY" : "REVERSE"
      end

      def record_success(migration)
        migrations.insert(
            commit_time: Time.now,
            scopes: scopes_applied(migration),
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
            scopes: scopes_applied(migration),
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

      def scopes_applied(migration)
        exclusions = [ :reverse ]
        exclusions += migration.name.split(':').map { |scope| scope.to_sym }
        Rake.application.context.active_scopes.map { |scope|
          scope.to_sym
        }.select { |scope|
          !exclusions.include?(scope)
        }.map { |scope| 
          scope.to_s
        }.join(', ')
      end

      def migrating_up?
        Rake.application.reverse.nil? || Rake.application.reverse == false
      end

      # is the specified migration required but still pending in the
      # current migration action
      def apply_pending?(migration)
      end

      def migrating_down?
        !migrating_up?
      end

      def reverse_pending?(migration)
      end

    end
  
  end
  