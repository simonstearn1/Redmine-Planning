class SchedulesController < ApplicationController
  unloadable
  
  CRAZY_DAY = 5832 # approx hours in venus day..
  
  # ############################################################################
  # Initialization
  # ############################################################################
  
  # Filters
  before_filter :require_login
  before_filter :find_users_and_projects, :only => [:index, :edit, :users, :projects, :fill]
  before_filter :find_optional_project, :only => [:report, :details]
  before_filter :find_project_by_version, :only => [:estimate]
  before_filter :save_entries, :only => [:edit]
  before_filter :save_default, :only => [:default]
  before_filter :fill_entries, :only => [:fill]



  # Included helpers
  include SchedulesHelper
  include ValidatedFieldsHelper
  include SortHelper
  helper :sort
  helper :validated_fields
  
  @@remote = false;
  
  def SchedulesController.fetch_default_status_id
    default_status = IssueStatus.find_by_is_default(1);
    if(default_status.nil?)
      default_status = IssueStatus.find(:first);
    end
    
    return default_status.id;
  end
  
  
  # ############################################################################
  # Class methods
  # ############################################################################
  
  
  # Return a list of the projects the user has permission to view schedules in
  def self.visible_projects
    Project.find(:all, :conditions => Project.allowed_to_condition(User.current, :view_schedules))
  end
  
  
  # Return a list of the users in the given projects which have permission to
  # view schedules
  def self.visible_users(members)
    members.select {|m| m.roles.detect {|role| role.allowed_to?(:view_schedules)}}.collect {|m| m.user}.uniq.sort
  rescue
    members.select {|m| m.role.allowed_to?(:view_schedules)}.collect {|m| m.user}.uniq.sort
  end
  
  
  # ############################################################################
  # Public actions
  # ############################################################################
  
  
  # View the schedule for the given week/user/project
  def index
    unless @users.empty?
      @entries = get_entries
      @availabilities = get_availabilities
      render :action => 'index', :layout => !request.xhr?
    end
  end
  
  #
  def projects
    @focus = "projects"
    index
  end
  
  #
  def users
    @focus = "users"
    index
  end
  
  
  # View the schedule for the given week for the current user
  def my_index
    params[:user_id] = User.current.id
    find_users_and_projects
    index
  end
  
  
  # Edit the current user's default availability
  def default
    @schedule_default = ScheduleDefault.find_by_user_id(@user)
    @schedule_default ||= ScheduleDefault.new
    @schedule_default.weekday_hours ||= [0,8,8,8,8,8,0]
    @schedule_default.user_id = @user.id
    @calendar = Redmine::Helpers::Calendar.new(Date.today, current_language, :week)
  end
  
  
  # Edit the schedule for the given week/user/project
  def edit
    @entries = get_entries
    @closed_entries = get_closed_entries
    
    render :layout => !request.xhr?
  end
  
  #
  #
  # # #
  def new_issue
    @issue = nil
  end
  
  #
  # When float number in textfield has decimal comma
  # instead of decimal dot, replace it with dot
  #
  def removeDecimalComma(number)
    return number.gsub(/,/, ".")
  end
  
  #
  #
  # # #
  def save_quick_issue
    scheduled_hours = params[:scheduled_hours].nil? ? 0 : params[:scheduled_hours].to_f;
    scheduled_hours += (params[:scheduled_minutes].to_f/100) unless params[:scheduled_minutes].nil?
    assigned_to = params[:quick_issue][:assigned_to].to_i != -1 ? 
    User.find(params[:quick_issue][:assigned_to].to_i) : nil;
    project = Project.find(params[:project_id].to_i);
    @date = params[:date]
    
    issue = Issue.create(
      :project => project,
      :subject => params[:quick_issue][:subject],
      :assigned_to => assigned_to,
      :author => User.current,
      :description => params[:quick_issue][:description],
      :tracker_id => params[:quick_issue][:tracker].to_i,
      :status_id => params[:quick_issue][:status].to_i,
      :start_date => params[:date],
      :estimated_hours => removeDecimalComma(params[:quick_issue][:estimated]).to_f,
      :due_date => nil);
    
    issue.fixed_version_id = params[:quick_issue][:sprint].to_i;
    
    issue.save
    
    if(scheduled_hours != 0)
      # Create and save scheduled_isuse entry
      scheduled_issue_entry = ScheduledIssue.create(
        :scheduled_hours => scheduled_hours,
        :user_id => assigned_to.id, :date => params[:date], :issue_id => issue.id,
        :project_id => project.id );
      scheduled_issue_entry.save;
      
      updateScheduleEntryHours(assigned_to.id, project.id, params[:date], scheduled_hours)
    end
    
    @@remote = true;
    render :text => scheduled_tickets and return;
  end
  
  #
  #
  # # #
  def SchedulesController.userHours(user_id, date)
    available_hours = ScheduleDefault.find_by_user_id(user_id);
    
    return available_hours.nil? ? 0 : available_hours.weekday_hours[Date.parse(date).wday];
  end
  
  #
  # Retrieve scheduled hours saved in schedule entry table
  #
  def schedule_entry_hours(user_id, project_id, date)
    schedule_entry = ScheduleEntry.find_by_user_id_and_project_id_and_date(user_id, project_id, date);
    
    if(!schedule_entry.nil?)
      return schedule_entry.hours;
    else
      return scheduled_hours_f(user_id, project_id, date);
    end
  end
  
  def r_schedule_entry_hours
    render :text => schedule_entry_hours(params[:user_id], params[:project_id],
    params[:date]).to_f.to_s
  end
  
  def not_empty_hours(user_id, project_id, date)
    issues = ScheduledIssue.all(:conditions => ["user_id = ? AND project_id = ?
        AND date = ? AND issue_id != 0", user_id, project_id, date])
    
    if(issues.nil?)
      hours = 0;
    else
      hours = issues.sum(&:scheduled_hours);
    end
    
    return hours;
  end
  
  def scheduled_hours_f(user_id, project_id, date)
    issues = ScheduledIssue.find_all_by_user_id_and_project_id_and_date(user_id, project_id, date);
    
    if(!issues.nil? && !issues.empty?)
      hours = issues.sum(&:scheduled_hours);
    else
      hours = 0;
    end
    
    return hours;
  end
  
  #
  #
  #
  def scheduled_hours
    render :text => scheduled_hours_f(params[:user_id], params[:project_id],
    params[:date]).to_s
  end
  
  #
  #
  # # #
  def SchedulesController.left_hours(user_id, date)
    scheduledIssues = ScheduledIssue.all(:conditions => ["user_id = ? AND date = ?", user_id, date])
    
    hours = 0
    if(!scheduledIssues.nil? && !scheduledIssues.empty?)
      scheduledIssues.each do |issue|
        if(!issue.nil?)
          hours += issue.scheduled_hours
        end
      end
    end
    
    return SchedulesController.userHours(user_id, date) - hours
  end
  
  #
  # Compute time spent by given user working on the issue
  #
  # @user_id ID of user @issue_id ID of issue
  #
  # # #
  def spentTime(user_id, issue_id)
    entries = TimeEntry.all(:conditions => ["issue_id = ? AND user_id = ?", issue_id, user_id ])
    sum = 0
    
    entries.each { |entry| sum += entry.hours; }
    
    return sum
  end
  
  #
  # Save scheduled issues for user/project/date
  #
  # # # #
  def save_scheduled_issues
    # hours scheduled for each issue
    hours = params[:hours_to_schedule];
    #minutes scheduled for each issue
    minutes = params[:minutes_to_schedule];
    # id of the user
    user_id = params[:user_id];
    # date in which to save
    date = params[:dateP];
    # issue ids
    issueIds = params[:issues];
    project_id = params[:project_id];
    sum = 0;
    
    # unite hours and minutes hash tables
    # updating hours hash table with minutes
    if !hours.nil?
      hours.each_key do |key|
        hours[key] = (hours[key].to_i + minutes[key].to_f/100).to_s unless minutes[key].to_i == 0
      end
    end
    
    ActiveRecord::Base.transaction do
      hours.each do |key, value|
        issue = Issue.find_by_id(issueIds[key].to_i);
        if(value.to_f != 0)
          sched_issue = ScheduledIssue.first(:conditions => ["issue_id = ? AND date = ?",
          issue.id, date]);
          if(sched_issue.nil?)
            sched_issue = ScheduledIssue.create(:scheduled_hours => value.to_f,
              :user_id => user_id, :date => date, :issue_id => issue.id,
              :project_id => issue.project.id);
          else
            sched_issue.scheduled_hours = value.to_f;
          end
          
          issue.assigned_to = User.find(user_id);
          issue.save;
          sum += value.to_f;
          sched_issue.save;
        else
          ScheduledIssue.destroy_all(["issue_id = ? AND date = ? AND user_id = ?", issue.id, date, user_id]);
        end
      end if !hours.nil?
      
      emptyHours = ScheduledIssue.emptyHours(user_id, project_id, date);
      if(emptyHours.nil?)
        if(params[:empty_hours].to_f != 0)
          emptyHours = ScheduledIssue.create(:user_id => user_id, :project_id => project_id,
            :date => date, :scheduled_hours => params[:empty_hours]);
          emptyHours.save;
        end
      else
        if(params[:empty_hours].to_f != 0)
          emptyHours.update_attribute(:scheduled_hours, params[:empty_hours]);
          emptyHours.save;
        else
          emptyHours.destroy;
        end
      end
    end
    
    sum += params[:empty_hours].to_f
    
    updateScheduleEntryHours(user_id, project_id, date, sum)
    
    render :nothing => true;
  end
  
  #
  # Used to delete database record of empty hours
  #
  def delete_empty_hours
    ScheduledIssue.delete("issue_id = 0 AND user_id=#{params[:user_id]} AND project_id = #{params[:project_id]} AND date='#{params[:date]}'")
    render :nothing => true
  end
  
  #
  #
  # # # #
  def scheduled_issues_for_project
    user_id = params[:user_id];
    
    if !user_id.nil?
      issues = ScheduledIssue.find_by_all(user_id, params[:project_id], params[:date]);
    end
    render :partial => 'scheduled_issues', :locals => { :scheduled_issues => issues }
  end
  
  #
  #
  # # # #
  def retrieveIssues(user_id, project_id, date)
    if(!user_id.nil? && !project_id.nil? && !date.nil?)
      #
      # get Tracker from settings
      default_tracker_id = Setting.plugin_redmine_planning['tracker'].to_s
      
      allIssues = Issue.all(:conditions => ["issues.project_id = :pid AND
        issue_statuses.is_closed = 0 AND trackers.id = " + default_tracker_id,
      { :pid => project_id, :uid => user_id}],
        :joins => "LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id LEFT JOIN trackers on issues.tracker_id = trackers.id");
      
      todaysScheduledIssues = ScheduledIssue.all(:conditions => ["user_id = ? AND date = ? AND project_id = ?", user_id, date, project_id]);
      
      notScheduledIssues = Set.new
      allIssues.each do |issue|
        sched_issue = ScheduledIssue.first(:conditions => ["issue_id = ? AND date = ?", issue.id, date]);
        
        if(sched_issue.nil?)
          notScheduledIssues << issue;
        end
      end
      
      emptyHours = 0;
      
      scheduledIssues = Array.new
      todaysScheduledIssues.each do |schedIssue|
        if(schedIssue.issue_id != 0)
          issue = Issue.find(schedIssue.issue_id);
          if(!issue.nil?)
            scheduledIssues << issue;
          end
        else
          emptyHours = schedIssue;
        end
      end
      
      unassignedIssues = Issue.all(:conditions => ["issues.assigned_to_id IS NULL AND issues.project_id = ? AND issue_statuses.is_closed = 0", project_id], :joins => "LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id");
      
      retArray = Hash.new;
      retArray['scheduledIssues'] = scheduledIssues;
      retArray['notScheduledIssues'] = notScheduledIssues;
      retArray['unassignedIssues'] = unassignedIssues;
      retArray['emptyHours'] = emptyHours;
      
      return retArray;
    else
      return nil;
    end
  end
  
  #
  # Fetch unassigned issues in given project
  #
  def fetchUnassignedIssues
    @i = params[:i].nil? ? 1 : params[:i].to_i;
    issues = Issue.all(:conditions => ["issues.assigned_to_id IS NULL
          AND issues.project_id = ? AND issue_statuses.is_closed = 0", params[:project_id]],
      :joins => "LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id");
    
    render :partial => 'scheduled_issues_table', :locals => { :issues => issues,
      :scheduled => false };
  end
  
  #
  # Fetch issues assigned to every member in given project
  #
  def fetchAllMembersIssues
    @i = params[:i].nil? ? 1 : params[:i].to_i;
    issues = Issue.all(:conditions => ["issues.assigned_to_id <> ? AND issues.project_id = ? AND issue_statuses.is_closed = 0", params[:user_id], params[:project_id]], :joins => "LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id");
    
    render :partial => 'scheduled_issues_table', :locals => { :issues => issues,
      :scheduled => false };
  end
  
  #
  # Fetch issues assigned to selected members in given project
  #
  def fetchMemberIssues
    @i = params[:i].to_i;
    issues = nil;
    
    if(!params[:members_ids].nil?)
      issues = Issue.all(:conditions => ["issues.assigned_to_id in (?)
        AND issues.assigned_to_id <> ? AND issues.project_id = ?
        AND issue_statuses.is_closed = 0",
      params[:members_ids], params[:user_id], params[:project_id]],
        :joins => "LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id");
    end
    
    render :partial => 'scheduled_issues_table', :locals => { :issues => issues,
      :scheduled => false }
  end
  
  #
  # Change schedule entry for given day/user/project given number of hours
  #
  def updateScheduleEntryHours(user_id, project_id, date, hours)
    scheduleEntry = ScheduleEntry.find_by_user_id_and_project_id_and_date(
                                                                          user_id, project_id, date);
    
    if(scheduleEntry.nil?)
      scheduleEntry = ScheduleEntry.create(:project => Project.find_by_id(project_id.to_i),
        :user => User.find_by_id(user_id.to_i), :date => date, :hours => hours.to_f)
      scheduleEntry.save;
      
      if(scheduleEntry.hours == 0)
        scheduleEntry.destroy;
      end
    else
      if(hours.to_f > 0)
        scheduleEntry.update_attribute(:hours, hours.to_f);
        scheduleEntry.save;
      else
        scheduleEntry.destroy
      end
    end
  end
  
  #
  #
  #
  def render_quick_issue
    project = Project.find(params[:project_id]);
    @issue = Issue.new;
    @default_status = IssueStatus.default;
    @trackers = project.trackers;
    @sprints = Version.all(:conditions => ["project_id = ?", params[:project_id]]);
    @assigned_to = project.members.collect(&:user);
    @available_statuses = Hash.new
    @first = nil;
    
    @trackers.each do |tracker|
      @first = tracker.name if @first.nil?
      @available_statuses[tracker.name] = ([@default_status] + Workflow.find(:all, :include => :new_status,
          :conditions => { :role_id => User.current.roles_for_project(project).collect(&:id),
            :old_status_id => @default_status.id, :tracker_id => tracker.id }).collect(&:new_status).compact).uniq.sort
    end
    render :partial => 'quick_issue', :locals => { :user_id => params[:user_id] }
  end
  
  #
  #
  #
  def updateEmptyHours
    date = params[:date];
    user_id = params[:user_id];
    project_id = params[:project_id];
    hours = params[:hours].to_f;
    
    if(!hours.nil? && !date.nil? && !user_id.nil? && !project_id.nil?)
      emptyHours = ScheduledIssue.first(:conditions => ["user_id = ? AND date = ?
        AND project_id = ? AND (issue_id IS NULL OR issue_id = 0)", user_id, date, project_id]);
      
      if(emptyHours.nil?)
        if(hours > 0)
          emptyHours = ScheduledIssue.create(
            :user_id => user_id,
            :project_id => project_id,
            :scheduled_hours => hours,
            :date => date );
          emptyHours.save;
        end
      else
        if(hours > 0)
          emptyHours.update_attribute(:scheduled_hours, hours);
          emptyHours.save;
        else
          emptyHours.delete
        end
      end
    end
    
    render :text => emptyHours.nil? ? '0' : "#{emptyHours.scheduled_hours.to_f}";
  end
  
  #
  #
  # # # #
  def scheduled_tickets
    @i = 1;
    
    @user_id = params[:user_id];
    @date = params[:date];
    @owner = params[:owner];
    project = Project.find(params[:project_id]);
    
    #    @project = Project.find_by_id(params[:project_id]);
    @project = project;
    @avaHours = SchedulesController.left_hours(@user_id, @date);
    @memberHours = SchedulesController.userHours(@user_id, @date);
    @scheduleEntryHours = schedule_entry_hours(params[:user_id], params[:project_id],
    params[:date]);
    @previouslyUsed = ScheduledIssue.previouslyUsedHours(params[:user_id], params[:project_id], params[:date]);
    @used = not_empty_hours(params[:user_id], params[:project_id], params[:date])
    
    issues = retrieveIssues(params[:user_id], params[:project_id], params[:date]);
    if(!issues.nil? && !issues.empty?) then
      @scheduledIssues = issues['scheduledIssues'];
      @notScheduledIssues = issues['notScheduledIssues'];
      @unassignedIssues = issues['unassignedIssues'];
      @emptyHours = issues['emptyHours'];
    end
    
    @trackers_exists = !project.trackers.empty?;
    
    if(@@remote == true)
      @@remote = false;
      return render_to_string(:partial => 'scheduled_ticket');
    else
      render :partial => 'scheduled_ticket' and return;
    end
  end
  
  # Edit the schedule for the given week/user/project
  def fill
    render_404 if @project.nil?
    
    user_ids = visible_users(@projects.collect(&:members).flatten.uniq).collect { |user| user.id }
    if !user_ids.nil? && !user_ids.empty? then
      @indexed_users = @users.index_by { |user| user.id }
      @defaults = get_defaults(user_ids).index_by { |default| default.user_id }
      @defaults.delete_if { |user_id, default| !default.weekday_hours.detect { |weekday| weekday != 0 }}
      @calendar = Redmine::Helpers::Calendar.new(Date.today, current_language, :week)
    end
    
  end
  
  
  # Given a version, we want to estimate when it can be completed. To generate
  # this date, we need open issues to have time estimates and for assigned
  # individuals to have scheduled time.
  #
  # This function makes a number of assumtions when generating the estimate
  # that, in practice, aren't generally true. For example, issues may have
  # multiple users addressing them or may require validation before the next
  # step begins. Issues often have undeclared dependancies that aren't initially
  # clear. These may affect when the version is completed.
  #
  # Note that this method talks about issue parents and children. These refer to
  # to issues that are blocked or preceded by others.
  def estimate
    
    # Obtain all open issues for the given version
    raise l(:error_schedules_not_enabled) if !@version.project.module_enabled?('schedule_module')
    @open_issues = @version.fixed_issues.collect { |issue| issue unless issue.closed? }.compact.index_by { |issue| issue.id }
    
    # Confirm that all issues have estimates, are assigned and only have parents
    # in this version
    raise l(:error_schedules_estimate_unestimated_issues) if !@open_issues.collect { |issue_id, issue| issue if issue.estimated_hours.nil? && (issue.done_ratio < 100) }.compact.empty?
    raise l(:error_schedules_estimate_unassigned_issues) if !@open_issues.collect { |issue_id, issue| issue if issue.assigned_to.nil? && (issue.done_ratio < 100) }.compact.empty?
    raise l(:error_schedules_estimate_open_interversion_parents) if !@open_issues.collect do |issue_id, issue|
      issue.relations.collect do |relation|
        Issue.find(
          :first,
          :include => :status,
          :conditions => ["#{Issue.table_name}.id=? AND #{IssueStatus.table_name}.is_closed=? AND (#{Issue.table_name}.fixed_version_id<>? OR #{Issue.table_name}.fixed_version_id IS NULL)", relation.issue_from_id, false, @version.id]
        ) if (relation.issue_to_id == issue.id) && schedule_relation?(relation)
      end
      end.flatten.compact.empty?
      
      # Obtain all assignees
      assignees = @open_issues.collect { |issue_id, issue| issue.assigned_to }.uniq
      @entries = ScheduleEntry.find(
      :all,
      :conditions => sprintf("user_id IN (%s) AND date > NOW() AND project_id = %s", assignees.collect {|user| user.id }.join(','), @version.project.id),
      :order => ["date"]
      ).group_by{ |entry| entry.user_id }
      raise l(:error_schedules_estimate_insufficient_scheduling) if @entries.empty?
      @entries.each { |user_id, user_entries| @entries[user_id] = user_entries.index_by { |entry| entry.date } }
      
      # Build issue precedence hierarchy
      floating_issues = Set.new    # Issues with no children or parents
      surfaced_issues = Set.new    # Issues with children, but no parents
      buried_issues = Set.new      # Issues with parents
      @open_issues.each do |issue_id, issue|
        issue.start_date = nil
        issue.due_date = nil
        issue.relations.each do |relation|
          if (relation.issue_to_id == issue.id) && schedule_relation?(relation)
            if @open_issues.has_key?(relation.issue_from_id)
              buried_issues.add(issue)
              surfaced_issues.add(@open_issues[relation.issue_from_id])
            end
          end
        end
      end
      surfaced_issues.subtract(buried_issues)
      floating_issues = Set.new(@open_issues.values).subtract(surfaced_issues).subtract(buried_issues)
      
      # Surface issues and schedule them
      while !surfaced_issues.empty?
        buried_issues.subtract(surfaced_issues)
        
        next_layer = Set.new    # Issues surfaced by scheduling the current layer
        surfaced_issues.each do |surfaced_issue|
          
          # Schedule the surfaced issue
          schedule_issue(surfaced_issue)
          
          # Move child issues to appropriate buckets
          surfaced_issue.relations.each do |relation|
            if (relation.issue_from_id == surfaced_issue.id) && schedule_relation?(relation) && @open_issues.include?(relation.issue_to_id) && buried_issues.include?(@open_issues[relation.issue_to_id])
              considered_issue = @open_issues[relation.issue_to_id]
              
              # If the issue is blocked by buried relations, then it stays buried
              if !considered_issue.relations.collect { |r| true if (r.issue_to_id == considered_issue.id) && schedule_relation?(r) && buried_issues.include?(@open_issues[r.issue_from_id]) }.compact.empty?
                
                # If the issue blocks buried relations, then it surfaces
              elsif !considered_issue.relations.collect { |r| true if (r.issue_from_id == considered_issue.id) && schedule_relation?(r) && buried_issues.include?(@open_issues[r.issue_to_id]) }.compact.empty?
                next_layer.add(considered_issue)
                
                # If the issue has no buried relations, then it floats
              else
                buried_issues.delete(considered_issue)
                floating_issues.add(considered_issue)
              end
            end
          end
        end
        surfaced_issues = next_layer
      end
      
      # Schedule remaining floating issues by priority
      floating_issues.sort { |a,b| b.priority <=> a.priority }.each { |floating_issue| schedule_issue(floating_issue) }
      
      # Version effective date is the latest due date of all open issues
      @version.effective_date = @open_issues.collect { |issue_id, issue| issue }.max { |a,b| a.due_date <=> b.due_date }.due_date
      
      # Save the issues and milestone date if requested.
      if params[:confirm_estimate]
        @open_issues.each { |issue_id, issue| issue.save }
        @version.save
        flash[:notice] = l(:label_schedules_estimate_updated)
        redirect_to({:controller => 'versions', :action => 'show', :id => @version.id})
      end
      
    rescue Exception => e
      flash[:error] = e.message
      redirect_to({:controller => 'versions', :action => 'show', :id => @version.id})
    end
    
    
    #
    def report
      timelog_report
    end
    
    
    # This method is based off of Redmine's timelog. It has been modified to
    # accommodate the needs of the Schedules plugin. In the event that changes are
    # made to the original, this method will need to be updated accordingly. As
    # such, efforts should be made to modify this method as little as possible as
    # it's effectively a branch that we want to keep in sync.
    def details
      sort_init 'date', 'desc'
      sort_update 'date' => 'date',
      'user' => 'user_id',
      'project' => "#{Project.table_name}.name",
      'hours' => 'hours'
      
      cond = ARCondition.new
      if @project.nil?
        cond << Project.allowed_to_condition(User.current, :view_schedules)
      end
      
      retrieve_date_range
      cond << ['date BETWEEN ? AND ?', @from, @to]
      
      ScheduleEntry.visible_by(User.current) do
        respond_to do |format|
          format.html {
            # Paginate results
            @entry_count = ScheduleEntry.count(:include => :project, :conditions => cond.conditions)
            @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
            @entries = ScheduleEntry.find(:all,
            :include => [:project, :user],
            :conditions => cond.conditions,
            :order => sort_clause,
            :limit  =>  @entry_pages.items_per_page,
            :offset =>  @entry_pages.current.offset)
            @total_hours = ScheduleEntry.sum(:hours, :include => :project, :conditions => cond.conditions).to_f
            
            render :layout => !request.xhr?
          }
          format.atom {
            entries = ScheduleEntry.find(:all,
            :include => [:project, :user],
            :conditions => cond.conditions,
            :order => "#{ScheduleEntry.table_name}.created_on DESC",
            :limit => Setting.feeds_limit.to_i)
            render_feed(entries, :title => l(:label_spent_time))
          }
          format.csv {
            # Export all entries
            @entries = ScheduleEntry.find(:all,
            :include => [:project, :user],
            :conditions => cond.conditions,
            :order => sort_clause)
            send_data(entries_to_csv(@entries).read, :type => 'text/csv; header=present', :filename => 'schedule.csv')
          }
        end
      end
    end
    
    #
    # Move scheduled entries from this to new date
    #
    
    def move_to
      # Setup params
      project_id = params[:entry_project]
      user_id = params[:entry_user]
      new_date = Date.parse(params[:new_date])
      old_date = Date.parse(params[:date])
      @focus = params[:focus]

      
      unless new_date == old_date
        # Begin Transaction - just to avoid the war of the project managers
        ActiveRecord::Base.transaction do
          # Schedule Entries first...
          # Find the pre-existing entry
          existingEntries = ScheduleEntry.find_by_all( user_id, project_id, old_date)
          hoursToMove = 0
          existingEntries.each { |entry| hoursToMove += entry.hours}
          totalHours = hoursToMove
          existingEntries = ScheduleEntry.find_by_all( user_id, project_id, new_date)
          unless existingEntries.nil? || existingEntries.empty?
            existingEntries.each { |entry| totalHours += entry.hours}
          end
          
          # Add new, remove old
          updateScheduleEntryHours(user_id, project_id, new_date, totalHours)
          updateScheduleEntryHours(user_id, project_id, old_date, 0.0)
          
          # Now fixup ScheduledIssues...
          sourceScheduledIssues = ScheduledIssue.find_by_all(user_id, project_id, old_date)
          destinationScheduledIssues = ScheduledIssue.find_by_all(user_id, project_id, new_date)
          
          # Create associative array to get quick access into the list
          destination=[]
          destinationScheduledIssues.each do | destinationIssue |
            destination[destinationIssue.issue_id] = destinationIssue
          end
          
          # Merge them in
          sourceScheduledIssues.each do | sourceScheduledIssue |
            
            hoursToMove -= sourceScheduledIssue.scheduled_hours             
            
            if destination[sourceScheduledIssue.issue_id].nil?
              # move scheduled issue entry
              sourceScheduledIssue.date = new_date
              sourceScheduledIssue.save
            else
              # Add new hours to existing entry
              destination[sourceScheduledIssue.issue_id].scheduled_hours += sourceScheduledIssue.scheduled_hours
              destination[sourceScheduledIssue.issue_id].save
              sourceScheduledIssue.destroy
            end
          end
          
        end
      end
      
      # Prepare to re-render the calendar
      @calendar = Redmine::Helpers::Calendar.new(old_date, current_language, :week)

      @projects = Project.find(:all, :conditions => ['identifier in (?)', params[:projects]])
      @projects.sort! unless @projects.nil? || @projects.empty?

      @users = User.find(:all, :conditions => ['id in (?)', params[:users]])
      @users.sort! unless @users.nil? || @users.empty?

      @entries = get_entries #(do_projects, do_users)
      @availabilities = get_availabilities

      # Re-render the div
      render :partial => 'calendar', :locals => {:date => @old_date, :calendar => @calendar, :project => @project, :projects => @projects, :user => @user, :users => @users, :focus => @focus}
 
     rescue ActiveRecord::RecordNotFound
      render_404
    end
    
    # Take some hours from this entry and move to a new entry some other time - consolidating as needed.
    # TODO: Not yet implemented, does nothing
    def chop_up
      # Setup params
      project_id = params[:entry_project]
      user_id = params[:entry_user]
      old_date = Date.parse(params[:date])
      @focus = params[:focus]

      # Prepare to re-render the calendar
      @calendar = Redmine::Helpers::Calendar.new(old_date, current_language, :week)
      @users = User.find_all_by_id(params[:users])
      @users.sort! unless @users.nil? || @users.empty?
      @projects = Project.find(:all, :conditions => ["identifier in (?)", params[:projects]])
      @projects.sort! unless @projects.nil? || @projects.empty?
      do_projects, do_users = true, true
      if @focus == 'users'
        do_projects = false
      end
      if @focus == 'projects'
        do_users = false
      end
      @entries = get_entries(do_projects, do_users)
      @availabilities = get_availabilities

      # Re-render the div
      render :partial => 'calendar', :locals => {:date => @old_date, :calendar => @calendar, :project_id => @project, :projects => @projects, :user_id => @user, :users => @users, :focus => @focus}
    end
    
    # Reschedule to first available slot - consolidating as needed.
    # TODO: Not yet implemented, does nothing
    def reschedule
      # Setup params
      project_id = params[:entry_project]
      user_id = params[:entry_user]
      old_date = Date.parse(params[:date])
      @focus = params[:focus]

      # Prepare to re-render the calendar
      @calendar = Redmine::Helpers::Calendar.new(old_date, current_language, :week)
      @users = User.find_all_by_id(params[:users])
      @users.sort! unless @users.nil? || @users.empty?
      @projects = Project.find(:all, :conditions => ["identifier in (?)", params[:projects]])
      @projects.sort! unless @projects.nil? || @projects.empty?
      do_projects, do_users = true, true
      if @focus == 'users'
        do_projects = false
      end
      if @focus == 'projects'
        do_users = false
      end
      @entries = get_entries(do_projects, do_users)
      @availabilities = get_availabilities

      # Re-render the div
      render :partial => 'calendar', :locals => {:date => @old_date, :calendar => @calendar, :project_id => @project, :projects => @projects, :user_id => @user, :users => @users, :focus => @focus}
    end
    # ############################################################################
    # Private methods
    # ############################################################################
    private
    
    
    # Given a specific date, show the projects and users that the current user is
    # allowed to see and provide edit access to those permission is granted to.
    def save_entries
      if request.post? && params[:commit]
        save_scheduled_entries unless params[:schedule_entry].nil?
        save_closed_entries unless params[:schedule_closed_entry].nil?
        
        # If all entries saved without issue, view the results
        if flash[:warning].nil?
          flash[:notice] = l(:label_schedules_updated)
          redirect_to({:action => 'index', :date => Date.parse(params[:date])})
        else
          redirect_to({:action => 'edit', :date => Date.parse(params[:date])})
        end
      end
    end
    
    
    # Given a set of schedule entries, sift through them looking for changes in
    # the schedule. For each change, remove the old entry and save the new one
    # assuming sufficient access by the modifying user.
    def save_scheduled_entries
      
      # Get the users and projects involved in this save
      user_ids = params[:schedule_entry].collect { |user_id, dates_projects_hours| user_id }
      users = User.find(:all, :conditions => "id IN ("+user_ids.join(',')+")").index_by { |user| user.id }
      project_ids = params[:schedule_entry].values.first.values.first.keys
      projects = Project.find(:all, :conditions => "id IN ("+project_ids.join(',')+")").index_by { |project| project.id }
      defaults = get_defaults(user_ids).index_by { |default| default.user_id }
      
      # Take a look at a user and their default schedule
      params[:schedule_entry].each do |user_id, dates_projects_hours|
        user = users[user_id.to_i]
        default = defaults[user.id]
        default ||= ScheduleDefault.new
        
        # Focus down on a specific day, determining the range we can work in
        dates_projects_hours.each do |date, projects_hours|
          date = Date.parse(date)
          restrictions = "date = '#{date}' AND user_id = #{user.id}"
          other_projects = " AND project_id NOT IN (#{projects_hours.collect {|ph| ph[0] }.join(',')})"
          available_hours = default.weekday_hours[date.wday]
          available_hours -= ScheduleEntry.sum(:hours, :conditions => restrictions + other_projects) if available_hours > 0
          closedEntry = ScheduleClosedEntry.find(:first, :conditions => restrictions) if available_hours > 0
          available_hours -= closedEntry.hours unless closedEntry.nil?
          
          # Look through the entries for each project, assuming access
          entries = Array.new
          projects_hours.each do |project_id, hours|
            project = projects[project_id.to_i]
            if User.current.allowed_to?(:edit_all_schedules, project) || (User.current == user && User.current.allowed_to?(:edit_own_schedules, project)) || User.current.admin?
              
              # Find the old schedule entry and create a new one
              old_entry = ScheduleEntry.find(:first, :conditions => {:project_id => project_id, :user_id => user_id, :date => date})
              new_entry = ScheduleEntry.new
              new_entry.project_id = project.id
              new_entry.user_id = user.id
              new_entry.date = date
              new_entry.hours = [hours.to_f, 0].max
              entries << { :new => new_entry, :old => old_entry }
              available_hours -= new_entry.hours
            end
          end
          
          # Save the day's entries given enough time or access
          if available_hours >= 0 || User.current == user || User.current.admin?
            entries.each { |entry| save_entry(entry[:new], entry[:old], projects[entry[:new].project.id]) }
          else
            flash[:warning] = l(:error_schedules_insufficient_availability)
          end
        end
      end
    end
    
    
    # Given a new schedule entry and the entry that it replaces, save the first
    # and delete the second. Send out a notification if necessary.
    def save_entry(new_entry, old_entry, project)
      if old_entry.nil? || new_entry.hours != old_entry.hours
        
        # Send mail if editing another user
        if (User.current != new_entry.user) && (params[:notify]) && (new_entry.user.allowed_to?(:view_schedules, project))
          ScheduleMailer.deliver_future_changed(User.current, new_entry.user, new_entry.project, new_entry.date, new_entry.hours)
        end
        
        # Save the changes
        new_entry.save if new_entry.hours > 0
        old_entry.destroy unless old_entry.nil?
      end
    end
    
    
    # Save schedule closed entries if the owning user or an admin is requesting
    # the change.
    def save_closed_entries
      
      # Get the users and projects involved in this save
      user_ids = params[:schedule_closed_entry].collect { |user_id, dates| user_id }
      users = User.find(:all, :conditions => "id IN ("+user_ids.join(',')+")").index_by { |user| user.id }
      
      # Save the user/day/hours triplet assuming sufficient access
      params[:schedule_closed_entry].each do |user_id, dates|
        user = users[user_id.to_i]
        if (User.current == user) || User.current.admin?
          dates.each do |date, hours|
            old_entry = ScheduleClosedEntry.find(:first, :conditions => {:user_id => user_id, :date => date})
            new_entry = ScheduleClosedEntry.new
            new_entry.user_id = user.id
            new_entry.date = date
            new_entry.hours = hours.to_f
            new_entry.save if new_entry.hours > 0
            old_entry.destroy unless old_entry.nil?
          end
        end
      end
    end
    
    
    # Save the given default availability if one was provided
    def save_default
      find_user
      if request.post? && params[:commit]
        
        # Determine the user's current availability default
        @schedule_default = ScheduleDefault.find_by_user_id(@user.id)
        @schedule_default ||= ScheduleDefault.new
        @schedule_default.weekday_hours ||= [0,0,0,0,0,0,0]
        @schedule_default.user_id = @user.id
        
        # Save the new default
        @schedule_default.weekday_hours = params[:schedule_default].sort.collect { |a,b| [b.to_f, 0.0].max }
        @schedule_default.save
        
        # Inform the user that the update was successful
        flash[:notice] = l(:notice_successful_update)
        redirect_to({:action => 'index', :user_id => @user.id})
      end
    end
    
    
    # Fills user schedules up to a specified number of hours
    def fill_entries
      if request.post?
        
        # Get the defaults for the users we want to fill time for
        if params[:fill_total] == nil
          return
        end
        params[:fill_total].delete_if { |user_id, fill_total| fill_total.to_f == 0}
        
        defaults = get_defaults(params[:fill_total].collect { |user_id, fill_total| user_id.to_i }).index_by { |default| default.user_id }
        
        # Fill the schedule of each specified user
        params[:fill_total].each do |user_id, fill_total|
          
          # Prepare variables for looping
          hours_remaining = fill_total.to_f
          user_id = user_id.to_i
          default = defaults[user_id].weekday_hours
          date_index = @date
          
          # Iterate through days until we've filled up enough
          while hours_remaining > 0
            fill_hours = params[:fill_entry][user_id.to_s][date_index.wday.to_s].to_f
            if fill_hours > 0 && default[date_index.wday] > 0
              
              # Find entries for this day
              restrictions = "date = '#{date_index}' AND user_id = #{user_id}"
              project_entry = ScheduleEntry.find(:first, :conditions => restrictions + " AND project_id = #{@project.id}")
              other_project_hours = ScheduleEntry.sum(:hours, :conditions => restrictions + " AND project_id <> #{@project.id}")
              closed_hours = ScheduleClosedEntry.sum(:hours, :conditions => restrictions)
              
              # Determine the number of hours available
              available_hours = default[date_index.wday]
              available_hours -= closed_hours
              available_hours -= other_project_hours
              available_hours -= project_entry.hours unless project_entry.nil?
              available_hours = [available_hours, fill_hours, hours_remaining].min
              
              # Create an entry if we're adding time to this day
              if available_hours > 0
                new_entry = ScheduleEntry.new
                new_entry.project_id = @project.id
                new_entry.user_id = user_id
                new_entry.date = date_index
                new_entry.hours = available_hours
                new_entry.hours += project_entry.hours unless project_entry.nil?
                save_entry(new_entry, project_entry, @project.id)
                hours_remaining -= available_hours
              end
            end
            date_index += 1
          end
        end
        
        # Inform the user that the update was successful
        flash[:notice] = l(:notice_successful_update)
        redirect_to({:action => 'index', :project_id => @project.id})
      end
    end
    
    
    # Get schedule entries between two dates for the specified users and projects
    def get_entries(project_restriction = true)
      restrictions = "(date BETWEEN '#{@calendar.startdt}' AND '#{@calendar.enddt}')"
      unless (!@focus.nil? || @users.nil? || @users.empty? )
        restrictions << " AND user_id IN (" + @users.collect {|user| user.id.to_s }.join(',')+")"
      end
      if project_restriction
        restrictions << " AND project_id IN ("+@projects.collect {|project| project.id.to_s }.join(',')+")" unless @projects.empty?
        restrictions << " AND project_id = " + @project.id.to_s unless @project.nil?
      end
      ScheduleEntry.find(:all, :conditions => restrictions)
    end
    
    
    # Get closed entries between two dates for the specified users
    def get_closed_entries
      restrictions = "(date BETWEEN '#{@calendar.startdt}' AND '#{@calendar.enddt}')"
      restrictions << " AND user_id IN ("+@users.collect {|user| user.id.to_s }.join(',')+")" unless @users.empty?
      ScheduleClosedEntry.find(:all, :conditions => restrictions)
    end
    
    
    # Get schedule defaults for the specified users
    def get_defaults(user_ids = nil)
      restrictions = "user_id IN ("+@users.collect {|user| user.id.to_s }.join(',')+")" unless @users.empty?
      unless user_ids.nil? then
        restrictions = "user_id IN ("+user_ids.join(',')+")" unless user_ids.empty?
      end
      
      ScheduleDefault.find(:all, :conditions => restrictions)
    end
    
    
    # Get availability entries between two dates for the specified users
    def get_availabilities
      
      # Get the user's scheduled entries
      entries_by_user = get_entries(false).group_by{ |entry| entry.user_id }
      entries_by_user.each { |user_id, user_entries| entries_by_user[user_id] = user_entries.group_by { |entry| entry.date } }
      
      # Get the user's scheduled unavailabilities
      closed_entries_by_user = get_closed_entries.group_by { |closed_entry| closed_entry.user_id }
      closed_entries_by_user.each { |user_id, user_entries| closed_entries_by_user[user_id] = user_entries.index_by { |entry| entry.date } }
      
      # Get the user's default availability
      defaults_by_user = get_defaults.index_by { |default| default.user.id }
      
      # Generate and return the availabilities based on the above variables
      availabilities = Hash.new
       (@calendar.startdt..@calendar.enddt).each do |day|
        availabilities[day] = Hash.new
        @users.each do |user|
          availabilities[day][user.id] = 0
          availabilities[day][user.id] = defaults_by_user[user.id].weekday_hours[day.wday] unless defaults_by_user[user.id].nil?
          availabilities[day][user.id] -= entries_by_user[user.id][day].collect {|entry| entry.hours }.sum unless entries_by_user[user.id].nil? || entries_by_user[user.id][day].nil?
          availabilities[day][user.id] -= closed_entries_by_user[user.id][day].hours unless closed_entries_by_user[user.id].nil? || closed_entries_by_user[user.id][day].nil?
          availabilities[day][user.id] = [0, availabilities[day][user.id]].max
        end
      end
      availabilities
    end
    
    #
    def find_user
      params[:user_id] = User.current.id if params[:user_id].nil?
      deny_access unless User.current.id == params[:user_id].to_i || User.current.admin?
      @user = User.find(params[:user_id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
    
    # Find the project associated with the given version
    def find_project_by_version
      @version = Version.find(params[:id])
      @project = @version.project
      deny_access unless User.current.allowed_to?(:edit_all_schedules, @project) && User.current.allowed_to?(:manage_versions, @project)
    rescue ActiveRecord::RecordNotFound
      render_404
    end
    
    #
    def find_users_and_projects
      
      # Parse the focused user and/or project
      @project = Project.find(params[:project_id]) if params[:project_id]
      @user = User.find(params[:user_id]) if params[:user_id]
      @focus = "users" if @project.nil? && @user.nil?
      @projects = visible_projects.sort
      @projects = @projects & @user.projects unless @user.nil?
      @projects = @projects & [@project] unless @project.nil?
      @users = visible_users(@projects.collect(&:members).flatten.uniq) if @users.nil?
      @users = @users & [@user] unless @user.nil?
      @users = [User.current] if @users.empty? && User.current.admin?
      deny_access if (@projects.empty? || @users.empty?) && !User.current.admin?
      
      # Parse the given date or default to today
      @date = Date.parse(params[:date]) if params[:date]
      @date ||= Date.civil(params[:year].to_i, params[:month].to_i, params[:day].to_i) if params[:year] && params[:month] && params[:day]
      @date ||= Date.today
      @calendar = Redmine::Helpers::Calendar.new(@date, current_language, :week)
      
    rescue ActiveRecord::RecordNotFound
      render_404
    end
    
    
    # Determines if a given relation will prevent another from being worked on
    def schedule_relation?(relation)
      return (relation.relation_type == "blocks" || relation.relation_type == "precedes")
    end
    
    
    # This function will schedule an issue for the earliest open schedule for the
    # issue's assignee. Maybe an issue should know how to schedule itself,
    # but here we are the other way around - at least I know about resource availability.
    # issue == the issue object to be scheduled
    # project_issues == array of issues in the project, indexed by issue_id
    # keep_dates == true if issue start / end dates are to be untouched regardless of resource 'availability'
    def schedule_issue(issue, project_issues = [], keep_dates = false)
      
      unless keep_dates
        # Issues start no earlier than today
        possible_start = [Date.today]
      
        # Find out when pre-requisite issues from this version have been tentatively
        # scheduled for
        possible_start << issue.relations.collect do |relation|
          project_issues[relation.issue_from_id] if (relation.issue_to_id == issue.id) && schedule_relation?(relation)
        end.compact.collect do |related_issue|
          related_issue if related_issue.fixed_version == issue.fixed_version
        end.compact.collect do |related_issue|
          related_issue.due_date
        end.max
            
        # Find out when pre-requisite issues outside of this version are due
        possible_start << issue.relations.collect do |relation|
          Issue.find(relation.issue_from_id) if (relation.issue_to_id == issue.id) && schedule_relation?(relation)
        end.compact.collect do |related_issue|
          related_issue if related_issue.fixed_version != issue.fixed_version
        end.compact.collect do |related_issue|
          related_issue.due_date unless related_issue.due_date.nil?
        end.compact.max
                  
        # Determine the earliest possible start date for this issue
        possible_start = possible_start.compact.max
        considered_date = possible_start

      else
        possible_start = issue.start_date
        considered_date = issue.start_date
      end
       
      hours_remaining = 0
      hours_remaining = issue.estimated_hours * ((100-issue.done_ratio)*0.01) unless issue.estimated_hours.nil?
                  
      # Chew up the necessary time starting from the earliest schedule opening
      # after the possible start dates.
      issue.start_date = considered_date
      while hours_remaining > 0
        considered_date_round = considered_date
        while !@entries[issue.assigned_to.id].nil? && @entries[issue.assigned_to.id][considered_date].nil? && !@entries[issue.assigned_to.id].empty? && (considered_date < Date.today + 365)
          considered_date += 1
        end
        raise l(:error_schedules_estimate_insufficient_scheduling, issue.assigned_to.to_s + " // " + issue.to_s + " // " + considered_date_round.to_s) if @entries[issue.assigned_to.id].nil? || @entries[issue.assigned_to.id][considered_date].nil?
        if hours_remaining > @entries[issue.assigned_to.id][considered_date].hours
          hours_remaining -= @entries[issue.assigned_to.id][considered_date].hours
          @entries[issue.assigned_to.id][considered_date].hours = 0
        else
          @entries[issue.assigned_to.id][considered_date].hours -= hours_remaining
          hours_remaining = 0
        end
        @entries[issue.assigned_to.id].delete(considered_date) if @entries[issue.assigned_to.id][considered_date].hours == 0
      end
      issue.due_date = considered_date

      # Store the modified issue back to the global
      @open_issues[issue.id] = issue
    end
                
  # ############################################################################
  # Instance method interfaces to class methods
  # ############################################################################
  def visible_projects
    self.class.visible_projects
  end
  def visible_users(members)
    self.class.visible_users(members)
  end
                
end
