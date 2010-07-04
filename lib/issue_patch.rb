require_dependency 'issue'

# Patch Redmine's Issues dynamically to track due date - to ensure this isnt before all scheduled work.  

module IssuePlanningPatch
  def self.included(base)
    
    base.extend(ClassMethods)
    
    base.send(:include, InstanceMethods)

    base.class_eval do
      unloadable
      
      acts_as_audited( :except => [ :lock_version, :updated_on, :created_on, :id , :lft, :rgt, :root_id] )
        
 #     has_many :scheduled_issues, :dependent => :destroy
      has_many :scheduled_issues

      before_validation :adjust_due_date

    end

  end
  

  
  module InstanceMethods
    # Return the 'augmented' issue title; that is, the issue name, with
    # the immediate parent name pre-pended if available.

    def augmented_title
      if ( self.parent )
        return "#{ self.project.name }: #{self.parent.subject}-#{ self.subject }"
      end
      return "#{ self.project.name }: #{ self.subject }"
    end

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
  
  module ClassMethods
    # Class method - sort an array of tasks by the augmented title.
    # Since this isn't done by the database, it's slow.
    
    def sort_by_augmented_title( list )
      list.sort! { | x, y | x.augmented_title <=> y.augmented_title }
    end
    
  end
end

# Add module to Issue
Issue.send(:include, IssuePlanningPatch)