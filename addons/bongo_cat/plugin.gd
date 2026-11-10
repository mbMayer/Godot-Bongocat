@tool
extends EditorPlugin

const DockContent = preload("res://addons/bongo_cat/bongo_cat_dock.gd")
const EditorOverlay = preload("res://addons/bongo_cat/bongo_cat_overlay.gd")
const ICON_PATH := "res://addons/bongo_cat/assets/bongo_cat.png"

var _dock: EditorDock
var _content: VBoxContainer
var _overlay: Control
var _plugin_icon: Texture2D


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.name = "BongoCatDock"
	_dock.title = "Bongo Cat"
	_dock.layout_key = "bongo_cat"
	_plugin_icon = EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
	_dock.dock_icon = _plugin_icon
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.closable = true
	_dock.dock_shortcut = _make_dock_shortcut()

	_content = DockContent.new()
	_dock.add_child(_content)
	add_dock(_dock)

	_overlay = EditorOverlay.new()
	EditorInterface.get_base_control().add_child(_overlay)
	_content.overlay_toggle_requested.connect(_overlay.set_overlay_visible)
	_content.overlay_corner_changed.connect(_overlay.set_corner)
	_overlay.overlay_visibility_changed.connect(_content.set_overlay_visible)
	_content.settings_changed.connect(_sync_overlay_settings)
	_content.reset_requested.connect(_overlay.release_all)
	_sync_overlay_settings()

	var root_window := get_tree().root
	if not root_window.focus_exited.is_connected(_on_editor_focus_exited):
		root_window.focus_exited.connect(_on_editor_focus_exited)
	set_process_input(true)
	call_deferred("_load_custom_icon")
	call_deferred("_open_dock")


func _exit_tree() -> void:
	set_process_input(false)
	if is_inside_tree():
		var root_window := get_tree().root
		if root_window.focus_exited.is_connected(_on_editor_focus_exited):
			root_window.focus_exited.disconnect(_on_editor_focus_exited)
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if is_instance_valid(_dock):
		remove_dock(_dock)
		_dock.queue_free()
	_dock = null
	_content = null


func _input(event: InputEvent) -> void:
	if is_instance_valid(_content):
		_content.handle_input(event)
	if is_instance_valid(_overlay):
		_overlay.handle_input(event)


func _open_dock() -> void:
	if is_instance_valid(_dock):
		_dock.open()


func _load_custom_icon() -> void:
	if ResourceLoader.exists(ICON_PATH):
		var texture := load(ICON_PATH) as Texture2D
		if texture != null:
			_plugin_icon = texture
			if is_instance_valid(_dock):
				_dock.dock_icon = texture


func _on_editor_focus_exited() -> void:
	if is_instance_valid(_content):
		_content.release_all()
	if is_instance_valid(_overlay):
		_overlay.release_all()


func _sync_overlay_settings() -> void:
	if is_instance_valid(_content) and is_instance_valid(_overlay):
		_content.apply_settings_to(_overlay.view)
		_overlay.set_corner(_content.overlay_corner(), false)


func _make_dock_shortcut() -> Shortcut:
	var shortcut := Shortcut.new()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_B
	event.alt_pressed = true
	shortcut.events = [event]
	return shortcut


func _get_plugin_name() -> String:
	return "Bongo Cat"


func _get_plugin_icon() -> Texture2D:
	return _plugin_icon
