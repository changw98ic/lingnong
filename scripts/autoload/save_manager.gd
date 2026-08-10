extends Node

const SAVE_VERSION := 18
# 存档路径（探针测试时改为隔离路径，避免覆盖真实存档）。
var save_path := "user://lingnong_save.json"

## v18 只保存当前游戏规则：
## - 轮回即核心：随时轮回 + 天人五衰三选择；转世天赋本世生效、跨世不保留。
## - 突破前稳定/强行选择成功率，碎丹经验跨局保留；天劫改为三道生产体系检查。
## - 宝箱（木/玉/仙/遗物）与天命奇遇的永久强化跨局保留。
## - 寿元按时间流逝，寿元归零进入大限；熟练度、成就、商店购买次数跨局保留。
## - 天降灵种、魔气侵染等新事件状态按当前局保存。

func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"spirit_stones": GameState.spirit_stones,
		"qi": GameState.qi,
		"cultivation": GameState.cultivation,
		"total_cultivation_earned": GameState.total_cultivation_earned,
		"talent_points": GameState.talent_points,
		"talent_points_earned": GameState.talent_points_earned,
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
		"crit_count": GameState.crit_count,
		"rare_crit_count": GameState.rare_crit_count,
		"windfall_count": GameState.windfall_count,
		"treasure_production_bonus": GameState.treasure_production_bonus,
		"treasure_crit_bonus": GameState.treasure_crit_bonus,
		"fate_permanent_production": GameState.fate_permanent_production,
		"broken_dan_experience": GameState.broken_dan_experience,
		"tribulation_refine_bonus": GameState.tribulation_refine_bonus,
		"shop_purchase_counts": GameState.shop_purchase_counts,
		"breakthrough_materials": GameState.breakthrough_materials,
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
		"active_buff_until": GameState.active_buff_until,
		"active_buff_mult": GameState.active_buff_mult,
		"lifespan_max_years": GameState.lifespan_max_years,
		"lifespan_years": GameState.lifespan_years,
		"lifespan_depleted": GameState.lifespan_depleted,
		"decay_active": GameState.decay_active,
		"fate_opportunity_at": GameState.fate_opportunity_at,
		"run_start_milestone_index": GameState.run_start_milestone_index,
		"run_start_promotion_count": GameState.run_start_promotion_count,
		"reincarnation_boon": GameState.reincarnation_boon,
		"pending_reincarnation_boon": GameState.pending_reincarnation_boon,
		"run_harvest_count": GameState.run_harvest_count,
		"run_random_event_count": GameState.run_random_event_count,
		"heavenly_seed_unlocked": GameState.heavenly_seed_unlocked,
		"healing_pills": GameState.healing_pills,
		"resistance_pills": GameState.resistance_pills,
		"enhancement_pills": GameState.enhancement_pills,
		"tribulation_active": GameState.tribulation_active,
		"tribulation_target_realm": GameState.tribulation_target_realm,
		"tribulation_total_strikes": GameState.tribulation_total_strikes,
		"tribulation_strikes_survived": GameState.tribulation_strikes_survived,
		"tribulation_prepared": GameState.tribulation_prepared,
		"tribulation_next_strike_at": GameState.tribulation_next_strike_at,
		"tribulation_last_result": GameState.tribulation_last_result,
		"spirit_rain_unlocked": GameState.spirit_rain_unlocked,
		"unlock_auto_cultivation": GameState.unlock_auto_cultivation,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档")
		return false
	file.store_string(JSON.stringify(data))
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
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

	var saved_breakthrough_materials = data.get("breakthrough_materials", {})
	GameState.breakthrough_materials = {}
	if saved_breakthrough_materials is Dictionary:
		for material_id_variant in saved_breakthrough_materials:
			var material_id := String(material_id_variant)
			if BalanceConfig.BREAKTHROUGH_MATERIALS.has(material_id):
				GameState.breakthrough_materials[material_id] = maxi(0, int(saved_breakthrough_materials[material_id_variant]))
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
	GameState.crit_count = maxi(0, int(data.get("crit_count", 0)))
	GameState.rare_crit_count = maxi(0, int(data.get("rare_crit_count", 0)))
	GameState.windfall_count = maxi(0, int(data.get("windfall_count", 0)))
	GameState.treasure_production_bonus = maxf(0.0, float(data.get("treasure_production_bonus", 0.0)))
	GameState.treasure_crit_bonus = maxf(0.0, float(data.get("treasure_crit_bonus", 0.0)))
	GameState.fate_permanent_production = maxf(0.0, float(data.get("fate_permanent_production", 0.0)))
	GameState.broken_dan_experience = clampf(float(data.get("broken_dan_experience", 0.0)), 0.0, BalanceConfig.BROKEN_DAN_SUCCESS_CAP)
	GameState.tribulation_refine_bonus = maxf(0.0, float(data.get("tribulation_refine_bonus", 0.0)))
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
	# v15 及更早存档没有累计字段，用“未消费点 + 已点亮节点成本”恢复最低可知总量。
	var legacy_earned_points := GameState.talent_points + TalentTree.unlocked_cost(GameState.talent_nodes)
	GameState.talent_points_earned = maxi(
		legacy_earned_points,
		int(data.get("talent_points_earned", legacy_earned_points))
	)
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
		GameState._award_talent_points(1)
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
	GameState.active_buff_until = float(data.get("active_buff_until", 0.0))
	GameState.active_buff_mult = float(data.get("active_buff_mult", BalanceConfig.DEFAULT_MULTIPLIER))

	var default_max := BalanceConfig.LIFESPAN_YEARS_BY_REALM[GameState.realm_index]
	GameState.lifespan_max_years = maxf(BalanceConfig.MIN_LIFESPAN_YEARS, float(data.get("lifespan_max_years", default_max)))
	GameState.lifespan_years = clampf(float(data.get("lifespan_years", GameState.lifespan_max_years)), 0.0, GameState.lifespan_max_years)
	GameState.lifespan_depleted = bool(data.get("lifespan_depleted", GameState.lifespan_years <= 0.0))
	GameState.decay_active = bool(data.get("decay_active", false)) and not GameState.lifespan_depleted
	GameState.fate_opportunity_at = maxf(0.0, float(data.get("fate_opportunity_at", 0.0)))
	GameState.run_start_milestone_index = clampi(int(data.get("run_start_milestone_index", GameState.talent_milestone_index)), 0, BalanceConfig.TALENT_MILESTONES.size())
	GameState.run_start_promotion_count = maxi(0, int(data.get("run_start_promotion_count", GameState.promotion_count)))
	GameState.reincarnation_boon = String(data.get("reincarnation_boon", ""))
	if GameState.reincarnation_boon != "" and BalanceConfig.reincarnation_boon(GameState.reincarnation_boon).is_empty():
		GameState.reincarnation_boon = ""
	GameState.pending_reincarnation_boon = bool(data.get("pending_reincarnation_boon", false))
	GameState.run_harvest_count = maxi(0, int(data.get("run_harvest_count", 0)))
	GameState.run_random_event_count = maxi(0, int(data.get("run_random_event_count", 0)))
	GameState.heavenly_seed_unlocked = bool(data.get("heavenly_seed_unlocked", false))
	GameState.healing_pills = maxi(0, int(data.get("healing_pills", 0)))
	GameState.resistance_pills = maxi(0, int(data.get("resistance_pills", 0)))
	GameState.enhancement_pills = maxi(0, int(data.get("enhancement_pills", 0)))
	GameState.tribulation_active = bool(data.get("tribulation_active", false))
	GameState.tribulation_target_realm = int(data.get("tribulation_target_realm", -1))
	GameState.tribulation_total_strikes = maxi(0, int(data.get("tribulation_total_strikes", BalanceConfig.TRIBULATION_TOTAL_CHECKS)))
	GameState.tribulation_strikes_survived = clampi(
		int(data.get("tribulation_strikes_survived", 0)),
		0,
		BalanceConfig.TRIBULATION_TOTAL_CHECKS
	)
	GameState.tribulation_prepared = [false, false, false]
	var saved_prepared = data.get("tribulation_prepared", [])
	if saved_prepared is Array:
		for prepared_index in range(mini(BalanceConfig.TRIBULATION_TOTAL_CHECKS, saved_prepared.size())):
			GameState.tribulation_prepared[prepared_index] = bool(saved_prepared[prepared_index])
	GameState.tribulation_next_strike_at = maxf(0.0, float(data.get("tribulation_next_strike_at", 0.0)))
	GameState.tribulation_last_result = String(data.get("tribulation_last_result", ""))
	if GameState.tribulation_active and (
		GameState.lifespan_depleted
		or
		GameState.tribulation_target_realm <= GameState.realm_index
		or GameState.tribulation_target_realm >= RealmConfig.realm_count()
		or GameState.tribulation_total_strikes != BalanceConfig.TRIBULATION_TOTAL_CHECKS
	):
		GameState.tribulation_active = false
		GameState.tribulation_target_realm = -1
		GameState.tribulation_total_strikes = BalanceConfig.TRIBULATION_TOTAL_CHECKS
		GameState.tribulation_strikes_survived = 0
		GameState.tribulation_prepared = [false, false, false]
		GameState.tribulation_next_strike_at = 0.0
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
