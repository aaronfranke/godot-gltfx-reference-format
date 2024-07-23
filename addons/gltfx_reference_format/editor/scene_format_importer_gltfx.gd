## Godot editor integration for importing GLTFX files. See GLTFXReference.
@tool
class_name EditorSceneFormatImporterGLTFX
extends EditorSceneFormatImporter


func _get_extensions() -> PackedStringArray:
	return ["gltfx", "glxf"]


func _get_import_flags() -> int:
	return IMPORT_SCENE


func _import_scene(path: String, flags: int, options: Dictionary) -> Node:
	var gltfx_ref := GLTFXReference.new()
	gltfx_ref.import_append_from_gltfx_file(path)
	return gltfx_ref.import_generate_godot_scene()
