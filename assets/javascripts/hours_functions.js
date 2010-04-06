/* 
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

var empty_hours_edited = false;
var saved_empty_hours_value = -1;

/**
 *
 */
//function getSelectedValue(selectElement)
//{
//  return selectElement.options[selectElement.selectedIndex].value;
//}

/**
 * Retrieve number of empty hours
 * same as displayed value, or 0
 */
function getEmptyHours()
{
  return empty_hours_number;
}

/**
 * Set visible number of empty hours
 */
function setEmptyHours(val)
{
  empty_hours_number = val;
}

/**
 * Retrieve number of hours scheduled
 * by the user for current day and project
 */
function previousHoursNumber()
{
  var previousHours = $('previouslyUsed');

  return previousHours == null ? 0 : parseFloat(previousHours.value);
}

/**
 * Retrieve number of hours used by the user
 * (empty + previous + scheduled)
 */
function getUsedHours()
{
  return previousHoursNumber() + getEmptyHours() + computeScheduledHours();
}

/**
 * Retrieve visible number of used hours
 */
function getVisibleUsedHours()
{
  var usedHours = $('usedHours');

  return usedHours == null ? 0 : (isNaN(usedHours.value) ? 0 : parseFloat(usedHours.value));
}

/**
 * Set visible number of used hours
 */
function setUsedHours(val)
{
  var usedHours = $('usedHours');

  usedHours.value = val;
}

function saveEmptyHours()
{
  var hours = parseFloat($('usedHours').value) - computeScheduledHours();

  var params = idToParams(_owner.id) + "&hours=" + hours.toString() +
  "&hours_to_schedule=" + $('usedHours').value;

  new Ajax.Request('/schedules/updateEmptyHours', {
    asynchronous: false,
    evalScripts: true,
    onComplete:function(response){
      if(null != $('emptyHoursSpan'))
      {
        if(hours > 0)
        {
          showEmptyHours(response.responseText);
        }else
        {
          hideEmptyHours();
        }
      }

      if(hours != 0 && getScheduledEntryHours() == 0)
      {
        $('schedule_entry_hours').value = hours;
      }
      updateEditfieldValue();
    },
    parameters:params
  });
}

function getAvailableHours()
{
  var ava = $('user_hours_left');
  
  return ava != null ? (isNaN(ava.innerHTML) ? 0 : ava.innerHTML) : 0;
}

/**
 *
 */
function showWarning()
{
  var totalUsed = getVisibleUsedHours() + previousHoursNumber();
  var availableHours = getAvailableHours();
  var warning = $('warningSpan');

  if(totalUsed > availableHours)
  {
    warning.innerHTML = $('warningMessage').value;
  }
  else
  {
    warning.innerHTML = "&nbsp;";
  }

  updateWindowSize('vert')
}

/**
 * Update empty hours element with proper value
 */
function showEmptyHours(empty_hours)
{
  $('emptyHoursSpan').update($('empty_hours_message').value +
    '<span id="emptyHours">' +
    empty_hours.toString() + '</span>');
}

/**
 * "Hide" empty hours element, updating it with "&nbsp;" value
 */
function hideEmptyHours()
{
  $('emptyHoursSpan').update('&nbsp;');
}

function saveUsedHoursValue()
{
  saved_empty_hours_value = $('usedHours').value;
}

var empty_hours_number = 0;

/**
 * Create or delete empty hours record
 * Update properly used hours number
 */
function updateEmptyHours()
{
  if($('usedHours').value == '')
  {
    $('usedHours').value = '0';
  }
  var usedHoursValue = isNaN($('usedHours').value) ? 0 : parseFloat($('usedHours').value);
  empty_hours_number = usedHoursValue - computeScheduledHours();
  if(!isNaN(empty_hours_number) && empty_hours_number > 0)
  {
    showEmptyHours(empty_hours_number);
  }else
  {
    hideEmptyHours();
  }
 
  var usedHours = getVisibleUsedHours();
  var scheduledHours = computeScheduledHours();

  if(usedHours < scheduledHours)
  {
    if(!isNaN(scheduledHours))
    {
      $('usedHours').value = scheduledHours;
    }
    else
    {
      $('usedHours').value = '0';
    }
  }
  if($('usedHours').value != saved_empty_hours_value && saved_empty_hours_value != -1)
  {
    empty_hours_edited = true;
  }
  
  $('schedule_entry_hours').value = $('usedHours').value;

  $('usedTotal').innerHTML = getVisibleUsedHours() + previousHoursNumber();
  _owner.value = getVisibleUsedHours();
  showWarning();

  updateTotalDayHours();
}

/**
 *
 */
function getScheduledEntryHours()
{
  var scheduleEntryHours = $('schedule_entry_hours');

  return scheduleEntryHours == null ? 0 : 
  isNaN(scheduleEntryHours.value) ? 0 : parseFloat(scheduleEntryHours.value);
}

function updateScheduledHours(owner_id, first)
{
  if(null == first)
  {
    first = false;
  }

  if(null != $(_owner))
  {
    if(!first)
    {
      edited = true;
    }
    var i = 1;

    var scheduledHours = computeScheduledHours(); //changed
    var emptyHours = getEmptyHours(); // getter from field (float value)
    var usedHours = getVisibleUsedHours(); // getter from field (float value)
    var usedHoursInput = $('usedHours');
    var scheduleEntryHours = getScheduledEntryHours(); // value passed from hiddenfield created by controller, assigned form db scheduleEntries

    if(scheduledHours < usedHours)
    {
      if(scheduleEntryHours != 0)
      {
        if(scheduledHours <= scheduleEntryHours)
        {
          emptyHours = scheduleEntryHours - scheduledHours;

          if(emptyHours > 0)
          {
            showEmptyHours(emptyHours);
            empty_hours_number = parseFloat(emptyHours);
          }
          else
          {
            hideEmptyHours();
            empty_hours_number = 0;
          }
         
          usedHoursInput.value = scheduleEntryHours;
        }
        else
        {
          hideEmptyHours();
          empty_hours_number = 0;
          
          usedHoursInput.value = scheduledHours;
        }
      }
      else
      {
        usedHoursInput.value = scheduledHours;
      }
    }
    else if(scheduledHours == usedHours)
    {
      hideEmptyHours();
      empty_hours_number = 0;
    }
    else
    {
      if(scheduleEntryHours != 0)
      {
        if(scheduledHours <= scheduleEntryHours)
        {
          emptyHours = scheduleEntryHours - scheduledHours;

          if(emptyHours > 0)
          {
            showEmptyHours(emptyHours);
            empty_hours_number = parseFloat(emptyHours)
          }
          else
          {
            hideEmptyHours();
            empty_hours_number = 0;
          }

          if(!isNaN(scheduleEntryHours))
          {
            usedHoursInput.value = scheduleEntryHours;
          }
          else
          {
            usedHoursInput.value = '0';
          }
        }
        else
        {
          hideEmptyHours();
          empty_hours_number = 0;

          if(!isNaN(scheduleEntryHours))
          {
            usedHoursInput.value = scheduledHours;
          }
          else
          {
            usedHoursInput.value = '0';
          }
        }
      }
      else
      {
        if(!isNaN(scheduledHours))
        {
          usedHoursInput.value = scheduledHours;
        }
        else
        {
          usedHoursInput.value = '0';
        }
      }
    }
  }

  _owner.value = usedHoursInput.value;
  if(null != $('usedTotal'))
  {
    $('usedTotal').innerHTML = (usedHoursInput.value == '' ? 0 : parseFloat(usedHoursInput.value)) + previousHoursNumber();
  }

  showWarning();
  updateTotalDayHours();
  updateWindowSize('vert');
}

/**
 * Update total number of hours for a day
 * (most bottom cell)
 */
function updateTotalDayHours()
{
  if(null != _owner)
  {
    var owner_id = $(_owner).id;
    var date = owner_id.replace(/^schedule_entry\[.+\]\[(.+)\]\[.+\]$/, "$1");
    var target = $('total_' + date);
    date = date.replace(/^(\d{4}).(\d{2}).(\d{2})/, "$1\\-$2\\-$3");
    var sum = scheduledHoursForDay(date);
    if(parseFloat(sum) == 0)
    {
      sum = '';
    }
    target.update(sum);
  }
}

/**
 * Find sum of all hours in given day (column)
 */
function totalDayHours(date)
{
  var elements = $$('input[type="text"]').findAll(function(el){
    return new RegExp('schedule_entry\\[.+\\]\\[' + date + '\\]\\[.+\\]').test(el.id);
  });
  var sum = 0;
  var i = 0;

  for(i; i< elements.length; i++)
  {
    if(null != $(elements[i]).value && $(elements[i]).value!=0)
    {
      sum += parseFloat($(elements[i]).value);
    }
  }

  return sum;
}

/**
 * Compute sum of scheduled hours for given day
 *
 * @date The day
 *
 */
function scheduledHoursForDay(date)
{
  var url = document.location.toString();
  var sum = 0;
  if(url.match(/account/)){
    sum = totalDayHours(date);
  }
  else if(url.match(/projects/))
  {
    var inScheduledField = $(_owner).value;
    var scheduled = computeScheduledHours();

    sum = Math.max(inScheduledField, scheduled);
  }

  return sum;
}

/**
 * Called when user clicked a checkbox to schedule or unschedule an issue
 *
 * @owner id of the checkbox
 * @cellOwner id of cell of the day we schedule now
 *
 */
//function activateScheduledHours(owner)
//{
//  var dropdown = $(owner.id.replace(/^scheduled_(.+)$/, "hours_to_schedule_$1"));
//
//  if(dropdown)
//  {
//    if(owner.checked)
//    {
//      if(dropdown.hasAttribute('disabled'))
//      {
//        dropdown.removeAttribute('disabled');
//      }
//    }
//    else
//    {
//      dropdown.setAttribute('disabled', 'disabled');
//    }
//  }
//
//  updateScheduledHours(_owner);
//}

/**
 * Computes scheduled hours from dropdowns in the window
 */
function computeScheduledHours()
{
  var hours = null;
  var i =1;
  var totalScheduled = 0;
  var issues = $$('.hours_to_schedule_select');

  if(issues)
  {
    for(i=1; i<issues.length+1; i++)
    {
      hours = $('hours_to_schedule_' + i);
      minutes = $('minutes_to_schedule_' + i);
      if(hours != null)
      {
        _minutes = parseFloat(minutes.options[minutes.selectedIndex].value);
        if ( _minutes != 0 )
          {
            totalScheduled +=  (parseFloat(hours.options[hours.selectedIndex].value) // hours
                                          + (_minutes/100) // minutes selectbox values converted to decimal (0.value)
                                          );
          }
        else
          {
            totalScheduled += parseFloat(hours.options[hours.selectedIndex].value);
          }
      }
    }

    return totalScheduled;
  }
  else{
    return 0;
  }
}

/**
 *
 */
function updateEditfieldValue()
{
  new Ajax.Request('/schedules/r_schedule_entry_hours', {
    asynchronous:false,
    evalScripts:true,
    onComplete:function(response)
    {
      var newVal = response.responseText;
      _owner.value = isNaN(newVal) ? '' : newVal == 0 ? '' : newVal;
    },
    parameters:idToParams(_owner.id)
  });
}
