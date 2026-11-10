@tool
extends RefCounted

const ORIGINAL := "original"
const BUILTIN_ROOT := "res://addons/bongo_cat/skins"
const USER_ROOT := "user://bongo_cat/skins"
const CAT_LAYERS := ["cubism_body.png", "cubism_paw.png", "cubism_arm_texture.png"]


static func root_for(id: String) -> String:
	if id.is_empty() or id == ORIGINAL:
		return ""
	var user_path := USER_ROOT.path_join(id)
	if DirAccess.dir_exists_absolute(user_path):
		return user_path
	var builtin := BUILTIN_ROOT.path_join(id)
	if DirAccess.dir_exists_absolute(builtin):
		return builtin
	return ""


static func list_ids() -> Array[String]:
	var ids: Array[String] = [ORIGINAL]
	for base in [USER_ROOT, BUILTIN_ROOT]:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with(".") and not ids.has(entry):
				ids.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	return ids


static func display_name(id: String) -> String:
	if id == ORIGINAL:
		return "Оригинал"
	var data := metadata(id)
	return String(data.get("name", id))


static func metadata(id: String) -> Dictionary:
	var root := root_for(id)
	if root.is_empty():
		return {}
	var path := root.path_join("skin.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func layer_path(id: String, filename: String) -> String:
	if id == ORIGINAL or not CAT_LAYERS.has(filename):
		return ""
	var root := root_for(id)
	if root.is_empty():
		return ""
	var path := root.path_join(filename)
	return path if FileAccess.file_exists(path) else ""


static func overlay_path(id: String, art_name: String) -> String:
	if id == ORIGINAL or art_name.is_empty():
		return ""
	var root := root_for(id)
	if root.is_empty():
		return ""
	var path := root.path_join("left-keys").path_join(art_name + ".png")
	return path if FileAccess.file_exists(path) else ""


static func load_texture(path: String) -> Texture2D:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			return texture
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func startup_id() -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--skin="):
			return arg.substr(7)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		var query := String(bridge.eval("location.search", true))
		for part in query.trim_prefix("?").split("&", false):
			if part.begins_with("skin="):
				return part.substr(5).uri_decode()
	return ORIGINAL
