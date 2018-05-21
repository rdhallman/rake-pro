
module Rake::Pro

    module DSL
  
      def migration(*args, &block) # :doc:
        task = Rake::Task.define_task(*args, &block)
        task.flag_as_migration
        task
      end
  
    end
  end
  
  # Extend the main object with the DSL commands. This allows top-level
  # calls to task, etc. to work from a Rakefile without polluting the
  # object inheritance tree.
  self.extend Rake::Pro::DSL
  