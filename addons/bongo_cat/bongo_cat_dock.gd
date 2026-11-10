@tool
extends VBoxContainer

const CatView = preload("res://addons/bongo_cat/bongo_cat_view.gd")
const SkinManager = preload("res://addons/bongo_cat/skin_manager.gd")

signal overlay_toggle_requested(enabled: bool)
signal overlay_corner_changed(corner: int)
signal settings_changed
signal reset_requested

const SETTING_ENABLED := "bongo_cat/reactions_enabled"
const SETTING_KEYBOARD := "bongo_cat/keyboard_enabled"
const SETTING_MOUSE := "bongo_cat/mouse_enabled"
const SETTING_SPEED := "bongo_cat/paw_response_speed"
const SETTING_OVERLAY := "bongo_cat/editor_overlay_visible"
const SETTING_CORNER := "bongo_cat/editor_overlay_corner"
const SETTING_MIRROR := "bongo_cat/mirror_cat"
const SETTING_FLYING_LETTERS := "bongo_cat/flying_letters"
const SETTING_SKIN := "bongo_cat/skin"

enum Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

var view: Control
var _enabled_check: CheckButton
var _keyboard_check: CheckButton
var _mouse_check: CheckButton
var _speed_slider: HSlider
var _overlay_check: CheckButton
var _corner_option: OptionButton
var _mirror_check: CheckButton
var _letters_check: CheckButton
var _skin_option: OptionButton
var _activity_label: Label
var _settings: EditorSettings


func _ready() -> void:
	name = "BongoCatContent"
	custom_minimum_size = Vector2(650.0, 320.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_settings = EditorInterface.get_editor_settings()
	_ensure_settings()
	_build_toolbar()

	view = CatView.new()
	view.name = "CatView"
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(view)
	view.activity_changed.connect(_on_activity_changed)
	var bottom_inset := Control.new()
	bottom_inset.name = "DockTabInset"
	bottom_inset.custom_minimum_size.y = 14.0
	bottom_inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_inset)
	_load_settings()


func _check(parent: Control, text: String, tooltip: String,
		handler: Callable) -> CheckButton:
	var box := CheckButton.new()
	box.text = text
	box.tooltip_text = tooltip
	box.toggled.connect(handler)
	parent.add_child(box)
	return box


func _button(parent: Control, text: String, tooltip: String,
		handler: Callable) -> Button:
	var box := Button.new()
	box.text = text
	box.tooltip_text = tooltip
	box.pressed.connect(handler)
	parent.add_child(box)
	return box


func _build_toolbar() -> void:
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)

	var title := Label.new()
	title.text = "Bongo Cat"
	title.tooltip_text = "Оригинальные модели vladelaina/BongoCat · MIT"
	title.add_theme_font_size_override("font_size", 15)
	toolbar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_enabled_check = _check(toolbar, "Реагировать",
		"Временно остановить реакцию на ввод (шорткаты редактора не затрагиваются)",
		_on_enabled_toggled)
	_keyboard_check = _check(toolbar, "Клавиши",
		"Реакция лап на физические клавиши клавиатуры", _on_keyboard_toggled)
	_mouse_check = _check(toolbar, "Мышь",
		"Движение мыши, кнопки и колесо", _on_mouse_toggled)
	_button(toolbar, "Сброс", "Снять залипшие клавиши и кнопки после смены фокуса",
		_on_reset_pressed)

	var overlay_row := HBoxContainer.new()
	overlay_row.add_theme_constant_override("separation", 10)
	add_child(overlay_row)
	_overlay_check = _check(overlay_row, "Кот поверх редактора",
		"Показывать кота без рамки поверх любых вкладок редактора, даже когда этот dock закрыт",
		_on_overlay_toggled)

	var corner_label := Label.new()
	corner_label.text = "Угол:"
	overlay_row.add_child(corner_label)
	_corner_option = OptionButton.new()
	_corner_option.add_item("Сверху слева", Corner.TOP_LEFT)
	_corner_option.add_item("Сверху справа", Corner.TOP_RIGHT)
	_corner_option.add_item("Снизу слева", Corner.BOTTOM_LEFT)
	_corner_option.add_item("Снизу справа", Corner.BOTTOM_RIGHT)
	_corner_option.tooltip_text = "Фиксированный угол editor-wide кота; перетаскивания нет"
	_corner_option.item_selected.connect(_on_corner_selected)
	overlay_row.add_child(_corner_option)

	_mirror_check = _check(overlay_row, "Зеркалить кота",
		"Повернуть всего кота по горизонтали: корпус, лапы, коврик, клавиатуру и надписи",
		_on_mirror_toggled)
	_letters_check = _check(overlay_row, "Вылетающие буквы",
		"Показывать одну букву текущей раскладки (Ф или A): вылет вверх, падение, один мягкий отскок и затухание",
		_on_letters_toggled)

	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 8)
	add_child(skin_row)
	var skin_label := Label.new()
	skin_label.text = "Скин:"
	skin_row.add_child(skin_label)
	_skin_option = OptionButton.new()
	_skin_option.custom_minimum_size.x = 180.0
	_skin_option.tooltip_text = "Папка с PNG кота и лап; устройства остаются оригинальными"
	_skin_option.item_selected.connect(_on_skin_selected)
	skin_row.add_child(_skin_option)
	_button(skin_row, "Обновить", "Перечитать папки скинов", _on_skin_refresh)

	var hint := Label.new()
	hint.text = "Кот без окна и рамки закреплён в выбранном углу; весь слой click-through."
	hint.add_theme_color_override("font_color", Color("a9b4c9"))
	add_child(hint)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	add_child(status_row)

	_activity_label = Label.new()
	_activity_label.text = "Готов — слушаю ввод редактора"
	_activity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_activity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity_label.add_theme_color_override("font_color", Color("a9b4c9"))
	status_row.add_child(_activity_label)

	var speed_label := Label.new()
	speed_label.text = "Отклик мыши"
	status_row.add_child(speed_label)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.6
	_speed_slider.max_value = 1.8
	_speed_slider.step = 0.05
	_speed_slider.custom_minimum_size.x = 110.0
	_speed_slider.tooltip_text = "Скорость pointer/local-reach движения; корпус и устройства неподвижны, вторая лапа использует короткий raised-paw переход"
	_speed_slider.value_changed.connect(_on_speed_changed)
	status_row.add_child(_speed_slider)


func _ensure_settings() -> void:
	var defaults := {
		SETTING_ENABLED: true,
		SETTING_KEYBOARD: true,
		SETTING_MOUSE: true,
		SETTING_SPEED: 1.0,
		SETTING_OVERLAY: true,
		SETTING_CORNER: Corner.BOTTOM_RIGHT,
		SETTING_MIRROR: false,
		SETTING_FLYING_LETTERS: true,
		SETTING_SKIN: SkinManager.ORIGINAL,
	}
	for setting_name in defaults:
		if not _settings.has_setting(setting_name):
			_settings.set_setting(setting_name, defaults[setting_name])
	if _settings.has_setting("bongo_cat/mouse_x_compensation"):
		_settings.erase("bongo_cat/mouse_x_compensation")


func _load_settings() -> void:
	var checks := {
		SETTING_ENABLED: _enabled_check, SETTING_KEYBOARD: _keyboard_check,
		SETTING_MOUSE: _mouse_check, SETTING_OVERLAY: _overlay_check,
		SETTING_MIRROR: _mirror_check, SETTING_FLYING_LETTERS: _letters_check,
	}
	for setting in checks:
		(checks[setting] as CheckButton).set_pressed_no_signal(
			bool(_settings.get_setting(setting)))
	_speed_slider.set_value_no_signal(float(_settings.get_setting(SETTING_SPEED)))
	_corner_option.select(clampi(int(_settings.get_setting(SETTING_CORNER)), 0, Corner.BOTTOM_RIGHT))
	_refresh_skin_options()
	apply_settings_to(view)


func handle_input(event: InputEvent) -> void:
	if is_instance_valid(view):
		view.handle_input(event)


func release_all() -> void:
	if is_instance_valid(view):
		view.release_all()


func apply_settings_to(target: Control) -> void:
	if not is_instance_valid(target):
		return
	target.set_reactions_enabled(bool(_settings.get_setting(SETTING_ENABLED)))
	target.set_keyboard_enabled(bool(_settings.get_setting(SETTING_KEYBOARD)))
	target.set_mouse_enabled(bool(_settings.get_setting(SETTING_MOUSE)))
	target.response_speed = float(_settings.get_setting(SETTING_SPEED))
	target.mirrored = bool(_settings.get_setting(SETTING_MIRROR))
	target.set_flying_letters_enabled(bool(_settings.get_setting(SETTING_FLYING_LETTERS)))
	target.set_skin(String(_settings.get_setting(SETTING_SKIN)))


func _refresh_skin_options() -> void:
	var current := String(_settings.get_setting(SETTING_SKIN))
	_skin_option.clear()
	var index := 0
	for id in SkinManager.list_ids():
		_skin_option.add_item(SkinManager.display_name(id))
		_skin_option.set_item_metadata(index, id)
		if id == current:
			_skin_option.select(index)
		index += 1
	if _skin_option.selected < 0:
		_skin_option.select(0)
		_settings.set_setting(SETTING_SKIN, SkinManager.ORIGINAL)


func _on_skin_selected(index: int) -> void:
	var id := String(_skin_option.get_item_metadata(index))
	_settings.set_setting(SETTING_SKIN, id)
	view.set_skin(id)
	settings_changed.emit()


func _on_skin_refresh() -> void:
	_refresh_skin_options()
	apply_settings_to(view)


func overlay_corner() -> int:
	return clampi(int(_settings.get_setting(SETTING_CORNER)), 0, Corner.BOTTOM_RIGHT)


func set_overlay_visible(value: bool) -> void:
	if is_instance_valid(_overlay_check):
		_overlay_check.set_pressed_no_signal(value)


func _on_enabled_toggled(value: bool) -> void:
	_settings.set_setting(SETTING_ENABLED, value)
	view.set_reactions_enabled(value)
	_activity_label.text = view.last_activity
	settings_changed.emit()


func _store(setting: String, value: Variant, apply: Callable) -> void:
	_settings.set_setting(setting, value)
	apply.call(value)
	settings_changed.emit()


func _on_keyboard_toggled(value: bool) -> void:
	_store(SETTING_KEYBOARD, value, func(v): view.set_keyboard_enabled(v))


func _on_mouse_toggled(value: bool) -> void:
	_store(SETTING_MOUSE, value, func(v): view.set_mouse_enabled(v))


func _on_speed_changed(value: float) -> void:
	_store(SETTING_SPEED, value, func(v): view.response_speed = v)


func _on_overlay_toggled(value: bool) -> void:
	_settings.set_setting(SETTING_OVERLAY, value)
	overlay_toggle_requested.emit(value)


func _on_corner_selected(index: int) -> void:
	var value := clampi(index, 0, Corner.BOTTOM_RIGHT)
	_settings.set_setting(SETTING_CORNER, value)
	overlay_corner_changed.emit(value)


func _on_mirror_toggled(value: bool) -> void:
	_store(SETTING_MIRROR, value, func(v): view.mirrored = v)


func _on_letters_toggled(value: bool) -> void:
	_store(SETTING_FLYING_LETTERS, value, func(v): view.set_flying_letters_enabled(v))


func _on_reset_pressed() -> void:
	view.reset_input()
	reset_requested.emit()


func _on_activity_changed(text: String) -> void:
	_activity_label.text = text
