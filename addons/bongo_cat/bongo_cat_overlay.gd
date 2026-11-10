@tool
extends Control

signal overlay_visibility_changed(enabled: bool)

const CatView = preload("res://addons/bongo_cat/bongo_cat_view.gd")
const SETTING_VISIBLE := "bongo_cat/editor_overlay_visible"
const SETTING_CORNER := "bongo_cat/editor_overlay_corner"
const SETTING_FLYING_LETTERS := "bongo_cat/flying_letters"
const CAT_SIZE := Vector2(376.0, 197.0)
const SIDE_MARGIN := 24.0
const TOP_MARGIN := 112.0
const BOTTOM_MARGIN := 72.0

enum Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

var view: Control
var _panel: Control
var _settings: EditorSettings
var _corner := Corner.BOTTOM_RIGHT


func _ready() -> void:
	name = "BongoCatEditorOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4096
	z_as_relative = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings = EditorInterface.get_editor_settings()
	_ensure_settings()
	_build_overlay()
	resized.connect(_apply_corner)
	get_tree().root.size_changed.connect(_apply_corner)
	call_deferred("_restore_layout")


func _exit_tree() -> void:
	if is_inside_tree() and get_tree().root.size_changed.is_connected(_apply_corner):
		get_tree().root.size_changed.disconnect(_apply_corner)
	if resized.is_connected(_apply_corner):
		resized.disconnect(_apply_corner)


func _ensure_settings() -> void:
	if not _settings.has_setting(SETTING_VISIBLE):
		_settings.set_setting(SETTING_VISIBLE, true)
	if not _settings.has_setting(SETTING_CORNER):
		_settings.set_setting(SETTING_CORNER, Corner.BOTTOM_RIGHT)
	if not _settings.has_setting(SETTING_FLYING_LETTERS):
		_settings.set_setting(SETTING_FLYING_LETTERS, true)


func _build_overlay() -> void:
	_panel = Control.new()
	_panel.name = "PinnedCat"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.clip_contents = false
	_panel.z_index = 4096
	_panel.z_as_relative = false
	_panel.custom_minimum_size = CAT_SIZE
	_panel.size = CAT_SIZE
	add_child(_panel)

	view = CatView.new()
	view.name = "PinnedCatView"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(view)


func _restore_layout() -> void:
	if not is_instance_valid(_panel):
		return
	_panel.reset_size()
	_panel.size = CAT_SIZE
	_corner = clampi(int(_settings.get_setting(SETTING_CORNER)), 0, Corner.BOTTOM_RIGHT)
	_panel.visible = bool(_settings.get_setting(SETTING_VISIBLE))
	_apply_corner()


func corner() -> int:
	return _corner


func set_corner(value: int, persist: bool = true) -> void:
	_corner = clampi(value, 0, Corner.BOTTOM_RIGHT)
	if persist and is_instance_valid(_settings):
		_settings.set_setting(SETTING_CORNER, _corner)
	_apply_corner()


func set_overlay_visible(enabled: bool, persist: bool = true) -> void:
	if persist and is_instance_valid(_settings):
		_settings.set_setting(SETTING_VISIBLE, enabled)
	if is_instance_valid(_panel):
		_panel.visible = enabled
	overlay_visibility_changed.emit(enabled)


func handle_input(event: InputEvent) -> void:
	if is_instance_valid(view):
		view.handle_input(event)


func release_all() -> void:
	if is_instance_valid(view):
		view.release_all()


func _apply_corner() -> void:
	if not is_instance_valid(_panel):
		return
	var left := SIDE_MARGIN
	var top := TOP_MARGIN
	var right := maxf(left, size.x - CAT_SIZE.x - SIDE_MARGIN)
	var bottom := maxf(top, size.y - CAT_SIZE.y - BOTTOM_MARGIN)
	var target := Vector2.ZERO
	match _corner:
		Corner.TOP_LEFT:
			target = Vector2(left, top)
		Corner.TOP_RIGHT:
			target = Vector2(right, top)
		Corner.BOTTOM_LEFT:
			target = Vector2(left, bottom)
		Corner.BOTTOM_RIGHT:
			target = Vector2(right, bottom)
	var maximum := (size - CAT_SIZE).max(Vector2.ZERO)
	_panel.position = target.clamp(Vector2.ZERO, maximum)
