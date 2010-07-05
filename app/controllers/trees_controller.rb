class TreesController < ApplicationController

  # Import the Tasks Helper methods into an object stored in a class variable.

  @@tasks_helper = Object.new.extend( TimesheetsHelper )

  # Respond to XHR requests from the YUI tree handling task selection. See
  # comments inside for details of the required parameters.
  #
  def index
    if ( request.xhr? && params.has_key?( :tree_parent_id ) )
      respond_to do | format |
        format.js do

          # Discover the restrictions which apply, if any. Understood keys are:
          #
          #   "inactive"   Returns only inactive projects and tasks. Without
          #                this key, returns only active projects and tasks.
          #
          #   "restrict"   Next array entry must be a user ID. Restricts tasks
          #                to those in the user's task list and projects to
          #                those where at least one of the project tasks are
          #                in the user's task list.
          #
          #   "include"    Next array entry must be one or more underscore-
          #                separated IDs. Only tasks in that list will be
          #                included in the tree. Projects or customers which
          #                end up with no included tasks will not be shown.
          #
          # Note that only tasks permitted by the current user will ever be
          # returned. All the above can do is produce subsets. Attempts to
          # bypass user restrictions by generating custom XHR requests will
          # therefore always fail.

          restrictions  = ( params[ :data ] || '' ).split( ',' )
          index         = 0

          restrict_user = nil
          include_only  = nil
          active        = :active

          until ( restriction = restrictions[ index ] ).nil?
            case restriction

              when 'inactive'
                active = :inactive

              when 'restrict'
                restrict_user = User.find( restrictions[ index + 1 ] )
                index += 1

              when 'include'
                include_only = restrictions[ index + 1 ].split( '_' ).map { | str | str.to_i }
                index += 1

            end
            index += 1
          end

          # Unless the current user is privileged, then always act as if the
          # task list is restricted by them. If the restricted user quoted in
          # the parameters is different then someone is probably trying to hack
          # around with the XHR call! Just override their request.

          restrict_user = User.current unless ( User.current.admin? )

          # Find the ID of the parent item selected in the tree. This must have
          # a textual prefix of 'C' or 'P' for Customers or Projects. Tasks
          # should never end up causing a call into this code because they are
          # always leaf nodes.

          id       = params[ :tree_parent_id ]
          children = []


          isLeaf   = false
          children = Project.find(:all, :conditions => ['parent_id = ', id])

          # Reject projects if there are no active/inactive tasks; or if we
          # are restricting by a user's permitted task list and the union
          # of the project and user's task list is empty; or if we are
          # restricting by a list of IDs and the union of that list of IDs
          # and the project's task IDs is empty.

# TODO - validate this

          if ( children.empty? )
            render :json => []
          else
            children.map!() do | child |
              YuiTree::make_node_object(
                "#{ prefix }#{ child.id }",
                child.title,
                isLeaf,
                ( child.is_a?( Task ) ) ? @@tasks_helper.taskhelp_billable_class( child ) : nil
              )
            end

            render :json => children
          end
        end # format.js do
      end   # respond_to do | format |
    end     # if ( request.xhr? ... )
  end

end


