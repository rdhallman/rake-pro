

namespace :migrate do

    desc "Migrate up to latest migration"
    task :up do
      ns = "#{File.basename(Rake.application.active_dir)}"
      #namespace ns do
        load "#{Rake.application.active_dir}/migrations.rake"
      #end
      Rake::Task["#{ns}:latest"].invoke
    end
  
    desc "Migrate down to specified migration"
    task :down do
      ns = "#{File.basename(Rake.application.active_dir)}"
      Rake.application.reverse = true
      #namespace ns do
        load "#{Rake.application.active_dir}/migrations.rake"
      #end
      Rake::Task["#{ns}:latest"].invoke(0)
    end
  
end