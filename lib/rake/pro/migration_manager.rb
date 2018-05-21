module Rake

    module MigrationManager 

      attr_reader :mdb
      attr_reader :migration_history
  
      def initialize # :nodoc:
        puts "Initializing task manager!!!"
        super
      end

      def init_migration_manager
        unless @migration_manager_initialized
            puts "Initing migration manager!!!" if Rake.verbose?
            @dbuser = Rake.context[:migrations][:user]
            @gateway, @host, @port = Rake::SSH.open_tunnel
            @mdb = sequel_connect(@host, @port, @dbuser)
            @mdb.loggers << Logger.new($stdout) if Rake.verbose?
            @migration_history = @mdb[Rake.context[:migrations][:table].to_sym].all
            @migration_manager_initialized = true
        end
        @mdb
      rescue Sequel::DatabaseError => ex
        raise RakeTaskError.new("Migration table not yet provisioned.  You need to run migrate:init task.", ex)
      end

    end
  
  end
  