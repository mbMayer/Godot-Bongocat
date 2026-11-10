@tool
extends RefCounted

const SIDE_UNSPECIFIED := 0


static func id_for_parts(code: int, location: int = SIDE_UNSPECIFIED) -> String:
	if not _is_sided_modifier(code):
		location = SIDE_UNSPECIFIED
	# Some platforms do not report the modifier side; default to left.
	if _is_sided_modifier(code) and location != KEY_LOCATION_RIGHT:
		location = KEY_LOCATION_LEFT
	return "%d:%d" % [code, location]


static func id_for_key(definition: Dictionary) -> String:
	return id_for_parts(
		int(definition.get("code", KEY_NONE)),
		int(definition.get("location", SIDE_UNSPECIFIED))
	)


static func id_for_event(event: InputEventKey) -> String:
	var code := int(event.physical_keycode)
	if code == KEY_NONE:
		code = int(event.keycode)
	return id_for_parts(code, int(event.location))


static func code_for_event(event: InputEventKey) -> int:
	var code := int(event.physical_keycode)
	if code == KEY_NONE:
		code = int(event.keycode)
	return code


static func _is_sided_modifier(code: int) -> bool:
	return code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


static func original_art_for_event(event: InputEventKey) -> Dictionary:
	return original_art(code_for_event(event), int(event.location))


static func original_art(code: int, location: int = SIDE_UNSPECIFIED) -> Dictionary:
	if code >= KEY_A and code <= KEY_Z:
		return _original_result("Key" + String.chr(code), "keyboard", true)
	if code >= KEY_0 and code <= KEY_9:
		return _original_result("Num" + String.chr(code), "keyboard", true)
	if code >= KEY_F1 and code <= KEY_F1 + 34:
		return _original_result("Fn", "keyboard", false)
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return _original_result("Num" + str(code - KEY_KP_0), "keyboard", false)

	match code:
		KEY_SHIFT:
			return _original_result(
				"ShiftRight" if location == KEY_LOCATION_RIGHT else "ShiftLeft",
				"keyboard", true
			)
		KEY_CTRL:
			return _original_result(
				"ControlRight" if location == KEY_LOCATION_RIGHT else "ControlLeft",
				"keyboard", true
			)
		KEY_ALT:
			return _original_result(
				"AltGr" if location == KEY_LOCATION_RIGHT else "Alt",
				"keyboard", true
			)
		KEY_META:
			return _original_result("Meta", "keyboard", true)
		KEY_ESCAPE:
			return _original_result("Escape", "keyboard", true)
		KEY_BACKSPACE:
			return _original_result("Backspace", "keyboard", true)
		KEY_TAB:
			return _original_result("Tab", "keyboard", true)
		KEY_ENTER:
			return _original_result("Return", "keyboard", true)
		KEY_KP_ENTER:
			return _original_result("Return", "keyboard", false)
		KEY_CAPSLOCK:
			return _original_result("CapsLock", "keyboard", true)
		KEY_SPACE:
			return _original_result("Space", "keyboard", true)
		KEY_DELETE:
			return _original_result("Delete", "keyboard", true)
		KEY_QUOTELEFT:
			return _original_result("BackQuote", "keyboard", true)
		KEY_SLASH:
			return _original_result("Slash", "keyboard", true)
		KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT:
			return _original_result("Return", "keyboard", false)
		KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH, \
		KEY_SEMICOLON, KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_LESS, \
		KEY_KP_DIVIDE, KEY_KP_MULTIPLY, KEY_KP_SUBTRACT, KEY_KP_PERIOD:
			return _original_result("Slash", "keyboard", false)
		KEY_KP_ADD:
			return _original_result("Return", "keyboard", false)
		KEY_INSERT, KEY_HOME, KEY_PAGEUP, KEY_END, KEY_PAGEDOWN:
			return _original_result("Delete", "keyboard", false)
		KEY_PRINT, KEY_SCROLLLOCK, KEY_PAUSE, KEY_NUMLOCK, KEY_MENU:
			return _original_result("Fn", "keyboard", false)
	return _original_result("Space", "keyboard", false)


static func _original_result(art_name: String, group: String, exact: bool) -> Dictionary:
	return {"name": art_name, "group": group, "exact": exact}
