extends RefCounted

const GRID_SIZE := 9
const ORIGIN_MIN := -30.0
const ORIGIN_STEP := 7.5
const SHOULDER_Y := 170.0
const LOCAL_SHOULDER_Y := 120.0
const WRIST_Y := 234.0
const KEY_HOVER := 12.0

var _metadata: Dictionary = {}
var _loaded := false
var _frame_count := 0
var _vertex_count := 0
var _frames := PackedFloat32Array()
var _mouse_centers := PackedVector2Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _rest_mouse_origin := Vector2.ZERO
var _rest_mouse_center := Vector2.ZERO
var _paw_origin := Vector2.ZERO
var _default_reach_target := Vector2.ZERO
var _key_targets: Dictionary = {}


func is_loaded() -> bool:
	return _loaded


func frame_count() -> int:
	return _frame_count


func vertex_count() -> int:
	return _vertex_count


func metadata() -> Dictionary:
	return _metadata


func paw_origin() -> Vector2:
	return _paw_origin


func default_reach_target() -> Vector2:
	return _default_reach_target


func key_target(art_name: String) -> Vector2:
	var target: Vector2 = _key_targets.get(art_name, _default_reach_target)
	return target


func key_target_count() -> int:
	return _key_targets.size()


func load_metadata(path: String) -> bool:
	_loaded = false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	for section in ["mesh", "mouse", "raised_paw", "reach"]:
		if not data.has(section):
			return false
	if not (data["mouse"].has("rest_origin") and data["mouse"].has("rest_center")
			and data["raised_paw"].has("origin") and data["reach"].has("target")
			and data["reach"].has("validation_vertices")):
		return false
	var mesh_info: Dictionary = data["mesh"]
	var binary_path := path.get_base_dir().path_join(String(mesh_info.get("file", "")))
	var file := FileAccess.open(binary_path, FileAccess.READ)
	if file == null:
		return false
	file.big_endian = false
	if file.get_buffer(8).get_string_from_ascii() != String(mesh_info.get("magic", "BCMESH01")):
		return false
	_frame_count = int(file.get_32())
	_vertex_count = int(file.get_32())
	var index_count := int(file.get_32())
	if _frame_count != GRID_SIZE * GRID_SIZE or _vertex_count <= 0 or index_count <= 0:
		return false
	if _frame_count != int(mesh_info.get("frame_count", -1)) \
	or _vertex_count != int(mesh_info.get("vertex_count", -1)) \
	or index_count != int(mesh_info.get("index_count", -1)):
		return false

	_uvs.clear()
	_colors.clear()
	for _index in range(_vertex_count):
		var u := file.get_float()
		var v := file.get_float()
		_uvs.append(Vector2(u, 1.0 - v))
		_colors.append(Color.WHITE)
	_indices.clear()
	for _index in range(index_count):
		_indices.append(int(file.get_16()))
	_frames.resize(_frame_count * _vertex_count * 2)
	for index in range(_frames.size()):
		_frames[index] = file.get_float()
	_mouse_centers.resize(GRID_SIZE * GRID_SIZE)
	for index in range(_mouse_centers.size()):
		_mouse_centers[index] = Vector2(file.get_float(), file.get_float())
	if file.get_position() != file.get_length():
		return false

	_metadata = data
	_rest_mouse_origin = _vector(data["mouse"]["rest_origin"])
	_rest_mouse_center = _vector(data["mouse"]["rest_center"])
	_paw_origin = _vector(data["raised_paw"]["origin"])
	_default_reach_target = _vector(data["reach"]["target"])
	_key_targets.clear()
	var key_text := FileAccess.get_file_as_string(path.get_base_dir().path_join("two_hand_keys.json"))
	var key_data = JSON.parse_string(key_text)
	if not key_data is Dictionary or not key_data.has("keys"):
		return false
	for art_name in key_data["keys"]:
		var entry: Dictionary = key_data["keys"][art_name]
		if not entry.has("target"):
			return false
		_key_targets[art_name] = _vector(entry["target"])
	if _key_targets.is_empty():
		return false
	_loaded = true
	return true


func _vector(value) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _cell(origin: Vector2) -> Dictionary:
	var gx := clampf((origin.x - ORIGIN_MIN) / ORIGIN_STEP, 0.0, GRID_SIZE - 1.0)
	var gy := clampf((origin.y - ORIGIN_MIN) / ORIGIN_STEP, 0.0, GRID_SIZE - 1.0)
	var x0 := mini(int(floor(gx)), GRID_SIZE - 1)
	var y0 := mini(int(floor(gy)), GRID_SIZE - 1)
	return {
		"x0": x0, "y0": y0,
		"x1": mini(x0 + 1, GRID_SIZE - 1), "y1": mini(y0 + 1, GRID_SIZE - 1),
		"tx": gx - x0, "ty": gy - y0,
	}


func _frame_vertex(frame: int, vertex: int) -> Vector2:
	var offset := (frame * _vertex_count + vertex) * 2
	return Vector2(_frames[offset], _frames[offset + 1])


func _mesh_vertex(cell: Dictionary, vertex: int) -> Vector2:
	var row0: int = int(cell["y0"]) * GRID_SIZE
	var row1: int = int(cell["y1"]) * GRID_SIZE
	var tx: float = cell["tx"]
	var ty: float = cell["ty"]
	var top := _frame_vertex(row0 + int(cell["x0"]), vertex).lerp(
		_frame_vertex(row0 + int(cell["x1"]), vertex), tx)
	var bottom := _frame_vertex(row1 + int(cell["x0"]), vertex).lerp(
		_frame_vertex(row1 + int(cell["x1"]), vertex), tx)
	return top.lerp(bottom, ty)


func _mouse_center_cell(cell: Dictionary) -> Vector2:
	var row0: int = int(cell["y0"]) * GRID_SIZE
	var row1: int = int(cell["y1"]) * GRID_SIZE
	var tx: float = cell["tx"]
	var ty: float = cell["ty"]
	var top := _mouse_centers[row0 + int(cell["x0"])].lerp(
		_mouse_centers[row0 + int(cell["x1"])], tx)
	var bottom := _mouse_centers[row1 + int(cell["x0"])].lerp(
		_mouse_centers[row1 + int(cell["x1"])], tx)
	return top.lerp(bottom, ty)


func mouse_center(origin: Vector2) -> Vector2:
	if not _loaded:
		return Vector2(147.5, 230.0) + origin
	return _mouse_center_cell(_cell(origin))


func mouse_origin(origin: Vector2) -> Vector2:
	return mouse_center(origin) - _rest_mouse_center + _rest_mouse_origin


func native_vertices(origin: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(_vertex_count)
	if not _loaded:
		return result
	var cell := _cell(origin)
	for vertex in range(_vertex_count):
		result[vertex] = _mesh_vertex(cell, vertex)
	return result


func local_reach_vertices(origin: Vector2, travel: float, tap: float,
		target: Vector2) -> PackedVector2Array:
	var base := native_vertices(origin)
	var amount := clampf(travel, 0.0, 1.0)
	if amount <= 0.0:
		return base
	var raised_target := target + Vector2(0.0, -KEY_HOVER * (1.0 - clampf(tap, 0.0, 1.0)))
	var delta := (raised_target - mouse_center(origin)) * amount
	var result := PackedVector2Array()
	result.resize(_vertex_count)
	for vertex in range(_vertex_count):
		var weight := smoothstep(LOCAL_SHOULDER_Y, WRIST_Y, base[vertex].y)
		result[vertex] = base[vertex] + delta * weight
	return result


func interpolated_vertices(origin: Vector2, reach: float, target: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(_vertex_count)
	if not _loaded:
		return result
	var cell := _cell(origin)
	var center := _mouse_center_cell(cell)
	var amount := clampf(reach, 0.0, 1.0)
	var delta := (target - center) * amount
	for vertex in range(_vertex_count):
		var point := _mesh_vertex(cell, vertex)
		var weight := smoothstep(SHOULDER_Y, WRIST_Y, point.y)
		result[vertex] = point + delta * weight
	return result


func update_vertices(mesh: ArrayMesh, vertices: PackedVector2Array) -> void:
	if not _loaded or mesh == null or vertices.size() != _vertex_count:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.clear_surfaces()
	if not arrays[Mesh.ARRAY_INDEX].is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func validation_error() -> float:
	if not _loaded:
		return INF
	var original_target := _vector(_metadata["reach"]["target"])
	var actual := interpolated_vertices(Vector2.ZERO, 1.0, original_target)
	var expected: Array = _metadata["reach"]["validation_vertices"]
	var maximum := 0.0
	for index in range(mini(actual.size(), expected.size())):
		var point := _vector(expected[index])
		maximum = maxf(maximum, actual[index].distance_to(point))
	return maximum
