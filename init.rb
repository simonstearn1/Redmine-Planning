# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 

require 'redmine'
require 'calendar_date_select'

require_dependency 'schedule_compatibility'
require_dependency 'issue_schedule_destroy_dependency'
require_dependency 'issue_patch'
require_dependency 'user_patch'
require_dependency 'time_entries_patch'
require_dependency 'lib_sections'
require_dependency 'lib_report'
require_dependency 'extend_acts_as_audited_model'
require_dependency 'extend_numeric_class_with_precision_method'


Redmine::Plugin.register :redmine_planning do
	name 'Redmine Planning Plugin'
	author 'Simon Stearn - based on bits from loader and Brad Beatties schedules plugin'
	description 'A bunch of (perhaps) useful stuff to allow loading of xml project plans and scheduling/timesheets against these'
	version '0.0.4'
  
	project_module :planning_module do
		permission :view_schedules,  {:schedules => [:index]}, :require => :member
		permission :edit_own_schedules, {:schedules => [:edit, :user, :project]}, :require => :member
		permission :edit_all_schedules, {}, :require => :member
		permission :import_issues_from_xml, :loader => [:new, :create], :require => :member
		permission :timesheets, {:timesheet => [:index]}
	end

	requires_redmine :version_or_higher => '0.9.4'

	settings :default => { 'tracker' => -1, 'category' => -1 }, :partial => 'settings/redmine_planning_settings'

	menu :project_menu, :loader, { :controller => 'loader', :action => 'new' }, :caption => 'Import Issues', :after => :new_issue, :param => :project_id

	menu :top_menu, :my_schedules, { :controller => 'schedules', :action => 'my_index', :project_id => nil, :user_id => nil }, :after => :my_page, :caption => :label_schedules_my_index, :if => Proc.new { SchedulesController.visible_projects.size > 0 }

	menu :top_menu, :schedules, { :controller => 'schedules', :action => 'index', :project_id => nil, :user_id => nil }, :after => :home, :caption => :label_bulk_schedules_index, :if => Proc.new { SchedulesController.visible_projects.size > 0 }

#  menu :top_menu, :timesheets, { :controller => 'timesheets', :action => 'index', :project_id => nil, :user_id => nil }, :after => :projects, :caption => 'Timesheets', :if => Proc.new { TimesheetsController.visible }
	menu :top_menu, :timesheets, { :controller => 'timesheets', :action => 'index'}, :after => :projects, :caption => 'Timesheets', :if => Proc.new { User.current.allowed_to?(:timesheet, nil, :global => true) }
	menu :project_menu, :schedules, { :controller => 'schedules', :action => 'index' }, :caption => :label_schedules_index, :after => :activity, :param => :project_id

end
