class_name Vector2iEdit;
extends GridContainer

signal value_changed(value : Vector2);

var value : Vector2:
	get:
		return _value;
	set(value):
		set_value_no_signal(value);
		value_changed.emit(value);

var _value : Vector2;
var _spin_x : SpinBox;
var _spin_y : SpinBox;
var _label_x : Label;
var _label_y : Label;

var min : Vector2:
	set(value):
		_spin_x.min_value = value.x;
		_spin_y.min_value = value.y;
		_spin_x.allow_lesser = false;
		_spin_y.allow_lesser = false;
		
func _init():
	columns = 4;
	_label_x = _label("X");
	_spin_x = _spin(_update_value);
	_label_y = _label("Y");
	_spin_y = _spin(_update_value);
	add_child(_label_x);
	add_child(_spin_x);
	add_child(_label_y);
	add_child(_spin_y);

func set_display_name(x_name : StringName, y_name : StringName, suffix : StringName) -> void:
	_label_x.text = x_name;
	_label_y.text = y_name;
	_spin_x.suffix = suffix;
	_spin_y.suffix = suffix;

func _update_value(new_value : float) -> void:
	_value = Vector2(_spin_x.value, _spin_y.value);
	value_changed.emit(_value);

func set_value_no_signal(value : Vector2) -> void:
	_value = value;
	_spin_x.set_value_no_signal(_value.x);
	_spin_y.set_value_no_signal(_value.y);

func _label(text : String) -> Label:
	var label := Label.new();
	label.text = text;
	return label;
	
func _spin(value_changed : Callable) -> SpinBox:
	var spin := SpinBox.new();
	spin.value_changed.connect(value_changed);
	spin.suffix = "px";
	spin.max_value = 0;
	spin.min_value = 0;
	spin.step = 1;
	spin.rounded = true;
	spin.allow_greater = true;
	spin.allow_lesser = true;
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	return spin;
