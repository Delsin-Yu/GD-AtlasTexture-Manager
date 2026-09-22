class_name Vector4iEdit;
extends GridContainer

signal value_changed(value : Vector4);

var value : Vector4:
	get:
		return _value;
	set(value):
		set_value_no_signal(value);
		value_changed.emit(value);

var min : Vector4:
	set(value):
		_spin_x.min_value = value.x;
		_spin_y.min_value = value.y;
		_spin_z.min_value = value.z;
		_spin_w.min_value = value.w;
		_spin_x.allow_lesser = false;
		_spin_y.allow_lesser = false;
		_spin_z.allow_lesser = false;
		_spin_w.allow_lesser = false;

var _value : Vector4;
var _spin_x : SpinBox;
var _spin_y : SpinBox;
var _spin_z : SpinBox;
var _spin_w : SpinBox;
var _label_x : Label;
var _label_y : Label;
var _label_z : Label;
var _label_w : Label;

func _init():
	columns = 4;
	_label_x = _label("X");
	_spin_x = _spin(_update_value);
	_label_y = _label("Y");
	_spin_y = _spin(_update_value);
	_label_z = _label("Z");
	_spin_z = _spin(_update_value);
	_label_w = _label("W");
	_spin_w = _spin(_update_value);
	add_child(_label_x);
	add_child(_spin_x);
	add_child(_label_y);
	add_child(_spin_y);
	add_child(_label_z);
	add_child(_spin_z);
	add_child(_label_w);
	add_child(_spin_w);

func set_display_name(x_name : StringName, y_name : StringName, z_name : StringName, w_name : StringName, suffix : StringName) -> void:
	_label_x.text = x_name;
	_label_y.text = y_name;
	_label_z.text = z_name;
	_label_w.text = w_name;
	_spin_x.suffix = suffix;
	_spin_y.suffix = suffix;
	_spin_z.suffix = suffix;
	_spin_w.suffix = suffix;

func _update_value(new_value : float) -> void:
	_value = Vector4(_spin_x.value, _spin_y.value, _spin_z.value, _spin_w.value);
	value_changed.emit(_value);

func set_value_no_signal(value : Vector4) -> void:
	_value = value;
	_spin_x.set_value_no_signal(_value.x);
	_spin_y.set_value_no_signal(_value.y);
	_spin_z.set_value_no_signal(_value.z);
	_spin_w.set_value_no_signal(_value.w);

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
	spin.custom_minimum_size = Vector2(100, 0);
	return spin;
