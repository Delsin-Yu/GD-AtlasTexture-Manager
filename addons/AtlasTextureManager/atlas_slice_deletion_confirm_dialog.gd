@tool
extends ConfirmationDialog

## Godot-style confirmation dialog listing AtlasTexture files to delete and their owners.

const _DIALOG_MIN_WIDTH := 500;
const _DIALOG_MAX_HEIGHT := 520;
const _FILES_LIST_MAX_HEIGHT := 160;
const _OWNERS_TREE_MAX_HEIGHT := 200;

var _owners_container : VBoxContainer;
var _files_scroll : ScrollContainer;
var _owners_scroll : ScrollContainer;
var _ui_built : bool;

func _init() -> void:
	title = "Please Confirm...";
	ok_button_text = "Remove";
	cancel_button_text = "Cancel";
	min_size = Vector2i(_DIALOG_MIN_WIDTH, 0);
	transient = true;
	exclusive = true;
	unresizable = false;

func _ensure_ui() -> void:
	if _ui_built:
		return;
	_ui_built = true;
	
	var vb := VBoxContainer.new();
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	vb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN;
	
	var summary := Label.new();
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	summary.custom_minimum_size.x = _DIALOG_MIN_WIDTH - 40;
	summary.text = "The files being removed are required by other resources in order for them to work.\nRemove them anyway? (Cannot be undone.)\nDepending on your filesystem configuration, the files will either be moved to the system trash or deleted permanently.";
	vb.add_child(summary);
	
	var files_label := Label.new();
	files_label.theme_type_variation = &"HeaderSmall";
	files_label.text = "Files to be deleted:";
	vb.add_child(files_label);
	
	_files_scroll = ScrollContainer.new();
	_files_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_files_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN;
	_files_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
	vb.add_child(_files_scroll);
	
	var files_list := ItemList.new();
	files_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	files_list.auto_height = true;
	_files_scroll.add_child(files_list);
	files_list.name = &"FilesList";
	
	_owners_container = VBoxContainer.new();
	_owners_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_owners_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN;
	vb.add_child(_owners_container);
	
	var owners_label := Label.new();
	owners_label.theme_type_variation = &"HeaderSmall";
	owners_label.text = "Owners of files to be deleted:";
	_owners_container.add_child(owners_label);
	
	_owners_scroll = ScrollContainer.new();
	_owners_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_owners_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN;
	_owners_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
	_owners_container.add_child(_owners_scroll);
	
	var owners_tree := Tree.new();
	owners_tree.hide_root = true;
	owners_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_owners_scroll.add_child(owners_tree);
	owners_tree.name = &"OwnersTree";
	
	add_child(vb);
	
	set_meta(&"files_list", files_list);
	set_meta(&"owners_tree", owners_tree);
	set_meta(&"summary_label", summary);

func configure(files : PackedStringArray, owners_by_file : Dictionary, on_confirm : Callable) -> void:
	_ensure_ui();
	_populate(files, owners_by_file);
	confirmed.connect(func():
		on_confirm.call();
		queue_free();
	);
	canceled.connect(func(): queue_free());

func present() -> void:
	_ensure_ui();
	_fit_content_sizes();
	reset_size();
	call_deferred(&"_present_deferred");

func _present_deferred() -> void:
	_fit_content_sizes();
	reset_size();
	EditorInterface.popup_dialog_centered_clamped(self, _desired_popup_size());

func _fit_content_sizes() -> void:
	var files_list : ItemList = get_meta(&"files_list");
	var owners_tree : Tree = get_meta(&"owners_tree");
	var files_height := maxf(_measured_height(files_list), _estimate_item_list_height(files_list));
	_files_scroll.custom_minimum_size = Vector2(0, clampf(files_height, 0.0, float(_FILES_LIST_MAX_HEIGHT)));
	if _owners_container.visible:
		var tree_height := maxf(_measured_height(owners_tree), _estimate_tree_height(owners_tree));
		_owners_scroll.custom_minimum_size = Vector2(0, clampf(tree_height, 0.0, float(_OWNERS_TREE_MAX_HEIGHT)));

func _measured_height(control : Control) -> float:
	return maxf(control.get_combined_minimum_size().y, control.get_minimum_size().y);

func _estimate_item_list_height(files_list : ItemList) -> float:
	var count := files_list.item_count;
	if count <= 0:
		return 0.0;
	var font_size := files_list.get_theme_font_size(&"font_size");
	if font_size <= 0:
		font_size = 16;
	var v_sep := files_list.get_theme_constant(&"v_separation");
	if v_sep < 0:
		v_sep = 4;
	var icon_h := 16;
	var item_icon := files_list.get_item_icon(0);
	if item_icon:
		icon_h = maxi(icon_h, item_icon.get_height());
	return float(count * (maxi(font_size, icon_h) + v_sep) + 8);

func _estimate_tree_height(owners_tree : Tree) -> float:
	var count := _count_visible_tree_items(owners_tree.get_root());
	if count <= 0:
		return 0.0;
	var font_size := owners_tree.get_theme_font_size(&"font_size");
	if font_size <= 0:
		font_size = 16;
	var v_sep := owners_tree.get_theme_constant(&"v_separation");
	if v_sep < 0:
		v_sep = 4;
	return float(count * (font_size + v_sep) + 8);

func _count_visible_tree_items(item : TreeItem) -> int:
	if item == null:
		return 0;
	var count := 0;
	var child := item.get_first_child();
	while child:
		count += 1;
		if !child.collapsed:
			count += _count_visible_tree_items(child);
		child = child.get_next();
	return count;

func _desired_popup_size() -> Vector2i:
	var desired := get_contents_minimum_size();
	desired.x = maxi(desired.x, _DIALOG_MIN_WIDTH);
	desired.y = clampi(desired.y, 1, _DIALOG_MAX_HEIGHT);
	return desired;

func _populate(files : PackedStringArray, owners_by_file : Dictionary) -> void:
	var files_list : ItemList = get_meta(&"files_list");
	var owners_tree : Tree = get_meta(&"owners_tree");
	var summary : Label = get_meta(&"summary_label");
	var theme := EditorInterface.get_editor_theme();
	
	files_list.clear();
	for path in files:
		var display_path := path.trim_prefix("res://");
		var icon := theme.get_icon(&"AtlasTexture", &"EditorIcons") if theme.has_icon(&"AtlasTexture", &"EditorIcons") else null;
		files_list.add_item(display_path, icon, false);
	
	var has_owners := false;
	owners_tree.clear();
	var root := owners_tree.create_item();
	for path in files:
		var owners : Array = owners_by_file.get(path, []);
		if owners.is_empty():
			continue;
		has_owners = true;
		var dependency_item := owners_tree.create_item(root);
		dependency_item.set_text(0, path.trim_prefix("res://"));
		dependency_item.set_icon(0, theme.get_icon(&"AtlasTexture", &"EditorIcons"));
		for owner_path in owners:
			var owner_item := owners_tree.create_item(dependency_item);
			owner_item.set_text(0, String(owner_path).trim_prefix("res://"));
			var file_type := EditorInterface.get_resource_filesystem().get_file_type(owner_path);
			var owner_icon := EditorInterface.get_editor_theme().get_icon(file_type, &"EditorIcons") if EditorInterface.get_editor_theme().has_icon(file_type, &"EditorIcons") else theme.get_icon(&"Object", &"EditorIcons");
			owner_item.set_icon(0, owner_icon);
	
	if has_owners:
		_owners_container.show();
		summary.text = "The files being removed are required by other resources in order for them to work.\nRemove them anyway? (Cannot be undone.)\nDepending on your filesystem configuration, the files will either be moved to the system trash or deleted permanently.";
	else:
		_owners_container.hide();
		summary.text = "Remove the selected files from the project? (Cannot be undone.)\nDepending on your filesystem configuration, the files will either be moved to the system trash or deleted permanently.";
