class_name EnvironmentArtLayer
extends Control

const Art = preload("res://scripts/art/art_catalog.gd")
const DESIGN_SIZE := Vector2(1920.0, 1080.0)

const LAYERS := [
	{"id": "animation.clouds_drift", "position": Vector2(960, 120), "scale": 1.55, "z": 1, "alpha": 0.42, "speed_scale": 0.72, "start_frame": 9},
	{"id": "animation.waterfall_flow", "position": Vector2(369, 294), "scale": 0.72, "z": 2, "speed_scale": 1.20, "start_frame": 2},
	{"id": "animation.stream_flow", "position": Vector2(299, 513), "scale": Vector2(0.54, 0.80), "z": 2, "alpha": 0.72, "speed_scale": 1.08, "start_frame": 6},
	{"id": "animation.waterwheel_turn", "position": Vector2(185, 635), "scale": 0.48, "z": 4, "flip_h": true, "speed_scale": 1.18, "start_frame": 4},
	{"id": "animation.gathering_array_cycle", "position": Vector2(960, 654), "scale": Vector2(0.89, 0.85), "z": 3, "alpha": 0.88, "speed_scale": 0.88, "start_frame": 8},
	{"id": "animation.spirit_crystal_breathe", "position": Vector2(960, 603), "scale": 0.40, "z": 5, "speed_scale": 0.82, "start_frame": 3},
	{"id": "animation.mind_flower_breathe", "position": Vector2(748, 490), "scale": 0.50, "z": 4, "speed_scale": 0.78, "start_frame": 1},
	{"id": "animation.sun_fruit_breathe", "position": Vector2(1201, 489), "scale": 0.50, "z": 4, "speed_scale": 0.74, "start_frame": 7},
	{"id": "animation.purple_mushroom_breathe", "position": Vector2(733, 848), "scale": 0.50, "z": 4, "speed_scale": 0.80, "start_frame": 12},
	{"id": "animation.nourishing_ginseng_breathe", "position": Vector2(1239, 851), "scale": 0.50, "z": 4, "speed_scale": 0.76, "start_frame": 5},
	{"id": "animation.disciple_inspecting", "position": Vector2(650, 480), "scale": 0.38, "z": 6, "speed_scale": 0.92, "start_frame": 4},
	{"id": "animation.disciple_casting", "position": Vector2(1310, 500), "scale": 0.38, "z": 6, "speed_scale": 0.96, "start_frame": 10},
	{"id": "animation.disciple_watering", "position": Vector2(625, 810), "scale": 0.38, "z": 6, "speed_scale": 0.90, "start_frame": 6},
	{"id": "animation.disciple_meditating", "position": Vector2(1320, 820), "scale": 0.38, "z": 6, "speed_scale": 0.72, "start_frame": 14},
	{"id": "animation.spirit_beast_idle", "position": Vector2(155, 885), "scale": 0.55, "z": 7, "speed_scale": 0.84, "start_frame": 5},
	{"id": "animation.butterfly_flight", "position": Vector2(1510, 520), "scale": 0.62, "z": 7, "speed_scale": 1.12, "start_frame": 11},
]

const STATIC_LAYERS := [
	{"id": "crop.five_element_ear", "position": Vector2(573, 640), "scale": 0.14, "z": 4},
	{"id": "crop.gathering_grass", "position": Vector2(1380, 649), "scale": 0.14, "z": 4},
]

var _visuals: Array[Node2D] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for definition in LAYERS:
		var sprite := Art.create_animated_sprite(String(definition["id"]))
		sprite.z_index = int(definition.get("z", 0))
		sprite.modulate.a = float(definition.get("alpha", 1.0))
		sprite.flip_h = bool(definition.get("flip_h", false))
		sprite.speed_scale = float(definition.get("speed_scale", 1.0))
		if sprite.sprite_frames != null:
			var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
			if frame_count > 0:
				sprite.frame = posmod(int(definition.get("start_frame", 0)), frame_count)
		sprite.play()
		sprite.set_meta("asset_id", definition["id"])
		sprite.set_meta("design_position", definition["position"])
		sprite.set_meta("design_scale", _scale_vector(definition.get("scale", 1.0)))
		add_child(sprite)
		_visuals.append(sprite)
	for definition in STATIC_LAYERS:
		var sprite := Sprite2D.new()
		sprite.texture = Art.static_texture(String(definition["id"]))
		sprite.z_index = int(definition.get("z", 0))
		sprite.set_meta("asset_id", definition["id"])
		sprite.set_meta("design_position", definition["position"])
		sprite.set_meta("design_scale", _scale_vector(definition.get("scale", 1.0)))
		add_child(sprite)
		_visuals.append(sprite)
	resized.connect(_layout_sprites)
	_layout_sprites()


func _layout_sprites() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cover_scale := maxf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var origin := (size - DESIGN_SIZE * cover_scale) * 0.5
	for sprite in _visuals:
		var design_position: Vector2 = sprite.get_meta("design_position")
		var design_scale: Vector2 = sprite.get_meta("design_scale")
		sprite.position = origin + design_position * cover_scale
		sprite.scale = design_scale * cover_scale


func _scale_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	return Vector2.ONE * float(value)
