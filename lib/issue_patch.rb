require_dependency 'issue'

# Patch Redmine's Issues dynamically to track due date - to ensure this isnt before all scheduled work.  

module IssuePlanningPatch
  def self.included(base)
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

    # Same as typing in the class 
    base.class_eval do
      unloadable # Send unloadable so it will not be unloaded in development
      has_many :scheduled_issues
      before_validation :adjust_due_date
      
    end

  end
  
  module ClassMethods
    
  end
  
  module InstanceMethods

 private

    # Enforce rule that scheduled issues cannot be due prior to work being done
    # TODO: Setup parameter to enable / disable on a per-project setting
    def adjust_due_date
     
      last_scheduled = self.scheduled_issues.max { |a, b| a.date <=> b.date }
      unless last_scheduled.nil? || self.due_date >= last_scheduled.date
        self.due_date = last_scheduled.date
        @current_journal = Journal.new(:journalized => self, :user => User.current, :notes => "due date for issue changed by scheduling")
        @current_journal.save
      end
    end
  end    
end

# Add module to Issue
Issue.send(:include, IssuePlanningPatch)