require_dependency 'time_entry'
require_dependency 'schedule_entry'
require_dependency 'scheduled_issue'


# Patch Redmine's time_entries to associate with timesheet_rows etc.  

module TimeEntryPlanningPatch
  def self.included(base)
    base.send(:include, InstanceMethods)

    base.class_eval do
      unloadable

      belongs_to( :timesheet_row )
  
      # Make sure the data is sane.
    
      validates_numericality_of(
        :hours,
        :less_than_or_equal_to    => 24,
        :greater_than_or_equal_to => 0
      )

      validates_inclusion_of(
        :day_number,
        :in => 0..6 # 0 = Sun, 6 = Sat, as per Date::DAYNAMES
      )
  
      # Set a Date indicating the start of the day which the time entry
      # represents whenever the time entry is saved. This helps a lot with
      # reports, since a report may have to query large numbers of packets
      # by date - we can make the database do that work. It isn't always
      # faster than doing that locally, surprisingly, but the code is much
      # more legible and maintainable.

      before_validation( :set_date )
      after_save ( :fudge_scheduled_issues )
    
    end


  end
  

  
  module InstanceMethods

  def set_date
    if ( self.timesheet_row and self.timesheet_row.timesheet )
      new_date = self.timesheet_row.timesheet.date_for( self.day_number, true )
    else
      new_date = Time.current
    end
    self.tyear = new_date.year unless self.tyear
    self.tweek = new_date.cweek unless self.tweek
    self.tmonth = new_date.month unless self.tmonth
    self.spent_on = new_date unless self.spent_on
  end

  # Find time entrys in rows related to the given issue ID, held in timesheets
  # owned by the given user ID, between the Dates in the given range. The range
  # MUST be inclusive, for reasons discussed below. The results are sorted by
  # time entry date, descending.
  #
  # The issue and user IDs are optional. All issues and/or users will be
  # included in the count if the given issue and/or user ID is nil. The date
  # range is mandatory.
  #
  # IMPORTANT - at the time of writing, Rails 2.1 (and earlier versions) will
  # build a BETWEEN statement in SQL with the given range. Although SQL says
  # that the values on either side of BETWEEN should be treated as inclusive,
  # i.e. a Ruby "a..b" kind of range, some databases may treat the right side
  # as exclusive; PostgreSQL is fine, but if in doubt you need to go to the
  # Rails console and run a test. For example, issue something like this:
  #
  #   User.all.collect { |x| x.id }.sort
  #
  # Note any two consecutive IDs listed - e.g. "[1, 2, ...]" - 1 and 2 will do.
  # Use these as part of range conditions for a find:
  #
  #   User.find(:all, :conditions => { :id => 1..2 } )
  #
  # Assuming you actually *have* users with IDs 1 and 2, then both should be
  # returned. If you only get one, BETWEEN isn't working and you need to use
  # another database or change the function below to do something else (e.g.
  # hard-code a condition using ">=" and "<=" if your database supports those
  # operators).
  #
  # A final twist is that Rails' "to_s( :db )" operator assumes all ranges are
  # inclusive and generates SQL accordingly. There's a ticket for this in the
  # case of dates:
  #
  #   http://dev.rubyonrails.org/ticket/8549
  #
  # ...but actually Rails seems to do this for any kind of range - e.g. change
  # the "1..2" to "1...2" in the User find above and note that the generated
  # SQL is the same. We'd expect it to only look for a user with id '1' (or
  # between 1 and 1) in this case.
  #
  # As a result, ensure you only ever pass inclusive ranges to this function.

  def self.find_by_issue_user_and_range( range, issue_id = nil, user_id = nil )
    return TimeEntry.find_by_issue_user_range_and_committed(
      range,
      nil,
      issue_id,
      user_id
    )
  end

  # As find_by_issue_user_and_range, but only counts time entrys belonging to
  # committed timesheets.

  def self.find_committed_by_issue_user_and_range( range, issue_id = nil, user_id = nil )
    # TODO: Use with_scope? Can we cope with the 'nil' case cleanly?

    return TimeEntry.find_by_issue_user_range_and_committed(
      range,
      true,
      issue_id,
      user_id
    )
  end

  # As find_by_issue_user_and_range, but only counts time entrys belonging to
  # timesheets which are not committed.

  def self.find_not_committed_by_issue_user_and_range( range, issue_id = nil, user_id = nil )
    return TimeEntry.find_by_issue_user_range_and_committed(
      range,
      false,
      issue_id,
      user_id
    )
  end

  # Support find_by_issue_user_and_range, find_committed_by_issue_user_and_range
  # and find_not_committed_by_issue_user_and_range. An extra mandatory second
  # parameter must be set to 'true' to only include time entrys from committed
  # timesheets, 'false' for not committed timesheets and 'nil' for either.

  def self.find_by_issue_user_range_and_committed( range, committed, issue_id = nil, user_id = nil )

    # The 'include' part needs some explanation. We include the timesheet rows,
    # a second order association, because the rows lead to issues and timesheets.
    # We need to eager-load issues because the search is limited by issue ID. We
    # need to eager-load timesheets because they lead to users and the search is
    # also limited by user ID. Rails supports eager-loading of third and deeper
    # order associations through passing hashes in as the value to ":include".
    # Each key's value is the next level of association. So :timesheet_row is
    # at the second order, pointing to an array giving two third order things;
    # :issue and, itself a hash key, :timesheet; since it is a hash key,
    # :timesheet's value is the second-order association of timesheets, or the
    # fourth-order association of the time entrys - :user.
    #
    # Ultimately eager-loading means LEFT OUTER JOIN in SQL statements. Due to
    # the way that ActiveRecord assembles the query, using :include rather than
    # :joins with some hard-coded SQL makes for a very verbose query in the
    # "find" case; it's nice and compact for "sum", though. In any event, at
    # least it is a query generated entirely through the database adapter, so
    # it stands a fighting chance of working fine on multiple database types.

    conditions = { :date => range }
    conditions[ 'issues.id' ] = issue_id unless issue_id.nil?
    conditions[ 'users.id' ] = user_id unless user_id.nil?
    conditions[ 'timesheets.committed' ] = committed unless committed.nil?

    return TimeEntry.all(
      :include     => { :timesheet_row => [ :issue, { :timesheet => :user } ] },
      :conditions  => conditions,
      :order       => 'date DESC'
    )

  end

  # Return the earliest (first by date) time entry, either across all issues
  # (pass nothing) or for the given issues specified as an array of issue IDs.
  # The time entry may be in either a not committed or committed timesheet.

  def self.find_earliest_by_issues( issue_ids = [] )
    return TimeEntry.find_first_by_issues_and_order( issue_ids, 'date ASC' )
  end

  # Return the latest (last by date) time entry, either across all issues
  # (pass nothing) or for the given issues specified as an array of issue IDs.
  # The time entry may be in either a not committed or committed timesheet.

  def self.find_latest_by_issues( issue_ids = [] )
    return TimeEntry.find_first_by_issues_and_order( issue_ids, 'date DESC' )
  end

  # Support find_earliest_by_issues and find_latest_by_issues. Pass an array
  # of issue IDs and a sort order (SQL fragment, e.g. "date ASC").

  def self.find_first_by_issues_and_order( issue_ids, order )
    if ( issue_ids.empty? )
      return TimeEntry.first(
        :order      => order,
        :conditions => 'hours > 0.0'
      )
    else
      return TimeEntry.first(
        :include    => [ :timesheet_row ],
        :conditions => [ 'hours > 0.0 AND timesheet_rows.issue_id IN (?)', issue_ids ],
        :order      => order
      )
    end
  end

  # fudge_scheduled_issues
  #
  # Correct schedule based on actuals entered so that historic review of schedule is accurate
  #
  def fudge_scheduled_issues
    
    
    # begin a transaction
    ScheduledIssue.transaction do
      todays_actuals = []
      # find scheduled_issues for same day / user and delete them unless actual
      todays_scheduled_issues = ScheduledIssue.find(:all, :conditions => ['date = ? AND user_id = ?', self.spent_on, self.user_id])
      todays_scheduled_issues.each do | scheduled_issue |
        if scheduled_issue.issue_id == self.issue_id && scheduled_issue.project_id == self.project_id && scheduled_issue.scheduled_hours == self.hours
            scheduled_issue.actual = 1
            scheduled_issue.save
            return
        end
        if scheduled_issue.actual == 1
          todays_actuals << scheduled_issue
        else
          scheduled_issue.destroy 
        end
      end
      
      # create new scheduled_issue representing actual work done
      new_actual = ScheduledIssue.new
      new_actual.issue_id = self.issue_id
      new_actual.project_id = self.project_id
      new_actual.user_id = self.user_id
      new_actual.scheduled_hours = self.hours
      new_actual.date = self.spent_on
      new_actual.actual = 1
      new_actual.save
      todays_actuals << new_actual
      
      # Sum actual hours for the day
      hours = 0
      todays_actuals.each do |actual|
        hours += actual.scheduled_hours if actual.project_id == self.project_id
      end
      
      # fixup or create schedule_entries for this day
      schedule_entries = ScheduleEntry.find(:all, :conditions => ['user_id = ? AND date = ? AND project_id = ?', self.user_id, self.spent_on, self.project_id])
      schedule_entry = schedule_entries.shift unless schedule_entries.nil?
      if schedule_entry.nil?
        schedule_entry = ScheduleEntry.new
      end
      unless schedule_entries.nil? || schedule_entries.empty?
        schedule_entries.each do | entry |
          entry.destroy
        end
      end
      
      schedule_entry.hours = hours
      schedule_entry.user_id = self.user_id
      schedule_entry.project_id = self.project_id
      schedule_entry.date = self.spent_on
      schedule_entry.save
      
    
    # commit
    end
    
  end

  end    
end

# Add module to TimeEntry class
TimeEntry.send(:include, TimeEntryPlanningPatch)