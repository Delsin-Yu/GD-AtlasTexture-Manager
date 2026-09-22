# Changelog

## 0.1.0

`plugin.cfg` version is `0.1.0`.

### New Features

- **Multi-select.** Select, toggle, and edit several slices together, including group moves and shared `filter_clip` changes.
- **Local undo/redo.** Region, margin, name, filter clip, add, remove, and deletion marks go through a history list.
- **Delete saved slices.** Marking a saved `AtlasTexture` for removal scans owners and asks for confirmation before the file is deleted. Unsaved slices can still be removed directly.
- **Editor undo for applied properties.** Region, margin, and `filter_clip` writes go through `EditorUndoRedoManager`.
- **Reload awareness.** Filesystem and resource reloads refresh the open texture's slices.

### Fixes

- Slice names are validated before they are stored, and discard restores the original name.
- Region spin boxes keep a usable minimum width.
