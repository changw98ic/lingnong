extends Node

const SAVE_PATH := "user://lingnong_save.json"
const SAVE_VERSION := 13

## v13 只保存当前游戏规则：
## - 无转世、无仙缘、无炼丹（配方/丹药/旧解锁标志已删除）；天赋树使用 talent_nodes + talent_points。
## - 作物成熟后自动收获并补种；点击加速直接修改成熟时间。
## - lifespan_max_years / lifespan_years 按时间流逝，寿元归零不重置进度。
## - 熟练度、晋级/轮回/收获计数和离线结算领取账本跨大限保留。
## - 成就和成就点跨大限、跨新局保留，并在加载时按当前定义校正。
## - 商店购买次数（狂暴丹等越买越贵商品的价格依据）跨大限保留。

func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"spirit_stones": GameState.spirit_stones,
		"qi": GameState.qi,
		"cultivation": GameState.cultivation,
		"total_cultivation_earned": GameState.total_cultivation_earned,
		"talent_points": GameState.talent_points,
		"talent_nodes": GameState.talent_nodes,
		"talent_milestone_index": GameState.talent_milestone_index,
		"achievements": GameState.achievements,
		"achievement_points": GameState.achievement_points,
		"crop_proficiency": GameState.crop_proficiency,
		"total_harvest_count": GameState.total_harvest_count,
		"promotion_count": GameState.promotion_count,
		"reincarnation_count": GameState.reincarnation_count,
		"offline_claimed_talent_points": GameState.offline_claimed_talent_points,
		"offline_claimed_spirit_stone_units": GameState.offline_claimed_spirit_stone_units,
		"shop_purchase_counts": GameState.shop_purchase_counts,
		"crop_inventory": GameState.crop_inventory,
		"realm_index": GameState.realm_index,
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
		"event_prod_mult": GameState.event_prod_mult,
		"event_cult_mult": GameState.event_cult_mult,
		"sword_art_cooldown_until": GameState.sword_art_cooldown_until,
		"next_auto_brew_at": GameState.next_auto_brew_at,
		"active_buff_until": GameState.active_buff_until,
		"active_buff_mult": GameState.active_buff_mult,
		"lifespan_max_years": GameState.lifespan_max_years,
		"lifespan_years": GameState.lifespan_years,
		"lifespan_depleted": GameState.lifespan_depleted,
		"spirit_rain_unlocked": GameState.spirit_rain_unlocked,
		"unlock_auto_cultivation": GameState.unlock_auto_cultivation,
		"unlock_mind_flower": GameState.unlock_mind_flower,
		"unlock_sun_fruit": GameState.unlock_sun_fruit,
		"unlock_heaven_lotus": GameState.unlock_heaven_lotus,
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
	GameState.qi = maxf(0.0, float(data.get("qi", 0.0)))
	GameState.cultivation = maxf(0.0, float(data.get("cultivation", 0.0)))
	GameState.realm_index = clampi(int(data.get("realm_index", BalanceConfig.INITIAL_REALM_INDEX)), 0, RealmConfig.realm_count() - 1)
	GameState.unlocked_fields = clampi(
		int(data.get("unlocked_fields", BalanceConfig.INITIAL_UNLOCKED_FIELDS)),
		BalanceConfig.INITIAL_UNLOCKED_FIELDS,
		BalanceConfig.FIELD_COUNT
	)

	GameState.crop_inventory = data.get("crop_inventory", {}) if data.get("crop_inventory", {}) is Dictionary else {}
	for crop_id in CropConfig.get_all():
		GameState.crop_inventory[crop_id] = maxi(0, int(GameState.crop_inventory.get(crop_id, 0)))
	var saved_purchase_counts = data.get("shop_purchase_counts", {})
	GameState.shop_purchase_counts = {}
	if saved_purchase_counts is Dictionary:
		for item_id_variant in saved_purchase_counts:
			GameState.shop_purchase_counts[String(item_id_variant)] = maxi(0, int(saved_purchase_counts[item_id_variant]))
	var saved_proficiency = data.get("crop_proficiency", {})
	GameState.crop_proficiency = {}
	if saved_proficiency is Dictionary:
		for crop_id_variant in saved_proficiency:
			var crop_id := String(crop_id_variant)
			if CropConfig.get_crop(crop_id) != null:
				GameState.crop_proficiency[crop_id] = maxi(0, int(saved_proficiency[crop_id_variant]))
	GameState.total_harvest_count = maxi(0, int(data.get("total_harvest_count", 0)))
	# 旧存档没有晋级计数时，用当前境界作为一次性迁移基线。
	GameState.promotion_count = maxi(0, int(data.get("promotion_count", GameState.realm_index)))
	GameState.reincarnation_count = maxi(0, int(data.get("reincarnation_count", 0)))
	GameState.offline_claimed_talent_points = maxi(0, int(data.get("offline_claimed_talent_points", 0)))
	GameState.offline_claimed_spirit_stone_units = maxf(0.0, float(data.get("offline_claimed_spirit_stone_units", 0.0)))
	GameState._ensure_inventory_keys()

	GameState.fields.clear()
	var saved_fields = data.get("fields", [])
	if saved_fields is Array:
		for field in saved_fields:
			if field is Dictionary:
				GameState.fields.append({
					"crop_id": String(field.get("crop_id", "")),
					"planted_at": float(field.get("planted_at", 0.0)),
					"ready_at": float(field.get("ready_at", 0.0)),
					"tier": clampi(int(field.get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1),
				})
	while GameState.fields.size() < BalanceConfig.FIELD_COUNT:
		GameState.fields.append({"crop_id": "", "planted_at": 0.0, "ready_at": 0.0, "tier": 0})
	while GameState.fields.size() > BalanceConfig.FIELD_COUNT:
		GameState.fields.pop_back()

	# 只读取当前规则的天赋点字段；旧的转世/仙缘字段不再进入运行状态。
	GameState.talent_points = maxi(0, int(data.get("talent_points", 0)))
	GameState.talent_nodes = {"root": true}
	var saved_nodes = data.get("talent_nodes", {})
	if saved_nodes is Dictionary:
		for node_id in TalentTree.node_ids():
			if bool(saved_nodes.get(node_id, false)):
				GameState.talent_nodes[node_id] = true
	GameState.total_cultivation_earned = maxf(
		GameState.cultivation,
		float(data.get("total_cultivation_earned", GameState.cultivation))
	)
	GameState.talent_milestone_index = clampi(
		int(data.get("talent_milestone_index", 0)),
		0,
		BalanceConfig.TALENT_MILESTONES.size()
	)
	while GameState.talent_milestone_index < BalanceConfig.TALENT_MILESTONES.size() and GameState.total_cultivation_earned >= BalanceConfig.TALENT_MILESTONES[GameState.talent_milestone_index]:
		GameState.talent_points += 1
		GameState.talent_milestone_index += 1

	# 成就只接受当前定义中的 id；点数由已解锁定义重算，避免存档字段和定义不一致。
	GameState.achievements = {}
	var saved_achievements = data.get("achievements", {})
	if saved_achievements is Dictionary:
		for definition in AchievementSystem.definitions():
			var achievement_id := String(definition.get("id", ""))
			if achievement_id != "" and bool(saved_achievements.get(achievement_id, false)):
				GameState.achievements[achievement_id] = true
	GameState.achievement_points = 0
	for definition in AchievementSystem.definitions():
		var achievement_id := String(definition.get("id", ""))
		if achievement_id != "" and bool(GameState.achievements.get(achievement_id, false)):
			GameState.achievement_points += int(definition.get("points", 0))

	_load_array(GameState.spirit_rain_until, data.get("spirit_rain_until", []), 0.0)
	_load_array(GameState.guardian_array_level, data.get("guardian_array_level", []), BalanceConfig.GUARDIAN_BASE_LEVEL)
	_load_array(GameState.guardian_array_charges, data.get("guardian_array_charges", []), BalanceConfig.GUARDIAN_BASE_CHARGES)
	_load_events(data.get("insect_events", []))
	GameState.insect_corpses = maxi(0, int(data.get("insect_corpses", 0)))

	GameState.season_index = clampi(int(data.get("season_index", BalanceConfig.INITIAL_SEASON_INDEX)), 0, BalanceConfig.SEASONS.size() - 1)
	GameState.season_started_at = float(data.get("season_started_at", Time.get_unix_time_from_system()))
	GameState.random_event = String(data.get("random_event", ""))
	GameState.random_event_until = float(data.get("random_event_until", 0.0))
	GameState.random_event_cooldown_until = float(data.get("random_event_cooldown_until", Time.get_unix_time_from_system() + BalanceConfig.RANDOM_EVENT_COOLDOWN_SECONDS))
	GameState.event_prod_mult = float(data.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER))
	GameState.event_cult_mult = float(data.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER))
	GameState.sword_art_cooldown_until = float(data.get("sword_art_cooldown_until", 0.0))
	GameState.next_auto_brew_at = float(data.get("next_auto_brew_at", 0.0))
	GameState.active_buff_until = float(data.get("active_buff_until", 0.0))
	GameState.active_buff_mult = float(data.get("active_buff_mult", BalanceConfig.DEFAULT_MULTIPLIER))

	var default_max := BalanceConfig.LIFESPAN_YEARS_BY_REALM[GameState.realm_index]
	GameState.lifespan_max_years = maxf(BalanceConfig.MIN_LIFESPAN_YEARS, float(data.get("lifespan_max_years", default_max)))
	GameState.lifespan_years = clampf(float(data.get("lifespan_years", GameState.lifespan_max_years)), 0.0, GameState.lifespan_max_years)
	GameState.lifespan_depleted = bool(data.get("lifespan_depleted", GameState.lifespan_years <= 0.0))
	var default_unlock_flags := BalanceConfig.default_unlock_flags(GameState.realm_index)
	for flag in default_unlock_flags:
		if data.has(flag):
			GameState.set(flag, bool(data[flag]))
		else:
			# 保留新游戏的默认解锁，再补上当前境界已经获得的规则奖励。
			GameState.set(flag, bool(GameState.get(flag)) or bool(default_unlock_flags[flag]))

	GameState.apply_offline_report()
	GameState.emit_state_changed()
	# 离线差额已经计入，立即写回领取账本，避免重复领取同一份长期统计。
	save_game()
	return true


func _load_array(target: Array, saved: Variant, default_value: Variant) -> void:
	target.clear()
	if saved is Array:
		for value in saved:
			target.append(int(value) if default_value is int else float(value))
	while target.size() < BalanceConfig.FIELD_COUNT:
		target.append(default_value)
	while target.size() > BalanceConfig.FIELD_COUNT:
		target.pop_back()


func _load_events(saved: Variant) -> void:
	GameState.insect_events.clear()
	if saved is Array:
		for event in saved:
			if event is Dictionary:
				GameState.insect_events.append(event)
	while GameState.insect_events.size() < BalanceConfig.FIELD_COUNT:
		GameState.insect_events.append({"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": Time.get_unix_time_from_system() + BalanceConfig.INSECT_INITIAL_DELAY_SECONDS})
	while GameState.insect_events.size() > BalanceConfig.FIELD_COUNT:
		GameState.insect_events.pop_back()
