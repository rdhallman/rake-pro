require 'stringio'
require 'logger'
require 'awesome_print'

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

      def load_migrations_in_scope
        ns = Rake.application.context.path_namespace

        load "#{Rake.application.active_dir}/migrations.rake" if File.exists?
        if ns.nil?
          mfile = "#{Rake.application.active_dir}/migrations.rake"
          load mfile if File.file?(mfile)
          load "#{Rake.application.active_dir}/migrations.rake" if File.file?
          Rake::Task["latest"].invoke
        else
          load "#{Rake.application.active_dir}/migrations.rake"
          Rake::Task["#{ns}:latest"].invoke
        end
      end


      def set_mode(direction, count = 0)
        @direction = direction
        @count = count
        Rake.application.reverse = direction == :down
        init_migration_manager()
      end

      def migration_history
        @migration_history = @mdb[Rake.context[:migrations][:table].to_sym].all unless @migration_history
        @migration_history
      end

      def latest_migrations
        lm = migration_history.reduce({}) { |acc, mig|
          key = mig[:name].to_sym
          if acc.has_key?(key)
            acc[key] << mig
          else
            acc[key] = [mig]
          end
          acc
        }
        lm.each_pair { |key, value|
          lm[key] = value.sort_by { |item|
            -item[:id]
          }
        }
        lm.each_pair { |key, value|
          lm[key] = value.first
        }
        lm
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
            Time :applied
            String :scopes, size: 128
            String :name, size: 128
            String :action, size: 32
            String :status, size: 32
            String :author, size: 64
            Time :created
            Time :updated
            String :revisions, size: 256
            String :executor, size: 64
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
        #migrating_up? ? "APPLY" : "REVERSE"
        migrating_up? ? "UP" : "DOWN"
      end

      def record_success(migration)
        migrations.insert(
            applied: Time.now,
            scopes: scopes_applied(migration),
            name: migration.name,
            action: action?,
            status: "SUCCEEDED",
            author: migration.author,
            created: migration.created,
            updated: migration.updated,
            revisions: migration.revisions,
            executor: Rake.whoami,
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
            author: migration.author,
            created: migration.created,
            updated: migration.updated,
            revisions: migration.revisions,
            executor: Rake.whoami,
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

      def migrate_up_pending?(migration)
        return false if !migrating_up?
        key = migration.name.to_s
        lm = latest_migrations
        return !(lm.has_key?(key) &&
            lm[key][:action].to_s == :UP &&
            lm[key][:status].to_s == :SUCCEEDED)
      end

      def migrate_down_pending?(migration)
        return false if !migrating_down?
        key = migration.name.to_s
        lm = latest_migrations
        return lm.has_key?(key) &&
            lm[key][:action].to_s == :UP &&
            lm[key][:status].to_s == :SUCCEEDED
      end

      def migrating_down?
        !migrating_up?
      end

    end
  
  end
  