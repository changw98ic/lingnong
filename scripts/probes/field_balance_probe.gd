extends Node

const CROP_ID := "gathering_grass"
const CROP_GROWTH_SECONDS := 5.0
const CROP_SELL_PRICE := 5.0
const TARGET_SLOT_COSTS := [0.0, 100.0, 500.0]
const TARGET_TIER_COSTS := [4000.0, 120000.0, 3000000.0]
const PAYBACK_MIN_SECONDS := 45.0
const PAYBACK_MAX_SECONDS := 90.0
const BASE_PAYBACK_MIN_SECONDS := 120.0
const BASE_PAYBACK_MAX_SECONDS := 180.0

var failures := 0


func _ready() -> void:
	var gs = GameState
	# 探针环境：关闭随机宝箱（避免污染精确资源断言）、隔离存档路径（不覆盖真实存档）。
	TreasureSystem.enabled = false
	SaveManager.save_path = "user://lingnong_probe_save.json"
	gs.initialize_new_game()
	var default_unlock_flags := BalanceConfig.default_unlock_flags(BalanceConfig.INITIAL_REALM_INDEX)
	_check(not default_unlock_flags.has("unlock_alchemy"), "炼丹解锁标志已删除")
	_check(not default_unlock_flags.has("unlock_qi_pill"), "修为丹解锁标志已删除")
	_check(not bool(default_unlock_flags.get("unlock_auto_cultivation", false)), "筑基自动修炼未提前解锁")
	var max_realm := RealmConfig.realm_count() - 1
	var winter_season := BalanceConfig.SEASONS.size() - 1
	var max_tier := BalanceConfig.FIELD_TIER_MULTS.size() - 1
	gs.season_index = winter_season # 冬：避免季节倍率干扰基础比较。
	gs.event_prod_mult = BalanceConfig.DEFAULT_MULTIPLIER
	gs.event_cult_mult = BalanceConfig.DEFAULT_MULTIPLIER
	gs.active_buff_until = 0.0
	gs.active_buff_mult = BalanceConfig.DEFAULT_MULTIPLIER
	gs.talent_nodes = {"root": true}
	gs.lifespan_depleted = false
	gs.realm_index = 1
	gs.spirit_stones = 100000000.0
	gs.unlocked_fields = 1
	_check(not gs.can_purchase_field_tier(1), "未购买的灵田不能升档")
	_check(float(BalanceConfig.FIELD_SLOT_COSTS[1].get("spirit_stones", 0.0)) == TARGET_SLOT_COSTS[1], "第 2 块灵田费用")
	_check(float(BalanceConfig.FIELD_SLOT_COSTS[2].get("spirit_stones", 0.0)) == TARGET_SLOT_COSTS[2], "第 3 块灵田费用")
	_check(is_equal_approx(float(gs.get_field_slot_cost(1).get("spirit_stones", 0.0)), 300.0), "炼气第 2 块灵田动态费用")
	_check(is_equal_approx(float(gs.get_field_slot_cost(2).get("spirit_stones", 0.0)), 1500.0), "炼气第 3 块灵田动态费用")
	_check(float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[0].get("spirit_stones", 0.0)) == TARGET_TIER_COSTS[0], "凡田→灵田费用")
	_check(float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[1].get("spirit_stones", 0.0)) == TARGET_TIER_COSTS[1], "灵田→宝田费用")
	_check(float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[2].get("spirit_stones", 0.0)) == TARGET_TIER_COSTS[2], "宝田→仙田费用")
	var linked_report := gs.get_simulation_report({
		"mode": "uniform",
		"realm_index": BalanceConfig.ADVANCED_COMBAT_REALM_INDEX,
		"season_index": winter_season,
		"talent_nodes": {"root": true},
		"crop_id": CROP_ID,
		"tier": 0,
		"field_count": 2,
		"qi": 0.0,
		"event_prod_mult": BalanceConfig.DEFAULT_MULTIPLIER,
		"event_cult_mult": BalanceConfig.DEFAULT_MULTIPLIER,
		"buff_mult": BalanceConfig.DEFAULT_MULTIPLIER,
	})
	_check(int(linked_report.get("active_fields", 0)) == 2, "模拟器读取内部灵田数量")
	_check(is_equal_approx(float(linked_report.get("total_spirit_stones_per_sec", 0.0)), 16.0), "模拟器读取内部境界/档位/作物公式")
	_check(linked_report.get("slot_rows", []).size() == 2, "模拟器返回槽位回本矩阵")
	var before_cultivation := float(gs.cultivation)
	var before_spirit_stones := float(gs.spirit_stones)
	var before_qi := float(gs.qi)
	var direct_result := _harvest_once(gs, 0, 0)
	_check(float(direct_result.get("cultivation", 0.0)) > 0.0, "灵田收获直接返回修为")
	_check(float(direct_result.get("spirit_stones", 0.0)) > 0.0, "灵田收获直接返回灵石")
	_check(float(gs.cultivation) > before_cultivation, "灵田收获增加当前修为")
	_check(float(gs.spirit_stones) > before_spirit_stones, "灵田收获增加灵石")
	_check(is_equal_approx(float(gs.qi), before_qi), "灵田收获不增加灵气")

	print("=== 灵田槽位：同境界、凡田、灵气为 0 ===")
	for realm in range(RealmConfig.realm_count()):
		gs.realm_index = realm
		var amounts: Array[int] = []
		var rates: Array[float] = []
		for field_index in range(BalanceConfig.FIELD_COUNT):
			var result := _harvest_once(gs, field_index, 0)
			var amount := int(result.get("amount", 0))
			amounts.append(amount)
			rates.append(float(amount) * CROP_SELL_PRICE / CROP_GROWTH_SECONDS)
		var slot2_payback := float(gs.get_field_slot_cost(1).get("spirit_stones", 0.0)) / maxf(0.001, rates[1])
		var slot3_payback := float(gs.get_field_slot_cost(2).get("spirit_stones", 0.0)) / maxf(0.001, rates[2])
		print("realm=%d  各田每轮产量=%s  各田灵石/秒=%s  总灵石/秒=%.2f/%.2f/%.2f  槽位回本=%.1f/%.1f秒" % [
			realm,
			str(amounts),
			str(rates),
			rates[0],
			rates[0] + rates[1],
			rates[0] + rates[1] + rates[2],
			slot2_payback,
			slot3_payback,
		])
		_check(is_equal_approx(rates[0] * 2.0, rates[0] + rates[1]), "第 2 块灵田增加 1 条等效生产线")
		_check(is_equal_approx(rates[0] * 3.0, rates[0] + rates[1] + rates[2]), "第 3 块灵田增加 1 条等效生产线")

	print("=== 灵田升档：单块田的产出和回本时间 ===")
	for realm in range(1, RealmConfig.realm_count()):
		gs.realm_index = realm
		var probe_max_tier := BalanceConfig.FIELD_TIER_MULTS.size() - 1
		for tier in range(mini(realm + 1, probe_max_tier + 1)):
			var result := _harvest_once(gs, 0, tier)
			var amount := float(result.get("amount", 0))
			var rate := amount * CROP_SELL_PRICE / CROP_GROWTH_SECONDS
			if tier >= realm or tier >= probe_max_tier:
				print("realm=%d tier=%d 产量=%d/轮 灵石/秒=%.2f" % [realm, tier, int(amount), rate])
				continue
			var next_result := _harvest_once(gs, 0, tier + 1)
			var next_amount := float(next_result.get("amount", 0))
			var next_rate := next_amount * CROP_SELL_PRICE / CROP_GROWTH_SECONDS
			var cost := float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[tier].get("spirit_stones", 0.0))
			var payback := cost / maxf(0.001, next_rate - rate)
			print("realm=%d tier=%d->%d  %.0f→%.0f 灵石/秒 费用=%.0f 回本=%.2f秒" % [
				realm, tier, tier + 1, rate, next_rate, cost, payback,
			])
			# 元婴是终点层（倍率 ×100），档位回本大幅快于 120~180 秒标定区间，跳过区间断言。
			if tier == realm - 1 and realm < RealmConfig.realm_count() - 1:
				_check(payback >= BASE_PAYBACK_MIN_SECONDS and payback <= BASE_PAYBACK_MAX_SECONDS, "realm=%d tier=%d→%d 无农道回本在目标区间" % [realm, tier, tier + 1])

	print("=== 自动修炼：灵田数量和档位对浓度的影响 ===")
	gs.realm_index = BalanceConfig.ADVANCED_COMBAT_REALM_INDEX
	gs.unlock_auto_cultivation = true
	for field_index in range(BalanceConfig.FIELD_COUNT):
		for clear_index in range(BalanceConfig.FIELD_COUNT):
			gs.fields[clear_index]["crop_id"] = CROP_ID if clear_index <= field_index else ""
			gs.fields[clear_index]["tier"] = 0
		gs.fields[field_index]["crop_id"] = CROP_ID
		gs.fields[field_index]["tier"] = 0
		gs.unlocked_fields = field_index + 1
		gs.insect_events[field_index] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": 9999999999.0}
		var rates := gs.get_auto_cultivation_per_sec()
		print("已种植田数=%d  浓度=%.1f  修为/秒=%.2f  灵气/秒=%.2f" % [
			field_index + 1,
			float(rates.get("density", 0.0)),
			float(rates.get("cultivation", 0.0)),
			float(rates.get("qi", 0.0)),
		])
		_check(is_equal_approx(float(rates.get("density", 0.0)), float(field_index + 1)), "灵气浓度随已种植灵田数量线性增加")

	print("=== 天赋树影响：农道全点时的升档回本 ===")
	var talent_profiles := {
		"root": ["root"],
		"farming_core": ["root", "farming_start", "farming_yield", "farming_speed"],
		"all_nodes": [
			"root", "farming_start", "farming_yield", "farming_speed", "farming_capstone",
			"alchemy_start", "alchemy_power", "alchemy_quality", "alchemy_capstone",
			"spirit_start", "spirit_qi", "spirit_lifespan", "spirit_capstone",
		],
	}
	for profile_name in talent_profiles:
		_set_talents(gs, talent_profiles[profile_name])
		gs.season_index = winter_season
		gs.event_prod_mult = BalanceConfig.DEFAULT_MULTIPLIER
		gs.active_buff_until = 0.0
		gs.qi = 0.0
		var payback_text := PackedStringArray()
		for realm in range(1, RealmConfig.realm_count()):
			gs.realm_index = realm
			var tier := mini(realm - 1, BalanceConfig.FIELD_TIER_UPGRADE_COSTS.size() - 1)
			var slot_rate := _sell_rate(gs, 0)
			var slot2_payback := float(gs.get_field_slot_cost(1).get("spirit_stones", 0.0)) / maxf(0.001, slot_rate)
			var slot3_payback := float(gs.get_field_slot_cost(2).get("spirit_stones", 0.0)) / maxf(0.001, slot_rate)
			var from_rate := _sell_rate(gs, tier)
			var to_rate := _sell_rate(gs, tier + 1)
			var cost := float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[tier].get("spirit_stones", 0.0))
			var payback := cost / maxf(0.001, to_rate - from_rate)
			payback_text.append("%d→%d %.1f秒，槽位 %.1f/%.1f秒" % [tier, tier + 1, payback, slot2_payback, slot3_payback])
			if profile_name == "farming_core" and realm < RealmConfig.realm_count() - 1:
				_check(payback >= PAYBACK_MIN_SECONDS and payback <= PAYBACK_MAX_SECONDS, "农道核心 realm=%d tier=%d→%d 回本在目标区间" % [realm, tier, tier + 1])
		print("profile=%s 生产天赋×%.2f 生长×%.2f  升档回本：%s" % [
			profile_name,
			gs.talent_multiplier("production_mult"),
			gs.get_growth_multiplier(0),
			" / ".join(payback_text),
		])

	_set_talents(gs, talent_profiles["all_nodes"])
	gs.season_index = winter_season
	gs.event_prod_mult = BalanceConfig.DEFAULT_MULTIPLIER
	gs.active_buff_until = 0.0
	gs.realm_index = max_realm
	var burst_from_rate := _sell_rate(gs, 2, CROP_ID, 2000.0)
	var burst_to_rate := _sell_rate(gs, 3, CROP_ID, 2000.0)
	var burst_payback := float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[2].get("spirit_stones", 0.0)) / maxf(0.001, burst_to_rate - burst_from_rate)
	print("all_nodes + 灵气库存 2000：金丹宝→仙，回本=%.2f秒（爆发值，不作为定价基线）" % burst_payback)

	print("=== 4次/秒突破流程：从凡人到金丹 ===")
	print("口径：冬季、无事件、凡田、从零修为；灵田收获直接结算修为和灵石，不产生灵气；4 次/秒为玩家全局点击频率。")
	for profile in SimulationSystem.talent_profiles(gs):
		for field_count in range(1, BalanceConfig.FIELD_COUNT + 1):
			var breakthrough_flow := gs.get_breakthrough_simulation({
				"start_realm": BalanceConfig.INITIAL_REALM_INDEX,
				"target_realm": max_realm,
				"start_cultivation": 0.0,
				"start_qi": 0.0,
				"profile_id": String(profile.get("id", "root")),
				"field_count": field_count,
				"tier": 0,
				"season_index": winter_season,
				"clicks_per_second": BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND,
				"click_scope": "global",
				"event_prod_mult": BalanceConfig.DEFAULT_MULTIPLIER,
				"event_cult_mult": BalanceConfig.DEFAULT_MULTIPLIER,
				"include_auto_cultivation": true,
				"enforce_breakthrough_materials": false,
				"enforce_tribulation_supplies": false,
			})
			var stage_text := PackedStringArray()
			for stage in breakthrough_flow.get("stages", []):
				stage_text.append("%s→%s %.2f秒" % [
					String(stage.get("from_realm_name", "")),
					String(stage.get("to_realm_name", "")),
					float(stage.get("duration_seconds", 0.0)),
				])
			print("profile=%s 田=%d 总耗时=%.2f秒 总点击=%d 阶段=%s 真实完成=%s 时间估算=%s" % [
				String(profile.get("id", "")),
				field_count,
				float(breakthrough_flow.get("total_seconds", 0.0)),
				int(breakthrough_flow.get("total_clicks", 0)),
				" / ".join(stage_text),
				str(bool(breakthrough_flow.get("completed", false))),
				str(bool(breakthrough_flow.get("estimated_completed", false))),
			])
			_check(bool(breakthrough_flow.get("estimated_completed", false)) and not bool(breakthrough_flow.get("completed", false)), "4次/秒突破时间估算完成且明确标记为估算：%s / %d块" % [String(profile.get("id", "")), field_count])
	var per_field_flow := gs.get_breakthrough_simulation({
		"start_realm": BalanceConfig.INITIAL_REALM_INDEX,
		"target_realm": max_realm,
		"start_cultivation": 0.0,
		"start_qi": 0.0,
		"profile_id": "root",
		"field_count": BalanceConfig.FIELD_COUNT,
		"tier": 0,
		"season_index": winter_season,
		"clicks_per_second": BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND,
		"click_scope": "per_field",
		"enforce_breakthrough_materials": false,
		"enforce_tribulation_supplies": false,
	})
	print("root 3块田切换为每块独立 4次/秒：总耗时=%.2f秒" % float(per_field_flow.get("total_seconds", 0.0)))
	_check(bool(per_field_flow.get("estimated_completed", false)) and not bool(per_field_flow.get("completed", false)), "每块灵田独立点击模式完成时间估算")

	print("=== 游戏内模拟器矩阵入口 ===")
	var realm_rows := gs.get_simulation_matrix("realm", {"crop_id": CROP_ID, "tier": 0, "qi": 0.0})
	var crop_rows := gs.get_simulation_matrix("crop", {"realm_index": max_realm, "field_count": BalanceConfig.FIELD_COUNT, "tier": max_tier, "qi": 0.0})
	var season_rows := gs.get_simulation_matrix("season", {"realm_index": max_realm, "crop_id": CROP_ID, "tier": 0, "field_count": BalanceConfig.FIELD_COUNT, "qi": 0.0})
	var talent_rows := gs.get_simulation_matrix("talent", {"realm_index": max_realm, "crop_id": CROP_ID, "tier": 0, "field_count": BalanceConfig.FIELD_COUNT, "qi": 0.0})
	var event_rows := gs.get_simulation_matrix("event", {"realm_index": max_realm, "crop_id": CROP_ID, "tier": 0, "field_count": BalanceConfig.FIELD_COUNT, "qi": 0.0})
	var progression_rows := gs.get_simulation_matrix("progression", {"profile_id": "all_nodes", "qi": 0.0})
	var breakthrough_rows := gs.get_simulation_matrix("breakthrough", {
		"start_realm": BalanceConfig.INITIAL_REALM_INDEX,
		"target_realm": max_realm,
		"start_cultivation": 0.0,
		"start_qi": 0.0,
		"profile_id": "all_nodes",
		"field_count": 1,
		"tier": 0,
		"season_index": winter_season,
		"clicks_per_second": BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND,
		"click_scope": "global",
		"enforce_breakthrough_materials": false,
		"enforce_tribulation_supplies": false,
	})
	var proficiency_rows := gs.get_simulation_matrix("proficiency", {
		"realm_index": max_realm,
		"field_count": 1,
		"tier": 0,
		"qi": 0.0,
	})
	var full_rows := gs.get_simulation_matrix("full", {"qi": 0.0, "event_id": "normal"})
	var expected_full_rows := 0
	for realm in range(RealmConfig.realm_count()):
		expected_full_rows += CropConfig.get_unlocked(realm).size() * BalanceConfig.SEASONS.size() * SimulationSystem.talent_profiles(gs).size() * gs.fields.size() * mini(realm + 1, BalanceConfig.FIELD_TIER_MULTS.size())
	_check(realm_rows.size() == RealmConfig.realm_count() * gs.fields.size(), "境界矩阵覆盖全部境界和田数")
	_check(crop_rows.size() == CropConfig.get_unlocked(max_realm).size(), "作物矩阵覆盖金丹全部作物")
	_check(season_rows.size() == BalanceConfig.SEASONS.size(), "四季矩阵覆盖全部时节")
	_check(talent_rows.size() == SimulationSystem.talent_profiles(gs).size(), "天赋矩阵读取天赋树预设")
	_check(event_rows.size() == SimulationSystem.event_profiles(gs).size(), "事件矩阵覆盖全部事件")
	_check(progression_rows.size() == RealmConfig.realm_count(), "境界总表覆盖全部境界")
	_check(breakthrough_rows.size() == 1 and bool(breakthrough_rows[0].get("estimated_completed", false)), "突破流程矩阵完成从凡人到金丹时间估算")
	_check(proficiency_rows.size() == CropConfig.get_all().size() * (BalanceConfig.CROP_PROFICIENCY_THRESHOLDS.size() + 1), "熟练度矩阵覆盖全部作物和档位")
	_check(full_rows.size() == expected_full_rows, "全量核心矩阵覆盖境界/作物/四季/天赋/田数/档位")
	_check_section_one(gs)
	_check_breakthrough_pacing(gs)
	_check_crop_switch_and_breakthrough_materials(gs)
	_check_tribulation_and_pills(gs)
	_check_reincarnation_loop(gs)
	_check_insect_disaster(gs)
	_check_achievements(gs)
	_check_frenzy_pill(gs)
	_check_expansion(gs)
	var simulation_panel := SimulationPanel.new()
	add_child(simulation_panel)
	var formatted_live: String = String(simulation_panel.call("_format_report", linked_report))
	_check(not formatted_live.is_empty(), "实时报告面板格式化")
	for pair in [
		["realm", realm_rows], ["crop", crop_rows], ["season", season_rows],
		["talent", talent_rows], ["event", event_rows],
		["proficiency", proficiency_rows], ["progression", progression_rows], ["breakthrough", breakthrough_rows], ["full", full_rows],
	]:
		var formatted: String = String(simulation_panel.call("_format_matrix", String(pair[0]), pair[1]))
		_check(not formatted.is_empty(), "模拟面板格式化 %s" % String(pair[0]))
	simulation_panel.queue_free()
	var achievement_panel := AchievementPanel.new()
	add_child(achievement_panel)
	_check(achievement_panel.get_child_count() > 0, "成就面板构建并读取当前进度")
	achievement_panel.queue_free()

	if failures > 0:
		print("BALANCE_PROBE_FAIL count=%d" % failures)
		get_tree().quit(1)
		return
	print("BALANCE_PROBE_PASS")
	get_tree().quit(0)


func _harvest_once(gs: Node, field_index: int, tier: int) -> Dictionary:
	gs.qi = 0.0
	gs.unlocked_fields = maxi(gs.unlocked_fields, field_index + 1)
	gs.fields[field_index]["crop_id"] = CROP_ID
	gs.fields[field_index]["tier"] = tier
	gs.fields[field_index]["ready_at"] = 0.0
	gs.insect_events[field_index] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": 9999999999.0}
	return gs.harvest_crop(field_index)


func _sell_rate(gs: Node, tier: int, crop_id: String = CROP_ID, qi_stock: float = 0.0) -> float:
	gs.qi = qi_stock
	gs.unlocked_fields = 1
	gs.fields[0]["crop_id"] = crop_id
	gs.fields[0]["tier"] = tier
	gs.fields[0]["ready_at"] = 0.0
	gs.insect_events[0] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": 9999999999.0}
	var result: Dictionary = gs.harvest_crop(0)
	var crop: Dictionary = CropConfig.get_crop(crop_id)
	var growth_seconds: float = float(crop.get("growth", CROP_GROWTH_SECONDS)) / gs.get_growth_multiplier(0)
	return float(result.get("amount", 0)) * float(crop.get("sell_price", CROP_SELL_PRICE)) / maxf(0.001, growth_seconds)


func _check_insect_disaster(gs: Node) -> void:
	print("=== 噬金虫灾害可见性 ===")
	var mortal_run_seconds := float(BalanceConfig.LIFESPAN_YEARS_BY_REALM[BalanceConfig.INITIAL_REALM_INDEX]) / BalanceConfig.LIFESPAN_DECAY_PER_SECOND
	_check(
		BalanceConfig.INSECT_INITIAL_DELAY_SECONDS + BalanceConfig.INSECT_ATTACK_INTERVAL_SECONDS <= mortal_run_seconds,
		"凡人一轮寿元内能看到首轮噬金虫"
	)
	gs.initialize_new_game()
	gs.realm_index = 2
	var fixed_next := Time.get_unix_time_from_system() + 20.0
	gs.insect_events[0] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": fixed_next}
	_check(gs.plant_crop(0, CROP_ID), "固定虫灾测试种植成功")
	var after_plant := float(gs.insect_events[0].get("next_attack_at", 0.0))
	_check(absf(after_plant - fixed_next) < 0.1, "手动种植不重置噬金虫计时")
	fixed_next = Time.get_unix_time_from_system() + 20.0
	gs.insect_events[0]["next_attack_at"] = fixed_next
	_check(gs.switch_crop(0, "mind_flower"), "固定虫灾测试切换成功")
	var after_switch := float(gs.insect_events[0].get("next_attack_at", 0.0))
	_check(absf(after_switch - fixed_next) < 0.1, "手动切换不重置噬金虫计时")

	# 聚灵草会频繁自动补种；补种不能把同一块田的虫害计时反复推迟。
	gs.initialize_new_game()
	gs.unlocked_fields = 1
	gs.fields[0]["crop_id"] = CROP_ID
	gs.fields[0]["tier"] = 0
	gs.fields[0]["ready_at"] = 0.0
	var next_before := Time.get_unix_time_from_system() + 20.0
	gs.insect_events[0] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": next_before}
	var harvest: Dictionary = gs.harvest_crop(0)
	_check(bool(harvest.get("ok", false)), "噬金虫回归测试收获成功")
	var next_after := float(gs.insect_events[0].get("next_attack_at", 0.0))
	_check(absf(next_after - next_before) < 0.1, "自动补种不重置噬金虫计时")
	gs.insect_events[0]["next_attack_at"] = Time.get_unix_time_from_system() - 1.0
	gs.update_world(0.1)
	_check(bool(gs.insect_events[0].get("active", false)), "虫灾计时到点后进入预警状态")


func _check_breakthrough_pacing(gs: Node) -> void:
	print("=== 突破节奏 ===")
	gs.initialize_new_game()
	gs.talent_nodes = {"root": true}
	var flow: Dictionary = gs.get_breakthrough_simulation({
		"start_realm": 0,
		"target_realm": 3,
		"profile_id": "root",
		"field_count": 3,
		"tier": 0,
		"season_index": BalanceConfig.SEASONS.size() - 1,
		"clicks_per_second": BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND,
		"click_scope": "global",
		"include_auto_cultivation": true,
		"enforce_breakthrough_materials": false,
		"enforce_tribulation_supplies": false,
	})
	var stages: Array = flow.get("stages", [])
	var qi_to_zhuji_seconds := 0.0
	var zhuji_to_jindan_seconds := 0.0
	if stages.size() > 1:
		qi_to_zhuji_seconds = float(stages[1].get("cultivation_seconds", stages[1].get("duration_seconds", 0.0)))
	if stages.size() > 2:
		zhuji_to_jindan_seconds = float(stages[2].get("cultivation_seconds", stages[2].get("duration_seconds", 0.0)))
	print("根骨、3块凡田、4次/秒：总耗时=%.2f秒；炼气→筑基修炼=%.2f秒；筑基→金丹修炼=%.2f秒" % [
		float(flow.get("total_seconds", 0.0)), qi_to_zhuji_seconds, zhuji_to_jindan_seconds,
	])
	_check(qi_to_zhuji_seconds >= 1440.0, "炼气→筑基至少 1440 秒")
	_check(zhuji_to_jindan_seconds >= qi_to_zhuji_seconds * 2.0, "筑基→金丹修炼段至少为炼气→筑基两倍")
	_check(int(stages[1].get("tribulation_strikes", 0)) > 0 and int(stages[2].get("tribulation_strikes", 0)) > 0, "模拟器把各阶段天劫计入总耗时")

	# 模拟器必须同步真实收获结算：熟练度跨档和修为里程碑都要发放天赋点。
	gs.initialize_new_game()
	gs.crop_proficiency["gathering_grass"] = 9
	var talent_flow: Dictionary = gs.get_breakthrough_simulation({
		"start_realm": 0,
		"target_realm": 1,
		"start_cultivation": 999.0,
		"start_total_cultivation_earned": 999.0,
		"start_talent_milestone_index": 0,
		"clicks_per_second": 0.0,
		"include_auto_cultivation": false,
		"season_index": BalanceConfig.SEASONS.size() - 1,
		"enforce_breakthrough_materials": false,
		"enforce_tribulation_supplies": false,
	})
	var talent_stage: Dictionary = talent_flow.get("stages", [])[0]
	_check(int(talent_stage.get("talent_points_before_tribulation", 0)) == 2, "模拟器同步熟练度与修为里程碑天赋点")
	_check(String(talent_flow.get("completion_mode", "")) == "estimate" and bool(talent_flow.get("estimated_completed", false)) and not bool(talent_flow.get("completed", false)), "模拟器估算结果不冒充真实完成")

	# 最大化模式：点数到账立即投入最能缩短当前突破时间的节点，灵石先买寿元/材料/渡劫丹，
	# 剩余灵石再买聚气玉；整个过程只读模型，不修改真实 GameState。
	gs.initialize_new_game()
	var maximized_flow: Dictionary = gs.get_breakthrough_simulation({
		"maximize_progression": true,
		"start_realm": 0,
		"target_realm": 3,
		"field_count": 3,
		"tier": 0,
		"season_index": BalanceConfig.SEASONS.size() - 1,
		"clicks_per_second": BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND,
		"click_scope": "global",
		"include_auto_cultivation": true,
		"enforce_breakthrough_materials": true,
		"enforce_tribulation_supplies": true,
		"auto_buy_shop_resources": true,
		"auto_use_tribulation_pills": true,
		"start_spirit_stones": 10000.0,
	})
	_check(bool(maximized_flow.get("completed", false)), "最大化模拟完成三段真实突破流程")
	var maximized_earned: int = int(maximized_flow.get("talent_points_earned", 0))
	var maximized_spent: int = int(maximized_flow.get("talent_points_spent", 0))
	var maximized_left: int = int(maximized_flow.get("talent_points", -1))
	_check(
		maximized_earned > 0 and maximized_spent > 0
			and maximized_spent <= maximized_earned
			and maximized_left == maximized_earned - maximized_spent,
		"最大化模拟立即消费天赋点且点数账平衡"
	)
	var maximized_purchases: Array = maximized_flow.get("shop_purchases", [])
	var bought_qi := false
	var bought_material := false
	for purchase_variant in maximized_purchases:
		var purchase: Dictionary = purchase_variant
		bought_qi = bought_qi or String(purchase.get("item_id", "")) == "qi_jade"
		bought_material = bought_material or String(purchase.get("item_id", "")).begins_with("breakthrough_")
	_check(bought_qi and bought_material, "最大化模拟用灵石购买灵气和突破材料")
	_check(is_zero_approx(gs.spirit_stones), "最大化模拟不修改真实灵石库存")


func _check_section_one(gs: Node) -> void:
	print("=== 第 1 节数值规则 ===")
	gs.initialize_new_game()
	gs.realm_index = 1
	_check(not gs.get_crop_options().has("mind_flower"), "凝神花只由作物配置的筑基门槛解锁")
	gs.realm_index = 2
	_check(gs.get_crop_options().has("mind_flower"), "筑基解锁凝神花")
	gs.realm_index = 3
	_check(gs.get_crop_options().has("sun_fruit") and gs.get_crop_options().has("heaven_lotus"), "金丹解锁赤阳果和天道莲")
	_check(is_equal_approx(float(BalanceConfig.LIFESPAN_DECAY_PER_SECOND), 0.2), "寿元衰减为 0.2 年/秒（5 秒 = 1 年）")
	_check(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM == [0, 3, 7, 15, 31], "突破天赋点表为 [0,3,7,15,31]")
	_check(is_equal_approx(float(BalanceConfig.REALMS[1].get("required_cultivation", 0.0)), 1000.0) and is_equal_approx(float(BalanceConfig.REALMS[2].get("required_cultivation", 0.0)), 80000.0) and is_equal_approx(float(BalanceConfig.REALMS[3].get("required_cultivation", 0.0)), 2000000.0), "境界修为门槛提高为 1000/80000/2000000")
	_check(is_equal_approx(80.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 400.0), "凡人一轮寿元约 6.7 分钟")
	_check(is_equal_approx(120.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 600.0), "炼气一轮寿元约 10 分钟")
	_check(is_equal_approx(300.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 1500.0), "筑基一轮寿元约 25 分钟")
	_check(is_equal_approx(1000.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 5000.0), "金丹一轮寿元约 83 分钟")

	for crop_id_variant in CropConfig.get_all():
		var crop_id := String(crop_id_variant)
		var at_10 := BalanceConfig.crop_proficiency_reward(crop_id, 10)
		var at_50 := BalanceConfig.crop_proficiency_reward(crop_id, 50)
		var at_150 := BalanceConfig.crop_proficiency_reward(crop_id, 150)
		var at_400 := BalanceConfig.crop_proficiency_reward(crop_id, 400)
		_check(int(at_10.get("yield_bonus", 0)) == 1 and int(at_10.get("talent_points", 0)) == 1, "%s 10次奖励" % crop_id)
		_check(int(at_50.get("yield_bonus", 0)) == 1 and int(at_50.get("talent_points", 0)) == 3, "%s 50次奖励与累计天赋" % crop_id)
		_check(int(at_150.get("yield_bonus", 0)) == 2 and int(at_150.get("talent_points", 0)) == 6, "%s 150次奖励与累计天赋" % crop_id)
		_check(int(at_400.get("yield_bonus", 0)) == 3 and int(at_400.get("talent_points", 0)) == 11, "%s 400次奖励与累计天赋" % crop_id)
		_check(BalanceConfig.crop_proficiency_talent_points(crop_id, 0, 400) == 11, "%s 四档天赋点总和" % crop_id)
	var proficiency_talent_total := 0
	for crop_id_variant in CropConfig.get_all():
		proficiency_talent_total += BalanceConfig.crop_proficiency_talent_points(String(crop_id_variant), 0, 400)
	_check(proficiency_talent_total == 55, "五种作物熟练度天赋点总计 55")
	_check(is_equal_approx(BalanceConfig.crop_base_growth_seconds("gathering_grass", 400), 4.0), "聚灵草最终基础成熟时间 4 秒")
	_check(is_equal_approx(BalanceConfig.crop_base_growth_seconds("mind_flower", 400), 28.0), "凝神花最终基础成熟时间 28 秒")
	_check(is_equal_approx(BalanceConfig.crop_base_growth_seconds("sun_fruit", 400), 115.0), "赤阳果最终基础成熟时间 115 秒")
	_check(is_equal_approx(BalanceConfig.crop_base_growth_seconds("heaven_lotus", 400), 1740.0), "天道莲最终基础成熟时间 1740 秒")

	# 真实收获跨门槛时发点，下一轮才使用新档位；这条路径与模拟器共用 field_result。
	gs.initialize_new_game()
	gs.season_index = BalanceConfig.SEASONS.size() - 1
	gs.crop_proficiency["gathering_grass"] = 9
	var points_before: int = gs.talent_points
	var harvest := _harvest_once(gs, 0, 0)
	_check(bool(harvest.get("ok", false)), "熟练度测试真实收获成功")
	_check(int(gs.crop_proficiency.get("gathering_grass", 0)) == 10, "真实收获增加作物熟练度")
	_check(gs.talent_points == points_before + 1, "真实收获跨 10 次门槛获得天赋点")

	# 突破点表按实际突破路径发放，并累计晋级次数。
	gs.initialize_new_game()
	var breakthrough_points := []
	for realm in range(1, RealmConfig.realm_count()):
		gs.realm_index = realm - 1
		gs.cultivation = float(BalanceConfig.REALMS[realm].get("required_cultivation", 0.0))
		_grant_breakthrough_materials(gs, realm)
		var before: int = gs.talent_points
		var break_result: Dictionary = gs.breakthrough()
		_check(bool(break_result.get("ok", false)), "开始%s三劫雷劫" % String(BalanceConfig.REALMS[realm].get("name", "")))
		_check(gs.realm_index == realm - 1 and gs.tribulation_active, "天劫完成前境界不提前增加")
		_finish_tribulation_for_probe(gs)
		_check(gs.realm_index == realm, "天劫成功后进入%s" % String(BalanceConfig.REALMS[realm].get("name", "")))
		breakthrough_points.append(gs.talent_points - before)
	_check(breakthrough_points == [3, 7, 15, 31], "实际突破发放 3/7/15/31 点")
	_check(gs.promotion_count == 4, "实际突破累计晋级次数")

	# 轮回：随时轮回保留长期成长，选择转世天赋。
	gs.initialize_new_game()
	gs.crop_proficiency["gathering_grass"] = 400
	gs.total_harvest_count = 400
	gs.promotion_count = 2
	gs.lifespan_depleted = true
	_check(gs.reincarnate_now(), "大限后可以立即轮回")
	_check(gs.reincarnation_count == 1, "轮回增加轮回次数")
	_check(int(gs.crop_proficiency.get("gathering_grass", 0)) == 400, "轮回保留作物熟练度")
	_check(gs.total_harvest_count == 400 and gs.promotion_count == 2, "轮回保留长期计数")
	_check(gs.pending_reincarnation_boon, "轮回后等待选择转世天赋")
	_check(not gs.reincarnate_now(), "选择转世天赋前不可再次轮回")
	_check(gs.choose_reincarnation_boon("wood_spirit"), "选择转世天赋·青木神通")
	_check(gs.reincarnation_boon == "wood_spirit" and not gs.pending_reincarnation_boon, "转世天赋本世生效")
	_check(not gs.choose_reincarnation_boon("not_real"), "非法转世天赋被拒绝")

	# 离线结算只按长期计数发放一次差额，不随离线时长变化，也不增加修为/灵气。
	gs.initialize_new_game()
	gs.realm_index = 2
	gs.reincarnation_count = 3
	gs.promotion_count = 4
	gs.total_harvest_count = 4000
	gs.lifespan_depleted = false
	var offline_preview: Dictionary = gs.get_offline_settlement_preview()
	_check(int(offline_preview.get("talent_points", 0)) == 7, "离线天赋点按公式封顶 7")
	_check(is_equal_approx(float(offline_preview.get("spirit_stones", 0.0)), 68400.0), "离线灵石按计数和境界倍率结算")
	var cultivation_before_offline: float = gs.cultivation
	var qi_before_offline: float = gs.qi
	gs.apply_offline_report()
	_check(is_equal_approx(gs.spirit_stones, 68400.0), "离线结算实际发放灵石")
	_check(gs.talent_points == 7, "离线结算实际发放天赋点")
	_check(is_equal_approx(gs.cultivation, cultivation_before_offline), "离线结算不增加修为")
	_check(is_equal_approx(gs.qi, qi_before_offline), "离线结算不增加灵气")
	var second_offline: Dictionary = gs.get_offline_settlement_preview()
	_check(int(second_offline.get("talent_points", 0)) == 0 and is_equal_approx(float(second_offline.get("spirit_stones", 0.0)), 0.0), "离线结算账本避免重复领取")
	gs.lifespan_depleted = true
	gs.offline_claimed_talent_points = 0
	gs.offline_claimed_spirit_stone_units = 0.0
	var stones_before_depleted: float = gs.spirit_stones
	gs.apply_offline_report()
	_check(is_equal_approx(gs.spirit_stones, stones_before_depleted), "大限未续命不结算离线奖励")


func _check_crop_switch_and_breakthrough_materials(gs: Node) -> void:
	print("=== 作物切换与突破材料 ===")
	gs.initialize_new_game()
	gs.realm_index = 2
	_check(not gs.plant_crop(0, "fu_qi_dan"), "突破材料不能种植")
	_check(gs.plant_crop(0, CROP_ID), "切换测试先种植聚灵草")
	var old_ready_at := float(gs.fields[0].get("ready_at", 0.0))
	_check(gs.switch_crop(0, "mind_flower"), "已种植灵田可以切换作物")
	_check(String(gs.fields[0].get("crop_id", "")) == "mind_flower", "切换后作物已更新")
	_check(float(gs.fields[0].get("ready_at", 0.0)) > old_ready_at, "切换后按新作物重新计时")

	gs.initialize_new_game()
	gs.spirit_stones = 1000.0
	gs.cultivation = float(BalanceConfig.REALMS[1].get("required_cultivation", 0.0))
	var blocked_flow: Dictionary = gs.get_breakthrough_simulation({
		"start_realm": 0,
		"target_realm": 1,
		"start_cultivation": gs.cultivation,
		"clicks_per_second": 4.0,
		"include_auto_cultivation": false,
		"enforce_breakthrough_materials": true,
		"enforce_tribulation_supplies": true,
	})
	_check(not bool(blocked_flow.get("completed", false)) and String(blocked_flow.get("blocked_reason", "")) == "突破材料不足", "模拟器按当前库存拦截突破")
	var prepared_flow: Dictionary = gs.get_breakthrough_simulation({
		"start_realm": 0,
		"target_realm": 1,
		"start_cultivation": gs.cultivation,
		"start_qi": 250.0,
		"start_harvest_cycles": 500,
		"clicks_per_second": 4.0,
		"include_auto_cultivation": false,
		"enforce_breakthrough_materials": true,
		"start_breakthrough_materials": {"fu_qi_dan": 10},
		"enforce_tribulation_supplies": true,
		"start_healing_pills": 4,
		"start_resistance_pills": 1,
		"start_enhancement_pills": 1,
	})
	_check(bool(prepared_flow.get("completed", false)), "模拟器使用已备齐材料和渡劫丹通过三道检查完成突破")
	_check(not gs.can_breakthrough(), "缺少突破材料不能突破")
	_check(gs.get_breakthrough_block_reason().begins_with("缺少服气丹"), "突破界面显示缺少的材料")
	var bought_fu_qi := true
	for _i in range(15):
		bought_fu_qi = gs.buy_shop_item("breakthrough_fu_qi_dan") and bought_fu_qi
	_check(bought_fu_qi, "服气丹只能通过商店兑换")
	_check(gs.get_breakthrough_material_count("fu_qi_dan") == 15, "服气丹库存达到稳定突破需求（10×1.5）")
	_check(gs.can_breakthrough(), "修为和服气丹齐备后可以突破")
	_check(gs.has_breakthrough_materials_for_mode(1, "stable"), "稳定突破 1.5 倍材料可满足")
	# 商店路径没有碎丹经验，探针直接堆满保证稳定突破必成。
	gs.broken_dan_experience = BalanceConfig.BROKEN_DAN_SUCCESS_CAP
	var stable_result: Dictionary = gs.breakthrough("stable")
	_check(bool(stable_result.get("success", false)), "稳定突破消耗 1.5 倍材料开始炼气天劫")
	_check(gs.tribulation_active and gs.realm_index == 0, "炼气天劫期间仍保持凡人境界")
	_finish_tribulation_for_probe(gs)
	_check(gs.realm_index == 1, "完成炼气天劫后进入炼气")
	_check(gs.get_breakthrough_material_count("fu_qi_dan") == 0, "炼气突破消耗 15 颗服气丹")

	gs.initialize_new_game()
	gs.spirit_stones = 100000.0
	_check(not gs.buy_shop_item("breakthrough_jin_yang_hua"), "未到炼气不能兑换筑基材料")
	_check(BalanceConfig.BREAKTHROUGH_REQUIREMENTS[1].size() == 1 and BalanceConfig.BREAKTHROUGH_REQUIREMENTS[2].size() == 5 and BalanceConfig.BREAKTHROUGH_REQUIREMENTS[3].size() == 6, "三段突破材料数量配置正确")
	_check(BalanceConfig.BREAKTHROUGH_MATERIALS.has("lei_ji_tao_mu"), "金丹突破材料已纳入统一数值表")
	var material_cost_flow: Dictionary = gs.get_breakthrough_simulation({
		"start_realm": 0,
		"target_realm": 3,
		"field_count": 1,
		"clicks_per_second": 0.0,
		"include_auto_cultivation": false,
		"enforce_breakthrough_materials": false,
		"enforce_tribulation_supplies": false,
	})
	_check(is_equal_approx(float(material_cost_flow.get("breakthrough_material_shop_cost", 0.0)), 3700.0), "三段突破材料需单独购买共 3700 灵石")


func _check_tribulation_and_pills(gs: Node) -> void:
	print("=== 天劫检查与渡劫丹 ===")
	# 稳定突破需要 1.5 倍材料；1 倍材料只够强行突破。
	gs.initialize_new_game()
	gs.cultivation = float(BalanceConfig.REALMS[1].get("required_cultivation", 0.0))
	_grant_breakthrough_materials(gs, 1)
	gs.talent_points = 0
	gs.talent_points_earned = 0
	_check(gs.has_breakthrough_materials_for_mode(1, "forced"), "强行突破只需 1 倍材料")
	gs.breakthrough_materials["fu_qi_dan"] = 10
	_check(not gs.has_breakthrough_materials_for_mode(1, "stable"), "1 倍材料不满足稳定突破的 1.5 倍需求")
	gs.breakthrough_materials["fu_qi_dan"] = 15
	_check(bool(gs.breakthrough().get("success", false)), "稳定突破成功率 100%（碎丹经验堆满）")
	_check(gs.realm_index == 0 and gs.tribulation_active, "天劫完成前不递增境界")
	_check(gs.get_breakthrough_material_count("fu_qi_dan") == 0, "稳定突破消耗 15 颗服气丹（×1.5）")

	# 灵气不足：第一劫失败，获得永久雷劫淬体。
	_check(gs.advance_tribulation(), "灵气不足时结算第一劫")
	_check(not gs.tribulation_active and gs.realm_index == 0, "第一劫失败、境界不变")
	_check(is_equal_approx(gs.tribulation_refine_bonus, BalanceConfig.TRIBULATION_REFINE_BONUS), "检查失败获得永久雷劫淬体 +5%")

	# 三项达标：三道检查依次通过后进入炼气。
	gs.initialize_new_game()
	gs.cultivation = float(BalanceConfig.REALMS[1].get("required_cultivation", 0.0))
	_grant_breakthrough_materials(gs, 1)
	gs.qi = BalanceConfig.tribulation_qi_requirement(1)
	gs.run_harvest_count = BalanceConfig.TRIBULATION_CHECK_HARVEST_REQUIREMENT
	gs.run_random_event_count = 1
	_check(bool(gs.breakthrough().get("success", false)), "材料齐备后开始三劫雷劫")
	_check(gs.realm_index == 0 and gs.tribulation_active, "天劫完成前不递增境界")
	_check(gs.advance_tribulation() and gs.tribulation_strikes_survived == 1, "手动结算第一劫·灵气")
	_check(gs.advance_tribulation() and gs.tribulation_strikes_survived == 2, "手动结算第二劫·底蕴")
	_check(gs.advance_tribulation(), "手动结算第三劫·气运")
	_check(gs.realm_index == 1 and not gs.tribulation_active, "完成三劫雷劫后进入炼气")
	_check(gs.tribulation_last_result.begins_with("渡劫成功"), "渡劫成功结果文本")

	# 渡劫丹是渡劫准备：治疗丹减半灵气需求、抗性丹减半底蕴需求、强化丹直通气运。
	gs.initialize_new_game()
	gs.cultivation = float(BalanceConfig.REALMS[1].get("required_cultivation", 0.0))
	_grant_breakthrough_materials(gs, 1)
	gs.spirit_stones = 100000.0
	_check(gs.buy_shop_item("healing_pill"), "商店购买治疗丹")
	_check(gs.buy_shop_item("resistance_pill"), "商店购买抗性丹")
	_check(gs.buy_shop_item("enhancement_pill"), "商店购买强化丹")
	_check(gs.healing_pills == 1 and gs.resistance_pills == 1 and gs.enhancement_pills == 1, "三类渡劫丹进入库存")
	# 灵气只有需求一半（治疗丹后达标）；底蕴只有 500 次（抗性丹后达标）。
	gs.qi = BalanceConfig.tribulation_qi_requirement(1) * BalanceConfig.TRIBULATION_HEAL_REQUIREMENT_MULT
	gs.run_harvest_count = ceili(float(BalanceConfig.TRIBULATION_CHECK_HARVEST_REQUIREMENT) * BalanceConfig.TRIBULATION_RESISTANCE_REQUIREMENT_MULT)
	_check(bool(gs.breakthrough().get("success", false)), "丹药准备后开始渡劫")
	_check(gs.use_healing_pill(), "使用治疗丹准备第一劫")
	_check(not gs.use_healing_pill(), "治疗丹每次渡劫限用 1 枚")
	_check(gs.advance_tribulation() and gs.tribulation_strikes_survived == 1, "治疗丹让灵气劫需求减半后通过")
	_check(gs.use_resistance_pill(), "使用抗性丹准备第二劫")
	_check(gs.advance_tribulation() and gs.tribulation_strikes_survived == 2, "抗性丹让底蕴劫需求减半后通过")
	_check(gs.use_enhancement_pill(), "使用强化丹准备第三劫")
	_check(gs.advance_tribulation(), "强化丹直接通过气运劫")
	_check(gs.realm_index == 1 and not gs.tribulation_active, "丹药备齐完成渡劫进入炼气")

	# 碎丹：强行突破 50% 成功率，固定种子强制失败验证经验累计。
	gs.initialize_new_game()
	gs.cultivation = float(BalanceConfig.REALMS[1].get("required_cultivation", 0.0))
	_grant_breakthrough_materials(gs, 1)
	gs.broken_dan_experience = 0.0
	var dan_failed := false
	randomize()
	for seed_index in range(200):
		seed(7000 + seed_index)
		gs.breakthrough_materials["fu_qi_dan"] = 10
		gs.broken_dan_experience = 0.0
		# 上一次尝试若成功会开启天劫，先复位渡劫状态再试下一次。
		gs.tribulation_active = false
		gs.tribulation_target_realm = -1
		gs.tribulation_strikes_survived = 0
		gs.tribulation_prepared = [false, false, false]
		var dan_result: Dictionary = gs.breakthrough("forced")
		if not bool(dan_result.get("success", false)) and bool(dan_result.get("ok", false)):
			dan_failed = true
			break
	randomize()
	_check(dan_failed, "强行突破可以碎丹失败")
	_check(is_equal_approx(gs.broken_dan_experience, BalanceConfig.BROKEN_DAN_SUCCESS_BONUS), "碎丹经验 +15%")
	_check(gs.get_breakthrough_material_count("fu_qi_dan") == 0, "碎丹消耗 10 颗服气丹")
	_check(not gs.tribulation_active and gs.realm_index == 0, "碎丹后不进入天劫、境界不变")
	_check(is_equal_approx(gs.get_breakthrough_success_rate("forced"), BalanceConfig.BREAKTHROUGH_FORCED_SUCCESS_RATE + BalanceConfig.BROKEN_DAN_SUCCESS_BONUS), "碎丹经验进入下次成功率")
	_check(gs.get_breakthrough_success_rate("forced") <= BalanceConfig.BREAKTHROUGH_FORCED_SUCCESS_RATE + BalanceConfig.BROKEN_DAN_SUCCESS_CAP, "碎丹经验封顶 45%")


func _check_reincarnation_loop(gs: Node) -> void:
	print("=== 轮回 / 天人五衰 / 宝箱 / 新事件 ===")
	# 轮回奖励预览：本世里程碑 ×2 + 本世突破 ×1；提前轮回 ×80%，天人五衰 ×100%。
	gs.initialize_new_game()
	gs.talent_milestone_index = 3
	gs.run_start_milestone_index = 1
	gs.promotion_count = 5
	gs.run_start_promotion_count = 3
	gs.lifespan_max_years = 80.0
	gs.lifespan_years = 30.0
	var early_preview: Dictionary = gs.get_reincarnation_reward_preview()
	_check(bool(early_preview.get("early", false)), "寿元 >20% 判定为提前轮回")
	_check(int(early_preview.get("points", 0)) == int(floor((2 * 2 + 2 * 1) * BalanceConfig.REINCARNATION_EARLY_PENALTY)), "提前轮回：里程碑×2+突破×1 再 ×80%")
	gs.lifespan_years = 10.0
	var decay_preview: Dictionary = gs.get_reincarnation_reward_preview()
	_check(not bool(decay_preview.get("early", false)), "寿元 ≤20% 进入天人五衰不扣奖励")
	_check(int(decay_preview.get("points", 0)) == 2 * 2 + 2 * 1, "天人五衰立即轮回 ×100%")

	# 天人五衰三选择·继续修炼：生产减半 + 天命奇遇。
	gs.initialize_new_game()
	gs.lifespan_max_years = 80.0
	gs.lifespan_years = 10.0
	_check(gs.is_decay_stage(), "寿元不足 20% 进入天人五衰阶段")
	var prod_normal := float(gs.get_production_mult(0))
	_check(gs.begin_decay_continuation(), "选择继续修炼")
	_check(gs.decay_active, "衰败状态激活")
	var prod_decay := float(gs.get_production_mult(0))
	_check(is_equal_approx(prod_decay, prod_normal * (1.0 - BalanceConfig.DECAY_PRODUCTION_PENALTY)), "继续修炼生产 -50%")
	var p_t := int(gs.talent_points)
	var p_qi := float(gs.qi)
	var p_fate := float(gs.fate_permanent_production)
	var p_life := float(gs.lifespan_max_years)
	gs.fate_opportunity_at = Time.get_unix_time_from_system() - 1.0
	gs.update_world(0.1)
	var any_gift := int(gs.talent_points) != p_t or not is_equal_approx(float(gs.qi), p_qi) \
		or not is_equal_approx(float(gs.fate_permanent_production), p_fate) \
		or not is_equal_approx(float(gs.lifespan_max_years), p_life)
	_check(any_gift, "天命奇遇发放了奖励")
	_check(gs.fate_opportunity_at > Time.get_unix_time_from_system(), "奇遇计时重置")

	# 渡劫续命：三丹 + 灵石；成败两种结果都要可复现。
	var tribulation_succeeded := false
	var tribulation_failed := false
	randomize()
	for seed_index in range(60):
		seed(9000 + seed_index)
		gs.initialize_new_game()
		gs.lifespan_max_years = 80.0
		gs.lifespan_years = 10.0
		gs.spirit_stones = 100000.0
		gs.healing_pills = 1
		gs.resistance_pills = 1
		gs.enhancement_pills = 1
		var stones_before_attempt := float(gs.spirit_stones)
		var result: Dictionary = gs.attempt_lifespan_tribulation()
		if not bool(result.get("ok", false)):
			continue
		if bool(result.get("success", false)):
			tribulation_succeeded = true
			_check(is_equal_approx(float(gs.spirit_stones), stones_before_attempt - 80.0 * BalanceConfig.LIFESPAN_TRIBULATION_STONE_RATIO), "渡劫续命消耗当前境界寿元上限 20% 的灵石")
			_check(gs.healing_pills == 0 and gs.resistance_pills == 0 and gs.enhancement_pills == 0, "渡劫续命消耗三丹")
			_check(gs.lifespan_years >= 10.0 + BalanceConfig.LIFESPAN_TRIBULATION_SUCCESS_YEARS and not gs.is_decay_stage(), "续命成功寿元增加并解除衰败")
		else:
			tribulation_failed = true
			_check(gs.reincarnation_count == 1 and gs.pending_reincarnation_boon, "续命失败强制轮回并等待转世天赋")
		if tribulation_succeeded and tribulation_failed:
			break
	randomize()
	_check(tribulation_succeeded, "渡劫续命成功路径可复现")
	_check(tribulation_failed, "渡劫续命失败路径可复现")

	# 转世天赋倍率：青木神通（产量）、丹心（修为）。
	gs.initialize_new_game()
	gs.pending_reincarnation_boon = true
	var prod_no_boon := float(gs.get_production_mult(0))
	_check(gs.choose_reincarnation_boon("wood_spirit"), "选择青木神通")
	_check(is_equal_approx(float(gs.get_production_mult(0)), prod_no_boon * BalanceConfig.reincarnation_boon("wood_spirit").get("production_mult", 1.0)), "青木神通产量 +50%")
	gs.initialize_new_game()
	gs.pending_reincarnation_boon = true
	var cult_no_boon := float(gs.get_cultivation_mult())
	_check(gs.choose_reincarnation_boon("dan_heart"), "选择丹心")
	_check(is_equal_approx(float(gs.get_cultivation_mult()), cult_no_boon * BalanceConfig.reincarnation_boon("dan_heart").get("cultivation_mult", 1.0)), "丹心修为 +20%")

	# 宝箱奖励入账（直接注入奖励描述，验证 GameState 是唯一入账方）。
	gs.initialize_new_game()
	gs._apply_treasure_reward({"reward": {"kind": "stones", "amount": 100.0}})
	_check(is_equal_approx(float(gs.spirit_stones), 100.0), "木箱灵石入账")
	gs._apply_treasure_reward({"reward": {"kind": "qi", "amount": 200.0}})
	_check(is_equal_approx(float(gs.qi), 200.0), "宝箱灵气入账")
	gs._apply_treasure_reward({"reward": {"kind": "talent_points", "amount": 1}})
	_check(int(gs.talent_points) == 1, "玉箱天赋点入账")
	gs._apply_treasure_reward({"reward": {"kind": "permanent_production", "amount": BalanceConfig.TREASURE_IMMORTAL_PRODUCTION_BONUS}})
	_check(is_equal_approx(float(gs.treasure_production_bonus), BalanceConfig.TREASURE_IMMORTAL_PRODUCTION_BONUS), "仙箱永久生产加成入账")
	gs._apply_treasure_reward({"reward": {"kind": "lifespan_max", "amount": BalanceConfig.TREASURE_IMMORTAL_LIFESPAN_BONUS}})
	_check(is_equal_approx(float(gs.lifespan_max_years), 80.0 + BalanceConfig.TREASURE_IMMORTAL_LIFESPAN_BONUS), "仙箱寿元上限加成入账")
	gs._apply_treasure_reward({"reward": {"kind": "permanent_crit", "amount": BalanceConfig.TREASURE_IMMORTAL_CRIT_BONUS}})
	_check(is_equal_approx(float(gs.treasure_crit_bonus), BalanceConfig.TREASURE_IMMORTAL_CRIT_BONUS), "仙箱永久暴击加成入账")
	_check(is_equal_approx(float(gs.get_production_mult(0)), 1.0 + BalanceConfig.TREASURE_IMMORTAL_PRODUCTION_BONUS), "永久生产加成进入生产倍率")

	# 天命：宝箱概率 ×5，收获时能开出宝箱。
	gs.initialize_new_game()
	gs.pending_reincarnation_boon = true
	gs.choose_reincarnation_boon("heaven_fate")
	gs.realm_index = 0
	gs.season_index = 0
	gs.unlocked_fields = 1
	gs.fields[0]["crop_id"] = CROP_ID
	gs.fields[0]["tier"] = 0
	gs.insect_events[0] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": 9999999999.0}
	TreasureSystem.enabled = true
	var chest_found := false
	randomize()
	for seed_index in range(100):
		seed(9800 + seed_index)
		gs.fields[0]["ready_at"] = 0.0
		var harvest: Dictionary = gs.harvest_crop(0)
		if bool(harvest.get("treasure_found", false)):
			chest_found = true
			break
	randomize()
	TreasureSystem.enabled = false
	_check(chest_found, "天命转世天赋下收获可开出宝箱")

	# 古修洞府三选一。
	gs.initialize_new_game()
	gs.random_event = "ancient_cave"
	gs.random_event_until = Time.get_unix_time_from_system() + 60.0
	var cave_stones_before := float(gs.spirit_stones)
	_check(gs.resolve_ancient_cave("stones"), "古修洞府选择灵石")
	_check(is_equal_approx(float(gs.spirit_stones), cave_stones_before + BalanceConfig.ANCIENT_CAVE_STONES), "洞府灵石入账")
	_check(gs.random_event == "", "洞府选择后事件结束")
	_check(not gs.resolve_ancient_cave("stones"), "事件结束后不能再次选择")
	gs.random_event = "ancient_cave"
	gs.random_event_until = Time.get_unix_time_from_system() + 60.0
	var cave_talent_before := int(gs.talent_points)
	_check(gs.resolve_ancient_cave("talent"), "古修洞府选择天赋点")
	_check(int(gs.talent_points) == cave_talent_before + BalanceConfig.ANCIENT_CAVE_TALENT_POINTS, "洞府天赋点入账")
	gs.random_event = "ancient_cave"
	gs.random_event_until = Time.get_unix_time_from_system() + 60.0
	var cave_stones_before_2 := float(gs.spirit_stones)
	_check(gs.resolve_ancient_cave("treasure"), "古修洞府选择宝箱")
	_check(float(gs.spirit_stones) >= cave_stones_before_2, "宝箱选择至少给灵石保底")

	# 魔气侵染：生产减半 + 灵石净化。
	gs.initialize_new_game()
	gs.spirit_stones = 10000.0
	gs.random_event = "demon_qi"
	gs.random_event_until = Time.get_unix_time_from_system() + 60.0
	var normal_prod_2 := float(gs.get_production_mult(0))
	gs.update_world(0.05)
	var demon_prod := float(gs.get_production_mult(0))
	_check(is_equal_approx(demon_prod, normal_prod_2 * (1.0 - BalanceConfig.DEMON_QI_PRODUCTION_PENALTY)), "魔气侵染生产 -50%")
	_check(gs.purify_demon_qi(), "净化魔气")
	_check(is_equal_approx(float(gs.spirit_stones), 9000.0), "净化消耗当前灵石 10%")
	_check(gs.random_event == "", "净化后事件结束")
	gs.update_world(0.05)
	_check(is_equal_approx(float(gs.get_production_mult(0)), normal_prod_2), "净化后生产恢复")

	# 天降灵种：本世解锁紫芝。
	gs.initialize_new_game()
	gs.random_event = "heavenly_seed"
	gs.random_event_until = Time.get_unix_time_from_system() + 30.0
	gs.update_world(0.05)
	_check(gs.heavenly_seed_unlocked, "天降灵种解锁紫芝")
	_check(gs.get_crop_options().has(BalanceConfig.HEAVENLY_SEED_CROP), "本世可种植紫芝")

	# 噬金虫王：剑诀击杀额外虫尸并结束事件。
	gs.initialize_new_game()
	gs.realm_index = BalanceConfig.ADVANCED_COMBAT_REALM_INDEX
	gs.qi = 1000.0
	gs.random_event = "insect_king"
	gs.random_event_until = Time.get_unix_time_from_system() + 60.0
	gs.fields[0]["crop_id"] = CROP_ID
	gs.insect_events[0] = {"active": true, "attacks": 3, "pest_level": 2, "next_attack_at": 0.0}
	_check(gs.cast_gengjin_sword(0), "剑诀击杀噬金虫王")
	_check(gs.insect_corpses >= BalanceConfig.INSECT_KING_CORPSE_REWARD + 3, "虫王额外虫尸 ×10")
	_check(gs.random_event == "", "虫王击杀后事件结束")

	# 存档 v18 往返：新字段全部保留。
	gs.initialize_new_game()
	gs.decay_active = true
	gs.fate_opportunity_at = 12345.0
	gs.treasure_production_bonus = 0.1
	gs.treasure_crit_bonus = 0.05
	gs.fate_permanent_production = 0.02
	gs.broken_dan_experience = 0.3
	gs.tribulation_refine_bonus = 0.1
	gs.run_harvest_count = 777
	gs.run_random_event_count = 3
	gs.heavenly_seed_unlocked = true
	gs.reincarnation_boon = "wood_spirit"
	gs.pending_reincarnation_boon = false
	gs.lifespan_years = 50.0
	gs.lifespan_depleted = false
	_check(SaveManager.save_game(), "保存 v18 存档")
	gs.initialize_new_game()
	_check(SaveManager.load_game(), "加载 v18 存档")
	_check(gs.decay_active, "加载后保留衰败状态")
	_check(is_equal_approx(float(gs.fate_opportunity_at), 12345.0), "加载后保留奇遇计时")
	_check(is_equal_approx(float(gs.treasure_production_bonus), 0.1), "加载后保留永久生产加成")
	_check(is_equal_approx(float(gs.treasure_crit_bonus), 0.05), "加载后保留永久暴击加成")
	_check(is_equal_approx(float(gs.fate_permanent_production), 0.02), "加载后保留天命永久加成")
	_check(is_equal_approx(float(gs.broken_dan_experience), 0.3), "加载后保留碎丹经验")
	_check(is_equal_approx(float(gs.tribulation_refine_bonus), 0.1), "加载后保留雷劫淬体")
	_check(int(gs.run_harvest_count) == 777 and int(gs.run_random_event_count) == 3, "加载后保留本世计数")
	_check(gs.heavenly_seed_unlocked and gs.reincarnation_boon == "wood_spirit", "加载后保留本世解锁与转世天赋")


func _finish_tribulation_for_probe(gs: Node) -> void:
	if not gs.tribulation_active:
		return
	# 探针只验证流程：直接满足三道检查的条件后逐道结算。
	gs.qi = maxf(gs.qi, BalanceConfig.tribulation_qi_requirement(gs.tribulation_target_realm))
	gs.run_harvest_count = maxi(gs.run_harvest_count, BalanceConfig.TRIBULATION_CHECK_HARVEST_REQUIREMENT)
	gs.run_random_event_count = maxi(gs.run_random_event_count, 1)
	while gs.tribulation_active:
		gs.advance_tribulation()


func _grant_breakthrough_materials(gs: Node, target_realm: int) -> void:
	for requirement in gs.get_breakthrough_requirements(target_realm):
		var material_id := String(requirement.get("material_id", ""))
		# 按稳定突破的 1.5 倍需求发放，保证任何模式都能发起。
		gs.breakthrough_materials[material_id] = ceili(int(requirement.get("amount", 0)) * BalanceConfig.BREAKTHROUGH_STABLE_MATERIAL_MULT)
	# 探针默认稳定突破必成；碎丹测试单独重置经验。
	gs.broken_dan_experience = BalanceConfig.BROKEN_DAN_SUCCESS_CAP


func _check_achievements(gs: Node) -> void:
	print("=== 成就系统 ===")
	gs.initialize_new_game()
	gs.total_harvest_count = 100
	gs.total_cultivation_earned = 1000.0
	gs.realm_index = 1
	gs.unlocked_fields = 2
	gs.crop_proficiency["gathering_grass"] = 10
	gs.talent_nodes = {
		"root": true,
		"farming_start": true,
		"farming_yield": true,
		"farming_speed": true,
		"farming_capstone": true,
	}
	gs.emit_state_changed()
	_check(gs.achievements.has("first_harvest"), "首次收获成就自动解锁")
	_check(gs.achievements.has("harvest_100"), "收获次数成就自动解锁")
	_check(gs.achievements.has("cultivation_1000"), "累计修为成就自动解锁")
	_check(gs.achievements.has("reach_qi"), "境界成就自动解锁")
	_check(gs.achievements.has("buy_second_field"), "灵田成就自动解锁")
	_check(gs.achievements.has("grass_proficiency_10"), "熟练度成就自动解锁")
	_check(gs.achievements.has("talent_5"), "天赋节点成就自动解锁")
	var points_after_first_refresh: int = gs.achievement_points
	gs.emit_state_changed()
	_check(gs.achievement_points == points_after_first_refresh, "重复刷新不重复发放成就点")
	_check(gs.get_achievement_rows().size() == BalanceConfig.ACHIEVEMENTS.size(), "成就进度覆盖全部定义")
	gs.lifespan_depleted = true
	_check(gs.reincarnate_now(), "成就测试可立即轮回")
	_check(gs.achievements.has("first_new_run"), "开始新局成就自动解锁")
	_check(gs.achievement_points == points_after_first_refresh + 2, "新局成就点只发放一次")


# 狂暴丹：递进价格、buff 效果、购买次数与跨局保留。
func _check_frenzy_pill(gs: Node) -> void:
	var shop: ShopSystem = gs.shop
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 0), 100.0), "狂暴丹第 1 次价格 100")
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 1), 150.0), "狂暴丹第 2 次价格 150")
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 2), 230.0), "狂暴丹第 3 次价格 230（225 四舍五入到 10）")
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 3), 340.0), "狂暴丹第 4 次价格 340")
	_check(shop.get_cost("longevity_pill", 999) == 1000.0, "长生丹价格为 1000 灵石")
	_check(shop.get_cost("qi_jade", 999) == 1000.0, "聚气玉价格为 1000 灵石")
	gs.initialize_new_game()
	gs.spirit_stones = 100000.0
	var before_count := int(gs.shop_purchase_counts.get("frenzy_pill", 0))
	_check(gs.buy_shop_item("frenzy_pill"), "狂暴丹可购买")
	_check(is_equal_approx(float(gs.spirit_stones), 100000.0 - 100.0), "狂暴丹扣减 100 灵石")
	_check(int(gs.shop_purchase_counts.get("frenzy_pill", 0)) == before_count + 1, "狂暴丹购买次数 +1")
	_check(gs.is_active_buff(), "购买后狂暴 buff 生效")
	_check(is_equal_approx(float(gs.active_buff_mult), 3.0), "狂暴 buff 倍率 ×3")
	_check(gs.get_active_buff_remaining() > 4.0, "狂暴 buff 持续约 5 秒")
	gs.active_buff_until = 0.0
	gs.lifespan_depleted = true
	_check(not gs.buy_shop_item("frenzy_pill"), "大限期间不能购买狂暴丹")
	gs.lifespan_years = 0.0
	_check(gs.reincarnate_now(), "大限后立即轮回")
	_check(int(gs.shop_purchase_counts.get("frenzy_pill", 0)) == before_count + 1, "狂暴丹购买次数跨新局保留")
	gs.spirit_stones = 100000.0
	_check(is_equal_approx(shop.get_cost("frenzy_pill", before_count + 1), 150.0), "新局价格按累计购买次数递进")
	_check(gs.buy_shop_item("frenzy_pill"), "新局可继续购买狂暴丹")


# 元婴层级 / 紫芝 / 天赋扩展 / 幸运暴击 / 新成就。
func _check_expansion(gs: Node) -> void:
	_check(RealmConfig.realm_count() == 5, "境界扩展到 5 层")
	_check(is_equal_approx(float(BalanceConfig.REALMS[4].get("required_cultivation", 0.0)), 100000000.0), "元婴门槛 1 亿修为")
	_check(is_equal_approx(float(BalanceConfig.REALMS[4].get("production", 0.0)), 100.0), "元婴生产倍率 ×100")
	_check(is_equal_approx(float(BalanceConfig.LIFESPAN_YEARS_BY_REALM[4]), 3000.0), "元婴寿元 3000 年")
	_check(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM[4] == 31, "元婴突破 +31 天赋点")
	var yuanying_reqs: Array = gs.get_breakthrough_requirements(4)
	_check(yuanying_reqs.size() == 7, "元婴突破需要 7 种材料")
	var total_material_cost := 0.0
	for requirement in yuanying_reqs:
		var material: Variant = BalanceConfig.BREAKTHROUGH_MATERIALS.get(String(requirement.get("material_id", "")), {})
		total_material_cost += float(material.get("cost", 0.0)) if material is Dictionary else 0.0
	_check(is_equal_approx(total_material_cost, 14000000.0), "元婴材料总成本 1400 万灵石")
	_check(not CropConfig.get_unlocked(3).has("zi_zhi"), "金丹不解锁紫芝")
	_check(CropConfig.get_unlocked(4).has("zi_zhi"), "元婴解锁紫芝")
	_check(BalanceConfig.CROP_PROFICIENCY_REWARDS.has("zi_zhi"), "紫芝有熟练度表")
	var grand_mult: float = TalentTree.multiplier("production_mult", {
		"root": true, "farming_start": true, "farming_yield": true, "farming_speed": true,
		"farming_capstone": true, "farming_grand": true,
	})
	_check(is_equal_approx(grand_mult, 1.2 * 1.5 * 2.0), "丰收大道生产 ×2.0 生效")
	var crit_bonus: float = TalentTree.bonus("crit_chance", {"root": true, "luck_start": true, "luck_capstone": true})
	_check(is_equal_approx(crit_bonus, 0.15), "幸运系暴击率相加 15%")
	var rare_bonus: float = TalentTree.bonus("rare_crit_chance", {"root": true, "luck_start": true, "luck_crit": true, "luck_capstone": true})
	_check(is_equal_approx(rare_bonus, 0.35), "稀有暴击率相加 35%")
	var luck_nodes: Dictionary = {"root": true, "luck_start": true, "luck_wealth": true, "luck_crit": true, "luck_capstone": true}
	var luck_report: Dictionary = gs.get_simulation_report({
		"mode": "uniform", "realm_index": 0, "season_index": 0, "talent_nodes": luck_nodes,
		"crop_id": "gathering_grass", "tier": 0, "field_count": 1, "qi": 0.0,
		"event_prod_mult": BalanceConfig.DEFAULT_MULTIPLIER, "event_cult_mult": BalanceConfig.DEFAULT_MULTIPLIER,
		"buff_mult": BalanceConfig.DEFAULT_MULTIPLIER,
	})
	var luck_rep: Dictionary = luck_report.get("representative", {})
	var expected_crit := 1.0 + 0.15 * (BalanceConfig.LUCK_CRIT_MULT * 0.65 + BalanceConfig.LUCK_RARE_CRIT_MULT * 0.35)
	_check(is_equal_approx(float(luck_rep.get("expected_crit_mult", 0.0)), expected_crit), "模拟器暴击期望倍率正确")
	_check(is_equal_approx(float(luck_rep.get("expected_stones_mult", 0.0)), expected_crit + 0.10 * 0.5), "模拟器横财期望倍率正确")

	# 真实收获暴击：固定随机种子，统计 200 次收获的暴击/横财触发。
	gs.initialize_new_game()
	_set_talents(gs, ["root", "luck_start", "luck_wealth", "luck_crit", "luck_capstone"])
	gs.realm_index = 0
	gs.season_index = 0
	gs.lifespan_depleted = false
	gs.fields[0]["crop_id"] = "gathering_grass"
	gs.fields[0]["tier"] = 0
	gs.insect_events[0] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": 9999999999.0}
	var crit_before := int(gs.crit_count)
	var rare_before := int(gs.rare_crit_count)
	var windfall_before := int(gs.windfall_count)
	seed(20260809)
	var luck_total := 0.0
	for _i in range(200):
		gs.fields[0]["ready_at"] = 0.0
		luck_total += float(gs.harvest_crop(0).get("luck_mult", 1.0))
	_check(gs.crit_count > crit_before, "200 次收获触发过暴击")
	_check(gs.rare_crit_count > rare_before, "稀有暴击可触发")
	_check(gs.windfall_count > windfall_before, "天降横财可触发")
	var avg_luck := luck_total / 200.0
	_check(avg_luck > 1.3 and avg_luck < 1.7, "200 次收获平均暴击倍率在期望区间")
	_check(gs.achievements.has("crit_10"), "暴击成就自动解锁")

	# 新成就 metric：商店购买次数与全仙田。
	gs.initialize_new_game()
	gs.spirit_stones = 10000000.0
	for _i in range(10):
		gs.buy_shop_item("frenzy_pill")
	_check(gs.achievements.has("frenzy_pill_10"), "购买 10 次狂暴丹成就解锁")
	for field_index in range(BalanceConfig.FIELD_COUNT):
		gs.fields[field_index]["tier"] = BalanceConfig.FIELD_TIER_MULTS.size() - 1
	gs.emit_state_changed()
	_check(gs.achievements.has("field_all_immortal"), "三田全仙田成就解锁")
	_check(gs.get_achievement_rows().size() == BalanceConfig.ACHIEVEMENTS.size(), "成就表扩展到 36 项全部可见")


func _set_talents(gs: Node, node_ids: Array) -> void:
	gs.talent_nodes = {}
	for node_id in node_ids:
		gs.talent_nodes[String(node_id)] = true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failures += 1
