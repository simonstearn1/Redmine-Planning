module LibSections

  # Initialise the section discovery mechanism. Call this before processing
  # rows. Then, for each row, call "new_section?" to find out if a new
  # section has been entered with the given row, "section_title" to discover
  # its title, then "new_group?" to find out if there is also a new group
  # within the section (if you wish to make such a distinction).
  #
  # Instance variables are used to record progress across calls. These are:
  #
  #   @sections_last_project  (internal state)
  #   @sections_last_group    (internal state)
  #   @sections_current_index (internal state)
  #
  # Calling code must avoid these variable names.
  #
  # Each new section is given a monotonically rising index value, starting at
  # zero. Use the "section_index" method to read the current section's index.

  def sections_initialise_sections
    @sections_last_project  = false
    @sections_last_group    = false
    @sections_current_index = -1
  end

  # See "initialise_sections" for details; call here, passing a issue related
  # to the currently processed row, to find out if this issue (and therefore
  # its associated row) are the first row in a new section. Returns 'true' if
  # so, else 'false'.

  def sections_new_section?( issue )
    this_project  = issue.project

    changed = ( this_project != @sections_last_project )

    if ( changed )
      @sections_last_project   = this_project
      @sections_last_group     = sections_group_title( issue )
      @sections_current_index += 1
    end

    return changed
  end

  # If "new_section?" returns 'true', call here to return a title appropriate
  # for this section (it'll be based on customer and project name set up by
  # the prior call to "new_section?"). If using in an HTML view, ensure you
  # escape the output using "h" / "html_escape".

  def sections_section_title
    if ( @sections_last_project.nil? )
      return 'No project'

    else
      return "#{ @sections_last_project.name }"
    end
  end

  # Return the section index of the current section. Call any time after at
  # least on prior call to "new_section?" (regardless of the return value of
  # that prior call).

  def sections_section_index
    return @sections_current_index
  end

  # Similar to "new_section?", except returns 'true' when the issue title
  # indicates a group. A issue title includes a group name if the title has at
  # least one ":" (colon) character in it. Any part of the title before the
  # first colon is considered a group name. View code usually makes only a
  # subtle disctinction for changes in group, e.g. an extra vertical spacer,
  # but if you want to explicitly show new group names then you can do so by
  # calling "group_title" to recover the name string.
  #
  # Unlike sections, groups are not given unique indices.

  def sections_new_group?( issue )
    this_group = sections_group_title( issue )

    changed = ( this_group != @sections_last_group )
    @sections_last_group = this_group if changed

    return changed
  end

  # Return the group name inferred from the given issue title, or 'nil' for no
  # apparent group name in the issue title. See "new_group?" for details. The
  # method is called "group_title" rather than "group_name" for symmetry with
  # "section_title" - it's more natural when writing caller code to remember
  # (or guess at!) a name of "group_title".

  def sections_group_title( issue )
    this_group = nil
    issue_title = issue.subject || ''
    colon      = issue_title.index( ':' )
    this_group = issue_title[ 0..( colon - 1 ) ] unless ( colon.nil? )

    return this_group
  end

end
