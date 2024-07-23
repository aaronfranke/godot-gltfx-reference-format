## Helper class for nodes found within a GLTFX file, the glTF Reference Format.
## See GLTFXReference for importing and exporting GLTFX files.
@tool
class_name GLTFXNode
extends Resource


var asset_id: int = -1
var children: PackedInt32Array = []
var transform: Transform3D


static func from_node(node: Node) -> GLTFXNode:
	if node == null:
		printerr("glTFX error: Cannot create GLTFXNode from null Node.")
		return null
	var ret := GLTFXNode.new()
	ret.resource_name = node.name
	if node is Node3D:
		ret.transform = node.transform
	return ret


func to_node() -> Node3D:
	if asset_id != -1:
		printerr("glTFX error: Nodes with an asset should be handled by GLTFXReference. Continuing anyway.")
	var node: Node3D = Node3D.new()
	node.name = resource_name
	node.transform = transform
	return node


static func from_dictionary(json: Dictionary) -> GLTFXNode:
	var ret := GLTFXNode.new()
	if json.has("asset"):
		ret.asset_id = int(json["asset"])
	if json.has("children"):
		ret.children = PackedInt32Array(Array(json["children"]))
	var xform: Transform3D = Transform3D.IDENTITY
	if json.has("matrix"):
		xform = _number_array_to_transform(Array(json["matrix"]))
	else:
		if json.has("translation"):
			xform.origin = _number_array_to_vector3(Array(json["translation"]))
		if json.has("rotation"):
			xform.basis = Basis(_number_array_to_quaternion(Array(json["rotation"])))
		if json.has("scale"):
			xform.basis *= Basis.from_scale(_number_array_to_vector3(Array(json["scale"])))
	ret.transform = xform
	if json.has("name"):
		ret.resource_name = String(json["name"]).validate_node_name()
	return ret


func to_dictionary() -> Dictionary:
	var ret: Dictionary = {}
	if asset_id >= 0:
		ret["asset"] = asset_id
	if not children.is_empty():
		ret["children"] = Array(children)
	if transform.basis.is_conformal():
		# An orthogonal transform is decomposable into TRS, so prefer that.
		if not transform.origin.is_zero_approx():
			ret["translation"] = _vector3_to_number_array(transform.origin)
		var rot: Quaternion = transform.basis.get_rotation_quaternion()
		if not rot.is_equal_approx(Quaternion.IDENTITY):
			ret["rotation"] = _quaternion_to_number_array(rot)
		var scale: Vector3 = transform.basis.get_scale()
		if not scale.is_equal_approx(Vector3.ONE):
			ret["scale"] = _vector3_to_number_array(scale)
	else:
		ret["matrix"] = _transform_to_gltf_matrix_array(transform)
	if not resource_name.is_empty():
		ret["name"] = resource_name
	return ret


static func _vector3_to_number_array(vec: Vector3) -> Array:
	return [vec.x, vec.y, vec.z]


static func _quaternion_to_number_array(quat: Quaternion) -> Array:
	return [quat.x, quat.y, quat.z, quat.w]


static func _transform_to_gltf_matrix_array(transform: Transform3D) -> Array:
	var x: Vector3 = transform.basis.x
	var y: Vector3 = transform.basis.y
	var z: Vector3 = transform.basis.z
	var o: Vector3 = transform.origin
	return [x.x, x.y, x.z, 0.0, y.x, y.y, y.z, 0.0, z.x, z.y, z.z, 0.0, o.x, o.y, o.z, 1.0]


static func _number_array_to_vector3(arr: Array) -> Vector3:
	if arr.size() < 3:
		printerr("Number array " + str(arr) + " too short to convert to Vector3.")
		return Vector3.ZERO
	return Vector3(arr[0], arr[1], arr[2])


static func _number_array_to_quaternion(arr: Array) -> Quaternion:
	if arr.size() < 4:
		printerr("Number array " + str(arr) + " too short to convert to Quaternion.")
		return Quaternion()
	return Quaternion(arr[0], arr[1], arr[2], arr[3])


static func _number_array_to_transform(arr: Array) -> Transform3D:
	if arr.size() < 16:
		printerr("Number array " + str(arr) + " too short to convert to Transform3D.")
		return Transform3D.IDENTITY
	var x: Vector3 = Vector3(arr[0], arr[1], arr[2])
	var y: Vector3 = Vector3(arr[4], arr[5], arr[6])
	var z: Vector3 = Vector3(arr[8], arr[9], arr[10])
	var o: Vector3 = Vector3(arr[12], arr[13], arr[14])
	return Transform3D(Basis(x, y, z), o)
