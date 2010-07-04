class ModifyTimeEntries < ActiveRecord::Migration
# Probably something

  def self.up
    add_column :time_entries, :day_number,  :integer
  end

  def self.down
    drop_column :time_entries, :day_number
  end
end