
class TimesheetRow < ActiveRecord::Base

  # Timesheets are made up of TimesheetRows, where each row
  # corresponds to a particular issue. Within that row, each
  # day of activity for that issue is represented by a
  # single TimeEntry.

  belongs_to( :timesheet )
  belongs_to( :issue      )

  has_many( :time_entries, { :dependent => :destroy } )

  acts_as_list( { :scope => :timesheet } )

  # Security controls - *no* mass assignments, please.

  attr_accessible()

  # Make sure the data is sane.

  validates_presence_of( :timesheet_id, :issue_id )
  validate( :issue_is_active_and_permitted )

  def issue_is_active_and_permitted()


  end

  # Create Work Packet objects after saving, if not already
  # present. This must be done after because the ID of this
  # object instance is needed for the association.

  after_create :add_time_entries

  # Day number order within a row - Monday to Sunday,

  DAY_ORDER = [ 1, 2, 3, 4, 5, 6, 0 ]
  FIRST_DAY = DAY_ORDER[ 0 ]
  LAST_DAY  = DAY_ORDER[ 6 ]
  DAY_NAMES = Date::DAYNAMES

  # Return the sum of hours in work packets on this row.

  def row_sum()
    return self.time_entries.sum( :hours )
  end

private

  def add_time_entries
    
    default_activity = []
    activity_list = self.issue.project.activities
    activity_list.each do | activity |
      if activity.is_default?
        default_activity = activity
      end
    end
    
    DAY_ORDER.each do | day |
      time_entry               = TimeEntry.new
      time_entry.project_id    = self.issue.project.id || 0
      time_entry.activity_id   = default_activity.id || 0
      time_entry.issue_id      = self.issue.id || 0
      time_entry.user_id       = self.timesheet.user_id
      time_entry.day_number    = day
      time_entry.hours         = 0
      time_entry.timesheet_row = self
      time_entry.save!
    end
  end
end
