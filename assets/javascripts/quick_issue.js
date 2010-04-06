/*  * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

var gy_focus = true;

Event.observe(document, 'click', function(e){
  check(e);
});

var quick_issue_edited = false;
var edited_value = null;

function select_innerHTML(objeto, innerHTML){
  /******
* select_innerHTML - corrige o bug do InnerHTML em selects no IE
* Veja o problema em: http://support.microsoft.com/default.aspx?scid=kb;en-us;276228
* Versão: 2.1 - 04/09/2007
* Autor: Micox - Náiron José C. Guimarães - micoxjcg@yahoo.com.br
* @objeto(tipo HTMLobject): o select a ser alterado
* @innerHTML(tipo string): o novo valor do innerHTML
*******/
  objeto.innerHTML = ""
  var selTemp = document.createElement("micoxselect")
  var opt;
  selTemp.id="micoxselect1"
  document.body.appendChild(selTemp)
  selTemp = document.getElementById("micoxselect1")
  selTemp.style.display="none"
  if(innerHTML.toLowerCase().indexOf("<option")<0){//se não é option eu converto
    innerHTML = "<option>" + innerHTML + "</option>"
  }
  innerHTML = innerHTML.toLowerCase().replace(/<option/g,"<span").replace(/<\/option/g,"</span")
  selTemp.innerHTML = innerHTML


  for(var i=0;i<selTemp.childNodes.length;i++){
    var spantemp = selTemp.childNodes[i];

    if(spantemp.tagName){
      opt = document.createElement("OPTION")

      if(document.all){ //IE
        objeto.add(opt)
      }else{
        objeto.appendChild(opt)
      }

      //getting attributes
      for(var j=0; j<spantemp.attributes.length ; j++){
        var attrName = spantemp.attributes[j].nodeName;
        var attrVal = spantemp.attributes[j].nodeValue;
        if(attrVal){
          try{
            opt.setAttribute(attrName, attrVal);
            opt.setAttributeNode(spantemp.attributes[j].cloneNode(true));
          }catch(e){}
        }
      }
      //getting styles
      if(spantemp.style){
        for(var y in spantemp.style){
          try{
            opt.style[y] = spantemp.style[y];
          }catch(e){}
        }
      }
      //value and text
      opt.value = spantemp.getAttribute("value")
      opt.text = spantemp.innerHTML.substr(0, 1).toUpperCase() + spantemp.innerHTML.substr(1);
      //IE
      opt.selected = spantemp.getAttribute('selected');
      opt.className = spantemp.className;
    }
  }
  document.body.removeChild(selTemp)
  selTemp = null
}

function changeStatusesByTracker(select)
{
  var target_select = $('quick_issue_status');
  if(target_select != null)
  {
    if($(select.options[select.selectedIndex].text+'_options').options.length > 0)
    {
      select_innerHTML(target_select, $(select.options[select.selectedIndex].text+'_options').innerHTML);
    }
    else
    {
      select_innerHTML(target_select, $('default_option').innerHTML)
    }
  }

  quick_issue_edited = true;
}

function quickIssueAssignedToChange()
{
  quick_issue_edited = true;
  if($('quick_issue_assigned_to') == null)
  {
    return;
  }
  
  if($('quick_issue_assigned_to').selectedIndex == 0)
  {
    $('scheduled_hours').setAttribute('disabled', 'disabled');
  }
  else
  {
    if($('scheduled_hours').hasAttribute('disabled'))
    {
      $('scheduled_hours').removeAttribute('disabled');
    }
  }
}

/**
 *
 */
function checkParent(t){
  while(t.parentNode){
    if(t == $('quickIssue') || t == $('qiOverlay')){
      return false
    }
    t = t.parentNode
  }
  return true
}

function cancel_tab_key(element)
{
  Event.observe($(element), 'keypress', function(e){
    var keycode = e.keyCode;

    if(keycode == Event.KEY_TAB)
    {
      Event.stop(e);
    }
  })
  Event.observe($(element), 'keydown', function(e){
    var keycode = e.keyCode;

    if(keycode == Event.KEY_TAB)
    {
      Event.stop(e);
    }
  })
}

/*
 *
 */
function check(e){
  var target = (e && e.target) || (window.event && window.event.srcElement);

  return checkParent(target)
}

var already_visible = false;

/**
 *
 */
function showQuickIssue()
{
  new Ajax.Updater('quickIssueContent', '/schedules/render_quick_issue', {
    asynchronous: true,
    evalScripts: true,
    onComplete:function(){
      if(IsIE7Browser() && !already_visible)
      {
        qiHide();
        already_visible = true;
        showQuickIssue();
      }
      
      var width = $$('body')[0].getWidth();
      var height = $$('body')[0].getHeight();
      
      if(IsIE8Browser())
      {
        width = document.body.scrollWidth;
        height = document.body.scrollHeight;
      }

      $('qiOverlay').setStyle({
        position: 'absolute',
        left: 0,
        top: 0,
        width: width + 'px',
        height: height + 'px'
      });

      Event.observe('qiOverlay', 'click', function() {
        cancelQuickIssue();
      });

      $('qiOverlay').show();
      
      $('quickIssue').show();
      $('quickIssueContent').setStyle({
        backgroundColor: '#deffed',
        zIndex: 10003
      })

      updateQIwindowMetrics();
    },
    parameters:idToParams(_owner.id)
  });

  new Draggable('quickIssue', { 
    handle: 'quickIssueBar'
  });
}

function updateQIwindowMetrics()
{
  var qi = $('quickIssue');
  var left = Modalbox.MBwindow.cumulativeOffset()['left'] + Modalbox.MBwindow.getWidth() + 10;
  var top = Modalbox.MBwindow.cumulativeOffset()['top'] + Modalbox.MBwindow.getHeight() - qi.getHeight();

  if(top < document.viewport.getScrollOffsets()['top'])
  {
    top = document.viewport.getScrollOffsets()['top'] + 10;
  }

  if(left + qi.getWidth() > document.viewport.getScrollOffsets()['left'] + document.viewport.getWidth())
  {
    left = Modalbox.MBwindow.cumulativeOffset()['left'] - qi.getWidth() - 10;
  }

  qi.setStyle({
    left: left + 'px',
    top: top + 'px',
    height: ($('qibox').getHeight() + 19) + 'px'
  })

}

function moveQIRight()
{
  var elements = $$('div td.logtime');
  var quickIssue = $('quickIssue');

  if(null != elements)
  {
    var lefts = elements.collect(function(el){
      return el.viewportOffset()['left'];
    });

    quickIssue.setStyle({
      left: (lefts + quickIssue.getWidth() + 3) + 'px'
    })
  }
}

/**
 *
 */
function saveQuickIssue(form, save)
{
  saveVisibility();
  
  new Ajax.Updater('scheduledTicket', '/schedules/save_quick_issue', {
    method: 'get',
    asynchronous: true,
    evalScripts: true,
    onComplete: function() {
      updateSelectValues();
      var editfieldValue = parseInt(_owner.value);
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
        emptyHours = ($('usedHours') != null ? parseInt($('usedHours').value) : 0) - scheduledValue;
      }

      if(parseInt(emptyHours) < 1)
      {
        empty_hours_number = 0;
        hideEmptyHours();
      }
      else
      {
        empty_hours_number = emptyHours
        showEmptyHours(empty_hours_number);
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

      updateScheduledHours();

      cancelQuickIssue(save);
      remote = true;
    },
    parameters:Form.serialize(form) + "&" + idToParams(_owner.id)
  })
}

/**
 *
 */
function cancelQuickIssue(save)
{
 
  if(save != undefined && save != null)
  {
    qiHide()
  }
  else
  {
    if((quick_issue_edited && confirm('Quit without saving changes?')) || !quick_issue_edited)
    {
      qiHide()
    }
  }
}

function qiHide()
{
  var quickIssueOverlay = $('qiOverlay');
  if(null != quickIssueOverlay)
  {
    $('quickIssue').hide();
    Event.stopObserving($('qiOverlay'), 'click');
    quickIssueOverlay.hide();
    
    quick_issue_edited = false;
  }

  self.scrollTo(0, document.viewport.getScrollOffsets()['top'])
}