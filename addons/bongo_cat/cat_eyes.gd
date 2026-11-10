@tool
extends RefCounted

const LEFT_REGION := Rect2i(231, 121, 22, 23)
const RIGHT_REGION := Rect2i(347, 156, 23, 25)
const INK_THRESHOLD := 0.92
const BLINK_MS := 160
const GAZE_X := 6.0
const GAZE_Y := 3.5

static var enabled := true
static var _next_blink_ms := -1
static var _blink_start_ms := 0


static func regions(metadata: Dictionary) -> Array[Rect2i]:
	if metadata.has("eye_regions"):
		var custom: Dictionary = metadata["eye_regions"]
		if custom.has("left") and custom.has("right"):
			var left: Array = custom["left"]
			var right: Array = custom["right"]
			if left.size() == 4 and right.size() == 4:
				return [Rect2i(int(left[0]), int(left[1]), int(left[2]), int(left[3])),
					Rect2i(int(right[0]), int(right[1]), int(right[2]), int(right[3]))]
	return [LEFT_REGION, RIGHT_REGION]


static func build(body: Image, eye_regions: Array[Rect2i]) -> Dictionary:
	var eyeless := body.duplicate() as Image
	var sprites: Array[Image] = []
	for region in eye_regions:
		var sprite := Image.create(region.size.x, region.size.y, false,
			Image.FORMAT_RGBA8)
		sprite.fill(Color(0.0, 0.0, 0.0, 0.0))
		for y in range(region.size.y):
			for x in range(region.size.x):
				var source := body.get_pixel(region.position.x + x,
					region.position.y + y)
				if source.a > 0.0 and (source.r + source.g + source.b) / 3.0 < INK_THRESHOLD:
					sprite.set_pixel(x, y, source)
					# Only the ink pixel is whitened; the surrounding original
					# white stays byte-identical.
					eyeless.set_pixel(region.position.x + x, region.position.y + y,
						Color(1.0, 1.0, 1.0, source.a))
		sprites.append(sprite)
	return {"eyeless": eyeless, "sprites": sprites, "regions": eye_regions}


static func blink_amount(now_ms: int) -> float:
	if not enabled:
		return 0.0
	if _next_blink_ms < 0:
		_next_blink_ms = now_ms + 3000 + randi() % 3000
	if _blink_start_ms == 0 and now_ms >= _next_blink_ms:
		_blink_start_ms = now_ms
		_next_blink_ms = now_ms + BLINK_MS + 3000 + randi() % 3000
	if _blink_start_ms == 0:
		return 0.0
	var t := float(now_ms - _blink_start_ms) / float(BLINK_MS)
	if t >= 1.0:
		_blink_start_ms = 0
		return 0.0
	return sin(t * PI)


static func gaze_offset(pointer_uv: Vector2, mirrored: bool) -> Vector2:
	var offset := (pointer_uv - Vector2(0.5, 0.5)) * Vector2(GAZE_X * 2.0, GAZE_Y * 2.0)
	if mirrored:
		offset.x = -offset.x
	return offset
