class ScheduleDefault < ActiveRecord::Base

	belongs_to :user
	serialize :weekday_hours
	validates_uniqueness_of :user_id
  acts_as_audited( :except => [ :lock_version, :updated_at, :created_at, :id ] )

	def initialize
		super
		self.weekday_hours = [0,8.0,8.0,8.0,8.0,8.0,0]
	end
end
