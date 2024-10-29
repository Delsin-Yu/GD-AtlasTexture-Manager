class_name ViewPanner
extends RefCounted

signal panned(position : Vector2);
signal zoomed(zoom_level : float, mouse_position : Vector2);

enum CONTROL_SCHEME
{
	SCROLL_ZOOMS,
	SCROLL_PANS
}

enum PAN_AXIS
{
	BOTH,
	HORIZONTAL,
	VERTICAL
}

var control_scheme := CONTROL_SCHEME.SCROLL_ZOOMS;
var pan_axis := PAN_AXIS.BOTH;
var scroll_speed := 32.0;
var enable_right_mouse_button := false;
var is_simple_panning := false;
var force_drag := false;
var pan_shortcut : Shortcut;

var _is_dragging : bool;
var _is_pan_key_pressed : bool;
var _scroll_zoom_factor := 1.1;


func _emit_pan(position : Vector2) -> void:
	panned.emit(position);
	
func _emit_zoom(zoom_level : float, mouse_position : Vector2) -> void:
	zoomed.emit(zoom_level, mouse_position);

func release_pan_key() -> void:
	_is_pan_key_pressed = false;
	_is_dragging = false;

func process_gui_input(input_event : InputEvent, canvas_rect : Rect2) -> bool:
	var mouse_button := input_event as InputEventMouseButton;
	if mouse_button:
		var scroll_vector := Vector2(
			int(mouse_button.button_index == MOUSE_BUTTON_WHEEL_RIGHT) - int(mouse_button.button_index == MOUSE_BUTTON_WHEEL_LEFT),
			int(mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN) - int(mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP));
		
		if scroll_vector != Vector2.ZERO and mouse_button.is_pressed():
			if control_scheme == CONTROL_SCHEME.SCROLL_PANS:
				if mouse_button.is_command_or_control_pressed():
					_handle_zoom(scroll_vector, mouse_button);
				else:
					_handle_pan(scroll_vector, mouse_button);
				return true;
		
			if mouse_button.is_command_or_control_pressed():
				_handle_pan(scroll_vector, mouse_button);
				return true;
				
			if !mouse_button.shift_pressed:
				_handle_zoom(scroll_vector, mouse_button);
				return true;
		
		if mouse_button.alt_pressed:
			return false;
			
		var is_drag_event = mouse_button.button_index == MOUSE_BUTTON_MIDDLE or (enable_right_mouse_button and mouse_button.button_index == MOUSE_BUTTON_RIGHT) or (!is_simple_panning and mouse_button.button_index == MOUSE_BUTTON_LEFT and (_is_dragging or _is_pan_key_pressed)) or (force_drag and mouse_button.button_index == MOUSE_BUTTON_LEFT);
			
		if is_drag_event:
			_is_dragging = mouse_button.is_pressed();
			return mouse_button.button_index != MOUSE_BUTTON_LEFT or mouse_button.is_pressed();
		
		return false;
		
	var mouse_motion := input_event as InputEventMouseMotion;
	if mouse_motion:
		
		if !_is_dragging:
			return false;
			
		_emit_pan(mouse_motion.relative);
		
		if canvas_rect != Rect2():
			Input.warp_mouse(mouse_motion.position);
			
		return true;
		
	var magnify_gesture := input_event as InputEventMagnifyGesture;
	if magnify_gesture:
		
		_emit_zoom(magnify_gesture.factor, magnify_gesture.position);
		
		return true;
		
	var pan_gesture := input_event as InputEventPanGesture;
	if pan_gesture:
		
		_emit_pan(-pan_gesture.delta * scroll_speed);
		
		return true;
		
	var screen_drag := input_event as InputEventScreenDrag;
	if screen_drag:
		
		_emit_pan(screen_drag.relative);
		
		return true;
		
	var key := input_event as InputEventKey;
	if key:
		
		if pan_shortcut and pan_shortcut.has_valid_event() and pan_shortcut.matches_event(key):
			_is_pan_key_pressed	 = key.is_pressed();
		
		if (is_simple_panning or (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0):
			_is_dragging = true;
		
		return true;
		
	return false;

func _handle_pan(scroll_vector : Vector2, mouse_button : InputEventMouseButton) -> void:
	var panning := scroll_vector * mouse_button.factor;
	match pan_axis:
		PAN_AXIS.HORIZONTAL:
			panning = Vector2(panning.x + panning.y, 0);
		PAN_AXIS.VERTICAL:
			panning = Vector2(0, panning.x + panning.y);
		PAN_AXIS.BOTH:
			if mouse_button.shift_pressed:
				panning = Vector2(panning.y, panning.x);
	_emit_pan(-panning * scroll_speed);
	
func _handle_zoom(scroll_vector : Vector2, mouse_button : InputEventMouseButton) -> void:
	var zoom := 1.0 / _scroll_zoom_factor if scroll_vector.x + scroll_vector.y > 0 else _scroll_zoom_factor;
	_emit_zoom(zoom, mouse_button.position);
