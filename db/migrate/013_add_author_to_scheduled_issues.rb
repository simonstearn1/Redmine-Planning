class AddAuthorToScheduledIssues < ActiveRecord::Migration
# Probably something

  def self.up
    add_column :scheduled_issues, :author_id,  :integer
  end

  def self.down
    drop_column :scheduled_issues, :author_id
  end
end
