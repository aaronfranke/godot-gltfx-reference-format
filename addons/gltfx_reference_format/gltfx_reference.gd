## Class for importing and exporting GLTFX files (glTF Reference Format).
## This class acts like GLTFDocument and GLTFState, but for GLTFX files.
@tool
class_name GLTFXReference
extends RefCounted


# GLTFX data.
var base_path: String = ""
var copyright: String = ""
var assets: Array[GLTFXAsset] = []
var nodes: Array[GLTFXNode] = []
var root_nodes: PackedInt32Array = []

# Export properties.
var export_model_subfolder: String = "models"
enum ExportModelFormat {
	GLB_BINARY = 0,
	GLTF_TEXT = 1,
}
var export_model_format: ExportModelFormat = ExportModelFormat.GLB_BINARY

enum ExportNestedScenes {
	## Allow nested glTFX files if a scene is purely referencing other Godot scenes, allowing for a deep hierarchy.
	ALLOW_NESTED_GLTFX = 0,
	## Merge the nested glTFX files into the main glTFX file, ensuring a flat hierarchy.
	MERGE_INTO_MAIN_GLTFX = 1,
	## Merge the nested glTFX files into the leaf glTF files, ensuring a flat hierarchy.
	MERGE_INTO_LEAF_GLTF = 2,
}
## With glTF, there is only one file (hierarchy depth of 0). The glTFX format allows for a heirarchy of scenes (depth >0).
## ALLOW_NESTED_GLTFX may produce hierarchies with depth >1, and the other two options will flatten the hierarchy to depth 1.
## This only affects exporting, and only if a child scene is purely referencing other Godot scenes (and therefore could itself become a glTFX).
var export_nested_scenes: ExportNestedScenes = ExportNestedScenes.ALLOW_NESTED_GLTFX

## Exposed for export settings, but also used for import.
var gltf_document := GLTFDocument.new()

# Internal properties.
static var _generator: String = "Godot " + Engine.get_version_info()["string"] + " with glTFX support by aaronfranke."
var _unique_file_names: Array = []
var _unique_node_names: Array = []
var _godot_scene_file_map: Dictionary = {}


func import_append_from_gltfx_file(file_path: String) -> Error:
	# Read the file from the given path.
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		printerr("glTFX error: Could not read from file at path: " + file_path)
		return ERR_FILE_CANT_OPEN
	var json_string: String = file.get_as_text()
	file.close()
	# Parse the JSON and asset header.
	base_path = file_path.get_base_dir()
	var gltfx_dict: Dictionary = JSON.parse_string(json_string)
	if gltfx_dict.has("asset"):
		var asset_json: Dictionary = gltfx_dict["asset"]
		if asset_json.has("copyright"):
			copyright = String(asset_json["copyright"])
	else:
		printerr("glTFX error: glTFX file at path " + file_path + " is missing the required 'asset' field. Continuing anyway.")
	# Parse assets and nodes.
	if gltfx_dict.has("assets"):
		for asset_json in gltfx_dict["assets"]:
			var gltfx_asset := GLTFXAsset.from_dictionary(asset_json)
			assets.append(gltfx_asset)
	if gltfx_dict.has("nodes"):
		for node_json in gltfx_dict["nodes"]:
			var gltfx_node := GLTFXNode.from_dictionary(node_json)
			nodes.append(gltfx_node)
	if gltfx_dict.has("scenes"):
		var scenes_json: Array = gltfx_dict["scenes"]
		if not scenes_json.is_empty():
			var scene_json: Dictionary = scenes_json[gltfx_dict.get("scene", 0)]
			root_nodes = PackedInt32Array(Array(scene_json["nodes"]))
	return OK


func import_generate_godot_scene() -> Node:
	var scene_root: Node
	if root_nodes.is_empty():
		scene_root = _import_generate_godot_nodes(nodes[0], null, null)
	else:
		scene_root = Node3D.new()
		for gltfx_root_index in root_nodes:
			var gltfx_node: GLTFXNode = nodes[gltfx_root_index]
			_import_generate_godot_nodes(gltfx_node, scene_root, scene_root)
	return scene_root


func _import_generate_godot_nodes(gltfx_node: GLTFXNode, parent: Node, owner: Node) -> Node:
	var node: Node
	if gltfx_node.asset_id != -1:
		# This node is a GLTFXAsset.
		var gltfx_asset: GLTFXAsset = assets[gltfx_node.asset_id]
		node = gltfx_asset.to_node(self)
		if node == null:
			printerr("glTFX error: GLTFXAsset " + gltfx_asset.resource_name + " could not be converted to a Godot node.")
			return null
		node.name = _get_unique_name(_unique_node_names, gltfx_node.resource_name)
		if node is Node3D:
			node.transform = gltfx_node.transform
		if node.scene_file_path.is_empty():
			for descendant in node.find_children("*"):
				descendant.owner = owner
	else:
		# This node does not have an asset, so it's a regular GLTFXNode.
		node = gltfx_node.to_node()
	if owner == null:
		assert(parent == null, "Expected both or neither to be null.")
		parent = node
		owner = node
	else:
		# Note: The reason we must pass in the parent is because the node MUST
		# be a descendant of its owner before we can set the owner property.
		parent.add_child(node)
		node.owner = owner
	for child_index in gltfx_node.children:
		_import_generate_godot_nodes(nodes[child_index], node, owner)
	return node


## Takes a Godot Engine scene node and exports it and its descendants into the GLTFXReference.
func export_append_from_godot_scene(scene_root: Node) -> Error:
	if scene_root == null:
		return ERR_INVALID_PARAMETER
	var root_gltfx_node := GLTFXNode.new()
	root_gltfx_node.resource_name = scene_root.name
	nodes.append(root_gltfx_node)
	for child in scene_root.get_children():
		var child_index: int = _export_append_godot_nodes(child)
		root_gltfx_node.children.append(child_index)
	return OK


func export_write_to_filesystem(file_path: String) -> Error:
	if nodes.is_empty():
		printerr("glTFX error: Cannot write GLTFXReference to filesystem without any nodes. Did you forget to run `append_from_godot_scene`?")
		return ERR_INVALID_DATA
	# Write the assets to files.
	var gltfx_folder: String = file_path.get_base_dir()
	DirAccess.make_dir_absolute(gltfx_folder.path_join(export_model_subfolder))
	var model_ext: String = ".glb" if export_model_format == ExportModelFormat.GLB_BINARY else ".gltf"
	for gltfx_asset in assets:
		var asset_ext: String = model_ext
		if export_nested_scenes == ExportNestedScenes.ALLOW_NESTED_GLTFX:
			if _export_can_subscene_become_gltfx(gltfx_asset.godot_node):
				asset_ext = ".gltfx"
		var filename: String = _get_unique_name(_unique_file_names, gltfx_asset.resource_name + asset_ext)
		gltfx_asset.uri = export_model_subfolder.path_join(filename)
		var err = gltfx_asset.write_asset_to_filesystem(gltfx_folder, self)
		if err != OK:
			return err
	# Write the main glTFX data to the desired file path.
	var gltfx_dict: Dictionary = _export_to_dictionary()
	var json_string: String = JSON.stringify(gltfx_dict, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return ERR_FILE_CANT_WRITE
	# Use store_line instead of store_string so that we get the trailing \n character.
	file.store_line(json_string)
	file.close()
	return OK


func _export_append_godot_nodes(godot_node: Node) -> int:
	var gltfx_node := GLTFXNode.from_node(godot_node)
	var index: int = nodes.size()
	nodes.append(gltfx_node)
	if _export_does_node_need_asset(godot_node):
		# This node is a GLTFXAsset. This means it's a leaf in our GLTFX tree, so we stop looking for children.
		var asset_id: int = _export_make_gltfx_asset_for_node_tree(godot_node)
		gltfx_node.asset_id = asset_id
		return index
	# Else, this node is a non-asset GLTFXNode and may have children that go in the GLTFX.
	for child in godot_node.get_children():
		var child_index: int = _export_append_godot_nodes(child)
		gltfx_node.children.append(child_index)
	return index


func _export_does_node_need_asset(godot_node: Node) -> bool:
	if godot_node is Node3D and godot_node.get_class() != "Node3D":
		# If this node isn't a base Node3D, it needs to become a GLTFXAsset.
		return true
	if not godot_node.scene_file_path.is_empty():
		# If this node is an instanced scene, it should become a GLTFXAsset, except possibly if MERGE_INTO_MAIN_GLTFX.
		if export_nested_scenes == ExportNestedScenes.MERGE_INTO_MAIN_GLTFX:
			if _export_can_subscene_become_gltfx(godot_node):
				return false
		return true
	return false


func _export_make_gltfx_asset_for_node_tree(godot_node: Node) -> int:
	# Check if we've already made a GLTFXAsset for this scene file path.
	var scene_file_path: String = godot_node.scene_file_path
	if _godot_scene_file_map.has(scene_file_path):
		return _godot_scene_file_map[scene_file_path]
	# Make a new GLTFXAsset for this node.
	var gltfx_asset := GLTFXAsset.from_node(godot_node)
	var index: int = assets.size()
	assets.append(gltfx_asset)
	if not scene_file_path.is_empty():
		_godot_scene_file_map[scene_file_path] = index
	return index


func _export_to_dictionary() -> Dictionary:
	# Serialize the required "asset" header.
	var asset_field = {
		"generator": _generator,
		"reference": true,
		"version": 2.0
	}
	if not copyright.is_empty():
		asset_field["copyright"] = copyright
	var gltfx_json: Dictionary = {
		"asset": asset_field
	}
	# Serialize assets, if any (very likely).
	if not assets.is_empty():
		var assets_json: Array = []
		for gltfx_asset in assets:
			assets_json.append(gltfx_asset.to_dictionary())
		gltfx_json["assets"] = assets_json
	# Serialize nodes.
	var nodes_json: Array = []
	for gltfx_node in nodes:
		nodes_json.append(gltfx_node.to_dictionary())
	gltfx_json["nodes"] = nodes_json
	return gltfx_json


func _to_string() -> String:
	return str(_export_to_dictionary())


static func _export_can_subscene_become_gltfx(godot_node: Node) -> bool:
	return _export_does_subscene_contain_other_scenes(godot_node) and not _export_does_subscene_directly_contain_non_base_nodes(godot_node)


static func _export_does_subscene_contain_other_scenes(godot_node: Node) -> bool:
	if godot_node == null:
		return false
	for child in godot_node.get_children():
		if not child.scene_file_path.is_empty():
			return true
		if _export_does_subscene_contain_other_scenes(child):
			return true
	return false


static func _export_does_subscene_directly_contain_non_base_nodes(godot_node: Node) -> bool:
	if godot_node == null:
		return false
	for child in godot_node.get_children():
		if not child.scene_file_path.is_empty():
			return false
		if godot_node is Node3D and godot_node.get_class() != "Node3D":
			return true
		if _export_does_subscene_directly_contain_non_base_nodes(child):
			return true
	return false


static func _get_unique_name(unique_names: Array, name: String) -> String:
	if not unique_names.has(name):
		unique_names.append(name)
		return name
	var i: int = 2
	while true:
		var new_name: String = name + str(i)
		if not unique_names.has(new_name):
			unique_names.append(new_name)
			return new_name
		i += 1
	# Unreachable.
	return ""


static func from_gltfx_settings(existing: GLTFXReference) -> GLTFXReference:
	var ret := GLTFXReference.new()
	ret.export_model_subfolder = existing.export_model_subfolder
	ret.export_model_format = existing.export_model_format
	ret.export_nested_scenes = existing.export_nested_scenes
	ret.gltf_document = existing.gltf_document
	return ret
