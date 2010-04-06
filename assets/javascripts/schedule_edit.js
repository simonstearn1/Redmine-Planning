/* 
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

var edited = null;
var parentCell = null;
var sprintCheckbox = false;
var versionCheckbox = false;
var schedIssVisible = false;
var notSchedIssVisible = false;
var unasIssVisible = false;
var allChecked = false;
var _owner = null;
var remote = false;
var functionalClicked = false;

  function updateSelectValues()
  {
    $$('.hours_to_schedule_values').each(function(element){
      element = $(element);
      if(/^hours_to_schedule_value_[0-9]+$/.test(element.id))
      {
        var number = element.id.replace(/^hours_to_schedule_value_([0-9]+)$/, "$1");
        if(number.match(/^[0-9]+$/))
        {
          $('hours_to_schedule_' + number).value = element.value;
        }
      }
    })
    $$('.minutes_to_schedule_values').each(function(element){
      element = $(element);
      if(/^minutes_to_schedule_value_[0-9]+$/.test(element.id))
      {
        var number = element.id.replace(/^minutes_to_schedule_value_([0-9]+)$/, "$1");
        if(number.match(/^[0-9]+$/))
        {
          $('minutes_to_schedule_' + number).value = element.value;
        }
      }
    })

  }

function updateSelectValue(select_id, value)
{
  var select = $(select_id);
  if(null != select)
  {
    select.value = value;
  }
}

function anotherWeek(user_id, date)
{
  new Ajax.Updater('content', '/account/schedule/' + user_id + '/edit?date=' + date, {
    asynchronous: true,
    evalScripts: true
  });
}

function saveSchedule(form)
{
  var sWindow = $('scheduledWindow');
  if(null == sWindow || edited == false || edited == null || confirmHiding())
  {
    form.submit();
  }
}

function saveColumnVisibility()
{
  sprintCheckbox = null != $('sprintCheckbox') ?
  $('sprintCheckbox').checked : false;
}

function updateColumnVisibility()
{
  if(null != $('sprintCheckbox'))
  {
    sprintCheckbox = null == sprintCheckbox ? false : sprintCheckbox;
    $('sprintCheckbox').checked = sprintCheckbox;

    if(sprintCheckbox == true)
    {
      showColumn('sprint');
    }
  }
}

/**
*
*/
function updateVisibility()
{
  if(null != $('scheduledIssues')){
    if(null != schedIssVisible && true == schedIssVisible)
    {
      $('scheduledIssues').style.display = '';
      $('scheduledTicket').setStyle({
        height: ($('scheduledTicket').getHeight() + $('scheduledIssues').getHeight()) + 'px'
      })
    }
    else{
      $('scheduledIssues').style.display = 'none';
    }
  }

  if(null != $('notScheduledIssues')){
    if(null != notSchedIssVisible && true == notSchedIssVisible)
    {
      $('notScheduledIssues').style.display = '';
      $('scheduledTicket').setStyle({
        height: ($('scheduledTicket').getHeight() + $('notScheduledIssues').getHeight()) + 'px'
      })
    }
    else{
      $('notScheduledIssues').style.display = 'none';
    }
  }

  if(null != $('unassignedIssues')){
    if(null != unasIssVisible && true == unasIssVisible)
    {
      $('unassignedIssuesDiv').style.display = '';
      $('scheduledTicket').setStyle({
        height: ($('scheduledTicket').getHeight() + $('unassignedIssuesDiv').getHeight()) + 'px'
      })
    }
    else{
      $('unassignedIssuesDiv').style.display = 'none';
    }
  }

  if(null != allChecked && true == allChecked)
  {
    $('none_ChB').checked = false;
    $('all_ChB').checked = true;
    
    setAllChecked($('project_id_hiddn').value, $('user_id_hiddn').value);
  }

  updateColumnVisibility();
  
  var scheduledCount = $$('div#scheduledIssues td.logtime').length;
  var notScheduledCount = $$('div#notScheduledIssues td.logtime').length;
  var unassignedCount = $$('div#unassignedIssues td.logtime').length;

  var arr = new Array(
    'scheduledIssues', scheduledCount,
    'notScheduledIssues', notScheduledCount,
    'unassignedIssues', unassignedCount
    );
  updateWindowInnerSize(arr)
}

/**
*
*/
function saveVisibility()
{
  saveColumnVisibility()
  
  schedIssVisible = null != $('scheduledIssues') ?
  ($('scheduledIssues').style.display == 'none' ? false : true) : false;

  notSchedIssVisible = null != $('notScheduledIssues') ?
  ($('notScheduledIssues').style.display == 'none' ? false : true) : false;

  unasIssVisible = null != $('unassignedIssuesDiv') ?
  ($('unassignedIssuesDiv').style.display == 'none' ? false : true) : false;

  allChecked = null != $('all_ChB') ? $('all_ChB').checked : false;
}

/**
*
*/
function showSchedulesIssues(e, user_id)
{
  if (!e) e = window.event;

  var mx = Event.pointerX(e);
  var my = Event.pointerY(e);

  $('scheduledTicket').show();
  $('scheduledTicket').setStyle(
  {
    position: "absolute",
    left: (mx + 35) + "px",
    top: (my-85) + "px"
  }
  );

  return 1 + "&uid=" + user_id;
}




/**
* Check all member checkboxes
* and fetch issues for all members
*/
function setAllChecked(project_id, user_id, owner_id)
{
  var i = $$('div#scheduledIssues td.logtime').length + $$('div#notScheduledIssues td.logtime').length + 1;

  if(null != $('all_ChB') && true == $('all_ChB').checked){
    var elements = $$('.member');

    elements.each(function (el){
      if(el.type == 'checkbox')
      {
        el.checked = true;
      }
    });

    $('none_ChB').checked = false;
    
    new Ajax.Updater('unassignedIssues', '/schedules/fetchAllMembersIssues', {
      method: 'post',
      asynchronous:true,
      evalScripts:true,
      onComplete:function(){
        var count = $$('div#unassignedIssues td.logtime').length;
        if(count != 0)
        {
          var arr = new Array('unassignedIssues', count);
          updateWindowInnerSize(arr);
        }
        else {
          $('unassignedIssues').setStyle({
            height: 0
          });
        }

        saveColumnVisibility()
        updateColumnVisibility();
        updateWindowSize();
      },
      parameters:"project_id=" + project_id + "&user_id=" + user_id + "&i=" + i + "&owner_id=" + owner_id
    });
  }
}

function fetchUnassignedIssues(i)
{
  var params = null;
  if(null != $('project_id_hiddn'))
  {
    params = "project_id=" + parseInt($('project_id_hiddn').value) + "&i=" + i;
  }

  new Ajax.Updater('unassignedIssues','/schedules/fetchUnassignedIssues', {
    method: 'post',
    asynchronous:false,
    evalScripts:true,
    onComplete:function(){
      var count = $$('div#unassignedIssues td.logtime').length;
      if(count != 0)
      {
        var arr = new Array('unassignedIssues', count);
        updateWindowInnerSize(arr);
      }
      else {
        $('unassignedIssues').setStyle({
          height: 0
        });
      }
    },
    parameters:null != params ? params : "project_id="
  });
}

/**
*
*/
function setNoneChecked()
{
  var i = $$('div#scheduledIssues td.logtime').length + $$('div#notScheduledIssues td.logtime').length + 1;
   
  if($('none_ChB').checked){
    var elements = $$('.member');

    elements.each(function (el){
      if(el.type == 'checkbox')
      {
        el.checked = false;
      }
    });

    $('all_ChB').checked = false;
    fetchUnassignedIssues(i);
  }
  else
  {
    $('unassignedIssues').update('No issues in this category');
  }
  
  saveColumnVisibility();
  updateColumnVisibility();
  updateWindowSize();
}

/**
*
*/
function saveScheduledIssues(form)
{
  saved = false;
  new Ajax.Request('/schedules/save_scheduled_issues', {
    asynchronous:true,
    evalScripts:true,
    onComplete:function()
    {
      updateEditfieldValue();
      saveVisibility();
      clearParentCell();
      edited = false;

      save_clicked = true;
      Modalbox.hide();
    },
    parameters:Form.serialize(form) + "&entered_hours=" + getVisibleUsedHours() +
    "&empty_hours=" + getEmptyHours()
  });
}

var save_clicked = false;

/**
* Show block of issues
*
* @block_id id of the div
*
*/
function showIssues(block_id)
{
  var issues = $(block_id);

  if(issues)
  {
    issues.setStyle({
      display: (issues.style.display == 'none') ? '' : 'none'
    });
  }

  validatePosition();
  updateWindowSize('vert');
}

/**
* Fetch issues assigned to selected members
* in given day
*/
function fetchMemberIssues(form, date)
{
  var i = $$('div#scheduledIssues td.logtime').length + $$('div#notScheduledIssues td.logtime').length + 1;

  new Ajax.Updater('unassignedIssues', '/schedules/fetchMemberIssues', {
    asynchronous: false,
    evalScripts: true,
    parameters:Form.serialize(form) + "&i=" + i + "&date=" + date
  });

  var count = $$('div#unassignedIssues td.logtime').length;
  if(count > 0)
  {
    var arr = new Array('unassignedIssues', count);
    updateWindowInnerSize(arr);
  }
  else {
    $('unassignedIssues').setStyle({
      height: 0
    });
  }

  if(null != $('sprintCheckbox'))
  {
    if($('sprintCheckbox').checked){
      showColumn('sprint');
    }else
    {
      hideColumn('sprint');
    }
  }

  updateWindowSize('vert');
}

/*
*
**/
function scheduledIssuesInfo(date, user_id, project_id, e)
{
  var pos = getMouseXY(e)
  new Ajax.Updater('scheduled_issue_info', '/schedules/scheduled_issues_for_project', {
    method: 'post',
    asynchronous:false,
    evalScripts:true,
    onComplete:function()
    {
      var w = $('scheduled_issue_info');
      w.setStyle({
        position: 'absolute',
        left: (pos[0] + 10) + 'px',
        top: (pos[1] - (0.3*w.getHeight())) + 'px',
        border: '1px solid black',
        fontSize: '0.85em',
        background: '#eee',
        width: '100px',
        height: 'auto',
        zIndex: '10002'
      });

      $('iiOverlay').setStyle({
        position: 'absolute',
        left: 0,
        top: 0,
        width: $(document.body).getWidth() + 'px',
        height: $(document.body).getHeight() + 'px',
        zIndex: '10001'
      })
    
      $('iiOverlay').show();
      w.show();
    },
    parameters:"date=" + date + "&user_id=" + user_id + "&project_id=" + project_id
  });
}

/**
 * Retrieve mouse coordinates with
 * (0, 0) point in top left page corner
 */
function getMouseXY(e) // works on IE6,FF,Moz,Opera7
{
  if (!e) e = window.event; // works on IE, but not NS (we rely on NS passing us the event)
  var mousex,mousey;
  if (e)
  {
    if (e.pageX || e.pageY)
    { // this doesn't work on IE6!! (works on FF,Moz,Opera7)
      mousex = e.pageX;
      mousey = e.pageY;
    }
    else if (e.clientX || e.clientY)
    { // works on IE6,FF,Moz,Opera7
      mousex = e.clientX  + document.viewport.getScrollOffsets()['left']
      mousey = e.clientY + document.viewport.getScrollOffsets()['top']
    }
    else if (e.offsetX || e.offsetY)
    {
      mousex = e.offsetX
      mousey = e.offsetY
    }
    else if (e.screenX || e.screenY)
    {
      mousex = e.screenX
      mousey = e.screeny
    }
    else if (e.x || e.y)
    {
      mousex = e.x;
      mousey = e.y
    }
  }

  return [mousex, mousey];
}

Event.observe(window, 'load', function(e){
  var overlay = $(document.createElement('div'));
  overlay.setAttribute('id', 'iiOverlay');
  overlay.className = 'divOverlay';
  overlay.setStyle({
    display: 'none'
  })

  var container = $(document.createElement('div'));
  container.setAttribute('id', 'scheduled_issue_info');

  document.body.appendChild(overlay);
  document.body.appendChild(container);
  Event.observe(overlay, 'click', function(){
    if(container != null)
    {
      container.hide();
    }
    this.hide();
  })
})