desc "Migrate up to latest migration"
task :migrate do
  begin
    puts "Migrating to latest"
    ns = "#{File.basename(Rake.application.active_dir)}"
    load "#{Rake.application.active_dir}/migrations.rake"
    Rake::MigrationManager.instance.migrate_to_latest
    Rake::Task["#{ns}:latest"].invoke
  ensure
    Rake::MigrationManager.instance.destroy
  end
end
  

namespace :migrate do

    desc "Migrate up to latest migration"
    task :up do
      begin
        ns = "#{File.basename(Rake.application.active_dir)}"
        #namespace ns do
          load "#{Rake.application.active_dir}/migrations.rake"
        #end
        Rake::MigrationManager.instance.migrate_up()
        Rake::Task["#{ns}:latest"].invoke
      ensure
        Rake::MigrationManager.instance.destroy()
      end
    end
  
    desc "Migrate down to specified migration"
    task :down do
      begin
        ns = "#{File.basename(Rake.application.active_dir)}"
        Rake.application.reverse = true
        #namespace ns do
          load "#{Rake.application.active_dir}/migrations.rake"
        #end
        Rake::MigrationManager.instance.migrate_down
        Rake::Task["#{ns}:latest"].invoke(0)
      ensure
        Rake::MigrationManager.instance.destroy
      end
    end

#migrations table
#task  |  Description  | Status  | Time  | Author? |  Deployer
# m0

    desc "Create initial migration table"
    task :init do
      sequel(Rake.context[:migrations][:user]) do |db|
        db.create_table(Rake.context[:migrations][:table]) do
          primary_key :id
          Time :applied_at
          String :name
          String :description
          String :action
          String :status
          String :output
          String :author
          String :dbuser
          String :prereqs
          String :dependents
        end
      end
    end

    desc "List migrations that have already been performed"
    task :list do
      Rake.migration_manager do |mgr, db|
        mgr.migration_history.each do |row, index|
          puts "#{row.inspect}"
        end
      end
    end

    desc "Insert some fake records"
    task :insert do
      sequel(Rake.context[:migrations][:user]) do |db|
        db.loggers << Logger.new($stdout)
        db.run "INSERT INTO public.testmitbl VALUES ('abc', '#{Time.now}', 'some desc', 'applied', 'max', '123')"
      end
    end

end