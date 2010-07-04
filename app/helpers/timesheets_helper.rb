module TimesheetsHelper

  include LibSections
  
  # Output HTML suitable as a label to show whether or not the
  # given timesheet is committed or otherwise. The second parameter
  # lets you override the given timesheet and force the generation of
  # a committed (pass 'true') or not committed (pass 'false') label.

  def commit_label( timesheet, committed = nil )
    committed = @timesheet.committed if ( committed.nil? )
    committed ? '<span class="timesheet_committed">Committed</span>' :
                '<span class="timesheet_not_committed">Not Committed</span>'
  end
  
# Return a year chart for the given year. This is a complete table of
  # months down the left and week numbers with dates of the first week in
  # individual cells along the monthly rows. Months indicate the month of
  # the first day of the week in that year, so in week 1 will often be for
  # the previous year (which is clearly indicated in the table). Cell
  # colours indicate the condition of a timesheet for each week with links
  # to edit the existing timesheets or create new timesheets as necessary.

  def year_chart( year )
    week_range = 1..( Timesheet.get_last_week_number( year ) )
    first_day  = TimesheetRow::FIRST_DAY
    months     = Hash.new

    # Compile a hash keyed by year/month number which points to arrays of
    # week numbers with start date. The length of each keyed entry indicates
    # the number of weeks in that month. Key names are sortable by default
    # sort function behaviour to provide a date-ascending list.

    week_range.each do | week |
      start_date = Timesheet.date_for( year, week, first_day, true )
      key        = "#{ start_date.year }-%02i" % start_date.month
      data       = { :week => week, :start_date => start_date }

      if ( months[ key ].nil? )
        months[ key ] = [ data ]
      else
        months[ key ].push( data )
      end
    end

    # Now run through the collated data to build the chart, working on the
    # basis of the sorted keys in the hash for each row and a maximum of 5
    # weeks in any of those rows. Blank entries are put at the start of a
    # row to make up 5 columns in case there aren't that many weeks in that
    # particular month.

    keys      = months.keys.sort
    row_class = 'even'
    output    = "<table class=\"timesheet_chart\" border=\"0\" cellspacing=\"0\" cellpadding=\"4\">\n"
    output   << "  <tr><th>Month</th><th colspan=\"5\">Week start date and number</th></tr>\n"

    keys.each do | key |
      data      = months[ key ]
      row_start = data[ 0 ][ :start_date ]

      heading = "#{ Date::MONTHNAMES[ row_start.month ] } "<<
                "#{ row_start.year }"

      row_class = ( row_class == 'even' ) ? 'odd' : 'even'
      row_class = row_class + ' last' if ( key == keys.last )

      output << "  <tr valign=\"middle\" class=\"#{ row_class }\">\n"
      output << "    <td class=\"timesheet_chart_month\" align=\"left\">#{ heading }</td>\n"
      output << "    <td align=\"center\">&nbsp;</td>\n" * ( 5 - data.length )

      data.each do | week |
        timesheet = Timesheet.find_by_user_id_and_year_and_week_number(
          User.current.id,
          year,
          week[ :week ]
        )

        bgcolor = ''
        content = "#{ week[ :start_date ].day }" <<
                  " #{ Date::ABBR_MONTHNAMES[ week[ :start_date ].month ] }" <<
                  " (#{ week[ :week ] })"

        if ( timesheet )
          if ( timesheet.committed )
            bgcolor = ' bgcolor="#77cc77" class="committed"'
            content = link_to( content,  url_for( :controller => 'timesheets' ) )
          else
            bgcolor = ' bgcolor="#ffaa77" class="not_committed"'
            content = link_to( content, url_for( :controller => 'timesheets', :action => 'edit', :id => timesheet.id ) )
          end
        else
          content = button_to(
            content,
            {
              :action      => :create,
              :method      => :post,
              :year        => year,
              :week_number => week[ :week ]
            }
          )
        end

        output << "    <td align='center'#{ bgcolor }>#{ content }</td>\n"
      end

      output << "  </tr>\n"
    end

    return output << '</table>'
  end
  
  #
  #
  
 def list_header( structure, model, actions_method )
    output = "        <tr valign=\"middle\" align=\"left\" class=\"info\">\n"

    structure.each_index do | index |
      entry      = structure[ index ]
      align      = entry[ :header_align ]
      sort_class = nil

      if ( params[ :sort ] == index.to_s )
        if ( params[ :direction ] == 'desc' )
          sort_class = "sorted_column_desc"
        else
          sort_class = "sorted_column_asc"
        end
      end

      output << "          <th"
      output << " class=\"#{ sort_class }\"" unless ( sort_class.nil? )

      if ( align.nil? )
        output << ">" if ( align.nil? )
      else
        output << " align=\"#{ align }\">"
      end

      if ( entry[ :value_method ] or entry[ :sort_by ] )
        output << list_header_link( model, entry[ :header_text ], index )
      else
        output << entry[ :header_text ]
      end

      output << "</th>\n"
    end

    output << "          <th width=\"1\">&nbsp;</th>\n" unless ( actions_method.nil? )
    return ( output << "        </tr>\n" )
  end
  
  #
  #
  #
  
 def list_row( structure, item, actions_method )
    output = "        <tr valign=\"top\" align=\"left\" class=\"#{ cycle( 'even', 'odd' ) }\">\n"

    # Handle the item columns first

    structure.each_index do | index |
      entry = structure[ index ]
      align = entry[ :value_align ]

      output << "          <td"

      if ( align.nil? )
        output << ">" if ( align.nil? )
      else
        output << " align=\"#{ align }\">"
      end

      method = entry[ :value_method ]
      helper = entry[ :value_helper ]

      if ( helper )
        output << send( helper, item )
      else

        # Restricted users can only edit their own account. Since they are not
        # allowed to list other users on the system, the list view is disabled
        # for them, so there can never be in-place editors in that case. For
        # any other object type, restricted users have no edit permission. The
        # result? Disable all in-place editors for restricted users.

        in_place = entry[ :value_in_place ] && User.current.admin?

        if ( in_place )
          output << safe_in_place_editor_field( item, method )
        else
          output << h( item.send( method ) )
        end
      end

      output << "</td>\n"
    end

    # Add the actions cell?

    unless ( actions_method.nil? )
      actions = [] # send( actions_method, item ) || []
      output << "          <td class=\"list_actions\" nowrap=\"nowrap\">\n"
      actions.each do | action |
        output << "            "
        output << link_to( action.humanize, { :action => action, :id => item.id } )
        output << "\n"
      end
      output << "          </td>\n"
    end

    return ( output << "        </tr>\n" )
  end
  # Return HTML suitable for inclusion in the form passed in the
  # first parameter (i.e. the 'f' in "form for ... do |f|" ), based
  # on the timesheet given in the second parameter, which provides:
  #
  # * A <select> tag listing available week numbers, with dates,
  #   which may be assigned to the timesheet.
  #
  # * An empty string if there are no free weeks - the edit view
  #   should never have been shown, but never mind...!

  def week_selection( form, timesheet )
    weeks = timesheet.unused_weeks();

    if ( weeks.empty? )
      return ''
    else
      return form.select(
        :week_number,
        weeks.collect do | week |
          [
            "#{ week } (#{ Timesheet.date_for( timesheet.year, week, TimesheetRow::FIRST_DAY ) })",
            week
          ]
        end
      )
    end
  end

  # Return an array of issues suitable for timesheet row addition.
  # Will be empty if all issues are already included, or no issues are
  # available for any other reason. Pass the timesheet of interest.

  def issues_for_addition( timesheet )
    issues = []
    
    default_tracker_id = Tracker.find(:first, :conditions => [ "id = ?", Setting.plugin_redmine_planning['tracker']]).id
    
    Issue.visible.each do | issue |
      if issue.tracker.id == default_tracker_id && !issue.status.is_closed
        issues << issue
      end
    end
    
    issues = issues -timesheet.issues
    return issues
  end
  
  
  # Return HTML suitable for inclusion in the form passed in the
  # first parameter (i.e. the 'f' in "form for ... do |f|" ), based
  # on the issue array given in the second parameter, which provides:
  #
  # * A <select> tag with options listing all issues not already used
  #   by this timesheet.
  #
  # * An empty string if the timesheet already has rows for every
  #   issue presently stored in the system.

  def issue_selection( form, issues )
    if ( issues.empty? )
      return ''
    else
      Issue.sort_by_augmented_title( issues )

      return collection_select(
        form,
        'issue_ids',
        issues,
        :id,
        :augmented_title
      )
    end
  end

  # Support function for list_header.
  #
  # Returns an HTML link based on a URL acquired by calling "models_path",
  # where "models" comes from pluralizing the given lower case singular
  # model name, wrapping the given link text (which will be protected in turn
  # with a call to "h(...)"). Pass also the index of the column in the list
  # structure. Generates a link with query string attempting to maintain or
  # set correctly the sort and pagination parameters based on the current
  # request parameters and given column index.
  #
  # E.g.:
  #
  #   list_header_link( 'users_path', 'User name', 0 )

  def list_header_link( model, text, index )

    # When generating the link, there is no point maintaining the
    # current page number - reset to 1. Do maintain the entries count.

    entries   = ''
    entries   = "&entries=#{ params[ :entries ] }" if params[ :entries ]

    # For the direction, if the current sort index in 'params' matches
    # the index for this column, the link should be used to toggle the
    # sort order; if currently on 'asc', write 'desc' and vice versa.
    # If building a link for a different column, default to 'asc'.

    direction = ''

    if ( params[ :sort ] == index.to_s && params[ :direction ] == 'asc' )
      direction = '&direction=desc'
    else
      direction = '&direction=asc'
    end

    # Get the base URL using the caller-supplied method and assemble the
    # query string after it.

    base = url_for( :controller => 'timesheets', :action => 'show', :id => model.id)
    url  = "#{ base }?sort=#{ index }#{ direction }&page=1#{ entries }"

    unless ( params[ :search ].nil? or params[ :search ].empty? )
      url << "&search=#{ params[ :search ] }"
    end

    return link_to( h( text ), url )
  end
  
  # Pass a string representation of worked hours or a duration and a string
  # to show instead of "0.0", if that's the duration/worked hours value.
  # Optionally, pass in a string to use instead of an empty string, should
  # the duration/worked hours value be empty itself.

  def string_hours( hours, alt_str, empty_str = nil )
    return ( empty_str ) if ( hours.empty? and not empty_str.nil? and not empty_str.empty? )
    return ( hours == '0.0' ? alt_str : hours )
  end

  def not_permitted
    flash[ :warning ] = 'Action not permitted'
    redirect_to( {:controller => 'timesheets', :action => 'show' } )
  end

  def help_delete( model )
    return not_permitted() unless ( @current_user.admin? )
    @record = model.constantize.find( params[ :id ] )
  end
  
  def delete_confirm( model )
    return not_permitted() unless ( @current_user.admin? )

    begin
      model.constantize.destroy( params[ :id ] )

      flash[ :notice ] = "Timesheet deleted"
      redirect_to( {:controller => 'timesheets', :action => 'show' } )

    rescue => error
      flash[ :error ] = "Could not destroy Timesheet: #{ error }"
      redirect_to( {:controller => 'timesheets', :action => 'index' } )

    end
  end




  # Return the timesheet description, or 'None' if it is empty.

  def always_visible_description( timesheet )
    if ( timesheet.description.nil? or timesheet.description.empty? )
      des = 'None'
    else
      des = h( timesheet.description )
    end

    return des
  end

  
  #############################################################################
  # LIST VIEWS
  #############################################################################

  # List helper - owner of the given timesheet

  def owner( timesheet )
    return link_to( timesheet.user.name, user_path( timesheet.user ) )
  end

  # List helper - formatted 'updated at' date for the given timesheet

  def updated_at( timesheet )
    return apphelp_date( timesheet.updated_at )
  end

  # List helper - formatted 'committed at' date for the given timesheet

  def committed_at( timesheet )
    if ( timesheet.committed )
      return parse_date( timesheet.committed_at )
    else
      return 'Not committed'
    end
  end

  # List helper - number of hours in total recorded in the given timesheet

  def hours( timesheet )
    return string_hours( timesheet.total_sum.to_s, '-', '-' )
  end

  # Return appropriate list view actions for the given timesheet

  def actions( timesheet )
    if ( @current_user.admin? )
      return [ 'edit', 'delete', 'show' ]
    elsif ( @current_user.manager? or timesheet.user_id == User.current.id )
      return [ 'show'         ] if ( timesheet.committed ) 
      return [ 'edit', 'show' ]
    else
      return []
    end
  end

  # Create a lightweight representation of the customer, project and issue
  # hierarchy in based on the array of issue objects passed in. issues with
  # no project are assigned to pseudo-project "(None)". Projects with no
  # customer are assigned to pseudo-customer "(None)". The issue list must
  # not be empty. All names are safe for HTML display.
  #
  # Format: First-level is a hash keyed by customer ID or 'none' for the
  # pseudo-customer. Values are in turn hashes with properties 'title',
  # the customer title, and 'projects'. The latter is a hash keyed by
  # project ID or 'none' for the pseudo-project. Values are in turn hashes
  # with properties 'title', the project title, and 'issues'. The latter is
  # a hash keyed by issue ID with a values of the issue titles.

  def structured_issue_list( issue_array )
    pseudo_customer_title = '(None)'
    pseudo_project_title  = '(None)'
    issue_info             = {}

    unless issue_array.nil? || issue_array.empty?
      Issue.sort_by_augmented_title( issue_array )

      issue_array.each do | issue |
        project        = issue.project
        project_title  = project.name

        project_id  = project.nil?  ? 'none' : project.id;

        if ( issue_info[ :projects ][ project_id ].nil? )
          issue_info[ customer_id ][ :projects ][ project_id ] = {
            :title => project_title,
            :code => project.identifier,
            :issues => {}
          }
        end

        issue_info[ :projects ][ project_id ][ :issues ][ issue.id ] = {
          :title => issue.subject,
          :code  => issue.id
        }
      end
    end

    return issue_info
  end

#
# Handle mis-hacked meta-programming.. probably a smarter way to do this..
#

  def timesheet_path (timesheet)
    return url_for(:controller => 'timesheets', :action => 'show', :id => timesheet.id)
  end
  
  def timesheethelp_owner (timesheet)
    return timesheet.user.firstname << " " << timesheet.user.lastname if !timesheet.nil? && !timesheet.user.nil?
    return ""
  end

  def timesheethelp_updated_at (timesheet)
    return timesheet.updated_at.asctime if !timesheet.nil? && !timesheet.updated_at.nil?
    return ""
  end
  
  def timesheethelp_committed_at (timesheet)
    return timesheet.committed_at.asctime if !timesheet.nil? && !timesheet.committed_at.nil?
    return ""
  end
    
    def timesheethelp_hours (timesheet)
    return timesheet.total_sum.to_s if !timesheet.nil? && !timesheet.total_sum.nil?
    return "0"
  end
    
end