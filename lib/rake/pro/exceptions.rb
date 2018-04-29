module Rake

    class RakeTaskError < StandardError
        attr_reader :definite_cause
        attr_reader :possible_cause
        def initialize(message, definite_cause = nil, possible_cause = nil, recursion_lock = false)
            super(message)
            @definite_cause = definite_cause
            @possible_cause = possible_cause
            if (definite_cause.nil? && possible_cause.nil? && !recursion_lock)
                Rake.application.scopes.each { |scope_set|
                    scope_selected = nil
                    Rake.application.context.active_scopes.each { |active_scope|
                        if scope_set.include?(active_scope)
                            scope_selected = active_scope
                        end
                    }
                    if (scope_selected.nil?)
                        @possible_cause = RakeTaskError.new("No target environment specified.  You may need to prefix task '#{Rake.application.current_task}' with one of [#{scope_set.map { |item| item.to_s }.join(', ')}].", nil, nil, true)
                        break
                    end
                }
            end
        end
        def message
            pm = super
            if !possible_cause.nil?
                "#{pm}\nPossibly Caused By:\n => #{possible_cause.message}"
            elsif !definite_cause.nil?
                "#{pm}\nCaused By:\n => #{definite_cause.message}"
            else
                pm
            end
        end
    end

end
