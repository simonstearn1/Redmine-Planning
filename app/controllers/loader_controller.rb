########################################################################
# File:    loader_controler.rb                                         #
#          Feb 2009 (SJS): Hacked into plugin for redmine              #
########################################################################


class LoaderController < ApplicationController
  
  unloadable
  
  before_filter :require_login
  before_filter :find_project, :authorize, :only => [:new, :create]  
  
  require 'zlib'
  require 'ostruct'
  require 'tempfile'
  require 'rexml/document'
  
  # Set up the import view. If there is no task data, this will consist of
  # a file entry field and nothing else. If there is parsed file data (a
  # preliminary task list), then this is included too.
  
  def new
    # This can and probably SHOULD be replaced with some URL rewrite magic
    # now that the project loader is Redmine project based.
    #  find_project()
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
      
      if ( tasks.nil? )
        flash[ :error ] = "Please choose a file before using the 'Analyse' button."
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
        struct.notes = task[ :notes ]
        
        
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
      
      if ( params[ :import ][ :import_selected ].nil? )
        flash[ :error ] = 'No new file was chosen for analysis. Please choose a file before using the "Analyse" button, or use the "Import" button to import tasks selected in the task list.'
      elsif ( to_import.empty? )
        flash[ :error ] = 'No tasks were selected for import. Please select at least one task and try again.'
      end
      
      # Get defaults to use for all tasks - keep track of these to save a few db lookups.
      #
      # Tracker
      default_tracker = Tracker.find(:first, :conditions => [ "id = ?", Setting.plugin_redmine_planning['tracker']])
      default_tracker_id = default_tracker.id unless default_tracker.nil?
      #
      # Category
      #
      default_category = Setting.plugin_redmine_planning['category']
      
      # We must have a default tracker, but we only require a default category if
      # none is set for one or more tasks in the project file.
      if ( default_tracker_id.nil? )
        flash[ :error ] = 'No valid default Tracker. Please ask your System Administrator to resolve this.'
      end
      
      # Bail out if we have errors to report.
      unless( flash[ :error ].nil? )
        render( { :action => :new } )
        flash.delete( :error  )
        return
      end
      
      # We're going to keep track of new issue ID's to make dependencies work later
      uidToIssueIdMap = {}
      
      # Right, good to go! Do the import.
      begin
        Issue.transaction do
          to_import.each do | source_issue |
            
            # Fudge category if none in XML
            if (source_issue.category.nil?) 
              source_issue.category = default_category
            end
            if (source_issue.category.nil?) 
              flash[ :error ] = 'No valid default Issue Category and none set for this issue. Please ask your System Administrator to resolve this (or set for all tasks in the XML).'
            end
            
            # Add the category entry if necessary
            category_entry = IssueCategory.find :first, :conditions => { :project_id => @project.id, :name => source_issue.category }
            
            if (category_entry.nil?)
              # Need to create it
              category_entry = IssueCategory.new do |i|
                i.name = source_issue.category
                i.project_id = @project.id
              end
              
              category_entry.save!
            end
            
            #
            # Find any issue for this project that 'matches' this one
            #
            existing_issue = Issue.find(:first, :conditions => ["project_id = ? and subject = ? and tracker_id=?", @project.id, source_issue.title.slice(0,255), default_tracker_id])
            
            #
            # Either populate and save a new issue, or update existing
            #
            if existing_issue.nil? then
              
              destination_issue          = Issue.new do |i|
                i.tracker_id = default_tracker_id
                i.category_id = category_entry.id
                i.subject    = source_issue.title.slice(0, 255) # Max length of this field is 255
                i.description = source_issue.notes unless source_issue.notes.nil?
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
              
            else
              # Delete all pre-existing dependencies for this issue
              issue_relation_list = IssueRelation.find(:all, :conditions => ["issue_to_id = ?", existing_issue.id])
              issue_relation_list.each do | issue_relation |
                issue_relation.destroy
              end
              # Update existing
              existing_issue.category_id = category_entry.id unless category_entry.id.nil?
              existing_issue.description = source_issue.notes unless source_issue.notes.nil?
              existing_issue.estimated_hours = source_issue.duration unless source_issue.duration.nil?
              existing_issue.done_ratio = source_issue.percentcomplete unless source_issue.percentcomplete.nil?
              # This is a kludge TODO: figure out why this is sometimes needed. probably stupid arithmetic for finish/duration.
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
          end # to_import.each
          # Now note the parent issue ids 
          to_import.each do | source_issue |
            next if source_issue.uid == "0" # Ignore top level issue, probably parent to all
            source_id = uidToIssueIdMap[source_issue.uid]
            parent_id = uidToIssueIdMap[source_issue.parent]
            next if source_id.nil? || parent_id.nil?
            existing_issue = Issue.find_by_id(source_id)
            parent_issue = Issue.find_by_id(parent_id)
            next if existing_issue.nil? || parent_issue.nil? # probably a milestone or malformed entry in the XML
            existing_issue.parent_issue_id = parent_id
            existing_issue.save!
          end          
          
          # Build up the dependencies being careful if the related issue doesn't exist
          to_import.each do | source_issue |
            source_issue.predecessors.each do | predecessor_uid |
              if ( uidToIssueIdMap.has_key?(predecessor_uid) )
                # Parent is being imported also.  Go ahead and confirm the association
                unless (IssueRelation.find(:all, :conditions => ["issue_from_id = ? and issue_to_id = ?", uidToIssueIdMap[predecessor_uid], uidToIssueIdMap[source_issue.uid]]))
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
        end  
        # Now do something with milestones
        
        # All good.
        flash[ :notice ] = "#{ to_import.length } #{ to_import.length == 1 ? 'task' : 'tasks' } imported successfully."
        
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
  
  # Is the current action permitted?
  
  def find_project
    # @project variable must be set before calling the authorize filter
    @project = Project.find(params[:project_id])
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
          struct.notes           = task.get_elements( 'Notes'        )[ 0 ].text unless task.get_elements( 'Notes' )[ 0 ].nil?
          milestones.push( struct )
        else
          struct.tid             = task.get_elements( 'ID'           )[ 0 ].text.to_i
          struct.uid             = task.get_elements( 'UID'          )[ 0 ].text.to_i
          struct.level           = task.get_elements( 'OutlineLevel' )[ 0 ].text.to_i
          struct.title           = task.get_elements( 'Name'         )[ 0 ].text.strip
          struct.start           = task.get_elements( 'Start'        )[ 0 ].text.split("T")[0] unless task.get_elements( 'Start' )[ 0 ].nil?
          struct.notes           = task.get_elements( 'Notes'        )[ 0 ].text unless task.get_elements( 'Notes' )[ 0 ].nil?
          struct.summary         = 0
          struct.summary         = task.get_elements( 'Summary'      )[ 0 ].text.to_i unless task.get_elements( 'Summary'      )[ 0 ].nil?
          struct.work            = task.get_elements( 'Work'         )[ 0 ].text.strip unless task.get_elements( 'Work' )[ 0 ].nil?
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
          
          struct.duration = ( ( ( hours * 3600 ) + ( mins * 60 ) + secs ) / 3600 ).prec_f
          
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
        puts "Malformed resource:" + name
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
  
  
end # class LoaderController
