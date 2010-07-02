########################################################################
# File:    loader_controller.rb                                         #
#          Updated to apply integration with scheduling                #
########################################################################


class LoaderController < ApplicationController
  
  unloadable
  
  before_filter :require_login
  before_filter :setup_defaults, :authorize, :only => [:new, :create]  
  
  require 'zlib'
  require 'ostruct'
  require 'tempfile'
  require 'rexml/document'
  @default_tracker_id = 0
  @default_category = "Project"
  
  # Set up the import view. If there is no task data, this will consist of
  # a file entry field and nothing else. If there is parsed file data (a
  # preliminary task list), then this is included too.
  
  def new
    
    
  end
  
  
  
  # Take the task data from the 'new' view form and 'create' an "import
  # session"; that is, create real Task objects based on the task list and
  # add them to the database, wrapped in a single transaction so that the
  # whole operation can be unwound in case of error.
  
  def create
    # This can and probably SHOULD be replaced with some URL rewrite magic
    # now that the project loader is Redmine project based.
    #    find_project()
    
    # Set up a new TaskImport session object and read the XML file details
    
    
    xmlfile = params[ :import ][ :xmlfile ]
    @import = TaskImport.new
    
    unless ( xmlfile.nil? )
      begin
        # The user selected a file to upload, so process it
        
        # We assume XML files always begin with "<" in the first byte and
        # if that's missing then it's GZip compressed. That's true in the
        # limited case of project files.
        
        byte = xmlfile.getc()
        xmlfile.rewind()
        
        xmlfile       = Zlib::GzipReader.new( xmlfile ) if ( byte != '<'[ 0 ] )
        xmldoc        = REXML::Document.new( xmlfile.read() )
        @import.tasks, @import.new_categories, @import.milestones = get_tasks_from_xml( xmldoc )
        
        if ( @import.tasks.nil? or @import.tasks.empty? )
          flash[ :error  ] = 'No usable tasks were found in that file'
        else
          flash[ :notice ] = 'Tasks read successfully. Please choose items to import.'
        end
        
      rescue => error
        
        # REXML errors can be huge, including a full backtrace. It can cause
        # session cookie overflow and we don't want the user to see it. Cut
        # the message off at the first newline.
        
        lines = error.message.split("\n")
        
        flash[ :error  ] = "Failed to read file: #{ lines[ 0 ] }"
      end
      
      render( { :action => :new } )
      flash.delete( :error  )
      flash.delete( :notice )
      
    else
      
      # No file was specified. If there are no tasks either, complain.
      # TODO: locales...
      
      tasks = params[ :import ][ :tasks ]
      
      # We must have tasks or a file, a default tracker, but we only require a default category if
      # none is set for one or more tasks in the project file.
      
      if ( tasks.nil? )
        flash[ :error ] = "Please choose a file before using the 'Analyse' button."
      elsif ( @default_tracker_id.nil? )
        flash[ :error ] = 'No valid default Tracker. Please ask your System Administrator to resolve this.'
      elsif ( params[ :import ][ :import_selected ].nil? )
        flash[ :error ] = 'No new file was chosen for analysis. Please choose a file before using the "Analyse" button, or use the "Import" button to import tasks selected in the task list.'
      end
      
      # Bail out quickly if we have errors to report.
      unless( flash[ :error ].nil? )
        render( { :action => :new } )
        flash.delete( :error  )
        return
      end
      
      # Compile the form submission's task list into something that the
      # TaskImport object understands.
      #
      # Since we'll rebuild the tasks array inside @import, we can render the
      # 'new' view again and have the same task list presented to the user in
      # case of error.
      
      @import.tasks = []
      @import.new_categories = []
      to_import     = []
      
      # Due to the way the form is constructed, 'task' will be a 2-element
      # array where the first element contains a string version of the index
      # at which we should store the entry and the second element contains
      # the hash describing the task itself.
      
      tasks.each do | taskinfo |
        index  = taskinfo[ 0 ].to_i
        task   = taskinfo[ 1 ]
        struct = OpenStruct.new
        
        struct.uid = task[ :uid ]        
        struct.title    = task[ :title    ]
        struct.level    = task[ :level    ]
        struct.code     = task[ :code     ]
        struct.duration = task[ :duration ]
        struct.start = task[ :start ]
        struct.finish = task[ :finish ]
        struct.percentcomplete = task[ :percentcomplete ]
        struct.parent = task[ :parent ]
        struct.predecessors = task[ :predecessors ].split(', ')
        struct.category = task[ :category ]
        struct.assigned_to = task[ :assigned_to ]
        struct.description = task[ :description ]
        
        
        @import.tasks[ index ] = struct
        to_import[ index ] = struct if ( task[ :import ] == '1' )
      end
      
      to_import.compact!
      
      # The "import" button in the form causes token "import_selected" to be
      # set in the params hash. The "analyse" button causes nothing to be set.
      # If the user has clicked on the "analyse" button but we've reached this
      # point, then they didn't choose a new file yet *did* have a task list
      # available. That's strange, so raise an error.
      #
      # On the other hand, if the 'import' button *was* used but no tasks were
      # selected for error, raise a different error.
      if ( to_import.empty? )
        flash[ :error ] = 'No tasks were selected for import. Please select at least one task and try again.'
      end
      
      # Bail out if we have errors to report.
      unless( flash[ :error ].nil? )
        render( { :action => :new } )
        flash.delete( :error  )
        return
      end
      
      # We're going to keep track of new issue ID's to make dependencies work later
      uidToIssueIdMap = {}
      all_fits = true
      extended_issue_ids = []
      # Right, good to go! Do the import.
      begin
        Issue.transaction do
          to_import.each do | source_issue |
            
            # Create if not there already
            category_entry = confirm_category(source_issue.category)
            next if category_entry.nil?
            #
            # Find any issue for this project that 'matches' this one
            #
            existing_issue = Issue.find(:first, :conditions => ["project_id = ? and subject = ? and tracker_id=?", @project.id, source_issue.title.slice(0,255), @default_tracker_id])
            
            #
            # Either populate and save a new issue, or update existing
            #
            if existing_issue.nil? then
              
              destination_issue          = Issue.new do |i|
                i.tracker_id = @default_tracker_id
                i.category_id = category_entry
                i.subject    = source_issue.title.slice(0, 255) # Max length of this field is 255
                i.description = source_issue.description unless source_issue.description.nil?
                i.estimated_hours = source_issue.duration
                i.project_id = @project.id
                i.author_id = User.current.id
                i.lock_version = 0
                i.done_ratio = source_issue.percentcomplete
                i.description = source_issue.title
                i.start_date = source_issue.start
                i.due_date = source_issue.finish unless source_issue.finish.nil?
                i.due_date = (Date.parse(source_issue.start, false) + ((source_issue.duration.to_f/40.0)*7.0).to_i).to_s unless i.due_date != nil
                
                if source_issue.assigned_to != ""
                  i.assigned_to_id = source_issue.assigned_to.to_i
                end
              end
              
              destination_issue.save!
              
              # Now that we know this issue's Redmine issue ID, save it off for later
              uidToIssueIdMap[ source_issue.uid ] = destination_issue.id
              existing_issue = destination_issue
              
            else
              # Delete all pre-existing dependencies for this issue
              issue_relation_list = IssueRelation.find(:all, :conditions => ["issue_to_id = ?", existing_issue.id])
              issue_relation_list.each do | issue_relation |
                issue_relation.destroy
              end
              # Update existing
              existing_issue.tracker_id = @default_tracker_id
              existing_issue.category_id = category_entry unless category_entry.nil?
              existing_issue.description = source_issue.description unless source_issue.description.nil?
              existing_issue.estimated_hours = source_issue.duration unless source_issue.duration.nil?
              existing_issue.done_ratio = source_issue.percentcomplete unless source_issue.percentcomplete.nil?
              # This is a kludge 
              # TODO: figure out why this is sometimes needed. probably stupid arithmetic for finish/duration.
              if source_issue.start && existing_issue.soonest_start && source_issue.start < existing_issue.soonest_start
                source_issue.start = existing_issue.soonest_start
              end
              existing_issue.start_date = source_issue.start unless source_issue.start.nil?
              existing_issue.due_date = source_issue.finish unless source_issue.finish.nil?
              existing_issue.due_date = (Date.parse(source_issue.start, false) + ((source_issue.duration.to_f/40.0)*7.0).to_i).to_s unless source_issue.due_date.nil?
              
              existing_issue.assigned_to_id = source_issue.assigned_to.to_i unless source_issue.assigned_to = ""
              
              existing_issue.save!
              
              # Now that we know this issue's Redmine issue ID, save it off for later
              uidToIssueIdMap[ source_issue.uid ] = existing_issue.id
            end # if existing_issue
            
            # Now schedule estimated hours across issue period for default available time for assigned resource
            unless ensure_issue_scheduled(existing_issue, Setting.plugin_redmine_planning['level']=="Y")
              all_fits = false
              extended_issue_ids << existing_issue.id
            end

          end # to_import.each
          # Now do something with milestones
          # TODO: think of some scheme that always makes sense.. 
        
          # Now note the parent issue ids 
          to_import.each do | source_issue |
            next if source_issue.uid == "0" # Ignore top level issue, probably parent to all
            source_id = uidToIssueIdMap[source_issue.uid]
            parent_id = uidToIssueIdMap[source_issue.parent]
            next if source_id.nil? || parent_id.nil?
            existing_issue = Issue.find_by_id(source_id)
            next if existing_issue.nil? # probably a milestone or malformed entry in the XML
            existing_issue.parent_issue_id = parent_id
            existing_issue.save!
          end          
          
          # Build up the dependencies being careful if the related issue doesn't exist
          to_import.each do | source_issue |
            source_issue.predecessors.each do | predecessor_uid |
              if ( uidToIssueIdMap.has_key?(predecessor_uid) )
                # Predecessor is being imported also.  Go ahead and confirm the association
                unless (IssueRelation.find(:all, :conditions => ["issue_from_id = ? and issue_to_id = ?", uidToIssueIdMap[predecessor_uid], uidToIssueIdMap[source_issue.uid]]).length >0)
                  relation_record = IssueRelation.new do |i|
                    i.issue_from_id = uidToIssueIdMap[predecessor_uid]
                    i.issue_to_id = uidToIssueIdMap[source_issue.uid]
                    i.relation_type = 'precedes'
                  end
                  relation_record.save!
                end
              end
            end
          end  
        end # Transaction
        # All good.
        flash[ :notice ] = "#{ to_import.length } #{ to_import.length == 1 ? 'task' : 'tasks' } imported successfully."
        
        unless all_fits # not likely !
          flash[ :warning ] = "The following new issue ids have modified timing as a result of scheduling:" + extended_issue_ids.join(",").to_s
        end
        # Now release user into the wild
        redirect_to( "/projects/#{@project.identifier}/issues" )
        
        # Not good
      rescue => error
        flash[ :error ] = "Unable to import tasks: #{ error }"
        render( { :action => :new } )
        flash.delete( :error )
        
      end
    end
  end
  
  private
  
  def setup_defaults
    # Get defaults to use for all tasks
    #
    # Project
    #
    @project = Project.find(params[:project_id])  
    #
    # Tracker
    #
    default_tracker = Tracker.find(:first, :conditions => [ "id = ?", Setting.plugin_redmine_planning['tracker']])
    @default_tracker_id = default_tracker.id unless default_tracker.nil?
   
    #
    # Category
    #
    @default_category = Setting.plugin_redmine_planning['category']
    
    # We must have a default tracker, but we only require a default category if
    # none is set for one or more tasks in the project file.
    if ( @default_tracker_id.nil? )
      flash[ :error ] = 'No valid default Tracker. Please ask your System Administrator to resolve this.'
    end
    
  end
  
  # Create new category if not already existing
  def confirm_category (issue_category)
    # Fudge category if none in XML
    if (issue_category.nil?) 
      issue_category = @default_category
    end
    if (issue_category.nil?) # Still ?!
      flash[ :error ] = 'No valid default Issue Category and none set for some issues. Please ask your System Administrator to resolve this (or set for all tasks in the XML).'
      return false
    end
    
    # Add the category entry if necessary
    category_entry = IssueCategory.find :first, :conditions => { :project_id => @project.id, :name => issue_category }
    
    if (category_entry.nil?)
      # Need to create it
      category_entry = IssueCategory.new do |i|
        i.name = issue_category
        i.project_id = @project.id
      end
      
      category_entry.save!
    end
    return category_entry.id
  end
  
  # Obtain a task list from the given parsed XML data (a REXML document).
  # Slow, difficult and error prone.  But there you go..
  
  def get_tasks_from_xml( doc )
    # Extract details of every task to populate various arrays, passing some of these back up
    tasks = []
    milestones = []
    all_categories = []
    
    # To hold ordered arrays
    uid_tasks = []
    uid_resources = []
    
    max_category_depth = 2
    max_category_depth = Setting.plugin_redmine_planning['depth'].to_i unless Setting.plugin_redmine_planning['depth'].nil?
    
    
    doc.each_element( 'Project/Tasks/Task' ) do | task |
      begin
        struct = OpenStruct.new
        # TODO: Dont do anything with milestones yet - maybe adjust versions later
        if task.get_elements( 'Milestone'    )[ 0 ].text.to_i == 1
          struct.title           = task.get_elements( 'Name'         )[ 0 ].text.strip
          struct.start           = task.get_elements( 'Start'        )[ 0 ].text.split("T")[0] unless task.get_elements( 'Start' )[ 0 ].nil?
          struct.description     = task.get_elements( 'Notes'        )[ 0 ].text unless task.get_elements( 'Notes' )[ 0 ].nil?
          milestones.push( struct )
        else
          struct.tid             = task.get_elements( 'ID'           )[ 0 ].text.to_i
          struct.uid             = task.get_elements( 'UID'          )[ 0 ].text.to_i
          struct.level           = task.get_elements( 'OutlineLevel' )[ 0 ].text.to_i
          struct.title           = task.get_elements( 'Name'         )[ 0 ].text.strip
          struct.start           = task.get_elements( 'Start'        )[ 0 ].text.split("T")[0] unless task.get_elements( 'Start' )[ 0 ].nil?
          struct.description     = task.get_elements( 'Notes'        )[ 0 ].text unless task.get_elements( 'Notes' )[ 0 ].nil?
          struct.summary         = 0
          struct.summary         = task.get_elements( 'Summary'      )[ 0 ].text.to_i unless task.get_elements( 'Summary'      )[ 0 ].nil?
          struct.work            = task.get_elements( 'Work'         )[ 0 ].text.strip unless task.get_elements( 'Work' )[ 0 ].nil?
          struct.duration        = task.get_elements( 'Duration'     )[ 0 ].text.strip unless task.get_elements( 'Duration' )[ 0 ].nil?
          struct.finish          = task.get_elements( 'Finish'       )[ 0 ].text.split("T")[0] unless task.get_elements( 'Finish')[ 0 ].nil?
          struct.percentcomplete = 0
          struct.percentcomplete = task.get_elements( 'PercentComplete')[0].text.to_i unless task.get_elements( 'PercentComplete')[0].nil?
          struct.parent_uid      = 0
          struct.users           = []
          
          # Parse the "Work" string: "PT<num>H<num>M<num>S", but with some
          # leniency to allow any data before or after the H/M/S stuff.
          hours = 0
          mins = 0
          secs = 0
          
          strs = struct.work.scan(/.*?(\d+)H(\d+)M(\d+)S.*?/).flatten unless struct.work.nil?
          hours, mins, secs = strs.map { | str | str.to_i } unless strs.nil?
          
          struct.work = ( ( ( hours * 3600 ) + ( mins * 60 ) + secs ) / 3600 ).prec_f
          
          hours = 0
          mins = 0
          secs = 0
          
          strs = struct.duration.scan(/.*?(\d+)H(\d+)M(\d+)S.*?/).flatten unless struct.duration.nil?
          hours, mins, secs = strs.map { | str | str.to_i } unless strs.nil?
          
          struct.duration = ( ( ( hours * 3600 ) + ( mins * 60 ) + secs ) / 3600 ).prec_f
          
          if struct.duration == 0
            struct.duration = struct.work
          end

          # Assume standard 8 hour day for work...
          increment = (struct.duration / 8.0) * 86400
          start_elements = struct.start.split("-")
          struct.finish = (Time.gm(start_elements[0], start_elements[1], start_elements[2]) + increment).strftime("%Y-%m-%d")
          # Handle dependencies
          struct.predecessors = []
          task.each_element( 'PredecessorLink' ) do | predecessor | 
            struct.predecessors.push( predecessor.get_elements('PredecessorUID')[0].text.to_i ) unless predecessor.get_elements('PredecessorUID')[0].nil?
          end # do
          tasks.push( struct )
          
        end # if
      rescue
        # Arrogantly ignore errors; they tend to indicate malformed tasks, or, at least,
        # XML file task entries that we do not understand.
      end # begin
    end # do doc.each_element
    
    # Sort the array by ID (wbs order). By sorting the array this way, the order
    # order will match the task order displayed to the user in the
    # project editor software which generated the XML file.
    tasks = tasks.sort_by { | task | task.tid }
    
    # Step through the sorted tasks. Each time we find one where the
    # *next* task has an outline level greater than the current task,
    # then the current task has children. Make a note of parenthood.
    
    last_summary_task=[]
    
    tasks.each_index do | index |
      task = tasks[index]
      next_task=tasks[index+1]
      
      next if next_task.nil?
      # Is next closer to leaf ?
      if next_task.level > task.level
        next_task.parent_uid = task.uid
        # We have just found a new summary task
        last_summary_task[task.level.to_i] = task.uid
        # not sure about this - but it will do for now
        if task.level < max_category_depth
          all_categories.push(task.title)
        end # if
      else
        # Make a note of the previous summary uid at this level
        level = next_task.level.to_i - 1
        next_task.parent_uid = last_summary_task[level]
      end # if
      task.category = all_categories[-1] # always most recent
    end #do each_index
    
    # Now create a secondary array, where the UID of any given task is
    # the array index at which it can be found. This is just to make
    # looking up tasks by UID really easy, rather than faffing around
    # with "tasks.find { | task | task.uid = <whatever> }".
    
    
    tasks.each do | task |
      uid_tasks[ task.uid ] = task
    end #do each
    
    # Same for resources
    #  
    
    doc.each_element( 'Project/Resources/Resource') do | resource |
      begin
        name = resource.get_elements( 'Name' )[0].text.downcase.split
        uid = resource.get_elements( 'UID' )[ 0 ].text.to_i
        
        # Try to find based on resource name == email
        potential_match = User.find(:first, :conditions => ["lower(mail) = ?", name[0]])
        
        # If that failed, try to find based on 'firstname<spaces>lastname'
        potential_match = User.find(:first, :conditions => ["lower(firstname) = ? and lower(lastname) = ?", name[0], name[1]])  unless potential_match
        
        # We may need this later
        uid_resources[ uid ] = potential_match.id unless potential_match.nil?
        
      rescue
        # Ignore malformed stupid stuff and our own ignorance
        puts "Malformed resource:" + name if !name.nil?
      end # begin
    end # do doc.each_element
    # Now map one to t'other
    #
    
    doc.each_element( 'Project/Assignments/Assignment' ) do | as |
      task_uid = as.get_elements( 'TaskUID' )[ 0 ].text.to_i
      task = uid_tasks[ task_uid ] unless task_uid.nil?
      next if ( task.nil? )
      
      resource_uid = as.get_elements( 'ResourceUID' )[0].text.to_i
      user_id = uid_resources[resource_uid] unless resource_uid.nil?
      
      task.users.push(user_id)
    end #do doc.each_element
    
    tasks = tasks.uniq unless tasks.nil?
    all_categories = all_categories.uniq.sort
    
    return tasks, all_categories, milestones
  end # get_tasks_from_xml
  
  # Make sure ScheduleEntry and ScheduledIssue objects are setup
  # for the issue - using resource assigned default availability
  # and re-using existing objects where this fits
  def ensure_issue_scheduled (existing_issue, fit)
    
    return true if existing_issue.nil? || existing_issue.assigned_to_id.nil?

    existing_scheduled_issues = ScheduledIssue.all(:conditions => ["user_id = ? AND issue_id = ?", existing_issue.assigned_to_id, existing_issue.id]);
    sum = 0
    sum = existing_scheduled_issues.sum(&:scheduled_hours) if !existing_scheduled_issues.nil?
 
    if existing_issue.estimated_hours.nil? || sum == existing_issue.estimated_hours
      return true # Nothing to do
    end
    
    if sum < existing_issue.estimated_hours
      return schedule_additional_issue_time(existing_issue, existing_issue.estimated_hours - sum, fit)
    else
      return sacrifice_issue_time(existing_issue.assigned_to_id, sum - existing_issue.estimated_hours, existing_scheduled_issues)
    end
    
  end # ensure_issue_scheduled
  
  def schedule_additional_issue_time(existing_issue, hours, fit)
    start_date = existing_issue.start_date
    due_date = existing_issue.due_date
    
    default_available_hours = ScheduleDefault.find_by_user_id(existing_issue.assigned_to_id)[:weekday_hours]
    
    # Check sum(default_available_hours) > 0 (or assume [0,8,8,8,8,8,0] as a default )
    # TODO: implement smarter resource calendars including regional holidays..
    if default_available_hours.sum == 0
      default_available_hours = [0,8,8,8,8,8,0]
    end
    
    # Step through range allocating out max available (ignoring current schedule)
    # until required hours are done.
    # TODO: take current commitments into account
    (start_date..due_date).each do |day|
      next if hours == 0
      max_hours = default_available_hours[day.wday]
      available = max_hours - committed_time(existing_issue.assigned_to_id, day, fit)
      if available > 0
        if hours >= available
          new_hours = available
          hours -= available
        else
          new_hours = hours
          hours = 0
        end
        # create new scheduled_issue entry or update existing to match
        schedule_additional_issue_entries(existing_issue.assigned_to_id, existing_issue.project_id, existing_issue.id, day, new_hours)
        # Create new schedule entry entry or update existing to match (urgh)        
        schedule_additional_project_entries(existing_issue.assigned_to_id, existing_issue.project_id, day, new_hours)
      end
    end
    
    return true if hours == 0
    
    day = due_date
    # Not all time scheduled 
    while (hours > 0)
      day += 1
      max_hours = default_available_hours[day.wday]
      available = max_hours - committed_time(existing_issue.assigned_to_id, day, fit)
      if available > 0
        if hours >= available
          new_hours = available
          hours -= available
        else
          new_hours = hours
          hours = 0
        end
        # create new scheduled_issue entry or update existing to match
        schedule_additional_issue_entries(existing_issue.assigned_to_id, existing_issue.project_id, existing_issue.id, day, new_hours)
        # Create new schedule entry entry or update existing to match (urgh)        
        schedule_additional_project_entries(existing_issue.assigned_to_id, existing_issue.project_id, day, new_hours)
      end
    end

    return false
        
  end # schedule_additional_issue_time

  # Setup scheduled issue entries to match new issue schedule
  # - create a new one if needed
  # - extend existing one otherwise
  def schedule_additional_issue_entries(user_id, project_id, issue_id, date, hours)
    existing_scheduled_issues = ScheduledIssue.find(:all, :conditions => ['user_id = ? AND project_id = ? AND issue_id = ? AND date = ?', user_id, project_id, issue_id, date ])
    
    if existing_scheduled_issues.nil? || existing_scheduled_issues.empty?
      new_scheduled_issue = ScheduledIssue.new
      new_scheduled_issue.issue_id = issue_id
      new_scheduled_issue.project_id = project_id
      new_scheduled_issue.user_id = user_id
      new_scheduled_issue.date = date
      new_scheduled_issue.scheduled_hours = hours
      new_scheduled_issue.save
      return
    end
    
    # If there are more than one returned issues that is an error..?
    existing_scheduled_issues[0].scheduled_hours = existing_scheduled_issues[0].scheduled_hours + hours
    existing_scheduled_issues[0].save
    return
  end # schedule_additional_project_time
  
  # Setup schedule entries to match new issue schedule
  # - create a new entry if needed
  # - extend existing one otherwise
  def schedule_additional_project_entries(user_id, project_id, date, hours)
    existing_schedule_entries = ScheduleEntry.find(:all, :conditions => ['user_id = ? AND project_id = ? AND date = ?', user_id, project_id, date])
    
    if existing_schedule_entries.nil? || existing_schedule_entries.empty?
      new_schedule_entry = ScheduleEntry.new
      new_schedule_entry.project_id = project_id
      new_schedule_entry.user_id = user_id
      new_schedule_entry.date = date
      new_schedule_entry.hours = hours
      new_schedule_entry.save
      return
    end
    
    # If there are more than one returned issues that is an error..?
    existing_schedule_entries[0].hours = existing_schedule_entries[0].hours + hours
    existing_schedule_entries[0].save
  end # schedule_additional_project_time
  
  # return sum of hours committed already
  # (these are already considered in required hours)
  
  def committed_time (user_id, date, fit)

    sum = 0
    if fit == true
      existing_scheduled_entries = ScheduleEntry.all(:conditions => ["user_id = ? AND date = ?", user_id, date]);
      sum = existing_scheduled_entries.sum(&:hours) if !existing_scheduled_entries.nil?
    end
    return sum
  end # commmitted_time
  
  def sacrifice_issue_time(user_id, hours, scheduled_issues)
    scheduled_issues.sort! { |a, b| a.date <=> b.date }
    while (hours > 0)
      oldest_entry = scheduled_issues.pop
      return false if oldest_entry.nil?
      
      if hours >= oldest_entry.scheduled_hours
        hours -= oldest_entry.scheduled_hours
        sacrifice_project_time(user_id, oldest_entry.project_id, oldest_entry.date, hours)
        oldest_entry.destroy
      else
        oldest_entry.scheduled_hours -= hours
        sacrifice_project_time(user_id, oldest_entry.project_id, oldest_entry.date, hours)
        oldest_entry.save
        hours = 0 # End
      end
    end
    return true  
  end # sacrifice_issue_time
  
  def sacrifice_project_time(user_id, project_id, date, hours)
    project_schedule = ScheduleEntry.find_by_all(user_id, project_id, date)
    
    return false if project_schedule.nil? || project_schedule.empty?

    if project_schedule[0].scheduled_hours > hours
      project_schedule[0].scheduled_hours -= hours
      project_schedule[0].save
    else
      project_schedule[0].destroy
    end
    
    return true
  end # sacrifice_project_time
  
  
end # class LoaderController
