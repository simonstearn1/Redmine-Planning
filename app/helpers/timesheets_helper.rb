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
            content = link_to( content,  url_for( :controller => 'timesheets' ))
          else
            bgcolor = ' bgcolor="#ffaa77" class="not_committed"'
            content = link_to( content, url_for( :controller => 'timesheets', :action => 'edit', :id => timesheet.id ))
          end
        else
          if Timesheet.overdue(year, week [:week] )
            bgcolor = ' bgcolor="#CC0000" class="overdue"'
            content = link_to( content, url_for( :controller => 'timesheets', :action => 'create', :year => year, :week => week, :week_number => week[ :week ], :method => :post ))
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
    issue_info ={}

    unless issue_array.nil? || issue_array.empty?
      Issue.sort_by_augmented_title( issue_array )

      issue_array.each do | issue |
        project        = issue.project

        if ( issue_info[ :projects ][ project_id ].nil? && project )
          issue_info[ :projects ][ project_id ] = {
            :title => project.name,
            :code => project.identifier,
            :issues => {}
          }
        end

        if project
          issue_info[ :projects ][ project_id ][ :issues ][ issue.id ] = {
            :title => issue.subject,
            :code  => issue.id
          }
        end
      end
    end

    return issue_info if issue_info
    
    return issue_info[:projects][0][:issues][0] = {:title => 'No issues defined', :code => 0}

  end
  
  # Setup default issue list
  
  def default_issuelist( timesheet )
    
    if timesheet.nil?
      return []
    end
    
    week  = timesheet.week_number - 1
    year = timesheet.year
    
    if week == 0
      year -= 1
      week = Timesheet.get_last_week_number( year )
    end
    
    issues = Issue.find(:all, :conditions => ['id in (select issue_id from time_entries where tweek = ? and tyear = ? and user_id = ?)', week, year, timesheet.user_id])    

    issues = issues.nil? ? [] : issues

    return issues

  end 
  
    # Generate a YUI tree issue selector. Pass a form builder object in the first
  # parameter (e.g. "bar" in "form_for @foo do | bar |"). The "object_name"
  # field is used to generate a unique ID and name for a hidden element which
  # carries IDs of selected YUI tree nodes, in the form "name[issue_ids][]" - as
  # used by non-JS SELECT lists elsewhere. In the form submission processing
  # code, you must handle the use of special IDs in the YUI tree ("P" prefix
  # for Projects, "C" prefix for Customers, no prefix for issues).
  #
  # In the next parameter optionally pass an options hash with keys and values
  # as shown below; any omitted key/value pair results in the described default
  # value being used instead.
  #
  #   Key              Meaning
  #   =========================================================================
  #   :inactive        If 'true', only inactive issues, customers and projects
  #                    are shown in the selector. By default, only active items
  #                    will be shown.
  #
  #   :restricted_by   The issue/project/customer list for currently logged in
  #                    users who are restricted is always restricted by that
  #                    user's permitted issue list no matter what you set here.
  #                    If the current user is privileged, though, then passing
  #                    in a User object results in restriction by that user's
  #                    permitted issue list. By default there is no restriction
  #                    so for privileged currently logged in users, all issues
  #                    would be shown.
  #
  #   :included_issues  If you know up-front a full list of issues to show, then
  #                    pass them in here. Only items in the included list will
  #                    be shown. IDs get passed to the XHR handler, among other
  #                    things. This is NOT a security feature - see
  #                    ":restricted_by" for that.
  #
  #   :selected_issues  An array of issues to be initially selected in the tree.
  #                    May be empty. By default no issues are selected. Ideally
  #                    the list should include no issues that the current user
  #                    or 'restricted_by' key would hide, but if it does, they
  #                    simply won't be shown or selected and only the issue IDs
  #                    will appear in HTML output.
  #
  #   :suffix_html     Beneath the text area gadget listing selected issues is
  #                    a "Change..." link which pops up the Leightbox overlay
  #                    containing the YUI tree. If you want any extra HTML
  #                    inserted directly after the "</a>" of this link but
  #                    before the (hidden) DIV enclosing the tree, use this
  #                    option to include it. To keep things tidy, ensure that
  #                    the string is terminated by a newline ("\n") character.
  #
  #   :change_text     Speaking of the "Change..." link - alter its text with
  #                    this option, or omit for the default "Change..." string.
  #
  #   :params_name     Name to use in params instead of "issue_ids", so that
  #                    instead of reading "params[form.object_name][:issue_ids]"
  #                    in the controller handling the form submission, you read
  #                    the params entry corresponding to the given name.
  #
  # See also "degrading_selector" for JS/non-JS degrading code.
  #
  def tree_selector( form, options = {} )

    inactive       = options.delete( :inactive       )
    restricted_by  = options.delete( :restricted_by  )
    included_issues = options.delete( :included_issues )
    selected_issues = options.delete( :selected_issues ) || []
    suffix_html    = options.delete( :suffix_html    ) || ''
    change_text    = options.delete( :change_text    ) || 'Change...'
    params_name    = options.delete( :params_name    ) || :issue_ids

    # Callers may generate trees restricted by the current user, but if that
    # user is themselves privileged their restricted issue list will be empty
    # (because they can see anything). The simplest way to deal with this is
    # to clear the restricted user field in such cases.

    restricted_by = nil #unless ( restricted_by.nil? || restricted_by.restricted? )

    # Based on the restricted issue list - or otherwise - try to get at the root
    # customer array as easily as possible, trying to avoid pulling all issues
    # out of the database. This is a bit painful either way, but usually a
    # restricted user will have a relatively small set of issues assigned to
    # them so doing the array processing in Ruby isn't too big a deal.

#    if ( @current_user.restricted? )
#      permitted_issues = User.current.active_permitted_issues()
#    else
#      permitted_issues = restricted_by.active_permitted_issues() unless ( restricted_by.nil? )
#   end

    # Maybe more rules here..
    permitted_issues = Timesheet.default_issues

    unless ( included_issues.nil? )
      if ( permitted_issues.nil? )
        permitted_issues  = included_issues
      else
        permitted_issues &= included_issues
      end
    end

    root_projects  = permitted_issues.map { | issue    | issue.project     }.uniq
    root_customers = root_projects.reject { | project | !project.parent_id.nil? }.uniq
    root_projects.reject! { | project | project.parent_id.nil? }


    # Now take the selected issue list and do something similar to get at the
    # selected project and customer IDs so we can build a complete list of the
    # node IDs to be initially expanded and checked in the YUI tree. The
    # customer list is sorted so that when the YUI tree starts expanding nodes,
    # it does it in display order from top to bottom - this looks better than
    # an arbitrary expansion order.

    selected_projects     = selected_issues.map    { | issue    | issue.project     }.uniq
    selected_customers    = selected_projects.reject { | project | !project.parent_id.nil? }.uniq
    selected_projects.reject! { | project | project.parent_id.nil? }

    selected_issue_ids     = selected_issues.map   { | item | item.id        }
    selected_project_ids  = selected_projects.map  { | item | "#{ item.id }" }
    selected_customer_ids = selected_customers.map { | item | "#{ item.id }" }

    selected_ids = selected_customer_ids + selected_project_ids + selected_issue_ids

    # Turn an included issue list into IDs too, if present

    included_ids = ( included_issues || [] ).map { | item | item.id }

    # Generate the root node data and extra XHR parameters to pass to the tree
    # controller in 'tree_controller.rb'.

    roots = root_customers.map do | customer |
      {
        :label  => customer.name,
        :isLeaf => false,
        :id     => "#{ customer.identifier }"
      }
    end
    
    if roots.nil? || roots.empty?
      roots = root_projects.map do | project |
        {
          :label  => project.name,
          :isLeaf => false,
          :id     => "#{ project.identifier }"
        }
      end
    end


    data_for_xhr_call  = []
    data_for_xhr_call << 'inactive' if ( inactive )
 #   data_for_xhr_call << "restrict,#{ restricted_by.id }" unless ( restricted_by.nil? )
    data_for_xhr_call << "include,#{ included_ids.join( '_' ) }" unless ( included_ids.empty? )

    # Create and (implicitly) return the HTML.

    id   = "#{ form.object_name }_#{ params_name }"
    name = "#{ form.object_name }[#{ params_name }][]"
    tree = yui_tree(
      :multiple             => true,
      :target_form_field_id => id,
      :target_name_field_id => "#{ id }_text",
      :name_field_separator => "\n", # Yes, a literal newline character
      :name_include_parents => ' &raquo; ',
      :name_leaf_nodes_only => true,
      :form_leaf_nodes_only => true,
      :expand               => selected_ids,
      :highlight            => selected_ids,
      :propagate_up         => true,
      :propagate_down       => true,
      :root_collection      => roots,
      :data_for_xhr_call    => data_for_xhr_call.join( ',' ),
      :div_id               => 'yui_tree_container_' << id
    ).gsub( /^/, '  ' )
    html = <<HTML
<textarea disabled="disabled" rows="5" cols="60" class="tree_selector_text" id="#{ id }_text">issue data loading...</textarea>
<br />
<a href="#leightbox_tree_#{ id }" rel="leightbox_tree_#{ id }" class="lbOn">#{ change_text }</a>
#{ suffix_html }<div id="leightbox_tree_#{ id }" class="leightbox">
  <a href="#" class="lbAction" rel="deactivate">Close</a>
  <p />
  #{ hidden_field_tag( id, selected_issue_ids.join( ',' ), { :name => name } ) }
#{ tree }
  <a href="#" class="lbAction" rel="deactivate">Close</a>
</div>
HTML
  end

  # Create a degrading issue selector using either a YUI tree or a SELECT list,
  # but not both. The latter has high database load. The former has greater
  # client requirements.
  #
  # The use cases for issue selectors in Track Record are so varied that very
  # specific cases are handled with special-case code and HTML output may
  # include extra text to help the user for certain edge conditions, such as
  # a lack of any available issues (in a timesheet editor, this may be because
  # all issues are already added to the timesheet; for a user's choice of the
  # default list of issues to show in timesheets, this may be because the user
  # has no permission to view any issues; when configuring the issues which a
  # restricted user is able to see, this may be because no active issues exist).
  #
  # As a result, pass the reason for calling in the first parameter and an
  # options list in the second.
  #
  # Supported reasons are symbols and listsed in the 'case' statement in the
  # code below. Each is preceeded by comprehensive comments describing the
  # mandatory and (if any) optional key/value pairs which should go into the
  # options hash. Please consult these comments for more information.
  #
  # The following global options are also supported (none are mandatory):
  #
  #   Key           Value
  #   =====================================================================
  #   :line_prefix  A string to insert at the start of each line of output
  #                 - usually spaces, used if worried about the indentation
  #                 of the overall view HTML.
  #
  def degrading_selector( reason, options )
    output = ''
    form   = options.delete( :form )
    user   = options.delete( :user )

    case reason

      # Generate a selector used to add issues to a given timesheet. Includes a
      # issue selector and "add" button which submits to the given form with
      # name "add_row". The timesheet and form are specified in the options:
      #
      #   Key         Value
      #   =====================================================================
      #   :form       Prevailing outer form, e.g. the value of "f" in a view
      #               which has enclosed the call in "form_for :foo do | f |".
      #
      #               Leads to "issue_ids" being invoked on the model associated
      #               with the form to determine which items, if any, must be
      #               initially selected for lists in the non-JS page version.
      #
      #   :timesheet  Instance of the timesheet being edited - used to find out
      #               which issues are already included in the timesheet and
      #               thus which, if any, should be offered in the selector.
      #
      # NOTE: An empty string is returned if all issues are already included in
      # the timesheet.
      #
      when :timesheet_editor
        issues = issues_for_addition( options[ :timesheet ] )

        unless ( issues.empty? )

# TODO - detect browser javascript
          if ( false )
            Issue.sort_by_augmented_title( issues )
            output << collection_select( form, :issue_ids, issues, :id, :augmented_title )
            output << '<br />'
            output << form.submit( 'Add', { :name => 'add_row', :id => nil } )
          else
            output << tree_selector(
              form,
              {
                :included_issues => issues,
                :change_text    => 'Choose issues...',
                :suffix_html    => " then #{ form.submit( 'add them', { :name => 'add_row', :id => nil } ) }\n"
              }
            )
          end

        end

      # Generate a selector used to add issues to a given report. The report and
      # form are specified in the following options:
      #
      #   Key        Value
      #   =====================================================================
      #   :form      Prevailing outer form, e.g. the value of "f" in a view
      #              which has enclosed the call in "form_for :foo do | f |".
      #
      #              Leads to "issue_ids" being invoked on the model associated
      #              with the form to determine which items, if any, must be
      #              initially selected for lists in the non-JS page version.
      #
      #   :report    Instance of the report being created - used to find out
      #              which issues are already included in the report (for form
      #              resubmissions, e.g. from validation failure).
      #
      #   :inactive  If 'true', the selector is generated for inactive issues
      #              only. If omitted or 'false', only active issues are shown.
      #
      #   :name      A name to use instead of "issue_ids" in the form submission
      #              - optional, required if you want multiple selectors in the
      #              same form.
      #
      # NOTE: All edge case conditions (no issues, etc.) are handled internally
      # with relevant messages included in the HTML output for individual
      # selectors, but the caller ought to check that at least *some* issues can
      # be chosen before presenting the user with a report generator form.
      #
      when :report_generator
        report =   options[ :report   ]
        active = ( options[ :inactive ] != true )
        field  = active ? :active_issue_ids : :inactive_issue_ids

# TODO - detect browser javascript
          if ( false )
          issues = active ? issue.active() : issue.inactive()
          count = issues.length
        else
          issues = active ? report.active_issues : report.inactive_issues
          count = @current_user.all_permitted_issues.count
        end

        if ( count.zero? )

          hint = active ? :active : :inactive
          output << "No #{ hint } issues are available."

        else

# TODO - detect browser javascript
          if ( false )
            issue.sort_by_augmented_title( issues )
            output << apphelp_collection_select(
              form,
              field,
              issues,
              :id,
              :augmented_title
            )
          else
            output << tree_selector(
              form,
              {
                :selected_issues => issues,
                :params_name    => field,
                :inactive       => ! active
              }
            )
          end
        end

      # Generate a selector which controls the default issue list shown in
      # new timesheets.
      #
      #   Key    Value
      #   =====================================================================
      #   :user  Instance of User model for the user for whom default timesheet
      #          options are being changed.
      #
      #   :form  Prevailing outer form, e.g. the value of "f" in a view
      #          which has enclosed the call in "form_for :foo do | f |".
      #          Typically this is used by a User configuration view, though,
      #          where a nested set of fields are being built via something
      #          like "fields_for :control_panel do | cp |". In such a case,
      #          use "cp" for the ":form" option's value.
      #
      #          This leads to "issue_ids" being invoked on the model associated
      #          with the form to determine which items in the selection list,
      #          if any, must be initially selected in the non-JS page version.
      #
      # NOTE: All edge case conditions (no issues, etc.) are handled internally
      # with relevant messages included in the HTML output.
      #
      when :user_default_issue_list

        if ( Issue.default.count.zero? )

          # Warn that the user has no permission to see any issues at all.

          output << "This account does not have permission to view\n"
          output << "any active issues.\n"
          output << "\n\n"
          output << "<p>\n"

          # If the currently logged in user is unrestricted, tell them how to
          # rectify the above problem. Otherwise, tell them to talk to their
          # system administrator.

          if ( !User.current.admin? )
            output << "  Please contact your system administrator for help.\n"
          else
            output << "  To enable this section, please assign issues to\n"
            output << "  the user account with the security settings above\n"
            output << "  and save your changes. Then edit the user account\n"
            output << "  again to see the new permitted issue list.\n"
          end

          output << "</p>"

        else

# TODO - detect browser javascript
          if ( false )
            issues = user.active_permitted_issues
            issue.sort_by_augmented_title( issues )
            output << apphelp_collection_select( form, :issue_ids, issues, :id, :augmented_title )
          else
            output << tree_selector(
              form,
              {
                :restricted_by  => ( user.restricted? ) ? user : nil,
                :selected_issues => user.control_panel.issues
              }
            )
          end

        end

      # Generate a selector which controls the list of issues the user is
      # permitted to see. Mandatory options:
      #
      #   Key    Value
      #   =====================================================================
      #   :user  Instance of User model for the user to whom issue viewing
      #          permission is being granted or revoked.
      #
      #   :form  Prevailing outer form, e.g. the value of "f" in a view
      #          which has enclosed the call in "form_for :foo do | f |".
      #
      #          This leads to "issue_ids" being invoked on the model associated
      #          with the form to determine which items in the selection list,
      #          if any, must be initially selected in the non-JS page version.
      #
      # NOTE: All edge case conditions (no issues, etc.) are handled internally
      # with relevant messages included in the HTML output.
      #
      when :user_permitted_issue_list
        return '' if ( !User.current.admin? ) # Privileged users only!

        if ( issue.active.count.zero? )

          output << "There are no issues currently defined. Please\n"
          output << "#{ link_to( 'create at least one', url_for(:controllers => 'issues', :action => 'new' ) ) }."

        else

# TODO - detect browser javascript
          if ( false )
            issues = Issue.default
            issue.sort_by_augmented_title( issues )
            output << collection_select( form, :issue_ids, issues, :id, :augmented_title )
          else

            # Don't use "user.[foo_]permitted_issues" here as we *want* an empty
            # list for privileged accounts where no issues have been set up.

            output << tree_selector(
              form,
              { :selected_issues => Issue.default }
            )
          end

          if ( User.current.admin? )
            output << "\n\n"
            output << "<p>\n"
            output << "  This list is only enforced for users with a\n"
            output << "  'Normal' account type. It is included here\n"
            output << "  in case you are intending to change the account\n"
            output << "  type and want to assign issues at the same time.\n"
            output << "</p>"
          end

        end
    end

    # All done. Indent or otherwise add a prefix to each line of output if
    # so required by the options and return the overall result.

    line_prefix = options.delete( :line_prefix )
    output.gsub!( /^/, line_prefix ) unless ( output.empty? || line_prefix.nil? )

    return output
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