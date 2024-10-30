@tool
extends EditorPlugin

static var _temp_slice_color := Color.YELLOW;
static var _default_slice_color := Color.WHITE;
static var _selected_slice_color := Color.GREEN;
static var _preview_slice_color := Color.BLUE;
static var _selected_handle_texture := EditorInterface.get_editor_theme().get_icon("EditorHandle", "EditorIcons");

var _gui_instance : Control;
static var _window_name := "AtlasTexture Manager";
static var _window_name_changed := "(*) AtlasTexture Manager";

#region EditorMethods
func _enter_tree() -> void:
	_gui_instance = _build_gui();
	_update_controls();
	_reset_inspecting_metrics();
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, _gui_instance);
	pass;

func _exit_tree() -> void:
	remove_control_from_bottom_panel(_gui_instance);
	_gui_instance.queue_free();
	pass;

func _handles(object) -> bool:
	var texture2D = object as Texture2D;
	if !texture2D or texture2D is AtlasTexture:
		return false;
	return !texture2D.resource_path.contains("::");

func _edit(object : Object) -> void:
	_set_editing_texture(object as Texture2D);
#endregion

func _build_gui() -> Control:
	var view := VBoxContainer.new();
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	view.add_child(_build_top_tool_bar());
	var additive_bottom_elements : Array[Control] = [];
	view.add_child(_build_main_viewport(additive_bottom_elements));
	view.add_child(_build_btm_tool_bar(additive_bottom_elements));
	return view;

func _build_top_tool_bar() -> Control:
	var top_tool_container := HBoxContainer.new();
	
	_slicer_toggle = _check_button("AtlasTexture Slicer");
	
	var scan_function := func(all_directories : bool):
		_editing_atlas_texture_info.clear();
		_inspecting_atlas_texture_info = null;
		
		var scan_result : Array[EditingAtlasTextureInfo] = [];
		
		var file_system := EditorInterface.get_resource_filesystem();
		
		if all_directories:
			var directory := file_system.get_filesystem();
			_find_texture_in_dir_recursive(_inspecting_texture, directory, scan_result);
		else:
			var source_path := _inspecting_texture.resource_path;
			var directory_path := source_path.get_base_dir();
			var directory := file_system.get_filesystem_path(directory_path);
			_find_texture_in_dir(_inspecting_texture, directory, scan_result);
			pass
		
		_editing_atlas_texture_info.append_array(scan_result);
		_reset_inspecting_metrics();
		_update_controls();
		
	var scan_in_dir_btn := _button("Scan in Directory", func(): scan_function.call(false));
	var scan_in_proj_btn := _button("Scan in Project", func(): scan_function.call(true));

	top_tool_container.add_child(_slicer_toggle);
	top_tool_container.add_child(_hspacer());
	top_tool_container.add_child(scan_in_dir_btn);
	top_tool_container.add_child(scan_in_proj_btn);
	return top_tool_container;
	

var _save_btn : Button;
var _discard_btn : Button;
	
func _build_btm_tool_bar(additive_elements : Array[Control]) -> Control:
	var btm_tool_container := HBoxContainer.new();
	
	_save_btn = _button("Discard", func():
		var deleting_atlas : Array[EditingAtlasTextureInfo] = [];
		for info in _editing_atlas_texture_info:
			if info.is_temp(): deleting_atlas.append(info);
			else : info.discard_changes();
		for info in deleting_atlas:
			if _inspecting_atlas_texture_info == info: _inspecting_atlas_texture_info = null;
			_editing_atlas_texture_info.erase(info);
		_update_controls();
		if _inspecting_atlas_texture_info: 
			_update_inspecting_metrics(_inspecting_atlas_texture_info);
		else: 
			_reset_inspecting_metrics();
	);
	
	_discard_btn = _button("Create & Update", func():
		var editor_file_system = EditorInterface.get_resource_filesystem();
		for info in _editing_atlas_texture_info:
			var path := info.apply_changes(_inspecting_texture, _current_source_texture_path)
			editor_file_system.update_file(path);
			
		editor_file_system.scan();
		
		_update_controls();
		if _inspecting_atlas_texture_info: 
			_update_inspecting_metrics(_inspecting_atlas_texture_info);
		else: 
			_reset_inspecting_metrics();
	);
	
	for item in additive_elements:
		btm_tool_container.add_child(item)
	btm_tool_container.add_child(_hspacer());
	btm_tool_container.add_child(_save_btn);
	btm_tool_container.add_child(_discard_btn);
	
	return btm_tool_container;
	
var _slicer_toggle : CheckButton;
var _hscroll : HScrollBar;
var _vscroll : VScrollBar;
	
var _preview_texture : CanvasTexture;
var _inspecting_texture : Texture2D;
var _current_source_texture_path : String;
var _dragging_handle_start_region : Rect2;
var _dragging_mouse_position_offset : Vector2;
var _dragging_handle : DRAG_TYPE;
var _modifying_region_buffer : Rect2;
var _dragging_handle_position : Vector2;
var _draw_offsets : Vector2;
var _draw_zoom : float;
var _is_dragging : bool;
var _is_updating_scroll : bool;
var _is_requesting_center : bool;
var _drag_type : DRAG_TYPE;
var _editing_atlas_texture_info : Array[EditingAtlasTextureInfo] = [];
var _slice_preview : Array[Rect2] = [];
var _view_panner : ViewPanner;
var _editor_drawer : Control;

var _inspecting_atlas_texture_info : EditingAtlasTextureInfo;
var _inspecting_tex_name : String;

enum DRAG_TYPE
{
	NONE = -1,
	AREA = -2,
	HANDLE_TOP_LEFT = 0,
	HANDLE_TOP = 1,
	HANDLE_TOP_RIGHT = 2,
	HANDLE_RIGHT = 3,
	HANDLE_BOTTOM_RIGHT = 4,
	HANDLE_BOTTOM = 5,
	HANDLE_BOTTOM_LEFT = 6,
	HANDLE_LEFT = 7,
}

var _mini_inspector_window : Control;

func _build_main_viewport(bottom_elements : Array[Control]) -> Control:
	var main_viewport := PanelContainer.new();
	main_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	main_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	
	var _editor_drawer_main := Panel.new();
	_editor_drawer_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_editor_drawer_main.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	main_viewport.add_child(_editor_drawer_main);
	
	_editor_drawer = Control.new();
	_editor_drawer.clip_contents = true;
	_editor_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_KEEP_SIZE);
	_editor_drawer_main.add_child(_editor_drawer);
	
	_mini_inspector_window = _build_mini_inspector();
	_editor_drawer.add_child(_mini_inspector_window);
	_mini_inspector_window.call_deferred(&"set_anchors_and_offsets_preset", Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10);
	
	_hscroll = HScrollBar.new();
	_vscroll = VScrollBar.new();
	_editor_drawer_main.add_child(_hscroll);
	_editor_drawer_main.add_child(_vscroll);
	
	_hscroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE);
	_vscroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE);

	_preview_texture = CanvasTexture.new();
	
#region Draw
	_editor_drawer.draw.connect(func():
		if !_inspecting_texture: return;
		
		var transform2D := Transform2D(
			Vector2(_draw_zoom, 0),
			Vector2(0, _draw_zoom),
			-_draw_offsets * _draw_zoom
		);
		
		var rid := _editor_drawer.get_canvas_item();
		RenderingServer.canvas_item_add_set_transform(rid, transform2D);
		
		_editor_drawer.draw_rect(
			Rect2(Vector2.ZERO, _preview_texture.get_size()),
			Color(.5,.5,.5,.5),
			false
		);
		
		_editor_drawer.draw_texture(_preview_texture, Vector2.ZERO);
		
		var scroll_rect := Rect2(Vector2.ZERO, _inspecting_texture.get_size());
		
		if _is_dragging:
			_draw_rect_frame(_modifying_region_buffer, _selected_handle_texture, _selected_slice_color, _drag_type);
		else:
			for info in _editing_atlas_texture_info:
				if info == _inspecting_atlas_texture_info:
					continue;
				_draw_rect_frame(info.region, _selected_handle_texture, _default_slice_color if !info.is_temp() else _temp_slice_color, DRAG_TYPE.AREA);
				
			if _inspecting_atlas_texture_info:
				_draw_rect_frame(_modifying_region_buffer, _selected_handle_texture, _selected_slice_color, DRAG_TYPE.NONE);
				
		if _slicer_toggle.button_pressed:
			for preview_rect in _slice_preview:
				_draw_rect_frame(preview_rect, _selected_handle_texture, _preview_slice_color, DRAG_TYPE.AREA);
				
		RenderingServer.canvas_item_add_set_transform(rid, Transform2D());
		
		var scroll_margin := _editor_drawer.size / _draw_zoom;
		scroll_rect.position -= scroll_margin;
		scroll_rect.size += scroll_margin * 2;
		
		_is_updating_scroll = true;
		
		_hscroll.min_value = scroll_rect.position.x;
		_hscroll.max_value = scroll_rect.position.x + scroll_rect.size.x;
		if absf(scroll_rect.position.x - (scroll_rect.position.x + scroll_rect.size.x)) <= scroll_margin.x:
			_hscroll.hide();
		else:
			_hscroll.show();
			_hscroll.page = scroll_margin.x;
			_hscroll.value = _draw_offsets.x;

		_vscroll.min_value = scroll_rect.position.y;
		_vscroll.max_value = scroll_rect.position.y + scroll_rect.size.y;
		if absf(scroll_rect.position.y - (scroll_rect.position.y + scroll_rect.size.y)) <= scroll_margin.y:
			_vscroll.hide();
			_draw_offsets.y = scroll_rect.position.y;
		else:
			_vscroll.show();
			_vscroll.page = scroll_margin.y;
			_vscroll.value = _draw_offsets.y;
			
		var _hscroll_min_size := _hscroll.get_combined_minimum_size();
		var _vscroll_min_size := _vscroll.get_combined_minimum_size();

		_hscroll.set_anchor_and_offset(SIDE_RIGHT, Control.Anchor.ANCHOR_END, -_hscroll_min_size.x if _vscroll.visible else 0.0);
		_vscroll.set_anchor_and_offset(SIDE_BOTTOM, Control.Anchor.ANCHOR_END, -_vscroll_min_size.y if _hscroll.visible else 0.0);

		_is_updating_scroll = false;

		if !_is_requesting_center or _hscroll.min_value >= 0: return;

		_hscroll.value = (_hscroll.min_value + _hscroll.max_value - _hscroll.page) / 2;
		_vscroll.value = (_vscroll.min_value + _vscroll.max_value - _vscroll.page) / 2;
		
		call_deferred(&"_pan", Vector2(1, 0));
		
		_is_requesting_center = false;
	);
#endregion
#region Input
	_editor_drawer.gui_input.connect(func(input_event : InputEvent):
		if !_inspecting_texture: return;
		
		if _get_view_panner().process_gui_input(input_event, Rect2()): return;
		
		var mouse_motion := input_event as InputEventMouseMotion;
		if mouse_motion:
			if (mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0: return;
			if !_is_dragging: return
			
			var new_mouse_position := (mouse_motion.position + _draw_offsets * _draw_zoom) / _draw_zoom;
			var diff := new_mouse_position + _dragging_mouse_position_offset - _dragging_handle_position;

			var region := _dragging_handle_start_region;

			if _dragging_handle == DRAG_TYPE.AREA: region.position += diff;
			else: region = _calculate_offset(region, _dragging_handle, diff);
				
			region = Rect2(region.position.round(), region.size.round());
			
			_modifying_region_buffer = region;
			
			_editor_drawer.queue_redraw();
			pass;
		var mouse_button := input_event as InputEventMouseButton;
		if mouse_button:
			if !mouse_button.pressed:
				if !_is_dragging: return;
				
				var flush_region_modifying_buffer_function := func():
					if !_inspecting_atlas_texture_info:
						if !_modifying_region_buffer.has_area(): return;
						_create_slice_and_set_to_inspecting(_modifying_region_buffer, Rect2(), false);
					else:
						if !_inspecting_atlas_texture_info.try_set_region(_modifying_region_buffer): return;
						_update_inspecting_metrics(_inspecting_atlas_texture_info);
					_update_controls();
				
				flush_region_modifying_buffer_function.call();
				_is_dragging = false;
				return;
				
			if (mouse_button.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0: return;
			if _is_dragging: return;
			
			var local_mouse_position := (mouse_button.position + _draw_offsets * _draw_zoom) / _draw_zoom;
			
			var process_mouse_drag_update_function := func():
				var draw_zoom := 11.25 / _draw_zoom;
				for info in _editing_atlas_texture_info:
					var handle_positions := _get_handle_positions_for_rect_frame(info.region);
					for index in range(handle_positions.size()):
						var handle_position := handle_positions[index];
						if local_mouse_position.distance_to(handle_position) > draw_zoom: continue;
						_dragging_handle = index as DRAG_TYPE;
						_dragging_handle_position = handle_position;
						_inspecting_atlas_texture_info = info;
						return;
				
				for info in _editing_atlas_texture_info:
					var region := info.region;
					if !region.has_point(local_mouse_position): continue;
					_dragging_handle = DRAG_TYPE.AREA;
					_dragging_handle_position = local_mouse_position;
					_inspecting_atlas_texture_info = info;
					return;
					
				_dragging_handle = DRAG_TYPE.HANDLE_BOTTOM_RIGHT;
				_dragging_handle_position = local_mouse_position;
				_inspecting_atlas_texture_info = null;
			
			process_mouse_drag_update_function.call();
			
			_is_dragging = true;
			
			if !_inspecting_atlas_texture_info:
				_dragging_mouse_position_offset = Vector2.ZERO;
				_dragging_handle_start_region = Rect2(local_mouse_position, Vector2.ZERO);
				_modifying_region_buffer = _dragging_handle_start_region;
				_reset_inspecting_metrics();
			else:
				_dragging_mouse_position_offset = local_mouse_position - _dragging_handle_position;
				_dragging_handle_start_region = _inspecting_atlas_texture_info.region;
				_modifying_region_buffer = _dragging_handle_start_region;
				_update_controls();
				_update_inspecting_metrics(_inspecting_atlas_texture_info);
			_editor_drawer.queue_redraw();
			pass;
		var magnify_gesture := input_event as InputEventMagnifyGesture;
		if magnify_gesture:
			_zoom(_draw_zoom * magnify_gesture.factor, magnify_gesture.position);
			pass;
		var pan_gesture := input_event as InputEventPanGesture;
		if pan_gesture:
			_hscroll.value += _hscroll.page * pan_gesture.delta.x / 8;
			_vscroll.value += _vscroll.page * pan_gesture.delta.y / 8;
			pass;
	);
	_editor_drawer.focus_exited.connect(_get_view_panner().release_pan_key);
#endregion
	
	_draw_zoom = 1.0;
	
	bottom_elements.append(_zoom_button("Zoom Out", "ZoomLess", func(): _zoom(_draw_zoom / 1.5, _editor_drawer.size / 2.0)));
	bottom_elements.append(_zoom_button("Zoom Reset", "ZoomReset", func(): _zoom(1.0, _editor_drawer.size / 2.0)));
	bottom_elements.append(_zoom_button("Zoom In", "ZoomMore", func(): _zoom(_draw_zoom * 1.5, _editor_drawer.size / 2.0)));
	
	var scroll_changed := func(value : float):
		if _is_updating_scroll: return;
		_draw_offsets = Vector2(_hscroll.value, _vscroll.value);
		_editor_drawer.queue_redraw();
	
	_hscroll.value_changed.connect(scroll_changed);
	_vscroll.value_changed.connect(scroll_changed);
	
	return main_viewport;

var _title_label : Label;
var _new_label : Label;
var _name_line_edit : LineEdit;
var _region_x_spin_box : SpinBox;
var _region_y_spin_box : SpinBox;
var _region_w_spin_box : SpinBox;
var _region_h_spin_box : SpinBox;
var _margin_x_spin_box : SpinBox;
var _margin_y_spin_box : SpinBox;
var _margin_w_spin_box : SpinBox;
var _margin_h_spin_box : SpinBox;
var _filter_clip_check_box : CheckBox;
var _delete_slice_btn : Button;

func _build_mini_inspector() -> Control:
	var outer_container := PanelContainer.new();
	outer_container.self_modulate = Color(Color.WHITE, .5);
	var panel := Panel.new();
	panel.self_modulate = Color(Color.WHITE, .5);
	outer_container.add_child(panel);
	var margin_container := MarginContainer.new();
	margin_container.add_theme_constant_override(&"margin_left", 10);
	margin_container.add_theme_constant_override(&"margin_top", 10);
	margin_container.add_theme_constant_override(&"margin_right", 10);
	margin_container.add_theme_constant_override(&"margin_bottom", 10);
	outer_container.add_child(margin_container);
	var vbox_container := VBoxContainer.new();
	vbox_container.alignment = BoxContainer.ALIGNMENT_CENTER;
	margin_container.add_child(vbox_container);
	
	var title_hbox := HBoxContainer.new();
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	vbox_container.add_child(title_hbox);
	
	_title_label = _label("Atlas Texture");
	_new_label = _label("(New)");
	title_hbox.add_child(_title_label);
	title_hbox.add_child(_new_label);
	
	var grid := GridContainer.new();
	grid.columns = 2;
	grid.add_theme_constant_override("h_separation", 20);
	vbox_container.add_child(grid);
	
	grid.add_child(_label("Name"));
	_name_line_edit = _line_edit(func(value : String):
		if !_inspecting_atlas_texture_info or !_inspecting_atlas_texture_info.is_temp() or !_inspecting_atlas_texture_info.try_set_name(value): return;
		_update_controls();
	);
	grid.add_child(_name_line_edit);
	grid.add_child(_label("Region"));
	
	var region_grid := GridContainer.new();
	region_grid.columns = 4;
	grid.add_child(region_grid);
	
	region_grid.add_child(_label("X"));
	
	_region_x_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var region := _inspecting_atlas_texture_info.region;
		region.position.x = value;
		if !_inspecting_atlas_texture_info.try_set_region(region): return;
		_update_controls();
	);
	region_grid.add_child(_region_x_spin_box);
	
	region_grid.add_child(_label("Y"));
	
	_region_y_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var region := _inspecting_atlas_texture_info.region;
		region.position.y = value;
		if !_inspecting_atlas_texture_info.try_set_region(region): return;
		_update_controls();
	);
	region_grid.add_child(_region_y_spin_box);
	
	region_grid.add_child(_label("W"));
	
	_region_w_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var region := _inspecting_atlas_texture_info.region;
		region.size.x = value;
		if !_inspecting_atlas_texture_info.try_set_region(region): return;
		_update_controls();
	);
	region_grid.add_child(_region_w_spin_box);
	
	region_grid.add_child(_label("H"));
	
	_region_h_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var region := _inspecting_atlas_texture_info.region;
		region.size.y = value;
		if !_inspecting_atlas_texture_info.try_set_region(region): return;
		_update_controls();
	);
	region_grid.add_child(_region_h_spin_box);
	
	grid.add_child(_label("Margin"));
	
	var margin_grid := GridContainer.new();
	margin_grid.columns = 4;
	grid.add_child(margin_grid);
	
	margin_grid.add_child(_label("X"));
	
	_margin_x_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var margin := _inspecting_atlas_texture_info.margin;
		margin.position.x = value;
		if !_inspecting_atlas_texture_info.try_set_margin(margin): return;
		_update_controls();
	);
	margin_grid.add_child(_margin_x_spin_box);
	
	margin_grid.add_child(_label("Y"));
	
	_margin_y_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var margin := _inspecting_atlas_texture_info.margin;
		margin.position.y = value;
		if !_inspecting_atlas_texture_info.try_set_margin(margin): return;
		_update_controls();
	);
	margin_grid.add_child(_margin_y_spin_box);
	
	margin_grid.add_child(_label("W"));
	
	_margin_w_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var margin := _inspecting_atlas_texture_info.margin;
		margin.size.x = value;
		if !_inspecting_atlas_texture_info.try_set_margin(margin): return;
		_update_controls();
	);
	margin_grid.add_child(_margin_w_spin_box);
	
	margin_grid.add_child(_label("H"));
	
	_margin_h_spin_box = _spin(func(value : float):
		if !_inspecting_atlas_texture_info: return;
		var margin := _inspecting_atlas_texture_info.margin;
		margin.size.y = value;
		if !_inspecting_atlas_texture_info.try_set_margin(margin): return;
		_update_controls();
	);
	margin_grid.add_child(_margin_h_spin_box);
	
	grid.add_child(_label("Filter Clip"));
	
	_filter_clip_check_box = _check_box("Enabled");
	grid.add_child(_filter_clip_check_box);
	
	_delete_slice_btn = _button("Delete", func():
		if !_inspecting_atlas_texture_info or !_inspecting_atlas_texture_info.is_temp(): return;
		_editing_atlas_texture_info.erase(_inspecting_atlas_texture_info);
		_inspecting_atlas_texture_info = null;
		_update_controls();
	);
	vbox_container.add_child(_delete_slice_btn);
	
	return outer_container;

func _get_handle_positions_for_rect_frame(rect : Rect2) -> Array[Vector2]:
	var raw_end_point_0 := rect.position;
	var raw_end_point_1 := rect.position + Vector2(rect.size.x, 0);
	var raw_end_point_2 := rect.end;
	var raw_end_point_3 := rect.position + Vector2(0, rect.size.y);
	var array : Array[Vector2] = [];
	array.resize(8);
	_calculate_handle_position(raw_end_point_0, raw_end_point_3, raw_end_point_1, array, 0);
	_calculate_handle_position(raw_end_point_1, raw_end_point_0, raw_end_point_2, array, 2);
	_calculate_handle_position(raw_end_point_2, raw_end_point_1, raw_end_point_3, array, 4);
	_calculate_handle_position(raw_end_point_3, raw_end_point_2, raw_end_point_0, array, 6);
	return array;
	
func _calculate_handle_position(position : Vector2, prev_position : Vector2, next_position : Vector2, array : Array[Vector2], index : int) -> void:
	var offset := ((position - prev_position).normalized() + (position - next_position).normalized()).normalized() * 10.0 / _draw_zoom;
	
	array[index] = position + offset;
	
	offset = (next_position - position) / 2;
	offset += (next_position - position).orthogonal().normalized() * 10.0 / _draw_zoom;
	
	array[index + 1] = position + offset;

func _create_slice_and_set_to_inspecting(region : Rect2, margin : Rect2, fileter_clip : bool) -> void:
	_inspecting_atlas_texture_info = EditingAtlasTextureInfo.create_empty(
			region, 
			margin,
			fileter_clip,
			_inspecting_tex_name,
			_editing_atlas_texture_info
		);
	return;
	_editing_atlas_texture_info.append(_inspecting_atlas_texture_info);
	_update_inspecting_metrics(_inspecting_atlas_texture_info);

# 无法创建多个切片
func _set_editing_texture(texture : Texture2D) -> void:
	if _inspecting_texture:
		_inspecting_texture.changed.disconnect(_on_tex_changed);
		_inspecting_texture = null;
		_editing_atlas_texture_info.clear();
		_inspecting_atlas_texture_info = null;
		_reset_inspecting_metrics();
		_hide_slicer_menu();
		_slicer_toggle.set_pressed_no_signal(false);
	_inspecting_texture = texture;
	_update_controls();
	if !_inspecting_texture:
		_hide_slicer_menu();
		return;
	_inspecting_tex_name = _inspecting_texture.resource_path.get_file().get_basename();
	_current_source_texture_path = _inspecting_texture.resource_path.get_base_dir();
	_inspecting_texture.changed.connect(_on_tex_changed);
	_update_inspecting_texture();
	_editor_drawer.queue_redraw();
	_is_requesting_center = true;
	pass;

func _on_tex_changed() -> void:
	if !_gui_instance or !_gui_instance.visible: return;
	_update_inspecting_texture();

func _update_inspecting_texture() -> void:
	var texture := _inspecting_texture;
	if !texture:
		_preview_texture.diffuse_texture = null;
		_zoom(1.0, _editor_drawer.size / 2.0);
		_hscroll.hide();
		_vscroll.hide();
		_editor_drawer.queue_redraw();
		return;
		
	_preview_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS;
	_preview_texture.diffuse_texture = texture;
	_editor_drawer.queue_redraw();


func _reset_inspecting_metrics() -> void:
	_name_line_edit.text = "";

	_new_label.hide();
	_delete_slice_btn.disabled = true;

	_region_x_spin_box.set_value_no_signal(0.0);
	_region_y_spin_box.set_value_no_signal(0.0);
	_region_w_spin_box.set_value_no_signal(0.0);
	_region_h_spin_box.set_value_no_signal(0.0);

	_margin_x_spin_box.set_value_no_signal(0.0);
	_margin_y_spin_box.set_value_no_signal(0.0);
	_margin_w_spin_box.set_value_no_signal(0.0);
	_margin_h_spin_box.set_value_no_signal(0.0);

	_filter_clip_check_box.set_pressed_no_signal(false);

func _update_inspecting_metrics(info : EditingAtlasTextureInfo) -> void:
	_name_line_edit.text = info.name;
	var is_temp := info.is_temp();
	_name_line_edit.editable = is_temp;
	_new_label.visible = is_temp;
	_delete_slice_btn.disabled = !is_temp;

	_region_x_spin_box.set_value_no_signal(info.region.position.x);
	_region_y_spin_box.set_value_no_signal(info.region.position.y);
	_region_w_spin_box.set_value_no_signal(info.region.size.x);
	_region_h_spin_box.set_value_no_signal(info.region.size.y);

	_margin_x_spin_box.set_value_no_signal(info.margin.position.x);
	_margin_y_spin_box.set_value_no_signal(info.margin.position.y);
	_margin_w_spin_box.set_value_no_signal(info.margin.size.x);
	_margin_h_spin_box.set_value_no_signal(info.margin.size.y);

	_filter_clip_check_box.set_pressed_no_signal(info.filter_clip);
	
func _update_controls() -> void:
	var is_editing_asset := true if _inspecting_texture else false;
	_gui_instance.propagate_call(&"set_disabled", [!is_editing_asset]);
	_gui_instance.propagate_call(&"set_editable", [is_editing_asset]);
	_gui_instance.modulate = Color.WHITE if is_editing_asset else Color(1.0, 1.0, 1.0, 0.5);

	var has_pending_changes := false;
	
	for item in _editing_atlas_texture_info:
		if !item.modified: continue;
		has_pending_changes = true;
		break;
	
	_gui_instance.name = _window_name if !has_pending_changes else _window_name_changed;

	_discard_btn.disabled = !has_pending_changes;
	_save_btn.disabled = !has_pending_changes;

	var is_inspecting_atlas_texture := true if _inspecting_atlas_texture_info else false;
	_mini_inspector_window.propagate_call(&"set_disabled", [!is_inspecting_atlas_texture]);
	_mini_inspector_window.propagate_call(&"set_editable", [is_inspecting_atlas_texture]);
	_mini_inspector_window.modulate = Color.WHITE if is_inspecting_atlas_texture else Color(1.0, 1.0, 1.0, 0.5);

	_editor_drawer.queue_redraw();
	pass;

func _calculate_offset(region : Rect2, drag_type : DRAG_TYPE, diff : Vector2) -> Rect2:
	match drag_type:
		DRAG_TYPE.HANDLE_TOP_LEFT: return region.grow_individual(-diff.x, -diff.y, 0, 0);
		DRAG_TYPE.HANDLE_TOP: return region.grow_individual(0, -diff.y, 0, 0);
		DRAG_TYPE.HANDLE_TOP_RIGHT: return region.grow_individual(0, -diff.y, diff.x, 0);
		DRAG_TYPE.HANDLE_RIGHT: return region.grow_individual(0, 0, diff.x, 0);
		DRAG_TYPE.HANDLE_BOTTOM_RIGHT: return region.grow_individual(0, 0, diff.x, diff.y);
		DRAG_TYPE.HANDLE_BOTTOM: return region.grow_individual(0, 0, 0, diff.y);
		DRAG_TYPE.HANDLE_BOTTOM_LEFT: return region.grow_individual(-diff.x, 0, 0, diff.y);
		DRAG_TYPE.HANDLE_LEFT: return region.grow_individual(-diff.x, 0, 0, 0);
	return region;

func _get_view_panner() -> ViewPanner:
	
	if !_view_panner:
		_view_panner = ViewPanner.new();
		_view_panner.panned.connect(_pan);
		_view_panner.zoomed.connect(func(zoom : float, position : Vector2):
			_zoom(zoom * _draw_zoom, position);
		);
		var editor_settings := EditorInterface.get_editor_settings();
		_view_panner.control_scheme = editor_settings.get_setting("editors/panning/sub_editors_panning_scheme") as ViewPanner.CONTROL_SCHEME;
		_view_panner.is_simple_panning = editor_settings.get_setting("editors/panning/simple_panning") as bool;
	
	return _view_panner;

func _zoom(zoom : float, position : Vector2) -> void:
	if zoom < 0.1 or zoom > 50:
		return;
		
	var prev_zoom := _draw_zoom;
	_draw_zoom = zoom;
	var offset := position;
	offset = offset / prev_zoom - offset / _draw_zoom;
	_draw_offsets = (_draw_offsets + offset).round();
	_editor_drawer.queue_redraw();
	
func _pan(scroll_vec : Vector2) -> void:
	scroll_vec /= _draw_zoom;
	_hscroll.value -= scroll_vec.x;
	_vscroll.value -= scroll_vec.y;

#region GUI Utilities
func _label(text : String) -> Label:
	var label := Label.new();
	label.text = text;
	return label;

func _button(text : String, on_press : Callable) -> Button:
	var button := Button.new();
	button.text = text;
	button.pressed.connect(on_press);
	return button;

func _line_edit(value_changed : Callable) -> LineEdit:
	var line_edit := LineEdit.new();
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	return line_edit;

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

func _check_box(text : String) -> CheckBox:
	var box := CheckBox.new();
	box.text = text;
	return box;

func _check_button(text : String) -> CheckButton:
	var button := CheckButton.new();
	button.text = text;
	return button;

func _hspacer() -> Control:
	var spacer := Control.new();
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	return spacer;
	
func _zoom_button(tooltip_text : String, icon_name : String, on_press : Callable) -> Button:
	var button := Button.new();
	button.flat = true;
	button.tooltip_text = tooltip_text;
	button.icon = EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons");
	button.pressed.connect(on_press);
	return button;
#endregion

#region Draw Utilities
func _draw_rect_frame(rect : Rect2, handle_texture : Texture2D, color : Color, handle_type : DRAG_TYPE):
	var positions := _get_handle_positions_for_rect_frame(rect);
	_editor_drawer.draw_rect(rect, Color.BLACK, false, 4 / _draw_zoom);
	_editor_drawer.draw_rect(rect, color, false, 2 / _draw_zoom);
	
	var handle_size := handle_texture.get_size() * 1.5 / _draw_zoom;
	var handle_size_half := handle_size / 2;
	
	match handle_type:
		DRAG_TYPE.NONE:
			for position in positions:
				_editor_drawer.draw_texture_rect(handle_texture, Rect2(position - handle_size_half, handle_size), false);
			return;
		DRAG_TYPE.AREA:
			return;
		
	_editor_drawer.draw_texture_rect(handle_texture, Rect2(positions[handle_type as int] - handle_size_half, handle_size), false);

#endregion
		
#region Other

func _find_texture_in_dir(source_tex : Texture2D, directory : EditorFileSystemDirectory, scan_result : Array[EditingAtlasTextureInfo]):
	var file_count := directory.get_file_count();
	for i in range(file_count):
		if directory.get_file_type(i) != &"AtlasTexture": continue;
		var file_path := directory.get_file_path(i);
		var resource := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE);
		var atlas_candidate := resource as AtlasTexture;
		if atlas_candidate.atlas == source_tex:
			scan_result.append(EditingAtlasTextureInfo.create(atlas_candidate, file_path));
	
func _find_texture_in_dir_recursive(source_tex : Texture2D, directory : EditorFileSystemDirectory, scan_result : Array[EditingAtlasTextureInfo]):
	_find_texture_in_dir(source_tex, directory, scan_result);
	var sub_dir_count := directory.get_subdir_count();
	for i in range(sub_dir_count):
		var sub_dir := directory.get_subdir(i);
		_find_texture_in_dir_recursive(source_tex, sub_dir, scan_result);
#endregion

#region Slicer
func _hide_slicer_menu() -> void:
	# TODO
	pass
#endregion
