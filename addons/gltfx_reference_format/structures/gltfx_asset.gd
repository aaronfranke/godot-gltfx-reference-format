## Helper class for assets found within a GLTFX file, the glTF Reference Format.
## See GLTFXReference for importing and exporting GLTFX files.
@tool
class_name GLTFXAsset
extends Resource


enum TransformType {
	NONE_DISCARD,
	LOCAL_NODE,
	GLOBAL_NODE,
}

var uri: String = ""
var scene: String = ""
var nodes: PackedStringArray = []
var transform_type: TransformType = TransformType.GLOBAL_NODE
var godot_node: Node = null


static func from_node(node: Node) -> GLTFXAsset:
	if node == null:
		printerr("glTFX error: Cannot create GLTFXAsset from null Node.")
		return null
	var ret := GLTFXAsset.new()
	ret.godot_node = node
	if node.scene_file_path.is_empty():
		ret.resource_name = node.name
	else:
		ret.resource_name = node.scene_file_path.get_file().get_basename()
	if ret.resource_name.is_empty():
		ret.resource_name = "model"
	return ret


func to_node(gltfx_reference: GLTFXReference) -> Node:
	var asset_path: String = gltfx_reference.base_path.path_join(uri)
	if uri.ends_with(".gltfx"):
		# This asset is another GLTFX file.
		var gltfx_ref := GLTFXReference.from_gltfx_settings(gltfx_reference)
		var err: Error = gltfx_ref.import_append_from_gltfx_file(asset_path)
		if err != OK:
			printerr("glTFX error: Could not append GLTFXAsset " + uri + " to GLTFXReference.")
			return null
		godot_node = gltfx_ref.import_generate_godot_scene()
	else:
		# Else, this is a GLB or GLTF file.
		var gltf_state := GLTFState.new()
		var err: Error = gltfx_reference.gltf_document.append_from_file(asset_path, gltf_state)
		if err != OK:
			printerr("glTFX error: Could not append GLTFXAsset " + uri + " to GLTFDocument.")
			return null
		godot_node = gltfx_reference.gltf_document.generate_scene(gltf_state)
	godot_node.scene_file_path = asset_path
	# If the GLTFXAsset specifies that it only wants specific nodes, find those.
	if not nodes.is_empty():
		var imported_root_node: Node = godot_node
		if nodes.size() == 1:
			godot_node = imported_root_node.find_child(nodes[0])
			if godot_node == null:
				godot_node = imported_root_node
			else:
				godot_node.get_parent().remove_child(godot_node)
		else:
			godot_node = Node3D.new()
			for node_name in nodes:
				var found: Node = imported_root_node.find_child(node_name)
				if found != null:
					found.get_parent().remove_child(found)
					godot_node.add_child(found)
	return godot_node


static func from_dictionary(json: Dictionary) -> GLTFXAsset:
	var ret := GLTFXAsset.new()
	if json.has("name"):
		ret.resource_name = String(json["name"])
	if json.has("nodes"):
		ret.nodes = PackedStringArray(Array(json["nodes"]))
	if json.has("scene"):
		ret.scene = String(json["scene"])
	if json.has("transform"):
		var transform_str: String = String(json["transform"])
		if transform_str == "none":
			ret.transform_type = TransformType.NONE_DISCARD
		elif transform_str == "local":
			ret.transform_type = TransformType.LOCAL_NODE
		elif transform_str == "global":
			ret.transform_type = TransformType.GLOBAL_NODE
		else:
			printerr("glTFX error: Unknown transform type " + transform_str + " in GLTFXAsset.")
	if json.has("uri"):
		ret.uri = String(json["uri"])
	return ret


func to_dictionary() -> Dictionary:
	var ret: Dictionary = {}
	if not resource_name.is_empty():
		ret["name"] = resource_name
	if not uri.is_empty():
		ret["uri"] = uri
	if not scene.is_empty():
		ret["scene"] = scene
	if not nodes.is_empty():
		ret["nodes"] = Array(nodes)
	if transform_type == TransformType.NONE_DISCARD:
		ret["transform"] = "none"
	elif transform_type == TransformType.LOCAL_NODE:
		ret["transform"] = "local"
	# Else, global is the default, so don't write it.
	return ret


func write_asset_to_filesystem(gltfx_folder: String, gltfx_reference: GLTFXReference) -> Error:
	if uri.is_empty() or gltfx_folder.is_empty():
		printerr("glTFX error: Cannot write GLTFXAsset to filesystem without a full file path (glTFX folder and relative URI).")
		return ERR_FILE_CANT_WRITE
	var full_path: String = gltfx_folder.path_join(uri)
	var extension: String = uri.get_extension()
	if extension == "gltfx":
		# This asset is another GLTFX file.
		var gltfx_ref := GLTFXReference.from_gltfx_settings(gltfx_reference)
		var err: Error = gltfx_ref.export_append_from_godot_scene(godot_node)
		if err != OK:
			return err
		err = gltfx_ref.export_write_to_filesystem(full_path)
		return err
	elif extension == "glb" or extension == "gltf":
		# This asset is a leaf GLB or GLTF file.
		var gltf_state := GLTFState.new()
		gltf_state.copyright = gltfx_reference.copyright
		gltfx_reference.gltf_document.append_from_scene(godot_node, gltf_state)
		gltfx_reference.gltf_document.write_to_filesystem(gltf_state, full_path)
	else:
		printerr("glTFX error: Cannot write GLTFXAsset " + uri + " to filesystem without a valid file extension.")
		return ERR_FILE_CANT_WRITE
	return OK
