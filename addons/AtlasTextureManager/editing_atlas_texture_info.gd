class_name EditingAtlasTextureInfo
extends RefCounted

var _backing : AtlasTexture;
var _resource_path : String;
var _name : String;
var _original_name : String;
var _region : Rect2;
var _margin : Rect2;
var	_filter_clip : bool;
var _modified : bool;
var _marked_for_deletion : bool;

var resource_path : String:
	get: return _resource_path;
var name : String:
	get: return _name;
var region : Rect2:
	get: return _region;
var margin : Rect2:
	get: return _margin;
var filter_clip : bool:
	get: return _filter_clip;
var modified : bool:
	get: return _modified;

func is_temp() -> bool:
	if _backing:
		return false;
	return true;

func is_marked_for_deletion() -> bool:
	return _marked_for_deletion;

func mark_for_deletion(value : bool) -> void:
	_marked_for_deletion = value;

func convert_to_temp() -> void:
	_backing = null;
	_resource_path = "";
	_modified = true;

func _init(backing : AtlasTexture, region : Rect2, margin : Rect2, filter_clip : bool, name : String, resource_path : String) -> void:
	_backing = backing;
	_region = region;
	_margin = margin;
	_filter_clip = filter_clip;
	_name = name;
	_original_name = name;
	_resource_path = resource_path;
	_modified = true;

func try_set_name(value : String) -> bool:
	var validated := value.validate_filename();
	if _name == validated:
		return false;
	_name = validated;
	_modified = _compute_modified();
	return true;

func try_set_region(value : Rect2) -> bool:
	if _region == value:
		return false;
	_region = value;
	_modified = true;
	return true;

func try_set_margin(value : Rect2) -> bool:
	if _margin == value:
		return false;
	_margin = value;
	_modified = true;
	return true;

func try_set_filter_clip(value : bool) -> bool:
	if _filter_clip == value:
		return false;
	_filter_clip = value;
	_modified = true;
	return true;

func discard_changes() -> void:
	if !_modified or !_backing:
		return;
		
	_name = _original_name;
	_region = _backing.region;
	_margin = _backing.margin;
	_filter_clip = _backing.filter_clip;
	_modified = false;

func _compute_modified() -> bool:
	if _name != _original_name:
		return true;
	if !_backing:
		return true;
	if _region != _backing.region:
		return true;
	if _margin != _backing.margin:
		return true;
	if _filter_clip != _backing.filter_clip:
		return true;
	return false;

func ensure_persistent_backing(source_texture : Texture2D, source_texture_dir : String) -> bool:
	if _backing:
		_resource_path = _backing.resource_path;
		return !_resource_path.is_empty();
	if _name == "":
		printerr("AtlasTexture.Name is WhiteSpace!");
		return false;
	_name = _name.validate_filename();
	_backing = AtlasTexture.new();
	_backing.atlas = source_texture;
	_backing.resource_name = _name;
	_resource_path = source_texture_dir.path_join("%s.tres" % _name);
	_backing.take_over_path(_resource_path);
	return true;

func enqueue_live_apply(undo_redo : EditorUndoRedoManager) -> void:
	if !_backing:
		return;
	if _backing.region != _region:
		undo_redo.add_do_method(_backing, &"set_region", _region);
		undo_redo.add_undo_method(_backing, &"set_region", _backing.region);
	if _backing.margin != _margin:
		undo_redo.add_do_method(_backing, &"set_margin", _margin);
		undo_redo.add_undo_method(_backing, &"set_margin", _backing.margin);
	if _backing.filter_clip != _filter_clip:
		undo_redo.add_do_method(_backing, &"set_filter_clip", _filter_clip);
		undo_redo.add_undo_method(_backing, &"set_filter_clip", _backing.filter_clip);

func save_applied() -> String:
	if !_backing or _resource_path.is_empty():
		return "";
	ResourceSaver.save(_backing, _resource_path);
	_original_name = _name;
	_modified = false;
	return _resource_path;

func apply_changes(source_texture : Texture2D, source_texture_dir : String) -> String:
	if !_modified:
		return "";
	if !ensure_persistent_backing(source_texture, source_texture_dir):
		return "";
	var undo_redo := EditorInterface.get_editor_undo_redo();
	undo_redo.create_action("Apply AtlasTexture Changes");
	enqueue_live_apply(undo_redo);
	undo_redo.commit_action();
	return save_applied();

#region Static Factory Functions

static func create(atlas_texture : AtlasTexture, resource_path : String) -> EditingAtlasTextureInfo:
	var instance := EditingAtlasTextureInfo.new(atlas_texture, atlas_texture.region, atlas_texture.margin, atlas_texture.filter_clip, resource_path.get_file().get_basename(), resource_path);
	instance._modified = false;
	return instance;

static func create_empty(region : Rect2, margin : Rect2, filter_clip : bool, name : String, exisiting_textures : Array[EditingAtlasTextureInfo]) -> EditingAtlasTextureInfo:
	var name_lower = name.to_lower();
	var existing_names_lower : Array[String] = [];
	for existing_texture in exisiting_textures:
		existing_names_lower.append(existing_texture.name.to_lower());
		
	var name_index := 0;
	var name_candidate := create_name(name_lower, name_index);
	while existing_names_lower.has(name_candidate):
		name_index += 1;
		name_candidate = create_name(name_lower, name_index);
	
	return EditingAtlasTextureInfo.new(null, region, margin, filter_clip, name_candidate, "");

static func create_name(name : String, index : int) -> String:
	return "%s_%s" % [name, index];
	
#endregion
