class CreateScheduledIssues < ActiveRecord::Migration
  def self.up
    create_table :scheduled_issues do |t|
      t.column :issue_id, :integer, :default => 0, :null => false
      t.column :user_id, :integer, :default => 0, :null => false
      t.column :project_id, :integer, :default => 0, :null => false
      t.column :scheduled_hours, :float, :null => false
      t.column :date, :date, :null => false
      t.timestamps :null => false
    end
    add_index "scheduled_issues", ["issue_id"], :name => "scheduled_issues_issue_id"
    add_index "scheduled_issues", ["user_id"], :name => "scheduled_issues_user_id"
    add_index "scheduled_issues", ["project_id"], :name => "scheduled_issues_project_id"
  end

  def self.down
    drop_table :scheduled_issues
  end
end