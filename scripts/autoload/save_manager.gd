extends Node

const SAVE_PATH := "user://lingnong_save.json"
const SAVE_VERSION := 6

func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"spirit_stones": GameState.spirit_stones,
		"qi": GameState.qi,
		"cultivation": GameState.cultivation,
		"crop_inventory": GameState.crop_inventory,
		"pills": GameState.pills,
		"realm_index": GameState.realm_index,
		"field_level": GameState.field_level,
		"unlocked_fields": GameState.unlocked_fields,
		"fields": GameState.fields,
		"spirit_rain_until": GameState.spirit_rain_until,
		"guardian_array_level": GameState.guardian_array_level,
		"guardian_array_charges": GameState.guardian_array_charges,
		"insect_events": GameState.insect_events,
		"insect_corpses": GameState.insect_corpses,
		"season_index": GameState.season_index,
		"season_started_at": GameState.season_started_at,
		"random_event": GameState.random_event,
		"random_event_until": GameState.random_event_until,
		"random_event_cooldown_until": GameState.random_event_cooldown_until,
		"sword_art_cooldown_until": GameState.sword_art_cooldown_until,
		"practitioner_upgrades": GameState.practitioner_upgrades,
		"knowledge_points": GameState.knowledge_points,
		"reincarnation_count": GameState.reincarnation_count,
		"reincarnation_mult": GameState.reincarnation_mult,
		"global_prod_mult": GameState.global_prod_mult,
		"qi_gen_mult": GameState.qi_gen_mult,
		"spirit_rain_unlocked": GameState.spirit_rain_unlocked,
		"auto_harvest_enabled": GameState.auto_harvest_enabled,
		"alchemy_unlocked": GameState.alchemy_unlocked,
		"foundation_pill_unlocked": GameState.foundation_pill_unlocked,
		"golden_pill_unlocked": GameState.golden_pill_unlocked,
		"spirit_vein_unlocked": GameState.spirit_vein_unlocked,
		"spirit_vein_active": GameState.automation.is_spirit_vein_active(),
		"next_auto_brew_at": GameState.next_auto_brew_at,
		"lifespan_days": GameState.lifespan_days,
		"saved_at": Time.get_unix_time_from_system(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档")
		return false
	file.store_string(JSON.stringify(data))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return false

	GameState.spirit_stones = float(data.get("spirit_stones", 0.0))
	GameState.qi = float(data.get("qi", 0.0))
	GameState.cultivation = float(data.get("cultivation", 0.0))
	GameState.crop_inventory = data.get("crop_inventory", {"gathering_grass": 0})
	GameState.pills = data.get("pills", {"qi_gathering_pill": 0})
	# 兼容旧存档：确保三枚丹药键齐全。
	GameState.pills["qi_gathering_pill"] = int(GameState.pills.get("qi_gathering_pill", 0))
	GameState.pills["foundation_pill"] = int(GameState.pills.get("foundation_pill", 0))
	GameState.pills["golden_pill"] = int(GameState.pills.get("golden_pill", 0))
	GameState.realm_index = int(data.get("realm_index", 0))
	GameState.field_level = int(data.get("field_level", 1))
	GameState.unlocked_fields = int(data.get("unlocked_fields", 1))
	var saved_fields = data.get("fields", [])
	if saved_fields is Array:
		GameState.fields.clear()
		for field in saved_fields:
			if field is Dictionary:
				GameState.fields.append(field)
	var saved_rain = data.get("spirit_rain_until", [])
	if saved_rain is Array:
		GameState.spirit_rain_until.clear()
		for value in saved_rain:
			GameState.spirit_rain_until.append(float(value))
	var saved_guardian_levels = data.get("guardian_array_level", [])
	if saved_guardian_levels is Array:
		GameState.guardian_array_level.clear()
		for value in saved_guardian_levels:
			GameState.guardian_array_level.append(int(value))
	var saved_guardian_charges = data.get("guardian_array_charges", [])
	if saved_guardian_charges is Array:
		GameState.guardian_array_charges.clear()
		for value in saved_guardian_charges:
			GameState.guardian_array_charges.append(int(value))
	var saved_insect_events = data.get("insect_events", [])
	if saved_insect_events is Array:
		GameState.insect_events.clear()
		for event in saved_insect_events:
			if event is Dictionary:
				GameState.insect_events.append(event)
	GameState.insect_corpses = int(data.get("insect_corpses", 0))
	GameState.season_index = int(data.get("season_index", 0))
	GameState.season_started_at = float(data.get("season_started_at", Time.get_unix_time_from_system()))
	GameState.random_event = String(data.get("random_event", ""))
	GameState.random_event_until = float(data.get("random_event_until", 0.0))
	GameState.random_event_cooldown_until = float(data.get("random_event_cooldown_until", Time.get_unix_time_from_system() + 180.0))
	GameState.sword_art_cooldown_until = float(data.get("sword_art_cooldown_until", 0.0))
	GameState.practitioner_upgrades = data.get("practitioner_upgrades", GameState.practitioner_upgrades)
	GameState.knowledge_points = int(data.get("knowledge_points", 0))
	GameState.reincarnation_count = int(data.get("reincarnation_count", 0))
	# version 6 新增字段，旧存档给默认值。
	GameState.reincarnation_mult = float(data.get("reincarnation_mult", 1.0 + 0.5 * float(GameState.reincarnation_count)))
	GameState.global_prod_mult = float(data.get("global_prod_mult", 1.0))
	GameState.qi_gen_mult = float(data.get("qi_gen_mult", 1.0))
	GameState.spirit_rain_unlocked = bool(data.get("spirit_rain_unlocked", GameState.realm_index >= 1))
	GameState.auto_harvest_enabled = bool(data.get("auto_harvest_enabled", GameState.realm_index >= 1))
	GameState.alchemy_unlocked = bool(data.get("alchemy_unlocked", GameState.realm_index >= 2))
	GameState.foundation_pill_unlocked = bool(data.get("foundation_pill_unlocked", GameState.realm_index >= 2))
	GameState.golden_pill_unlocked = bool(data.get("golden_pill_unlocked", GameState.realm_index >= 3))
	GameState.spirit_vein_unlocked = bool(data.get("spirit_vein_unlocked", GameState.realm_index >= 3))
	GameState.next_auto_brew_at = float(data.get("next_auto_brew_at", 0.0))
	# 灵脉激活状态回写。
	if bool(data.get("spirit_vein_active", false)):
		GameState.automation.activate_spirit_vein()
	GameState.lifespan_days = float(data.get("lifespan_days", GameState.max_lifespan_days))

	# 离线结算：按 (现在 - saved_at) 结算灵脉产出（封顶 8 小时）。
	var saved_at := float(data.get("saved_at", Time.get_unix_time_from_system()))
	GameState.apply_offline_report(saved_at)
	GameState.emit_state_changed()
	return true
