require 'rake'
require 'yaml'
require 'etc'
require_relative './hashex'

module Rake
  class Application
    attr_accessor :cfg
    attr_accessor :scopes
    attr_accessor :active_dir

    class KeySpace
      def initialize
        @cfg_files = []
        @kvp_stack = []
        @kvp = {}
      end

      def [](key)
        @kvp[key]
      end

      def values()
        @kvp
      end

      def home()
        Etc.getpwuid.dir;
      end
  
      def root()
        Rake.original_dir
      end

      def rpath(*paths)
        return File.join(paths)
      end

      def push_scope scope
        (@scopes ||= []).push(scope)
      end

      def pop_scope
        @scopes.pop
      end

      def push_cfg cfg_file
        #puts "Loading cfg file:  #{cfg_file}..."
        cfg = YAML.load_file(cfg_file).symbolize_keys
        source = if (cfg.has_key?(:default))
                    cfg[:default]
                  elsif (cfg.has_key?(:source))
                    cfg[:source]
                  elsif (cfg.has_key?(:system))
                    cfg[:system]
                  elsif(cfg.has_key?(:target))
                    cfg[:target]
                  end

        push_scope(source.to_sym) if source
        @kvp_stack.push(cfg)
      end

      def pop_cfg
        @kvp_stack.pop
      end

      def load_once(cfg_file)
        unless @cfg_files.include?(cfg_file)
          if (File.file?(cfg_file))
            Rake.application.active_dir = File.dirname(cfg_file)
            push_cfg(cfg_file)
          end
          @cfg_files.push(cfg_file)
        end
      end

      def scope_siblings scope
        siblings = nil
        Rake.application.scopes.each { |scope_set|
          siblings = scope_set if scope_set.include?(scope)
        }
        siblings
      end
          
      def before_invoke task_details
        task_name = task_details[0]
        parts = task_name.split(':')
        push_scope(parts[0].to_sym) if parts.length == 1

        load_paths = parts.reduce([
            rpath(root, 'cfg.yml'),
            rpath(root, '.cfg.yml'),
            rpath(root, 'cfg-private.yml')
            rpath(root, '.cfg-private.yml')
            rpath(root, 'cfg-local.yml')
            rpath(root, '.cfg-local.yml')
          ]) { |paths, folder|
          paths.push(rpath(root, folder, 'cfg.yml'))
          paths.push(rpath(root, folder, '.cfg.yml'))
          paths.push(rpath(root, folder, 'cfg-private.yml'))
          paths.push(rpath(root, folder, '.cfg-private.yml'))
          paths.push(rpath(root, folder, 'cfg-local.yml'))
          paths.push(rpath(root, folder, '.cfg-local.yml'))
          paths
        }
        load_paths.push(rpath(home, '.cyborg.yml'))

        load_paths.each { |path|
          load_once(path)
        }

        # promote and prune the key space
        pruned = false
        pruned_stack = []
        @kvp_stack.each_with_index { |kvp, index| 
          @scopes.each_with_index { |scope, i2|
            kvp, didprune = kvp.promote_key(scope)
            siblings = scope_siblings(scope)
            kvp = kvp.prune_keys(scope_siblings(scope)) if siblings
            pruned |= (didprune && scope == task_name.to_sym)
          }
          pruned_stack.push(kvp)
        }

        # merge the kvp stack entries into a single map
        @kvp = pruned_stack.reduce({}) { |acc, kvp|
          acc.recursive_merge(kvp)
        }

        [task_name, pruned]
      end

      def after_invoke task_details
        task_name = task_details[0]
        parts = task_name.split(':')
        if parts.length > 1
          pop_scope
          pop_cfg
        end
      end

    end
  end

  module Intercept
    def invoke_task *args
      task_name, pruned = (Rake.application.cfg ||= Application::KeySpace.new).before_invoke(parse_task_string args.first)
      super if Rake::Task.task_defined?(task_name) || !pruned
      Rake.application.cfg.after_invoke(parse_task_string args.first)
    end
  end

end

Rake::Application.class_eval do
  prepend Rake::Intercept
end