desc "Reverse the specifed migration; ie. invoke the down migration block"
task :reverse do
  Rake.application.reverse = true
end
  
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

    desc "Insert some fake records"
    task :insert do
      sequel(Rake.context[:migrations][:user]) do |db|
        db.loggers << Logger.new($stdout)
        db.run "INSERT INTO public.testmitbl VALUES ('abc', '#{Time.now}', 'some desc', 'applied', 'max', '123')"
      end
    end

end

desc "List all migrations that have been committed to the target environment"
task :migrations do
  Rake.migration_manager do |mgr, db|
    keys = db[mgr.migrations].columns.map { |key| key.to_s }
    keys = [:id, :commit_time, :name, :action, :status]
    puts "#{keys.map { |key| key.to_s }.join("\t")}"
    mgr.migration_history.each do |row, index|
      puts "#{row[:id]}\t#{row[:commit_time]}\t#{row[:name]}\t#{row[:action]}\t#{row[:status]}"
      #puts row.inspect
=begin
      line = ""
      keys.each do |key|
        if index == 0
          #keys = row.keys
          keys = mgr.migrations.columns
          puts keys.join("\t\t")
        end

        
        line << row[key] + "\t"
      end
      puts line
=end
    end
  end
end


namespace :migrations do

    desc "Create initial migration table"
    task :setup do
      Rake.migration_manager do |mgr|
        mgr.setup
      end
    end

    desc "Drop the migrations table - destructive action"
    task :teardown do
      Rake.migration_manager do |mgr|
        mgr.teardown
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