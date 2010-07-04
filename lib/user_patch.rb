require_dependency 'user'

# Patch Redmine's User dynamically to enable audit records to be useful..

module UserPlanningPatch
  def self.included(base)
    base.send(:include, InstanceMethods)

    base.class_eval do
      unloadable

    end

  end
  

  
  module InstanceMethods

    # TODO: Figure out how to get acts_as_audited to record user details properly..

    def auditor_name
	    return User.current.firstname + " " + User.current.lastname     
    end
  end    
end

# Add module to Issue
User.send(:include, UserPlanningPatch)
