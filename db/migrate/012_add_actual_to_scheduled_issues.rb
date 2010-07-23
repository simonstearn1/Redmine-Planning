class AddActualToScheduledIssues < ActiveRecord::Migration
# Probably something

  def self.up
    add_column :scheduled_issues, :actual,  :boolean
  end

  def self.down
    drop_column :scheduled_issues, :actual
  end
end
