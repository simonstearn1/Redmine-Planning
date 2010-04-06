# To change this template, choose Tools | Templates and open the template in the
# editor.

module ValidatedFieldsHelper

  #
  #
  # # # #
  def validated_textfield(name, title, id, options)
    char_regexp = options.is_a?(Hash) ? (options.include?(:char) ? options[:char] : '.') : '.';
    value_regexp = options.is_a?(Hash) ? (options.include?(:value) ? options[:value] : '.*') : '.*';
    failure = options.is_a?(Hash) ? (options.include?(:failure) ? options[:failure] : '') : '';
    success = options.is_a?(Hash) ? (options.include?(:success) ? options[:success] : '') : '';

    validate_value = "
    if(!tb.value.match(/#{value_regexp}/)){
      #{failure}
    } else
    {
      #{success}
    };";

    focus = "
    if(tb.value == tb.getAttribute('title'))
    {
      tb.className = '';
      tb.value = '';
    }
    else
    {
      tb.className = '';
    };
    ";

    click = focus;

    blur = "
    if(tb.value == '')
    {
      tb.value = tb.getAttribute('title');
      tb.className = '';
    }
    ";

    keypress = "
    var keyCode = window.event ? e.keyCode : e.which;
    
    if(null != keyCode)
    {

      var charc = String.fromCharCode(keyCode);

      if(tb.value == tb.getAttribute('title'))
      {
        tb.value = '';
      }

      if(!charc.match(/#{char_regexp}/))
      {
        if(e.keyCode != 9 && e.keyCode != 8 && e.keyCode != 46)
        {
          Event.stop(e);
        }
      }
    };

    if(tb.className != '' && tb.value != tb.getAttribute('title')) tb.className = '';
    ";

    keyup = "#{validate_value}";

    events = options.is_a?(Hash) ?
      (options.include?(:events) && options[:events].is_a?(Hash) ? options[:events] : Hash.new) : Hash.new;
    
    events['keyup'] = keyup if !events.include?('keyup');
    events['keypress'] = keypress if !events.include?('keypress');
    events['blur'] = blur if !events.include?('blur');
    events['focus'] = focus if !events.include?('focus');
    events['click'] = click if !events.include?('click');

    retValue = text_field_tag name, title,
      :id => id, :title => title,
      :onfocus => "edited_value = this.value;",
      :onblur => "if(edited_value != this.value) quick_issue_edited = true; edited_value = null;",
      :tabindex => 105, :style => "width: 35px";

    retValue += " <script type='text/javascript'>var tb = $('#{id}');";

    events.each do |key, value|
      retValue += "Event.observe(tb, '#{key}', function(e){
      #{value}
      });
      ";
    end

    retValue += "</script>";

  end

  #
  #
  # # # #
  def number_field(name, title, id)
    
    h = Hash.new;
    h[:char] = '[0-9.,]';
    h[:value] = '^[1-9][0-9]*$';
    
    return validated_textfield(name, title, id, h);
  end
end
