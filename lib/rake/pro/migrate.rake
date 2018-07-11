task :list do
  puts "arg == " + ARGV.inspect
  #puts "options == " + Rake.application.options
  #ARGV = ["-T"]
  Rake.application.run(["-T"])
  #Rake.application.handle_options(["-T"])
  #Rake.application.top_level
  #Rake.application.options.show_all_tasks = true
  #Rake.application.options.show_tasks = :tasks
  #Rake.application.options.show_task_pattern = /.*/
  #Rake.application.display_tasks_and_comments
  raise SystemExit
end

task :tasks do
  Rake.application.run(["-T"])
  raise SystemExit
end

task :t do
  Rake.application.run(["-T"])
  raise SystemExit
end

task :m do
  Rake.application.options.show_tasks = :migrations
  Rake.application.run(["-M"])
  raise SystemExit
end
  
  
desc "Reverse the specifed migration; ie. invoke the down migration block"
task :reverse do
  Rake.application.reverse = true
end
  
desc "Migrate up to latest migration"
task :migrate do
  Rake::Task["migrate:up"].invoke
end
  

def invoke_if_defined

end

namespace :migrate do

    desc "Migrate up to latest migration"
    task :up, [:count] do |t, args|
      begin
        if args.has_key?(:count)
          count = args[:count]
        else
          count = 0
        end

        if ARGV.length > 0
          arg = ARGV.shift

          if Rake::Task.task_defined?(arg)
            puts "!!!!!! task #{arg} is defined!!!!!"
            Rake::Task[arg].invoke
          elsif Rake::Task.task_defined?("#{arg}:latest")
            puts "!!!!!! task #{arg} ::: latest is defined!!!!!"
            Rake::Task["#{arg}:latest"].invoke
          end
        end



=begin
        ns = Rake.application.context.path_namespace
        if ns.nil?
          exit_needed = ARGV.length > 0
          ns = ARGV.shift if exit_needed
        end

        puts "--=  #{Rake.application.top_level_tasks}"
        puts "--=  #{Rake::Task.tasks}"
        puts "--=  #{Rake::Task.tasks[5].sources}"
        puts "--=  #{Rake::Task['latest'].sources}"


        if Rake::Task.task_defined?('latest')
          mig_target = 'latest'
        elsif Rake::Target.task_defined?("#{ns}:latest")
          mig_target = '#{ns}:latest'
        end

        puts "--=  #{Rake::Task.task_defined?('latest')}"

        #raise SystemExit if exit_needed
=end

=begin
        Rake::MigrationManager.instance.set_mode(:up, args[:count], ARGV.shift)
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
        if Rake::Task.task_defined?(mig_target)
          Rake::Task[mig_target].invoke
        else
          raise "Migration target not found."
        end
=end

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
        Rake::MigrationManager.instance.set_mode(:down)
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

    desc "Show latest migrations applied"
    task :latest do
      Rake.migration_manager do |mgr, db|
        mgr.latest_migrations.each do |name, history|
          #puts "Name:  #{name}    HISTORY:  #{history.inspect}"
        end
      end
    end

end