@tool
extends RefCounted
const CatEyes = preload("res://addons/bongo_cat/cat_eyes.gd")

const MAX_LAYERS := 16
const MAX_OVERLAYS := 64
const MAX_BODIES := 64
const MAX_EYE_SETS := 8

static var _layers: Dictionary = {}
static var _overlays: Dictionary = {}
static var _bodies: Dictionary = {}
static var _overlay_order: Array[String] = []
static var _body_order: Array[String] = []
static var _eye_sets: Dictionary = {}


static func smoothed(image: Image, fix_edges: bool) -> Texture2D:
	var copy := image.duplicate() as Image
	if fix_edges:
		copy.fix_alpha_edges()
	if not copy.has_mipmaps():
		copy.generate_mipmaps()
	return ImageTexture.create_from_image(copy)


static func layer(path: String, texture: Texture2D, fix_edges: bool) -> Texture2D:
	if _layers.has(path):
		return _layers[path] as Texture2D
	var image := texture.get_image()
	if image == null:
		return texture
	var result := smoothed(image, fix_edges)
	if _layers.size() >= MAX_LAYERS:
		_layers.clear()
	_layers[path] = result
	return result


static func overlay(key: String) -> Texture2D:
	return _overlays.get(key, null) as Texture2D


static func _remember(cache: Dictionary, order: Array[String], limit: int,
		key: String, texture: Texture2D) -> void:
	if cache.has(key):
		return
	if order.size() >= limit:
		cache.erase(order.pop_front())
	cache[key] = texture
	order.append(key)


static func remember_overlay(key: String, texture: Texture2D) -> void:
	_remember(_overlays, _overlay_order, MAX_OVERLAYS, key, texture)


static func body(key: String) -> Texture2D:
	return _bodies.get(key, null) as Texture2D


static func remember_body(key: String, texture: Texture2D) -> void:
	_remember(_bodies, _body_order, MAX_BODIES, key, texture)


static func eyes(key: String, source: Texture2D, regions: Array[Rect2i],
		fix_edges: bool) -> Dictionary:
	if _eye_sets.has(key):
		return _eye_sets[key] as Dictionary
	var image := source.get_image()
	if image == null:
		return {}
	var built := CatEyes.build(image, regions)
	var sprites: Array[Texture2D] = []
	for sprite in built["sprites"]:
		sprites.append(ImageTexture.create_from_image(sprite as Image))
	var result := {
		"eyeless": smoothed(built["eyeless"] as Image, fix_edges),
		"sprites": sprites,
		"regions": built["regions"],
	}
	if _eye_sets.size() >= MAX_EYE_SETS:
		_eye_sets.clear()
	_eye_sets[key] = result
	return result


static func clear() -> void:
	_layers.clear()
	_overlays.clear()
	_bodies.clear()
	_overlay_order.clear()
	_body_order.clear()
	_eye_sets.clear()


static func counts() -> Dictionary:
	return {"layers": _layers.size(), "overlays": _overlays.size(),
		"bodies": _bodies.size(), "eyes": _eye_sets.size()}
