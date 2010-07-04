class CreateTimesheetRows < ActiveRecord::Migration
# Probably something

  def self.up
    create_table :timesheet_rows do | t |

      t.belongs_to :timesheet, :null => false
      t.belongs_to :issue,     :null => false

      t.timestamps

    end
  end

  def self.down
    drop_table :timesheet_rows
  end
end