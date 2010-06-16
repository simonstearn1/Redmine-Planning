require_dependency 'issue'

# Patch Redmine's Issues dynamically to track due date - to ensure this isnt before all scheduled work.  

module IssuePlanningPatch
  def self.included(base)
    base.send(:include, InstanceMethods)

    base.class_eval do
      unloadable
 #     has_many :scheduled_issues, :dependent => :destroy

      before_validation :adjust_due_date

    end

  end
  

  
  module InstanceMethods

 private

    # Enforce rule that scheduled issues cannot be due prior to work being done
    # TODO: Setup parameter to enable / disable on a per-project setting
    def adjust_due_date
     
      last_scheduled = self.scheduled_issues.max { |a, b| a.date <=> b.date }
      unless last_scheduled.nil? || self.due_date >= last_scheduled.date
        self.due_date = last_scheduled.date
        a_journal = Journal.new(:journalized => self, :user => User.find_by_id(Setting.plugin_redmine_planning['user']), :notes => "Due date for issue changed by scheduling process. This indicates contention for a named resource across the issue planned period and may require manual resolution.")
        a_journal.save
      end
    end
  end    
end

# Add module to Issue
Issue.send(:include, IssuePlanningPatch)