## Most of this file is for exporting GLTFX files.
@tool
extends EditorPlugin


var _file_dialog: EditorFileDialog
var _export_settings: GLTFXEditorExportSettings
var _settings_inspector: EditorInspector


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	# Set up the editor scene format importer. This is the only part of this file that is for importing.
	var imp := EditorSceneFormatImporterGLTFX.new()
	add_scene_format_importer_plugin(imp)
	# Set up the editor export file dialog.
	_file_dialog = EditorFileDialog.new()
	_file_dialog.set_file_mode(EditorFileDialog.FILE_MODE_SAVE_FILE)
	_file_dialog.set_access(EditorFileDialog.ACCESS_FILESYSTEM)
	_file_dialog.clear_filters()
	_file_dialog.add_filter("*.gltfx")
	_file_dialog.title = "Export Scene to glTFX File (glTF External Reference Format)"
	_file_dialog.file_selected.connect(_export_scene_as_gltfx)
	EditorInterface.get_base_control().add_child(_file_dialog)
	# Set up the export settings menu. Only available in Godot 4.4 or later.
	_export_settings = GLTFXEditorExportSettings.new()
	_settings_inspector = EditorInspector.new()
	if _settings_inspector.has_method(&"edit"):
		_settings_inspector.custom_minimum_size = Vector2(300.0, 300.0) * EditorInterface.get_editor_scale()
		_file_dialog.add_side_menu(_settings_inspector, "Export Settings")
	# Add a button to the Scene -> Export menu to pop up the settings dialog.
	var export_menu: PopupMenu = get_export_as_menu()
	var index: int = export_menu.get_item_count()
	export_menu.add_item("glTFX Reference Format...")
	export_menu.set_item_metadata(index, _try_begin_gltfx_editor_export)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_file_dialog.queue_free()
	_settings_inspector.queue_free()


func _try_begin_gltfx_editor_export() -> void:
	_popup_gltfx_editor_export_dialog()


func _popup_gltfx_editor_export_dialog() -> void:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		printerr("glTFX error: Cannot export scene without a root node.")
		return
	# Set the file dialog's file name to the scene name.
	var filename: String = scene_root.get_scene_file_path().get_file().get_basename()
	if filename.is_empty():
		filename = scene_root.get_name()
	_file_dialog.set_current_file(filename + ".gltfx")
	# Generate and refresh the export settings. Only available in Godot 4.4 or later.
	if _settings_inspector.has_method(&"edit"):
		_settings_inspector.edit(null)
		_settings_inspector.edit(_export_settings)
	# Show the file dialog.
	_file_dialog.popup_centered_ratio()


func _export_scene_as_gltfx(file_path: String) -> void:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		printerr("glTFX editor export error: Cannot export scene without a root node.")
		return
	var gltfx: GLTFXReference = _export_settings.to_gltfx_reference()
	var err: Error = gltfx.export_append_from_godot_scene(scene_root)
	if err != OK:
		printerr("glTFX editor export: Error while running export_append_from_godot_scene")
		return
	err = gltfx.export_write_to_filesystem(file_path)
	if err != OK:
		printerr("glTFX editor export: Error while running export_write_to_filesystem")
		return
