@tool
extends Control

signal activity_changed(text: String)

const KeyMap = preload("res://addons/bongo_cat/key_map.gd")
const PoseGrid = preload("res://addons/bongo_cat/cubism_pose_grid.gd")
const SkinManager = preload("res://addons/bongo_cat/skin_manager.gd")
const ArtCache = preload("res://addons/bongo_cat/art_cache.gd")
const CatEyes = preload("res://addons/bongo_cat/cat_eyes.gd")

const BASE_SIZE := Vector2(612.0, 354.0)
const PAD_EXTENSION := 32.0
const ART_ROOT := "res://addons/bongo_cat/assets/original"
const MOUSE_TRAVEL := Vector2(30.0, 30.0)
const STANDARD_KEYBOARD_OFFSET := Vector2.ZERO
const STANDARD_MOUSE_REST_ORIGIN := Vector2.ZERO
const STANDARD_PAD_OFFSET := Vector2.ZERO
const LETTER_LIFETIME := 1.9
const LETTER_GRAVITY := 430.0
const LETTER_LAUNCH := 128.0
const LETTER_BOUNCE := 0.42
const LETTER_FLOOR := BASE_SIZE.y - 18.0
const LETTER_MAX := 24
const WHEEL_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
const BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "левая кнопка", MOUSE_BUTTON_RIGHT: "правая кнопка",
	MOUSE_BUTTON_MIDDLE: "средняя кнопка", MOUSE_BUTTON_WHEEL_UP: "колесо вверх",
	MOUSE_BUTTON_WHEEL_DOWN: "колесо вниз", MOUSE_BUTTON_WHEEL_LEFT: "колесо влево",
	MOUSE_BUTTON_WHEEL_RIGHT: "колесо вправо", MOUSE_BUTTON_XBUTTON1: "боковая кнопка 1",
	MOUSE_BUTTON_XBUTTON2: "боковая кнопка 2",
}
var reactions_enabled := true
var skin_id := SkinManager.ORIGINAL
var keyboard_enabled := true
var mouse_enabled := true
var flying_letters_enabled := true
var _letter_particles: Array[Dictionary] = []
var _letter_contacts: Dictionary = {}
var _glyph_widths: Dictionary = {}
var mirrored := false
var response_speed := 1.0
var last_activity := "Готов — оригинальный Bongo Cat"

var _pressed_keys: Dictionary = {}
var _key_order: Array[String] = []
var _input_serial := 0

var _layers: Dictionary = {}
var _display: Dictionary = {}
var _pressed_body: Texture2D
var _eye_set: Dictionary = {}
var _blink := 0.0
var _prev_blink := 0.0
var _pose_grid = PoseGrid.new()
var _arm_mesh: ArrayMesh
var _last_mesh_origin := Vector2(INF, INF)
var _art_pending := false
var _art_retry := 0.0
var _active_keyboard_id := ""
var _keyboard_texture: Texture2D

var _mouse_target_uv := Vector2(0.5, 0.5)
var _drag_current := STANDARD_MOUSE_REST_ORIGIN
var _drag_target := STANDARD_MOUSE_REST_ORIGIN
var _mouse_buttons: Dictionary = {}
var _mouse_press_visual := 0.0
var _wheel_flash := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--no-blink":
			CatEyes.enabled = false
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		if "noblink=1" in String(bridge.eval("location.search", true)):
			CatEyes.enabled = false
	name = "OriginalBongoCatView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_arm_mesh = ArrayMesh.new()
	_load_model()
	set_process(true)
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(306.0, 177.0)


func _required_layer_files() -> Array[String]:
	return [
		"cubism_body.png", "cubism_paw.png", "cubism_arm_texture.png",
		"layers/mouse.png", "layers/keyboard.png", "layers/left_device.png",
	]


func _layer_path(filename: String) -> String:
	var custom := SkinManager.layer_path(skin_id, filename)
	if not custom.is_empty():
		return custom
	return "%s/standard/%s" % [ART_ROOT, filename]


func _path_exists(path: String) -> bool:
	if path.begins_with("res://"):
		return ResourceLoader.exists(path)
	return FileAccess.file_exists(path)


func _smoothed(texture: Texture2D, fix_edges: bool = false) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return texture
	return ArtCache.smoothed(image, fix_edges)


func _make_pressed_body(overlay: Texture2D, art_name: String) -> Texture2D:
	if overlay == null or art_name.is_empty():
		return null
	var key := skin_id + "|" + art_name
	var cached := ArtCache.body(key)
	if cached != null:
		return cached
	var base := _display.get("cubism_body.png") as Texture2D
	if base == null:
		return null
	var body := base.get_image()
	var arm := overlay.get_image()
	if body == null or arm == null:
		return null
	var copy := body.duplicate() as Image
	for y in range(140, 256):
		for x in range(455, 526):
			var a := arm.get_pixel(x, y)
			if a.a < 0.78 or minf(a.r, minf(a.g, a.b)) < 0.78:
				continue
			var pixel := copy.get_pixel(x, y)
			if pixel.a > 0.0:
				copy.set_pixel(x, y, Color(1.0, 1.0, 1.0, pixel.a))
	var texture := ArtCache.smoothed(copy, false)
	ArtCache.remember_body(key, texture)
	return texture


func set_skin(id: String) -> void:
	if skin_id == id:
		return
	skin_id = id
	_load_model()


func _load_model() -> void:
	for filename in _required_layer_files():
		var candidate := _layer_path(filename)
		if not _path_exists(candidate):
			_art_pending = true
			return
	if not _pose_grid.load_metadata(
		"%s/standard/cubism_poses.json" % ART_ROOT
	):
		_art_pending = true
		return
	_art_pending = false
	_load_letter_contacts()
	_layers.clear()
	_display.clear()
	_pressed_body = null
	_keyboard_texture = null
	for filename in _required_layer_files():
		var path := _layer_path(filename)
		var texture := SkinManager.load_texture(path)
		if texture == null:
			push_error("Bongo Cat: cannot load layer: " + path)
		else:
			_layers[filename] = texture
			_display[filename] = ArtCache.layer(
				path, texture, path.begins_with("user://"))
	var body_path := _layer_path("cubism_body.png")
	var body_source := _layers.get("cubism_body.png") as Texture2D
	if body_source != null:
		_eye_set = ArtCache.eyes(skin_id + "|eyes", body_source,
			CatEyes.regions(SkinManager.metadata(skin_id)),
			body_path.begins_with("user://"))
		if not _eye_set.is_empty():
			_display["cubism_body.png"] = _eye_set["eyeless"] as Texture2D
	_update_arm_mesh(true)
	queue_redraw()


func _load_letter_contacts() -> void:
	_letter_contacts.clear()
	var path := "%s/standard/two_hand_keys.json" % ART_ROOT
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("keys"):
		return
	var keys: Dictionary = parsed["keys"]
	for key_name in keys:
		var entry: Dictionary = keys[key_name]
		var target: Array = entry.get("target", [])
		if target.size() >= 2:
			_letter_contacts[String(key_name)] = Vector2(float(target[0]), float(target[1]))


func handle_input(event: InputEvent) -> void:
	if not reactions_enabled:
		return
	if event is InputEventKey and keyboard_enabled:
		_handle_key(event)
	elif event is InputEventMouseMotion and mouse_enabled:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton and mouse_enabled:
		_handle_mouse_button(event)


func _handle_key(event: InputEventKey) -> void:
	var id := KeyMap.id_for_event(event)
	var code := KeyMap.code_for_event(event)
	if code == KEY_NONE:
		return

	if not event.pressed:
		if not _pressed_keys.has(id):
			return
		_pressed_keys.erase(id)
		_key_order.erase(id)
		_refresh_active_art()
		return

	if event.echo or _pressed_keys.has(id):
		return

	var label := _key_label(event, code)
	_input_serial += 1
	var art := KeyMap.original_art_for_event(event)
	_pressed_keys[id] = art
	_key_order.append(id)
	_refresh_active_art()
	_set_activity("Клавиша: " + label)
	_spawn_flying_letter(_flying_letter_text(event, code), String(art.get("name", "")))


func _refresh_active_art() -> void:
	_active_keyboard_id = "" if _key_order.is_empty() else _key_order.back()
	_keyboard_texture = null
	if not _active_keyboard_id.is_empty():
		var art: Dictionary = _pressed_keys[_active_keyboard_id]
		_keyboard_texture = _overlay_texture(String(art.get("name", "")))
	_pressed_body = _make_pressed_body(_keyboard_texture,
		active_overlay_name("keyboard"))
	queue_redraw()


func _key_label(event: InputEventKey, code: int) -> String:
	# key_label follows the OS layout; physical_keycode does not.
	var text := event.as_text_key_label()
	if text.is_empty() or text == "(unset)":
		text = event.as_text_keycode()
	if text.is_empty() or text == "(unset)":
		text = OS.get_keycode_string(code)
	return text


func _flying_letter_text(event: InputEventKey, code: int) -> String:
	var text := _key_label(event, code)
	if text.length() == 1:
		text = text.to_upper()
	return text


func _spawn_flying_letter(text: String, art_name: String) -> void:
	if not flying_letters_enabled:
		return
	var base_pos: Vector2 = _letter_contacts.get(art_name, Vector2(394.0, 282.0))
	var jitter := float((_input_serial * 37) % 13) - 6.0
	var drift := float((_input_serial * 53) % 41) - 20.0
	base_pos.x += jitter
	base_pos.y -= 12.0
	_letter_particles.append({
		"text": text,
		"pos": base_pos,
		"vel": Vector2(drift, -LETTER_LAUNCH),
		"age": 0.0,
		"bounced": false,
	})
	while _letter_particles.size() > LETTER_MAX:
		_letter_particles.pop_front()
	queue_redraw()


func _update_letter_particles(delta: float) -> void:
	if _letter_particles.is_empty():
		return
	var dt := delta if delta < 0.25 else 0.05
	var alive: Array[Dictionary] = []
	for particle in _letter_particles:
		var age := float(particle["age"]) + dt
		if age >= LETTER_LIFETIME:
			continue
		var pos: Vector2 = particle["pos"]
		var vel: Vector2 = particle["vel"]
		pos += vel * dt
		vel.y += LETTER_GRAVITY * dt
		if pos.y >= LETTER_FLOOR and not bool(particle["bounced"]):
			pos.y = LETTER_FLOOR
			vel.y = -absf(vel.y) * LETTER_BOUNCE
			vel.x *= 0.65
			particle["bounced"] = true
		particle["pos"] = pos
		particle["vel"] = vel
		particle["age"] = age
		alive.append(particle)
	_letter_particles = alive


func _letter_alpha(particle: Dictionary) -> float:
	var age := float(particle["age"])
	var fade_in := clampf(age / 0.09, 0.0, 1.0)
	var fade_out := clampf((LETTER_LIFETIME - age) / 0.45, 0.0, 1.0)
	return fade_in * fade_out


func _draw_letter_particles() -> void:
	if _letter_particles.is_empty():
		return
	var font := ThemeDB.fallback_font
	var draw_scale := minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)
	var origin := (size - BASE_SIZE * draw_scale) * 0.5
	var font_size := int(maxf(14.0, 22.0 * draw_scale))
	for particle in _letter_particles:
		var alpha := _letter_alpha(particle)
		if alpha <= 0.0:
			continue
		var base_pos: Vector2 = particle["pos"]
		var sx := origin.x + base_pos.x * draw_scale
		var sy := origin.y + base_pos.y * draw_scale
		if mirrored:
			sx = size.x - sx
		var age := float(particle["age"])
		var pop := clampf(age / 0.13, 0.0, 1.0)
		var scale := 0.70 + 0.30 * smoothstep(0.0, 1.0, pop)
		var text := String(particle["text"])
		var width_key := text + "|" + str(font_size)
		if not _glyph_widths.has(width_key):
			_glyph_widths[width_key] = font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var width: float = _glyph_widths[width_key]
		var offset := Vector2(-width * 0.5, font_size * 0.35)
		draw_set_transform(Vector2(sx, sy), 0.0, Vector2(scale, scale))
		draw_string_outline(font, offset, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2,
			Color(0.03, 0.04, 0.07, alpha * 0.92))
		draw_string(font, offset, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color(0.44, 0.90, 0.89, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func set_flying_letters_enabled(value: bool) -> void:
	flying_letters_enabled = value
	if not value:
		_letter_particles.clear()
	queue_redraw()


func _overlay_texture(art_name: String) -> Texture2D:
	if art_name.is_empty():
		return null
	var key := skin_id + "|" + art_name
	var cached := ArtCache.overlay(key)
	if cached != null:
		return cached
	var custom := SkinManager.overlay_path(skin_id, art_name)
	var path := custom if not custom.is_empty() else \
		"%s/common/left-keys/%s.png" % [ART_ROOT, art_name]
	if not _path_exists(path):
		return null
	var texture := _smoothed(SkinManager.load_texture(path), path.begins_with("user://"))
	if texture == null:
		push_warning("Bongo Cat: key frame is unavailable: " + path)
		return null
	ArtCache.remember_overlay(key, texture)
	return texture


func active_overlay_name(group: String = "keyboard") -> String:
	if group != "keyboard" or _active_keyboard_id.is_empty():
		return ""
	var art: Dictionary = _pressed_keys.get(_active_keyboard_id, {})
	return String(art.get("name", ""))


func has_key_overlay() -> bool:
	return _keyboard_texture != null


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.relative.is_zero_approx() and event.screen_relative.is_zero_approx():
		return
	_update_mouse_position(event.global_position, event.screen_relative)
	_input_serial += 1
	_set_activity("Мышь: движение")


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	_update_mouse_position(event.global_position, Vector2.ZERO)
	var button := int(event.button_index)
	var is_wheel := button in WHEEL_BUTTONS
	if is_wheel:
		if event.pressed:
			_input_serial += 1
			_wheel_flash = 1.0
			_set_activity("Мышь: " + _mouse_button_name(button))
			queue_redraw()
		return

	_input_serial += 1
	if event.pressed:
		_mouse_buttons[button] = true
		_set_activity("Мышь: " + _mouse_button_name(button))
	else:
		_mouse_buttons.erase(button)
	queue_redraw()


func _update_mouse_position(global_position: Vector2, relative: Vector2) -> void:
	var viewport_size := Vector2.ZERO
	if is_inside_tree():
		viewport_size = get_tree().root.get_visible_rect().size
	if viewport_size.x > 1.0 and viewport_size.y > 1.0:
		_mouse_target_uv = global_position / viewport_size
	elif not relative.is_zero_approx():
		_mouse_target_uv += relative * 0.002
	_mouse_target_uv = _mouse_target_uv.clamp(Vector2.ZERO, Vector2.ONE)
	var mapped_uv := _mouse_target_uv
	# Both pointer axes are compensated. The horizontal mirror flips X again,
	# so X is skipped when mirrored; Y is always flipped.
	if not mirrored:
		mapped_uv.x = 1.0 - mapped_uv.x
	mapped_uv.y = 1.0 - mapped_uv.y
	_drag_target = _pointer_origin_for_uv(mapped_uv)
	queue_redraw()


func _pointer_origin_for_uv(uv: Vector2) -> Vector2:
	var requested := STANDARD_MOUSE_REST_ORIGIN + (uv * 2.0 - Vector2.ONE) * MOUSE_TRAVEL
	return requested.clamp(-MOUSE_TRAVEL, MOUSE_TRAVEL)


func _mouse_button_name(button: int) -> String:
	return String(BUTTON_NAMES.get(button, "кнопка %d" % button))


func _process(delta: float) -> void:
	_blink = CatEyes.blink_amount(Time.get_ticks_msec())
	if _art_pending:
		_art_retry -= delta
		if _art_retry <= 0.0:
			_art_retry = 0.25
			_load_model()
	_update_letter_particles(delta)
	var old_drag := _drag_current
	var old_press := _mouse_press_visual
	var old_wheel := _wheel_flash
	var blend := 1.0 - exp(-delta * 13.0 * clampf(response_speed, 0.6, 1.8))
	_drag_current = _drag_current.lerp(_drag_target, blend)
	# Snap to an exact resting pose once the difference is sub-pixel.
	if _drag_current.distance_squared_to(_drag_target) < 0.00001:
		_drag_current = _drag_target
	var press_target := 1.0 if not _mouse_buttons.is_empty() else 0.0
	_mouse_press_visual = lerpf(_mouse_press_visual, press_target, blend)
	_wheel_flash = maxf(0.0, _wheel_flash - delta * 3.4)
	if old_drag.distance_squared_to(_drag_current) > 0.00001 \
		or not is_equal_approx(old_press, _mouse_press_visual) \
		or not is_equal_approx(old_wheel, _wheel_flash) \
		or not _letter_particles.is_empty() \
		or _blink > 0.0 or _prev_blink > 0.0:
		queue_redraw()
	_prev_blink = _blink
	_update_arm_mesh()


func set_reactions_enabled(value: bool) -> void:
	reactions_enabled = value
	if not reactions_enabled:
		reset_input("Пауза — ввод не отслеживается")
	else:
		_set_activity("Готов — слушаю ввод редактора")
	queue_redraw()


func set_keyboard_enabled(value: bool) -> void:
	keyboard_enabled = value
	if not keyboard_enabled:
		_pressed_keys.clear()
		_key_order.clear()
		_refresh_active_art()
	queue_redraw()


func set_mouse_enabled(value: bool) -> void:
	mouse_enabled = value
	if not mouse_enabled:
		_mouse_buttons.clear()
		_mouse_press_visual = 0.0
		_wheel_flash = 0.0
		_mouse_target_uv = Vector2(0.5, 0.5)
		_drag_target = STANDARD_MOUSE_REST_ORIGIN
	queue_redraw()


func reset_input(status: String = "Готов — слушаю ввод редактора") -> void:
	release_all()
	_set_activity(status)
	queue_redraw()


func release_all() -> void:
	_pressed_keys.clear()
	_key_order.clear()
	_mouse_buttons.clear()
	_active_keyboard_id = ""
	_keyboard_texture = null
	_pressed_body = null
	_wheel_flash = 0.0
	_mouse_press_visual = 0.0
	_letter_particles.clear()
	_mouse_target_uv = Vector2(0.5, 0.5)
	_drag_current = STANDARD_MOUSE_REST_ORIGIN
	_drag_target = STANDARD_MOUSE_REST_ORIGIN
	queue_redraw()


func _set_activity(text: String) -> void:
	if last_activity == text:
		return
	last_activity = text
	activity_changed.emit(text)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func mouse_arm_tip() -> Vector2:
	return _pose_grid.mouse_center(_drag_current)


func _update_arm_mesh(force: bool = false) -> void:
	if _arm_mesh == null or not _pose_grid.is_loaded():
		return
	if not force and _drag_current.distance_squared_to(_last_mesh_origin) < 0.0000001:
		return
	_pose_grid.update_vertices(_arm_mesh, _pose_grid.native_vertices(_drag_current))
	_last_mesh_origin = _drag_current


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	if mirrored:
		draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	_draw_content()
	if mirrored:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_letter_particles()


func _draw_content() -> void:
	if not _layers.has("cubism_body.png"):
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(18.0, 30.0), "Импорт оригинальных ресурсов Bongo Cat…",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("a9b4c9"))
		return

	var draw_scale := minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)
	var origin := (size - BASE_SIZE * draw_scale) * 0.5
	var destination := Rect2(origin, BASE_SIZE * draw_scale)
	var left_device := _display.get("layers/left_device.png") as Texture2D
	var keyboard_device := _display.get("layers/keyboard.png") as Texture2D
	if left_device != null:
		# Derived pad is 32 px wider on the left; other layers keep 612x354.
		var pad_origin := origin - Vector2(PAD_EXTENSION, 0.0) * draw_scale
		var pad_size := Vector2((BASE_SIZE.x + PAD_EXTENSION) * draw_scale,
			BASE_SIZE.y * draw_scale)
		draw_texture_rect(left_device, Rect2(pad_origin, pad_size), false)
	var keyboard_destination := Rect2(origin, BASE_SIZE * draw_scale)
	if keyboard_device != null:
		draw_texture_rect(keyboard_device, keyboard_destination, false)
	_draw_standard(destination, keyboard_destination, origin, draw_scale)

func _draw_standard(destination: Rect2, keyboard_destination: Rect2, origin: Vector2, draw_scale: float) -> void:
	var mouse := _display.get("layers/mouse.png") as Texture2D
	if mouse != null:
		var press_offset := Vector2(0.0, 2.0 * _mouse_press_visual - 3.0 * _wheel_flash)
		var mouse_origin := origin + (
			_pose_grid.mouse_origin(_drag_current) + press_offset
		) * draw_scale
		draw_texture_rect(mouse, Rect2(mouse_origin, mouse.get_size() * draw_scale), false)

	var has_key := _keyboard_texture != null
	if has_key:
		draw_texture_rect(_keyboard_texture, keyboard_destination, false)
	var body := _display.get("cubism_body.png") as Texture2D
	if has_key and _pressed_body != null:
		body = _pressed_body
	if body != null:
		draw_texture_rect(body, destination, false)
	_draw_eyes(origin, draw_scale)
	var arm_texture := _display.get("cubism_arm_texture.png") as Texture2D
	if arm_texture != null and _arm_mesh != null and _arm_mesh.get_surface_count() > 0:
		draw_mesh(_arm_mesh, arm_texture, Transform2D(Vector2(draw_scale, 0.0),
			Vector2(0.0, draw_scale), origin))
	if not has_key:
		var raised := _display.get("cubism_paw.png") as Texture2D
		if raised != null:
			draw_texture_rect(raised, Rect2(origin + _pose_grid.paw_origin() * draw_scale,
				raised.get_size() * draw_scale), false)


func _draw_eyes(origin: Vector2, draw_scale: float) -> void:
	if _eye_set.is_empty():
		return
	var gaze := CatEyes.gaze_offset(_mouse_target_uv, mirrored)
	var squash := 1.0 - 0.92 * _blink
	var sprites: Array = _eye_set["sprites"]
	var regions: Array = _eye_set["regions"]
	for index in range(sprites.size()):
		var region: Rect2i = regions[index]
		var center := Vector2(region.position) + Vector2(region.size) * 0.5
		var size := Vector2(region.size) * draw_scale
		size.y *= squash
		var position := origin + (center + gaze) * draw_scale - size * 0.5
		draw_texture_rect(sprites[index] as Texture2D, Rect2(position, size), false)


