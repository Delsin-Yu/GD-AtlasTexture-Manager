@tool
extends EditorPlugin

static var _temp_slice_color := Color.YELLOW;
static var _default_slice_color := Color.WHITE;
static var _selected_slice_color := Color.GREEN;
static var _changed_slice_color := Color.GREEN_YELLOW;
static var _preview_slice_color := Color.CYAN;
static var _dim_slice_color := Color.GRAY;
static var _pending_delete_color := Color(1.0, 0.35, 0.35);
static var _marquee_fill_color := Color(0.3, 0.6, 1.0, 0.25);
static var _marquee_outline_color := Color(0.3, 0.6, 1.0, 0.8);
static var _selected_handle_texture := EditorInterface.get_editor_theme().get_icon("EditorHandle", "EditorIcons");

var _gui_instance : Control;
var _resource_filesystem := EditorInterface.get_resource_filesystem();
var _local_undo : UndoRedo;
var _history_list : ItemList;
var _history_undo_btn : Button;
var _history_redo_btn : Button;
var _history_updating := false;

const _window_name := "AtlasTexture Manager";
const _window_name_changed := "(*) AtlasTexture Manager";
const _transparent := Color(Color.WHITE, 0.5);
const _DeletionConfirmDialog := preload("res://addons/AtlasTextureManager/atlas_slice_deletion_confirm_dialog.gd");


#region EditorMethods
var _dock : EditorDock;
func _enter_tree() -> void:
	_local_undo = UndoRedo.new();
	_local_undo.set_max_steps(64);
	_gui_instance = _build_gui();
	_update_controls();
	_reset_inspecting_metrics();
	_hide_slicer_menu();
	_dock = EditorDock.new();
	_dock.title = _window_name;
	_dock.icon_name = "AtlasTexture";
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM;
	_dock.add_child(_gui_instance);
	add_dock(_dock);
	_resource_filesystem.filesystem_changed.connect(_on_filesystem_changed);
	_resource_filesystem.resources_reload.connect(_on_resources_reload);

func _exit_tree() -> void:
	remove_dock(_dock);
	_resource_filesystem.filesystem_changed.disconnect(_on_filesystem_changed);
	_resource_filesystem.resources_reload.disconnect(_on_resources_reload);
	_dock.queue_free();
	_dock = null;
	if _local_undo:
		_local_undo.free();
		_local_undo = null;

func _handles(object) -> bool:
	var texture2D = object as Texture2D;
	if !texture2D or texture2D is AtlasTexture:
		return false;
	return !texture2D.resource_path.contains("::");

func _edit(object : Object) -> void:
	_set_editing_texture(object as Texture2D);
#endregion

func _on_filesystem_changed() -> void:
	if _editing_atlas_texture_info:
		for info in _editing_atlas_texture_info:
			if info.is_temp(): continue;
			if ResourceLoader.exists(info.resource_path): continue;
			info.convert_to_temp();
		_refresh_atlas_slices();
	if !_inspecting_texture: return;
	if !ResourceLoader.exists(_inspecting_texture.resource_path):
		_set_editing_texture(null);

func _on_resources_reload(resources: PackedStringArray) -> void:
	if !_inspecting_texture: return;
	var reloaded := {};
	for path in resources:
		reloaded[path] = true;
	var selection_paths := _get_selection_paths();
	var temp_refs : Array[EditingAtlasTextureInfo] = [];
	for info in _selected_slices:
		if info.is_temp():
			temp_refs.append(info);
	var primary_path := _inspecting_atlas_texture_info.resource_path if _inspecting_atlas_texture_info and !_inspecting_atlas_texture_info.is_temp() else "";
	var selection_reloaded := false;
	for i in _editing_atlas_texture_info.size():
		var info := _editing_atlas_texture_info[i];
		if info.is_temp() or info.modified: continue;
		if !reloaded.has(info.resource_path): continue;
		var atlas := ResourceLoader.load(info.resource_path) as AtlasTexture;
		if !atlas: continue;
		_editing_atlas_texture_info[i] = EditingAtlasTextureInfo.create(atlas, info.resource_path);
		if selection_paths.has(info.resource_path) or info.resource_path == primary_path:
			selection_reloaded = true;
	if selection_reloaded:
		_restore_selection_by_paths(selection_paths, primary_path, temp_refs);
	_update_controls();

func _build_gui() -> Control:
	var view := VBoxContainer.new();
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	view.add_child(_build_top_tool_bar());
	var additive_bottom_elements : Array[Control] = [];
	var body := HBoxContainer.new();
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	body.add_child(_build_history_panel());
	body.add_child(_build_main_viewport(additive_bottom_elements));
	view.add_child(body);
	view.add_child(_build_btm_tool_bar(additive_bottom_elements));
	return view;

func _build_top_tool_bar() -> Control:
	var top_tool_container := HBoxContainer.new();
	
	_slicer_toggle = _check_button("AtlasTexture Slicer");
	_slicer_toggle.toggled.connect(func(value : bool):
		if !_inspecting_texture: return;
		if value : _show_slicer_menu();
		else: _hide_slicer_menu();
	);
	
	var refresh_btn := _button("Refresh", func():
		if !_inspecting_texture: return;
		_refresh_atlas_slices();
	);

	top_tool_container.add_child(_slicer_toggle);
	top_tool_container.add_child(_hspacer());
	top_tool_container.add_child(refresh_btn);
	return top_tool_container;

var _save_btn : Button;
var _discard_btn : Button;
	
func _build_btm_tool_bar(additive_elements : Array[Control]) -> Control:
	var btm_tool_container := HBoxContainer.new();
	
	_save_btn = _button("Discard", func():
		for info in _editing_atlas_texture_info:
			if info.is_marked_for_deletion():
				info.mark_for_deletion(false);
				continue;
			if info.is_temp():
				continue;
			info.discard_changes();
		var deleting_atlas : Array[EditingAtlasTextureInfo] = [];
		for info in _editing_atlas_texture_info:
			if info.is_temp(): deleting_atlas.append(info);
		for info in deleting_atlas:
			_selected_slices.erase(info);
			if _inspecting_atlas_texture_info == info: _inspecting_atlas_texture_info = null;
			_editing_atlas_texture_info.erase(info);
		_sync_primary_from_selection();
		_clear_local_history();
		_update_controls();
		if _inspecting_atlas_texture_info: 
			_update_inspecting_metrics(_inspecting_atlas_texture_info);
		else: 
			_reset_inspecting_metrics();
	);
	
	_discard_btn = _button("Apply Changes", func():
		_prompt_apply_changes();
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
var _selected_slices : Array[EditingAtlasTextureInfo] = [];
var _marquee_start : Vector2;
var _selection_marquee_rect : Rect2;
var _marquee_additive : bool;
var _group_move_start_regions : Dictionary = {};
var _group_move_preview_regions : Dictionary = {};

const _OWNER_SCAN_BATCH_SIZE := 160;
var _owner_scan_delete_paths : PackedStringArray;
var _owner_scan_delete_set : Dictionary = {};
var _owner_scan_owners_by_file : Dictionary = {};
var _owner_scan_file_paths : Array[String] = [];
var _owner_scan_file_index : int;

enum DRAG_TYPE
{
	NONE = -1,
	AREA = -2,
	MARQUEE = -3,
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
var _slicer_window : Control;

func _build_history_panel() -> Control:
	var panel := VBoxContainer.new();
	panel.custom_minimum_size.x = 200;
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	panel.add_child(_label("History"));
	_history_list = ItemList.new();
	_history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_history_list.item_selected.connect(_on_history_item_selected);
	panel.add_child(_history_list);
	var buttons := HBoxContainer.new();
	_history_undo_btn = _button("Undo", _undo_local_history);
	_history_redo_btn = _button("Redo", _redo_local_history);
	buttons.add_child(_history_undo_btn);
	buttons.add_child(_history_redo_btn);
	panel.add_child(buttons);
	_refresh_history_list();
	return panel;

func _build_main_viewport(bottom_elements : Array[Control]) -> Control:
	var main_viewport := PanelContainer.new();
	main_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	main_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	
	var _editor_drawer_main := Panel.new();
	_editor_drawer_main.self_modulate = _transparent;
	_editor_drawer_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_editor_drawer_main.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	main_viewport.add_child(_editor_drawer_main);
	
	_editor_drawer = Control.new();
	_editor_drawer.clip_contents = true;
	_editor_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_KEEP_SIZE);
	_editor_drawer_main.add_child(_editor_drawer);
	
	_mini_inspector_window = _build_mini_inspector();
	var mini_inspector_container := PanelContainer.new();
	_editor_drawer.add_child(mini_inspector_container);
	mini_inspector_container.call_deferred(&"set_anchors_and_offsets_preset", Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10);
	mini_inspector_container.add_child(_mini_inspector_window);
	mini_inspector_container.mouse_filter = Control.MOUSE_FILTER_PASS;
	_mini_inspector_window.size_flags_horizontal = Control.SIZE_SHRINK_END;
	_mini_inspector_window.size_flags_vertical = Control.SIZE_SHRINK_END;
	
	var selection_hint := _label("Hold Ctrl and left-drag to select multiple slices");
	selection_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE;
	_editor_drawer.add_child(selection_hint);
	selection_hint.call_deferred(&"set_anchors_and_offsets_preset", Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10);
	
	_slicer_window = _build_slicer_menu();
	_editor_drawer.add_child(_slicer_window);
	_slicer_window.call_deferred(&"set_anchors_and_offsets_preset", Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 10);
	
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
			if _dragging_handle == DRAG_TYPE.MARQUEE:
				for info in _editing_atlas_texture_info:
					var draw_color := _get_slice_draw_color(info);
					if _is_selected(info): draw_color = _selected_slice_color;
					_draw_rect_frame(info.region, _selected_handle_texture, draw_color, DRAG_TYPE.AREA);
				_editor_drawer.draw_rect(_selection_marquee_rect, _marquee_fill_color, true);
				_editor_drawer.draw_rect(_selection_marquee_rect, _marquee_outline_color, false, 2 / _draw_zoom);
			elif _dragging_handle == DRAG_TYPE.AREA and _is_group_move_drag():
				for info in _editing_atlas_texture_info:
					if _is_selected(info):
						var preview_region := _group_move_preview_regions.get(info, info.region) as Rect2;
						_draw_rect_frame(preview_region, _selected_handle_texture, _selected_slice_color, DRAG_TYPE.AREA);
					else:
						_draw_rect_frame(info.region, _selected_handle_texture, _dim_slice_color, DRAG_TYPE.AREA);
			else:
				_draw_rect_frame(_modifying_region_buffer, _selected_handle_texture, _selected_slice_color, _dragging_handle);
				for info in _editing_atlas_texture_info:
					if !_is_selected(info):
						_draw_rect_frame(info.region, _selected_handle_texture, _dim_slice_color, DRAG_TYPE.AREA);
		else:
			for info in _editing_atlas_texture_info:
				if _is_selected(info):
					continue;
				_draw_rect_frame(info.region, _selected_handle_texture, _get_slice_draw_color(info), DRAG_TYPE.AREA);
				
			for info in _selected_slices:
				var handle_type := DRAG_TYPE.NONE if _selected_slices.size() == 1 else DRAG_TYPE.AREA;
				var draw_region := _modifying_region_buffer if _selected_slices.size() == 1 and info == _inspecting_atlas_texture_info else info.region;
				_draw_rect_frame(draw_region, _selected_handle_texture, _selected_slice_color, handle_type);
				
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
			
			if _dragging_handle == DRAG_TYPE.MARQUEE:
				_selection_marquee_rect = Rect2(_marquee_start, new_mouse_position - _marquee_start).abs();
				_editor_drawer.queue_redraw();
				return;
			
			var diff := new_mouse_position + _dragging_mouse_position_offset - _dragging_handle_position;

			if _dragging_handle == DRAG_TYPE.AREA and _is_group_move_drag() and !_group_move_start_regions.is_empty():
				diff = diff.round();
				for info in _selected_slices:
					if !_group_move_start_regions.has(info):
						continue;
					var start_region := _group_move_start_regions[info] as Rect2;
					var region := Rect2((start_region.position + diff).round(), start_region.size.round());
					_group_move_preview_regions[info] = region;
					if info == _inspecting_atlas_texture_info:
						_modifying_region_buffer = region;
				_editor_drawer.queue_redraw();
				return;

			var region := _dragging_handle_start_region;

			if _dragging_handle == DRAG_TYPE.AREA: region.position += diff;
			else: region = _calculate_offset(region, _dragging_handle, diff);
				
			region = Rect2(region.position.round(), region.size.round());
			_modifying_region_buffer = region;
			_editor_drawer.queue_redraw();
			
		var mouse_button := input_event as InputEventMouseButton;
		if mouse_button:
			if !mouse_button.pressed:
				if !_is_dragging: return;
				
				if _dragging_handle == DRAG_TYPE.MARQUEE:
					if _selection_marquee_rect.has_area():
						var hits : Array[EditingAtlasTextureInfo] = [];
						for info in _editing_atlas_texture_info:
							if info.region.intersects(_selection_marquee_rect):
								hits.append(info);
						if _marquee_additive:
							var combined := _selected_slices.duplicate();
							for info in hits:
								if !combined.has(info):
									combined.append(info);
							_set_selection(combined, hits.back() if !hits.is_empty() else _inspecting_atlas_texture_info);
						else:
							_set_selection(hits, hits.back() if !hits.is_empty() else null);
					elif !_marquee_additive:
						_clear_selection();
						_update_controls();
					_selection_marquee_rect = Rect2();
					_is_dragging = false;
					_editor_drawer.queue_redraw();
					return;
				
				if _dragging_handle == DRAG_TYPE.AREA and _is_group_move_drag() and !_group_move_start_regions.is_empty():
					_commit_group_move();
					_group_move_start_regions.clear();
					_group_move_preview_regions.clear();
					_is_dragging = false;
					_editor_drawer.queue_redraw();
					return;
				
				var flush_region_modifying_buffer_function := func():
					if !_inspecting_atlas_texture_info:
						if !_modifying_region_buffer.has_area(): return;
						_create_slice_and_set_to_inspecting(_modifying_region_buffer, Rect2(), false);
					else:
						_commit_single_region_change(_inspecting_atlas_texture_info, _modifying_region_buffer);
				
				flush_region_modifying_buffer_function.call();
				_group_move_start_regions.clear();
				_group_move_preview_regions.clear();
				_is_dragging = false;
				_editor_drawer.queue_redraw();
				return;
				
			if (mouse_button.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0: return;
			if _is_dragging: return;
			
			var local_mouse_position := (mouse_button.position + _draw_offsets * _draw_zoom) / _draw_zoom;
			var ctrl_held := mouse_button.ctrl_pressed;
			var hit_info : EditingAtlasTextureInfo = null;
			var hit_handle : DRAG_TYPE = DRAG_TYPE.NONE;
			var draw_zoom := 11.25 / _draw_zoom;
			
			for info in _editing_atlas_texture_info:
				if info != _inspecting_atlas_texture_info or _selected_slices.size() != 1: continue;
				var handle_positions := _get_handle_positions_for_rect_frame(info.region);
				for index in range(handle_positions.size()):
					var handle_position := handle_positions[index];
					if local_mouse_position.distance_to(handle_position) > draw_zoom: continue;
					hit_info = info;
					hit_handle = index as DRAG_TYPE;
					break;
				if hit_info: break;
			
			if !hit_info:
				if _selected_slices.size() > 1:
					for info in _selected_slices:
						if !info.region.has_point(local_mouse_position): continue;
						hit_info = info;
						hit_handle = DRAG_TYPE.AREA;
						break;
				if !hit_info:
					for info in _editing_atlas_texture_info:
						if !info.region.has_point(local_mouse_position): continue;
						hit_info = info;
						hit_handle = DRAG_TYPE.AREA;
						break;
			
			if hit_info and ctrl_held:
				_toggle_in_selection(hit_info);
				_editor_drawer.queue_redraw();
				return;
			
			if hit_info:
				if !_is_selected(hit_info):
					_set_selection([hit_info], hit_info);
				elif hit_info != _inspecting_atlas_texture_info:
					_inspecting_atlas_texture_info = hit_info;
					_modifying_region_buffer = hit_info.region;
					_update_inspecting_metrics(hit_info);
					_update_selection_title();
				if hit_info.is_marked_for_deletion():
					_update_controls();
					_editor_drawer.queue_redraw();
					return;
				_dragging_handle = hit_handle;
				_dragging_handle_position = local_mouse_position if hit_handle == DRAG_TYPE.AREA else _get_handle_positions_for_rect_frame(hit_info.region)[hit_handle as int];
				_is_dragging = true;
				_dragging_mouse_position_offset = local_mouse_position - _dragging_handle_position;
				_dragging_handle_start_region = _inspecting_atlas_texture_info.region;
				_modifying_region_buffer = _inspecting_atlas_texture_info.region;
				if hit_handle == DRAG_TYPE.AREA and _is_group_move_drag():
					_group_move_start_regions.clear();
					_group_move_preview_regions.clear();
					for info in _selected_slices:
						if info.is_marked_for_deletion():
							continue;
						_group_move_start_regions[info] = info.region;
						_group_move_preview_regions[info] = info.region;
				_update_controls();
				_update_inspecting_metrics(_inspecting_atlas_texture_info);
				_editor_drawer.queue_redraw();
				return;
			
			if ctrl_held:
				_dragging_handle = DRAG_TYPE.MARQUEE;
				_marquee_start = local_mouse_position;
				_selection_marquee_rect = Rect2();
				_marquee_additive = !_selected_slices.is_empty();
				_is_dragging = true;
				_editor_drawer.queue_redraw();
				return;
			
			_dragging_handle = DRAG_TYPE.HANDLE_BOTTOM_RIGHT;
			_dragging_handle_position = local_mouse_position;
			_clear_selection();
			_is_dragging = true;
			_dragging_mouse_position_offset = Vector2.ZERO;
			_dragging_handle_start_region = Rect2(local_mouse_position, Vector2.ZERO);
			_modifying_region_buffer = _dragging_handle_start_region;
			_editor_drawer.queue_redraw();
		var magnify_gesture := input_event as InputEventMagnifyGesture;
		if magnify_gesture:
			_zoom(_draw_zoom * magnify_gesture.factor, magnify_gesture.position);
		var pan_gesture := input_event as InputEventPanGesture;
		if pan_gesture:
			_hscroll.value += _hscroll.page * pan_gesture.delta.x / 8;
			_vscroll.value += _vscroll.page * pan_gesture.delta.y / 8;
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
var _region_edit : Vector4iEdit;
var _margin_edit : Vector4iEdit;
var _filter_clip_check_box : CheckBox;
var _fit_to_pixel_btn : Button;
var _delete_slice_btn : Button;

func _build_base_float_window(container : Array[VBoxContainer], color : Color, back_ground_alpha : float) -> Control:
	var outer_container := PanelContainer.new();
	outer_container.self_modulate = Color(color, back_ground_alpha);
	var panel := Panel.new();
	panel.self_modulate = Color(color, back_ground_alpha);
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
	container.clear();
	container.append(vbox_container);
	return outer_container;

func _build_mini_inspector() -> Control:
	var array : Array[VBoxContainer] = [];
	var outer_container := _build_base_float_window(array, Color.DIM_GRAY, 0.5);
	var vbox_container = array[0];
	
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
		if !_inspecting_atlas_texture_info or !_inspecting_atlas_texture_info.is_temp():
			return;
		_commit_rename(_inspecting_atlas_texture_info, value);
	);
	grid.add_child(_name_line_edit);
	grid.add_child(_label("Region"));
	
	_region_edit = _rect_edit(func(rect : Rect2i):
		_apply_region_delta_to_selection(Rect2(rect));
	);
	grid.add_child(_region_edit);
	
	grid.add_child(_label("Margin"));
	
	_margin_edit = _rect_edit(func(rect : Rect2i):
		_apply_margin_delta_to_selection(Rect2(rect));
	);
	grid.add_child(_margin_edit);
	
	grid.add_child(_label("Filter Clip"));
	
	_filter_clip_check_box = _check_box("Enabled");
	_filter_clip_check_box.toggled.connect(func(value : bool):
		_apply_filter_clip_to_selection(value);
	);
	grid.add_child(_filter_clip_check_box);
	
	var action_hbox := HBoxContainer.new();
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	_fit_to_pixel_btn = _button("Fit to Pixel", func():
		_fit_selected_slices_to_pixels();
	);
	_fit_to_pixel_btn.tooltip_text = "Snap the selected slice(s) to the opaque pixel block they overlap; can shrink, grow, or shift.";
	_delete_slice_btn = _button("Delete", func():
		_delete_selected_slices();
	);
	action_hbox.add_child(_fit_to_pixel_btn);
	action_hbox.add_child(_delete_slice_btn);
	vbox_container.add_child(action_hbox);
	
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

func _create_slice(region : Rect2, margin : Rect2, filter_clip : bool) -> void:
	var info := EditingAtlasTextureInfo.create_empty(
			region, 
			margin,
			filter_clip,
			_inspecting_tex_name,
			_editing_atlas_texture_info
		);
	_commit_add_slices("Create Slice", [info]);

func _create_slice_and_set_to_inspecting(region : Rect2, margin : Rect2, filter_clip : bool) -> void:
	_create_slice(region, margin, filter_clip);

func _set_editing_texture(texture : Texture2D) -> void:
	if _inspecting_texture:
		_inspecting_texture.changed.disconnect(_on_tex_changed);
		_inspecting_texture = null;
		_editing_atlas_texture_info.clear();
		_clear_selection();
		_hide_slicer_menu();
		_slicer_toggle.set_pressed_no_signal(false);
		_clear_local_history();
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
	call_deferred(&"_refresh_atlas_slices");

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
	_mini_inspector_window.propagate_call(&"set_disabled", [true]);
	_mini_inspector_window.propagate_call(&"set_editable", [false]);

	_new_label.hide();
	_fit_to_pixel_btn.disabled = true;
	_delete_slice_btn.disabled = true;

	_region_edit.set_value_no_signal(Vector4i.ZERO);
	_margin_edit.set_value_no_signal(Vector4i.ZERO);

	_filter_clip_check_box.set_pressed_no_signal(false);
	_mini_inspector_window.modulate = _transparent;
	_update_selection_title();

# LineEdit.text 的 setter 会把 caret 重置到 0，逐字改名时不能直接赋值，否则光标每次都跳回开头。
func _set_name_line_edit_text(value : String) -> void:
	if _name_line_edit.text == value:
		return;
	if !_name_line_edit.has_focus():
		_name_line_edit.text = value;
		return;
	# 焦点在输入框上：按“校验后前缀长度”保留 caret，兼容 validate_filename() 剔掉非法字符的情况。
	var caret_column := _name_line_edit.caret_column;
	var validated_prefix_length := _name_line_edit.text.substr(0, caret_column).validate_filename().length();
	_name_line_edit.text = value;
	_name_line_edit.caret_column = mini(validated_prefix_length, value.length());

func _update_inspecting_metrics(info : EditingAtlasTextureInfo) -> void:
	_set_name_line_edit_text(info.name);
	_mini_inspector_window.propagate_call(&"set_disabled", [false]);
	var is_temp := info.is_temp();
	var is_pending_delete := info.is_marked_for_deletion();
	_mini_inspector_window.propagate_call(&"set_editable", [!is_pending_delete]);
	_name_line_edit.editable = is_temp and !is_pending_delete;
	_new_label.visible = is_temp or is_pending_delete or _selected_slices.size() > 1;
	var no_selection := _selected_slices.is_empty();
	_fit_to_pixel_btn.disabled = no_selection or is_pending_delete;
	_delete_slice_btn.disabled = no_selection;

	_region_edit.set_value_no_signal(_to_vector(info.region));
	_margin_edit.set_value_no_signal(_to_vector(info.margin));

	_filter_clip_check_box.set_pressed_no_signal(info.filter_clip);
	_mini_inspector_window.modulate = Color.WHITE;
	_update_selection_title();

func _update_selection_title() -> void:
	if _selected_slices.size() > 1:
		_new_label.text = "(%d selected)" % _selected_slices.size();
		_new_label.show();
	elif _inspecting_atlas_texture_info and _inspecting_atlas_texture_info.is_marked_for_deletion():
		_new_label.text = "(Pending deletion)";
		_new_label.show();
	elif _inspecting_atlas_texture_info and _inspecting_atlas_texture_info.is_temp():
		_new_label.text = "(New)";
		_new_label.show();
	else:
		_new_label.hide();

static func _to_rect(value : Vector4i) -> Rect2i:
	return Rect2i(value.x, value.y, value.z, value.w);

static func _to_vector(value : Rect2i) -> Vector4i:
	return Vector4i(value.position.x, value.position.y, value.size.x, value.size.y);

func _update_controls() -> void:
	var is_editing_asset := true if _inspecting_texture else false;
	_gui_instance.propagate_call(&"set_disabled", [!is_editing_asset]);
	_gui_instance.propagate_call(&"set_editable", [is_editing_asset]);
	_gui_instance.modulate = Color.WHITE if is_editing_asset else _transparent;

	var has_pending_changes := false;
	
	for item in _editing_atlas_texture_info:
		if item.is_marked_for_deletion():
			has_pending_changes = true;
			continue;
		if !item.modified: continue;
		has_pending_changes = true;
		break;
	
	_gui_instance.name = _window_name if !has_pending_changes else _window_name_changed;

	_discard_btn.disabled = !has_pending_changes;
	_save_btn.disabled = !has_pending_changes;

	var is_inspecting_atlas_texture := true if _inspecting_atlas_texture_info else false;
	var is_pending_delete := _inspecting_atlas_texture_info.is_marked_for_deletion() if _inspecting_atlas_texture_info else false;
	_mini_inspector_window.propagate_call(&"set_disabled", [!is_inspecting_atlas_texture]);
	_mini_inspector_window.propagate_call(&"set_editable", [is_inspecting_atlas_texture and !is_pending_delete]);
	_mini_inspector_window.modulate = Color.WHITE if is_inspecting_atlas_texture else _transparent;
	var no_selection := _selected_slices.is_empty();
	if _delete_slice_btn:
		_delete_slice_btn.disabled = no_selection;
	if _fit_to_pixel_btn:
		_fit_to_pixel_btn.disabled = no_selection or is_pending_delete;
	_refresh_history_list();
	_editor_drawer.queue_redraw();

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
static func _label(text : String) -> Label:
	var label := Label.new();
	label.text = text;
	return label;

static func _button(text : String, on_press : Callable) -> Button:
	var button := Button.new();
	button.text = text;
	button.pressed.connect(on_press);
	return button;

static func _line_edit(value_changed : Callable) -> LineEdit:
	var line_edit := LineEdit.new();
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	line_edit.text_changed.connect(value_changed);
	line_edit.text_submitted.connect(value_changed);
	line_edit.expand_to_text_length = true;
	return line_edit;

static func _spin(value_changed : Callable) -> SpinBox:
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

static func _check_box(text : String) -> CheckBox:
	var box := CheckBox.new();
	box.text = text;
	return box;

static func _check_button(text : String) -> CheckButton:
	var button := CheckButton.new();
	button.text = text;
	return button;

static func _hspacer() -> Control:
	var spacer := Control.new();
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	return spacer;
	
static func _rect_edit(value_changed : Callable) -> Vector4iEdit:
	var edit := Vector4iEdit.new();
	edit.set_display_name("X", "Y", "W", "H", "px");
	edit.value_changed.connect(func(value : Vector4i):
		value_changed.call(_to_rect(value));
	);
	return edit;
	
static func _zoom_button(tooltip_text : String, icon_name : String, on_press : Callable) -> Button:
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
		
#region Deletion

func _get_slice_draw_color(info : EditingAtlasTextureInfo) -> Color:
	if info.is_marked_for_deletion():
		return _pending_delete_color;
	if info.is_temp():
		return _temp_slice_color;
	if info.modified:
		return _changed_slice_color;
	return _default_slice_color;

func _delete_selected_slices() -> void:
	if _selected_slices.is_empty() or !_local_undo:
		return;
	var temps : Array[EditingAtlasTextureInfo] = [];
	var persisted : Array[EditingAtlasTextureInfo] = [];
	for info in _selected_slices:
		if info.is_temp():
			temps.append(info);
		elif !info.is_marked_for_deletion():
			persisted.append(info);
	if temps.is_empty() and persisted.is_empty():
		return;
	_local_undo.create_action("Delete Slices");
	for info in temps:
		_local_undo.add_do_method(_history_remove_slice.bind(info));
		_local_undo.add_undo_method(_history_add_slice.bind(info));
	for info in persisted:
		_local_undo.add_do_method(_history_mark_deletion.bind(info, true));
		_local_undo.add_undo_method(_history_mark_deletion.bind(info, false));
	_finish_local_action();

func _get_pending_deletion_paths() -> PackedStringArray:
	var paths : PackedStringArray = [];
	for info in _editing_atlas_texture_info:
		if info.is_marked_for_deletion() and !info.is_temp():
			paths.append(info.resource_path);
	return paths;

func _match_delete_target(dep : String, delete_set : Dictionary) -> String:
	if delete_set.has(dep):
		return dep;
	var fallback := dep.get_slice("::", 2);
	if delete_set.has(fallback):
		return fallback;
	var uid_part := dep.get_slice("::", 0);
	if uid_part.begins_with("uid://"):
		var resolved := ResourceUID.uid_to_path(uid_part);
		if delete_set.has(resolved):
			return resolved;
	return "";

func _collect_all_project_file_paths(directory : EditorFileSystemDirectory, result : Array[String]) -> void:
	if !directory:
		return;
	for i in directory.get_subdir_count():
		_collect_all_project_file_paths(directory.get_subdir(i), result);
	for i in directory.get_file_count():
		result.append(directory.get_file_path(i));

func _accumulate_owners_for_file(file_path : String) -> void:
	if _owner_scan_delete_set.has(file_path):
		return;
	for dep in ResourceLoader.get_dependencies(file_path):
		var target_path := _match_delete_target(dep, _owner_scan_delete_set);
		if target_path == "":
			continue;
		var owners : Array = _owner_scan_owners_by_file[target_path];
		if owners.has(file_path):
			continue;
		owners.append(file_path);

func _start_deletion_owner_scan(delete_paths : PackedStringArray) -> void:
	_owner_scan_delete_paths = delete_paths;
	_owner_scan_delete_set.clear();
	_owner_scan_owners_by_file.clear();
	for path in delete_paths:
		_owner_scan_delete_set[path] = true;
		_owner_scan_owners_by_file[path] = [];
	_owner_scan_file_paths.clear();
	_collect_all_project_file_paths(_resource_filesystem.get_filesystem(), _owner_scan_file_paths);
	_owner_scan_file_index = 0;
	_discard_btn.disabled = true;
	_owner_scan_step();

func _owner_scan_step() -> void:
	var batch_end := mini(_owner_scan_file_index + _OWNER_SCAN_BATCH_SIZE, _owner_scan_file_paths.size());
	while _owner_scan_file_index < batch_end:
		_accumulate_owners_for_file(_owner_scan_file_paths[_owner_scan_file_index]);
		_owner_scan_file_index += 1;
	if _owner_scan_file_index >= _owner_scan_file_paths.size():
		_finish_deletion_owner_scan();
		return;
	call_deferred(&"_owner_scan_step");

func _finish_deletion_owner_scan() -> void:
	var delete_paths := _owner_scan_delete_paths;
	var owners_by_file := _owner_scan_owners_by_file;
	_owner_scan_delete_paths = PackedStringArray();
	_owner_scan_file_paths.clear();
	_update_controls();
	var dialog : ConfirmationDialog = _DeletionConfirmDialog.new();
	dialog.configure(delete_paths, owners_by_file, _execute_apply_changes.bind(delete_paths));
	dialog.present();

func _prompt_apply_changes() -> void:
	var delete_paths := _get_pending_deletion_paths();
	if delete_paths.is_empty():
		_execute_apply_changes(PackedStringArray());
		return;
	_start_deletion_owner_scan(delete_paths);

func _execute_apply_changes(delete_paths : PackedStringArray) -> void:
	var applying : Array[EditingAtlasTextureInfo] = [];
	for info in _editing_atlas_texture_info:
		if info.is_marked_for_deletion() or !info.modified:
			continue;
		if !info.ensure_persistent_backing(_inspecting_texture, _current_source_texture_path):
			continue;
		applying.append(info);
	if !applying.is_empty():
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Apply AtlasTexture Changes");
		for info in applying:
			info.enqueue_live_apply(undo_redo);
		undo_redo.commit_action();
		for info in applying:
			var saved_path := info.save_applied();
			if !saved_path.is_empty():
				_resource_filesystem.update_file(saved_path);
	
	for path in delete_paths:
		_delete_resource_file(path);
	
	var removed : Array[EditingAtlasTextureInfo] = [];
	for info in _editing_atlas_texture_info:
		if info.is_marked_for_deletion():
			removed.append(info);
	for info in removed:
		_selected_slices.erase(info);
		if _inspecting_atlas_texture_info == info:
			_inspecting_atlas_texture_info = null;
		_editing_atlas_texture_info.erase(info);
	
	_sync_primary_from_selection();
	_resource_filesystem.scan();
	_update_controls();
	if _inspecting_atlas_texture_info:
		_update_inspecting_metrics(_inspecting_atlas_texture_info);
	else:
		_reset_inspecting_metrics();

func _delete_resource_file(path : String) -> void:
	if !ResourceLoader.exists(path):
		return;
	var abs_path := ProjectSettings.globalize_path(path);
	if abs_path.is_empty():
		return;
	var err := OS.move_to_trash(abs_path);
	if err != OK:
		err = DirAccess.remove_absolute(abs_path);
	if err != OK:
		push_error("AtlasTextureManager: Cannot remove %s (error %s)" % [path, err]);
		return;
	_resource_filesystem.update_file(path);

#endregion
		
#region Local history

func _finish_local_action() -> void:
	if !_local_undo:
		return;
	_local_undo.add_do_method(_refresh_after_local_history);
	_local_undo.add_undo_method(_refresh_after_local_history);
	_local_undo.commit_action();

func _refresh_after_local_history() -> void:
	if _inspecting_atlas_texture_info and _editing_atlas_texture_info.has(_inspecting_atlas_texture_info):
		_modifying_region_buffer = _inspecting_atlas_texture_info.region;
		_update_inspecting_metrics(_inspecting_atlas_texture_info);
	else:
		_sync_primary_from_selection();
	_update_controls();
	if !_history_updating:
		_refresh_history_list();

func _refresh_history_list() -> void:
	if !_history_list:
		return;
	var was_updating := _history_updating;
	_history_updating = true;
	_history_list.clear();
	_history_list.add_item("(Original)");
	if _local_undo:
		for i in _local_undo.get_history_count():
			_history_list.add_item(_local_undo.get_action_name(i));
		_history_list.select(_local_undo.get_current_action() + 1);
		if _history_undo_btn:
			_history_undo_btn.disabled = !_local_undo.has_undo();
		if _history_redo_btn:
			_history_redo_btn.disabled = !_local_undo.has_redo();
	else:
		_history_list.select(0);
		if _history_undo_btn:
			_history_undo_btn.disabled = true;
		if _history_redo_btn:
			_history_redo_btn.disabled = true;
	_history_updating = was_updating;

func _on_history_item_selected(index : int) -> void:
	if _history_updating:
		return;
	_history_jump_to(index - 1);

func _history_jump_to(target_action : int) -> void:
	if !_local_undo:
		return;
	_history_updating = true;
	while _local_undo.get_current_action() > target_action and _local_undo.has_undo():
		_local_undo.undo();
	while _local_undo.get_current_action() < target_action and _local_undo.has_redo():
		_local_undo.redo();
	_history_updating = false;
	_refresh_after_local_history();

func _undo_local_history() -> void:
	if !_local_undo or !_local_undo.has_undo():
		return;
	_local_undo.undo();
	_refresh_after_local_history();

func _redo_local_history() -> void:
	if !_local_undo or !_local_undo.has_redo():
		return;
	_local_undo.redo();
	_refresh_after_local_history();

func _clear_local_history() -> void:
	if _local_undo:
		_local_undo.clear_history(false);
	_refresh_history_list();

func _history_set_region(info : EditingAtlasTextureInfo, rect : Rect2) -> void:
	info.try_set_region(rect);

func _history_set_margin(info : EditingAtlasTextureInfo, rect : Rect2) -> void:
	info.try_set_margin(rect);

func _history_set_filter_clip(info : EditingAtlasTextureInfo, value : bool) -> void:
	info.try_set_filter_clip(value);

func _history_set_name(info : EditingAtlasTextureInfo, value : String) -> void:
	info.try_set_name(value);

func _history_mark_deletion(info : EditingAtlasTextureInfo, value : bool) -> void:
	info.mark_for_deletion(value);

func _history_add_slice(info : EditingAtlasTextureInfo) -> void:
	if !_editing_atlas_texture_info.has(info):
		_editing_atlas_texture_info.append(info);
	if !_is_selected(info):
		_selected_slices.append(info);
	_inspecting_atlas_texture_info = info;

func _history_remove_slice(info : EditingAtlasTextureInfo) -> void:
	_selected_slices.erase(info);
	_editing_atlas_texture_info.erase(info);
	if _inspecting_atlas_texture_info == info:
		_inspecting_atlas_texture_info = null;

func _commit_add_slices(action_name : String, infos : Array[EditingAtlasTextureInfo]) -> void:
	if !_local_undo or infos.is_empty():
		return;
	_local_undo.create_action(action_name);
	for info in infos:
		_local_undo.add_do_method(_history_add_slice.bind(info));
		_local_undo.add_undo_method(_history_remove_slice.bind(info));
	_finish_local_action();

func _commit_single_region_change(info : EditingAtlasTextureInfo, new_rect : Rect2) -> void:
	if !_local_undo or info.region == new_rect:
		return;
	_local_undo.create_action("Set Region", UndoRedo.MERGE_ENDS);
	_local_undo.add_do_method(_history_set_region.bind(info, new_rect));
	_local_undo.add_undo_method(_history_set_region.bind(info, info.region));
	_finish_local_action();

func _commit_group_move() -> void:
	if !_local_undo:
		return;
	var changes : Array = [];
	for info in _selected_slices:
		if info.is_marked_for_deletion() or !_group_move_preview_regions.has(info):
			continue;
		var start_region := _group_move_start_regions.get(info, info.region) as Rect2;
		var next_region := _group_move_preview_regions[info] as Rect2;
		if start_region == next_region:
			continue;
		changes.append([info, start_region, next_region]);
	if changes.is_empty():
		return;
	_local_undo.create_action("Move Slices");
	for change in changes:
		var info : EditingAtlasTextureInfo = change[0];
		_local_undo.add_do_method(_history_set_region.bind(info, change[2]));
		_local_undo.add_undo_method(_history_set_region.bind(info, change[1]));
	_finish_local_action();

func _commit_rename(info : EditingAtlasTextureInfo, value : String) -> void:
	if !_local_undo:
		return;
	var previous := info.name;
	if previous == value.validate_filename():
		return;
	_local_undo.create_action("Rename Slice", UndoRedo.MERGE_ENDS);
	_local_undo.add_do_method(_history_set_name.bind(info, value));
	_local_undo.add_undo_method(_history_set_name.bind(info, previous));
	_finish_local_action();

#endregion
		
#region Selection

func _is_selected(info : EditingAtlasTextureInfo) -> bool:
	return _selected_slices.has(info);

func _editable_selected_slices() -> Array[EditingAtlasTextureInfo]:
	if !_selected_slices.is_empty():
		return _selected_slices;
	var fallback : Array[EditingAtlasTextureInfo] = [];
	if _inspecting_atlas_texture_info:
		fallback.append(_inspecting_atlas_texture_info);
	return fallback;

func _apply_region_delta_to_selection(new_rect : Rect2) -> void:
	_apply_rect_delta_to_selection(new_rect, true);

func _apply_margin_delta_to_selection(new_rect : Rect2) -> void:
	_apply_rect_delta_to_selection(new_rect, false);

func _apply_rect_delta_to_selection(new_rect : Rect2, apply_to_region : bool) -> void:
	var primary := _inspecting_atlas_texture_info;
	if !primary or !_local_undo:
		return;
	var old_rect := primary.region if apply_to_region else primary.margin;
	var delta_pos := new_rect.position - old_rect.position;
	var delta_size := new_rect.size - old_rect.size;
	if delta_pos == Vector2.ZERO and delta_size == Vector2.ZERO:
		return;
	var changes : Array = [];
	for info in _editable_selected_slices():
		if info.is_marked_for_deletion():
			continue;
		var current := info.region if apply_to_region else info.margin;
		var next := Rect2((current.position + delta_pos).round(), (current.size + delta_size).round());
		if current == next:
			continue;
		changes.append([info, current, next]);
	if changes.is_empty():
		return;
	_local_undo.create_action("Set Region" if apply_to_region else "Set Margin", UndoRedo.MERGE_ENDS);
	for change in changes:
		var info : EditingAtlasTextureInfo = change[0];
		if apply_to_region:
			_local_undo.add_do_method(_history_set_region.bind(info, change[2]));
			_local_undo.add_undo_method(_history_set_region.bind(info, change[1]));
		else:
			_local_undo.add_do_method(_history_set_margin.bind(info, change[2]));
			_local_undo.add_undo_method(_history_set_margin.bind(info, change[1]));
	_finish_local_action();

func _apply_filter_clip_to_selection(value : bool) -> void:
	if !_inspecting_atlas_texture_info or !_local_undo:
		return;
	var changes : Array = [];
	for info in _editable_selected_slices():
		if info.is_marked_for_deletion():
			continue;
		if info.filter_clip == value:
			continue;
		changes.append(info);
	if changes.is_empty():
		return;
	_local_undo.create_action("Set Filter Clip");
	for info in changes:
		_local_undo.add_do_method(_history_set_filter_clip.bind(info, value));
		_local_undo.add_undo_method(_history_set_filter_clip.bind(info, info.filter_clip));
	_finish_local_action();

func _is_group_move_drag() -> bool:
	return _selected_slices.size() > 1;

func _clear_selection() -> void:
	_selected_slices.clear();
	_inspecting_atlas_texture_info = null;
	_reset_inspecting_metrics();

func _set_selection(infos : Array[EditingAtlasTextureInfo], primary : EditingAtlasTextureInfo = null) -> void:
	_selected_slices = infos.duplicate();
	if primary and _selected_slices.has(primary):
		_inspecting_atlas_texture_info = primary;
	elif _selected_slices.is_empty():
		_inspecting_atlas_texture_info = null;
	else:
		_inspecting_atlas_texture_info = _selected_slices[_selected_slices.size() - 1];
	if _inspecting_atlas_texture_info:
		_modifying_region_buffer = _inspecting_atlas_texture_info.region;
		_update_inspecting_metrics(_inspecting_atlas_texture_info);
	else:
		_reset_inspecting_metrics();

func _toggle_in_selection(info : EditingAtlasTextureInfo) -> void:
	if _is_selected(info):
		_selected_slices.erase(info);
		_sync_primary_from_selection();
	else:
		_selected_slices.append(info);
		_inspecting_atlas_texture_info = info;
		_modifying_region_buffer = info.region;
		_update_inspecting_metrics(info);

func _sync_primary_from_selection() -> void:
	if _selected_slices.is_empty():
		_inspecting_atlas_texture_info = null;
		_reset_inspecting_metrics();
	elif !_is_selected(_inspecting_atlas_texture_info):
		_inspecting_atlas_texture_info = _selected_slices[_selected_slices.size() - 1];
		_modifying_region_buffer = _inspecting_atlas_texture_info.region;
		_update_inspecting_metrics(_inspecting_atlas_texture_info);
	else:
		_update_selection_title();

func _get_selection_paths() -> Array[String]:
	var paths : Array[String] = [];
	for info in _selected_slices:
		if info.is_temp():
			continue;
		paths.append(info.resource_path);
	return paths;

func _restore_selection_by_paths(paths : Array[String], primary_path : String, temp_refs : Array[EditingAtlasTextureInfo]) -> void:
	var restored : Array[EditingAtlasTextureInfo] = [];
	for path in paths:
		var info := _find_info_by_path(path);
		if info:
			restored.append(info);
	for info in temp_refs:
		if _editing_atlas_texture_info.has(info) and !restored.has(info):
			restored.append(info);
	var primary : EditingAtlasTextureInfo = null;
	if primary_path != "":
		primary = _find_info_by_path(primary_path);
	if primary and !restored.has(primary):
		primary = null;
	_set_selection(restored, primary);

#endregion
		
#region Atlas slice discovery

func _dependency_refers_to_source(dep: String, source_path: String) -> bool:
	if dep == source_path:
		return true;
	var fallback := dep.get_slice("::", 2);
	if fallback == source_path:
		return true;
	var uid_part := dep.get_slice("::", 0);
	if uid_part.begins_with("uid://"):
		var resolved := ResourceUID.uid_to_path(uid_part);
		if resolved == source_path:
			return true;
	return false;

func _file_depends_on_source(file_path: String, source_path: String) -> bool:
	if !ResourceLoader.exists(file_path):
		return false;
	for dep in ResourceLoader.get_dependencies(file_path):
		if _dependency_refers_to_source(dep, source_path):
			return true;
	return false;

func _collect_atlas_slices(source_path: String) -> Array[EditingAtlasTextureInfo]:
	var result: Array[EditingAtlasTextureInfo] = [];
	_collect_atlas_slices_recursive(_resource_filesystem.get_filesystem(), source_path, result);
	return result;

func _collect_atlas_slices_recursive(directory: EditorFileSystemDirectory, source_path: String, result: Array[EditingAtlasTextureInfo]) -> void:
	if !directory:
		return;
	for i in directory.get_subdir_count():
		_collect_atlas_slices_recursive(directory.get_subdir(i), source_path, result);
	for i in directory.get_file_count():
		if directory.get_file_type(i) != &"AtlasTexture":
			continue;
		var file_path := directory.get_file_path(i);
		if !_file_depends_on_source(file_path, source_path):
			continue;
		var atlas := ResourceLoader.load(file_path) as AtlasTexture;
		if !atlas:
			continue;
		result.append(EditingAtlasTextureInfo.create(atlas, file_path));

func _refresh_atlas_slices() -> void:
	if !_inspecting_texture:
		return;
	var source_path := _inspecting_texture.resource_path;
	var discovered := _collect_atlas_slices(source_path);
	var preserved: Array[EditingAtlasTextureInfo] = [];
	var preserved_paths := {};
	for info in _editing_atlas_texture_info:
		if info.is_temp() or info.modified or info.is_marked_for_deletion():
			preserved.append(info);
			if !info.is_temp():
				preserved_paths[info.resource_path] = true;
	var selection_paths := _get_selection_paths();
	var temp_refs : Array[EditingAtlasTextureInfo] = [];
	for info in _selected_slices:
		if info.is_temp():
			temp_refs.append(info);
	var primary_path := _inspecting_atlas_texture_info.resource_path if _inspecting_atlas_texture_info and !_inspecting_atlas_texture_info.is_temp() else "";
	var new_list: Array[EditingAtlasTextureInfo] = [];
	new_list.append_array(preserved);
	for info in discovered:
		if preserved_paths.has(info.resource_path):
			continue;
		new_list.append(info);
	_editing_atlas_texture_info = new_list;
	_restore_selection_by_paths(selection_paths, primary_path, temp_refs);
	_update_controls();

func _find_info_by_path(path: String) -> EditingAtlasTextureInfo:
	for info in _editing_atlas_texture_info:
		if info.is_temp():
			continue;
		if info.resource_path == path:
			return info;
	return null;

#endregion

#region Slicer

var _slicer_type_opt_btn : OptionButton;
var _cell_size_edit : Vector2iEdit;
var _col_row_edit : Vector2iEdit;
var _slicer_offset_edit : Vector2iEdit;
var _padding_edit : Vector2iEdit;
var _slicer_margin_edit : Vector4iEdit;
var _slicer_filter_clip_check : CheckBox;
var _slice_method_opt_btn : OptionButton;

func _build_slicer_menu() -> Control:
	var array : Array[VBoxContainer] = [];
	var outer_container := _build_base_float_window(array, Color.DIM_GRAY, 0.5);
	var vbox_container = array[0];
	
	var grid := GridContainer.new();
	grid.columns = 2;
	vbox_container.add_child(grid);
	
	grid.add_child(_label("Slicer Type"));
	_slicer_type_opt_btn = OptionButton.new();
	_slicer_type_opt_btn.add_item("Automatic", 0);
	_slicer_type_opt_btn.add_item("Cell Size", 1);
	_slicer_type_opt_btn.add_item("Cell Count", 2);
	grid.add_child(_slicer_type_opt_btn);
	
	# CellSize
	var cell_size_label := _label("Cell Size");
	_cell_size_edit = Vector2iEdit.new();
	_cell_size_edit.min = Vector2.ONE;
	_cell_size_edit.value = Vector2(16.0, 16.0);
	_cell_size_edit.value_changed.connect(_preview_current_slice_deferred);
	grid.add_child(cell_size_label); 
	grid.add_child(_cell_size_edit);
	
	# CellCount
	var col_row_label := _label("Columns & Rows");
	_col_row_edit = Vector2iEdit.new();
	_col_row_edit.set_display_name("Column", "Row", "");
	_col_row_edit.min = Vector2.ONE;
	_col_row_edit.value = Vector2(8, 8);
	_col_row_edit.value_changed.connect(_preview_current_slice_deferred);
	grid.add_child(col_row_label); 
	grid.add_child(_col_row_edit); 
	
	# CellSize, CellCount
	var offset_label := _label("Offset");
	_slicer_offset_edit = Vector2iEdit.new();
	_slicer_offset_edit.value_changed.connect(_preview_current_slice_deferred);
	var padding_label := _label("Padding");
	_padding_edit = Vector2iEdit.new();
	_padding_edit.value_changed.connect(_preview_current_slice_deferred);
	grid.add_child(offset_label); 
	grid.add_child(_slicer_offset_edit); 
	grid.add_child(padding_label);
	grid.add_child(_padding_edit);
	
	grid.add_child(_label("Margin"));
	_slicer_margin_edit = _rect_edit(_preview_current_slice_deferred);
	grid.add_child(_slicer_margin_edit);
	grid.add_child(_label("Filter Clip"));
	_slicer_filter_clip_check = _check_box("Enable");
	_slicer_filter_clip_check.toggled.connect(_preview_current_slice_deferred);
	grid.add_child(_slicer_filter_clip_check);
	grid.add_child(_label("Slice Method"));
	_slice_method_opt_btn = OptionButton.new();
	_slice_method_opt_btn.item_selected.connect(_preview_current_slice_deferred);
	_slice_method_opt_btn.add_item("Ignore Existing (Additive)", 0);
	_slice_method_opt_btn.add_item("Avoid Existing (Smart)", 1);
	_slice_method_opt_btn.selected = 1;
	grid.add_child(_slice_method_opt_btn);
	
	vbox_container.add_child(_button("Slice", _perform_slice));
	
	var update_current_selection_function := func(index : int):
		var is_automatic := index == 0;
		var is_by_cell_size := index == 1;
		var is_by_cell_count := index == 2;
		var is_by_cell_size_or_count := is_by_cell_size or is_by_cell_count;
		
		cell_size_label.visible = is_by_cell_size;
		_cell_size_edit.visible = is_by_cell_size;
		
		col_row_label.visible = is_by_cell_count;
		_col_row_edit.visible = is_by_cell_count;
		
		offset_label.visible = is_by_cell_size_or_count;
		_slicer_offset_edit.visible =  is_by_cell_size_or_count;
		padding_label.visible = is_by_cell_size_or_count;
		_padding_edit.visible =  is_by_cell_size_or_count;
		
		_preview_current_slice();
	
	_slicer_type_opt_btn.item_selected.connect(update_current_selection_function);
	_slicer_type_opt_btn.selected = 0;
	update_current_selection_function.call(0);
	
	return outer_container;

func _preview_current_slice_deferred(value : Variant) -> void:
	call_deferred(&"_preview_current_slice");

func _show_slicer_menu() -> void:
	_slicer_window.show();
	_preview_current_slice();
	_editor_drawer.queue_redraw();

func _hide_slicer_menu() -> void:
	_slice_preview.clear();
	_slicer_window.hide();
	_editor_drawer.queue_redraw();
	
func _preview_current_slice() -> void:
	_slice_preview.clear();
	if !_inspecting_texture: return;
	var offset := _slicer_offset_edit.value;
	var padding := _padding_edit.value;
	match _slicer_type_opt_btn.selected:
		0: # Automatic
			pass;
		1: # Cell Size
			var cell_size := _cell_size_edit.value;
			if cell_size.x == 0 or cell_size.y == 0: return;
			_calculate_slice_by_cell_size(_inspecting_texture, _slice_preview, cell_size, offset, padding);
		2: # Cell Count
			var cell_count := _col_row_edit.value;
			if cell_count.x == 0 or cell_count.y == 0: return;
			_calculate_slice_by_cell_count(_inspecting_texture, _slice_preview, cell_count, offset, padding);
	_editor_drawer.queue_redraw();

func _perform_slice() -> void:
	if !_inspecting_texture: return;
	match _slicer_type_opt_btn.selected:
		0: # Automatic
			_slice_preview.clear();
			_calculate_automatic_slice(_inspecting_texture, _slice_preview);
		1: # Cell Size (pre-calculated in preview)
			pass;
		2: # Cell Count (pre-calculated in preview)
			pass;
	
	if _slice_method_opt_btn.selected == 1: # Avoid Existing (Smart)
		for index in range(_slice_preview.size() - 1, -1, -1):
			var slice := _slice_preview[index];
			var has_intersection := false;
			for match_candidate in _editing_atlas_texture_info:
				if !match_candidate.region.intersects(slice): continue;
				has_intersection = true;
				break;
			if !has_intersection : continue;
			_slice_preview.remove_at(index);
			
	var filter_clip = _slicer_filter_clip_check.button_pressed;
	
	var margin = _to_rect(_slicer_margin_edit.value);

	var created : Array[EditingAtlasTextureInfo] = [];
	var name_pool : Array[EditingAtlasTextureInfo] = [];
	name_pool.append_array(_editing_atlas_texture_info);
	for slice in _slice_preview:
		var info := EditingAtlasTextureInfo.create_empty(
			slice,
			margin,
			filter_clip,
			_inspecting_tex_name,
			name_pool
		);
		created.append(info);
		name_pool.append(info);
	_slice_preview.clear();
	if !created.is_empty():
		_commit_add_slices("Slice", created);
	_clear_selection();
	_update_controls();

static func _calculate_automatic_slice(texture : Texture2D, slice_info : Array[Rect2]) -> void:
	var mask := BitMap.new();
	mask.create_from_image_alpha(texture.get_image());
	var mask_rect := Rect2i(Vector2i.ZERO, mask.get_size());
	var polygons := mask.opaque_to_polygons(mask_rect, 0.0);
	
	var raw_slice_data : Array[Rect2] = [];
	
	for polygon in polygons:
		var rect := Rect2(polygon[0], Vector2.ZERO);
		for index in range(1, polygon.size()):
			rect = rect.expand(polygon[index]);
		raw_slice_data.append(rect);
	
	for slice in raw_slice_data:
		var is_enclosed := false;
		for match_slice in raw_slice_data:
			if match_slice == slice: continue;
			if !match_slice.encloses(slice): continue;
			is_enclosed = true;
			break;
		if is_enclosed: continue;
		slice_info.append(slice);

func _fit_selected_slices_to_pixels() -> void:
	if _selected_slices.is_empty() or !_inspecting_texture or !_local_undo:
		return;
	var blobs : Array[Rect2] = [];
	_calculate_automatic_slice(_inspecting_texture, blobs);
	var texture_size := _inspecting_texture.get_size();
	var changes : Array = [];
	for info in _selected_slices:
		if info.is_marked_for_deletion():
			continue;
		var fitted := _fit_region_to_opaque_blob(info.region, blobs, texture_size);
		if info.region == fitted:
			continue;
		changes.append([info, info.region, fitted]);
	if changes.is_empty():
		return;
	_local_undo.create_action("Fit to Pixel");
	for change in changes:
		var info : EditingAtlasTextureInfo = change[0];
		_local_undo.add_do_method(_history_set_region.bind(info, change[2]));
		_local_undo.add_undo_method(_history_set_region.bind(info, change[1]));
	_finish_local_action();

static func _fit_region_to_opaque_blob(region : Rect2, blobs : Array[Rect2], texture_size : Vector2) -> Rect2:
	var best := region;
	var best_area := 0.0;
	for blob in blobs:
		if !blob.intersects(region):
			continue;
		var area := blob.intersection(region).get_area();
		if area <= best_area:
			continue;
		best_area = area;
		best = blob;
	if best_area <= 0.0:
		return region;
	var clamped := best.intersection(Rect2(Vector2.ZERO, texture_size));
	if !clamped.has_area():
		return region;
	return Rect2(clamped.position.round(), clamped.size.round());

static func _calculate_slice_by_cell_count(texture : Texture2D, slice_info : Array[Rect2], column_row : Vector2, offset : Vector2, margin : Vector2) -> void:
	var size := texture.get_size();
	var pixel_size := size / Vector2(maxf(column_row.x, 1.0), maxf(column_row.y, 1.0));
	_calculate_slice_by_cell_size(texture, slice_info, pixel_size, offset, margin);

static func _calculate_slice_by_cell_size(texture : Texture2D, slice_info : Array[Rect2], pixel_size : Vector2, offset : Vector2, margin : Vector2) -> void:
	var size := texture.get_size();
	var width := size.x;
	var height := size.y;
	pixel_size = Vector2(maxf(pixel_size.x, 1.0), maxf(pixel_size.y, 1.0));
	for y in range(offset.y, height, pixel_size.y + margin.y):
		for x in range(offset.x, width, pixel_size.x + margin.x):
			slice_info.append(Rect2(x, y, pixel_size.x, pixel_size.y));
#endregion
