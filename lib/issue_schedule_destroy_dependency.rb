require_dependency 'issue'

# Adds the schedule issue entries to the Issue model
module IssueSchedulePatch
  def self.included(base) # :nodoc:
    # Same as typing in the class
    base.class_eval do
      unloadable # Send unloadable so it will not be unloaded in development
      has_many :schedule_registry, :dependent => :destroy, :class_name => 'ScheduledIssue', :foreign_key => 'issue_id'
    end
  end
end

# Add module to Version
Issue.send(:include, IssueSchedulePatch)