require 'redmine'
require 'calendar_date_select'

require_dependency 'schedule_compatibility'
require_dependency 'issue_schedule_destroy_dependency'

Redmine::Plugin.register :redmine_planning do
	name 'Redmine Planning Plugin'
	author 'Simon Stearn - based on bits from loader and Brad Beatties schedules plugin'
	description 'A bunch of (perhaps) useful stuff to allow loading of xml project plans and scheduling against these'
	version '0.0.0.1'
  
	project_module :planning_module do
		permission :view_schedules,  {:schedules => [:index]}, :require => :member
		permission :edit_own_schedules, {:schedules => [:edit, :user, :project]}, :require => :member
		permission :edit_all_schedules, {}, :require => :member
    permission :import_issues_from_xml, :loader => [:new, :create], :require => :member
	end

	requires_redmine :version_or_higher => '0.1'

	settings :default => { 'tracker' => -1, 'category' => -1 }, :partial => 'settings/redmine_planning_settings'

	
	menu :project_menu, :loader, { :controller => 'loader', :action => 'new' },    :caption => 'Import Issues', :after => :new_issue, :param => :project_id

	menu :top_menu, :my_schedules, { :controller => 'schedules', :action => 'my_index', :project_id => nil, :user_id => nil }, :after => :my_page, :caption => :label_schedules_my_index, :if => Proc.new { SchedulesController.visible_projects.size > 0 }

	menu :top_menu, :schedules, { :controller => 'schedules', :action => 'index', :project_id => nil, :user_id => nil }, :before => :projects, :caption => :label_bulk_schedules_index, :if => Proc.new { SchedulesController.visible_projects.size > 0 }

	menu :project_menu, :schedules, { :controller => 'schedules', :action => 'index' }, :caption => :label_schedules_index, :after => :activity, :param => :project_id

end
