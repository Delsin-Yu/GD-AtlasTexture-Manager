class_name EditingAtlasTextureInfo
extends RefCounted

var _backing : AtlasTexture;
var _resource_path : String;
var _name : String;
var _region : Rect2;
var _margin : Rect2;
var	_filter_clip : bool;
var _modified : bool;

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
	_resource_path = resource_path;
	_modified = true;

func try_set_name(value : String) -> bool:
	if _name == value:
		return false;
	_name = value.validate_filename();
	_modified = true;
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
		
	_region = _backing.region;
	_margin = _backing.margin;
	_filter_clip = _backing.filter_clip;
	_modified = false;

func apply_changes(source_texture : Texture2D, source_texture_dir : String) -> String:
	if !_modified:
		return "";
		
	if !_backing:
		if _name == "":
			printerr("AtlasTexture.Name is WhiteSpace!");
			return "";
			
		_name = _name.validate_filename();
		
		_backing = AtlasTexture.new();
		_backing.atlas = source_texture;
		
		_resource_path = source_texture_dir.path_join("%s.tres" % _name);
		
	_backing.region = _region;
	_backing.margin = _margin;
	_backing.filter_clip = _filter_clip;
	_modified = false;
	ResourceSaver.save(_backing, _resource_path);
	return _resource_path;

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
