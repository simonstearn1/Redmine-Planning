/* 
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

var saved = true;
var scrollPos = new Array();

/**
 *
 */
function clearParentCell(){
  if(null != parentCell)
  {
    parentCell.setStyle({
      background: '#fff'
    });
  }
  
  parentCell = null;
}

/**
 * Used to scroll viewport to position where it was
 * before schedule window hiding
 */
function scrollToLastPosition()
{
  if(IsIE8Browser())
  {
    document.documentElement.scrollTop = scrollPos['top'];
    document.documentElement.scrollLeft = scrollPos['left'];
  }
  else
  {
    self.scrollTo(scrollPos['left'], scrollPos['top']);
  }
}

/**
 *
 */
function confirmHiding()
{
  var seWindow = $('scheduledTicket');

  if(null != edited && true == edited)
  {
    if(saved){
      if(confirm('Close without saving?'))
      {
        if(null != seWindow)
        {
          saveVisibility();
        }
      
        clearParentCell();
        edited = false;
        updateEditfieldValue();
      }
      else{
        return false;
      }
    }
  }
  else
  {
    edited = false;
    if(null != seWindow)
    {
      saveVisibility();
    }
    
    updateEditfieldValue();
    clearParentCell();
    cancelQuickIssue();
  }

  saved = true;
  if(IsIE8Browser())
  {
    scrollPos['top'] = document.body.scrollTop;
    scrollPos['left'] = document.body.scrollLeft;
  }
  else
  {
    scrollPos = document.viewport.getScrollOffsets();
  }
  return true;
}

/**
 *
 */
function validatePosition(positionedAtDisplay)
{
  if(null == positionedAtDisplay)
  {
    positionedAtDisplay = false;
  }
  poziomo = false;
  pionowo = false;

  var newLeft = Modalbox.MBwindow.cumulativeOffset()['left'];
  
  if(newLeft + Modalbox.MBwindow.getWidth() > document.viewport.getWidth())
  {
    newLeft = document.viewport.getScrollOffsets()['left'] + document.viewport.getWidth()
    - Modalbox.MBwindow.getWidth() - 10;
    poziomo = true;
  }

  var newTop = Modalbox.MBwindow.cumulativeOffset()['top'];

  if(newTop + Modalbox.MBwindow.getHeight() + 5 > document.viewport.getScrollOffsets()['top'] +
    document.viewport.getHeight())
    {
    newTop = document.viewport.getScrollOffsets()['top'] + document.viewport.getHeight()
    - Modalbox.MBwindow.getHeight() - 5;
    pionowo = true;
  }
  
  if(poziomo){
    newTop = Modalbox.MBwindow.cumulativeOffset()['top']

    Modalbox.setPosition(newTop, newLeft);
  }

  if(pionowo)
  {
    newLeft = Modalbox.MBwindow.cumulativeOffset()['left'];
    Modalbox.setPosition(newTop, newLeft);
  }
}

/* *
 */
function showScheduledProjects(editFieldID)
{
  _owner = $(editFieldID);
  if(null != _owner){
    clearParentCell()

    parentCell = $(_owner.parentNode);
    if(null != parentCell)
    {
      parentCell.setStyle({
        background: '#f64'
      })
    }
  }

  new Ajax.Updater('scheduledTicket', '/schedules/scheduled_tickets', {
    asynchronous:true,
    evalScripts:true,
    onComplete:function(){
      Modalbox.show($('scheduledTicket'), {
        doNotMove: true,
        title: 'Schedule editor',
        overlayDuration: 0.0,
        slideDownDuration: 0.0,
        slideUpDuration: 0.0,
        resizeDuration: 0.0,
        overlayOpacity: 0.01,
        autoFocusing: false,
        afterLoad: function(){
          updateSelectValues();
          var editfieldValue = parseFloat(_owner.value);
          var scheduledValue = computeScheduledHours();
          var previousValue = previousHoursNumber();
          var emptyHours = 0;

          if(null != $('usedHours'))
          {
            $('usedHours').value = isNaN(editfieldValue) ? '0' : editfieldValue;
            $('usedHours').className = 'abc'
          }

          if(null != $('usedTotal'))
          {
            $('usedTotal').innerHTML = previousValue + (isNaN(editfieldValue) ? 0 : editfieldValue);
          }

          if(null != $('emptyHours'))
          {
            emptyHours = ($('usedHours') != null ? parseFloat($('usedHours').value) : 0) - scheduledValue;
          }

          if(parseFloat(emptyHours) == 0)
          {
            empty_hours_number = 0;
            hideEmptyHours();
          }
          else
          {
            empty_hours_number = emptyHours
            showEmptyHours(empty_hours_number);
          //            }
          }

          var scheduledCount = $$('div#scheduledIssues td.logtime').length;
          var notScheduledCount = $$('div#notScheduledIssues td.logtime').length;
          var unassignedCount = $$('div#unassignedIssues td.logtime').length;

          var arr = new Array(
            'scheduledIssues', scheduledCount,
            'notScheduledIssues', notScheduledCount,
            'unassignedIssues', unassignedCount
            );
              
          
          updateVisibility();
          updateWindowInnerSize(arr);
          Modalbox.resizeToContent();

          if(IsIE8Browser())
          {
            $(document.body).setStyle({
              position: 'relative'
            })
          }

          var newTop = _owner.cumulativeOffset()['top'] - 70;
          if(newTop + Modalbox.MBwindow.getHeight() > document.viewport.getHeight() +
            scrollPos['top'])
            {
            newTop = document.viewport.getHeight() + scrollPos['top']
            - Modalbox.MBwindow.getHeight() - 50;
          }
          else if(newTop - scrollPos['top'] < 20)
          {
            newTop = scrollPos['top'] + 20;
          }
          
          var newLeft = _owner.cumulativeOffset()['left'] + _owner.getWidth() + 10;
          if(newLeft + Modalbox.MBwindow.getWidth() > document.viewport.getWidth() +
            scrollPos['left'])
            {
            newLeft = _owner.cumulativeOffset()['left'] - 30 - Modalbox.MBwindow.getWidth();
          }

          Modalbox.setPosition(newTop, newLeft);
          if(IsIE8Browser())
          {
            document.body.scrollTop = scrollPos['top'];
          }
          else
          {
            self.scrollTo(0, scrollPos['top'])
          }

          first = true;
          new Draggable(Modalbox.MBwindow, {
            handle: Modalbox.MBcaption
          });
        },
        beforeHide: confirmHiding,
        afterHide: scrollToLastPosition
      });
    },
    parameters:idToParams(editFieldID) + "&owner=" + editFieldID
  })
}

function IsIE8Browser() {
  return (document.documentMode != undefined && document.documentMode == 8);
}

/**
*
*/
function setInfoWindowPosition(e)
{
  var x,y;

  x = mouseX(e);
  y = mouseY(e);

  var scheduledWindow = $('scheduled_issue_info');

  scheduledWindow.setStyle({
    position: "absolute"
  });

  scheduledWindow.setStyle({
    left: (x + 10) + 'px',
    top: (y + 10) + 'px'
  });
}

/**
 *
 */
function toggleColumn(columnClass)
{
  if($$('.'+columnClass).length > 0)
  {
    if($$('.'+columnClass)[0].style.display != 'none')
    {
      hideColumn(columnClass);
    }
    else
    {
      showColumn(columnClass);
    }
  }
}

/**
 *
 */
function showColumn(columnClass)
{
  var elements = $$('.' + columnClass)
  if(elements.length > 0)
  {
    elements.each(function(el){
      el.show();
    });
  }

  updateWindowSize('grow');
}

/**
 *
 */
function hideColumn(columnClass)
{
  var elements = $$('.' + columnClass)
  if(elements.length > 0)
  {
    elements.each(function(el){
      el.hide();
    });
  }

  updateWindowSize('shrink');
}

/**
 *
 */
function updateWindowInnerSize(arr)
{
  if(null != arr)
  {
    var i, id = null, size = null;

    for(i=0; i<arr.length/2; i++)
    {
      id = arr[i*2];
      size = arr[i*2+1];

      if(null == $(id))
      {
        break;
      }
      
      if (size<3 && size>0)
      {
        $(id).setStyle({
          height: ((size+1)*30) + 'px'
        });
      }
      else if (size == 0)
      {
        $(id).setStyle({
          height: '14px'
        });
      }
      else
      {
        $(id).setStyle({
          height: '137px'
        });
      }
    }
  }

  updateWindowSize('vert');
}

/**
 *
 */
function updateWindowSize(action)
{
  if(null == action)
  {
    action = false;
  }
  
  var save = $('saveIssues');
  var seWindow = $('scheduledTicket');

  var newT = -1;
  if(action == 'grow')
  {
    newT = 565;
  }
  else if(action == 'shrink')
  {
    newT = 466;
  }
  
  if(null != save && null != seWindow)
  {
    var newHeight = Element.viewportOffset(save)['top'] + save.getHeight() -
    Element.viewportOffset(seWindow)['top'] + 2;
    seWindow.style.height = newHeight + 'px';

    if(action != 'vert' && newT != -1)
    {
      seWindow.setStyle({
        width: newT + 'px'
      })
    }
  }

  Modalbox.resizeToContent();
  validatePosition();
}

function IsIE7Browser()
{
  return navigator.appVersion.indexOf('MSIE 7.') == -1 ? false : true;
}

/**
 *
 */
function parseCellId(id)
{
  var date = id.replace(/^schedule_entry\[.+\]\[(.+)\]\[.+\]$/, "$1");
  var user_id = id.replace(/^schedule_entry\[(.+)\]\[.+\]\[.+\]$/, "$1");
  var project_id = id.replace(/^schedule_entry\[.+\]\[.+\]\[(.+)\]$/, "$1");
  
  var retValue = new Array();
  retValue.date = date;
  retValue.user_id = user_id;
  retValue.project_id = project_id;

  return retValue;
}

/**
 *
 */
function idToParams(id)
{
  if(id == null)
  {
    if(_owner != null)
    {
      id = _owner.id;
    }
  }
  
  var arr = parseCellId(_owner.id);
  return "user_id=" + arr.user_id + "&project_id=" +
  arr.project_id + "&date=" + arr.date;
}