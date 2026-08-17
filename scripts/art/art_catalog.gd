class_name ArtCatalog
extends RefCounted

const MANIFEST_PATH := "res://assets/art/manifest.json"
const DEFAULT_ANIMATION := &"default"

static var _manifest_cache: Dictionary = {}


static func manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("找不到美术资产清单：%s" % MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("美术资产清单不是有效的 JSON 对象：%s" % MANIFEST_PATH)
		return {}
	_manifest_cache = parsed
	return _manifest_cache


static func static_entry(asset_id: String) -> Dictionary:
	var entries: Variant = manifest().get("static", {})
	if not entries is Dictionary:
		return {}
	var entry: Variant = entries.get(asset_id, {})
	return entry if entry is Dictionary else {}


static func animation_entry(animation_id: String) -> Dictionary:
	var entries: Variant = manifest().get("animations", {})
	if not entries is Dictionary:
		return {}
	var entry: Variant = entries.get(animation_id, {})
	return entry if entry is Dictionary else {}


static func static_texture(asset_id: String) -> Texture2D:
	var entry := static_entry(asset_id)
	var path := String(entry.get("texture", ""))
	if path.is_empty():
		push_error("美术清单中没有静态资产：%s" % asset_id)
		return null
	return load(path) as Texture2D


static func sprite_frames(animation_id: String) -> SpriteFrames:
	var entry := animation_entry(animation_id)
	var path := String(entry.get("sprite_frames", ""))
	if path.is_empty():
		push_error("美术清单中没有动画：%s" % animation_id)
		return null
	return load(path) as SpriteFrames


static func create_animated_sprite(
	animation_id: String, autoplay: bool = true
) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sprite_frames(animation_id)
	sprite.animation = DEFAULT_ANIMATION
	var entry := animation_entry(animation_id)
	if String(entry.get("blend_mode", "mix")) == "additive":
		var additive_material := CanvasItemMaterial.new()
		additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = additive_material
	if autoplay and sprite.sprite_frames != null:
		sprite.play()
	return sprite
