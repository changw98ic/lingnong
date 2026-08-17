extends Node

const Art = preload("res://scripts/art/art_catalog.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var manifest := Art.manifest()
	var static_assets: Dictionary = manifest.get("static", {})
	var animations: Dictionary = manifest.get("animations", {})
	_check(static_assets.size() == 86, "静态图数量必须为 86", failures)
	_check(animations.size() == 26, "动画数量必须为 26", failures)

	for asset_id in static_assets:
		var texture := Art.static_texture(String(asset_id))
		_check(texture != null, "静态图可加载：%s" % asset_id, failures)

	var playback_frames := 0
	for animation_id in animations:
		var entry: Dictionary = animations[animation_id]
		var frames := Art.sprite_frames(String(animation_id))
		_check(frames != null, "动画资源可加载：%s" % animation_id, failures)
		if frames == null:
			continue
		_check(
			frames.has_animation(Art.DEFAULT_ANIMATION),
			"动画包含 default 轨道：%s" % animation_id,
			failures,
		)
		var expected_frames := int(entry.get("playback_frame_count", 0))
		playback_frames += expected_frames
		_check(
			frames.get_frame_count(Art.DEFAULT_ANIMATION) == expected_frames,
			"动画播放帧数正确：%s" % animation_id,
			failures,
		)
		_check(
			is_equal_approx(
				frames.get_animation_speed(Art.DEFAULT_ANIMATION),
				float(entry.get("playback_fps", 0)),
			),
			"动画播放速度正确：%s" % animation_id,
			failures,
		)

	var additive_sprite := Art.create_animated_sprite("animation.breakthrough", false)
	_check(
		additive_sprite.material is CanvasItemMaterial,
		"黑底特效自动使用加法混合",
		failures,
	)
	additive_sprite.queue_free()

	if failures.is_empty():
		print(
			"ART_CATALOG_PROBE_PASS static=%d animations=%d playback_frames=%d"
			% [static_assets.size(), animations.size(), playback_frames]
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("ART_CATALOG_PROBE_FAIL: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
