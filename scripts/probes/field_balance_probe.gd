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
		for tier in range(realm + 1):
			var result := _harvest_once(gs, 0, tier)
			var amount := float(result.get("amount", 0))
			var rate := amount * CROP_SELL_PRICE / CROP_GROWTH_SECONDS
			if tier >= realm:
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
			if tier == realm - 1:
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
			var tier := realm - 1
			var slot_rate := _sell_rate(gs, 0)
			var slot2_payback := float(gs.get_field_slot_cost(1).get("spirit_stones", 0.0)) / maxf(0.001, slot_rate)
			var slot3_payback := float(gs.get_field_slot_cost(2).get("spirit_stones", 0.0)) / maxf(0.001, slot_rate)
			var from_rate := _sell_rate(gs, tier)
			var to_rate := _sell_rate(gs, tier + 1)
			var cost := float(BalanceConfig.FIELD_TIER_UPGRADE_COSTS[tier].get("spirit_stones", 0.0))
			var payback := cost / maxf(0.001, to_rate - from_rate)
			payback_text.append("%d→%d %.1f秒，槽位 %.1f/%.1f秒" % [tier, tier + 1, payback, slot2_payback, slot3_payback])
			if profile_name == "farming_core":
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
			})
			var stage_text := PackedStringArray()
			for stage in breakthrough_flow.get("stages", []):
				stage_text.append("%s→%s %.2f秒" % [
					String(stage.get("from_realm_name", "")),
					String(stage.get("to_realm_name", "")),
					float(stage.get("duration_seconds", 0.0)),
				])
			print("profile=%s 田=%d 总耗时=%.2f秒 总点击=%d 阶段=%s 完成=%s" % [
				String(profile.get("id", "")),
				field_count,
				float(breakthrough_flow.get("total_seconds", 0.0)),
				int(breakthrough_flow.get("total_clicks", 0)),
				" / ".join(stage_text),
				str(bool(breakthrough_flow.get("completed", false))),
			])
			_check(bool(breakthrough_flow.get("completed", false)), "4次/秒突破模拟完成：%s / %d块" % [String(profile.get("id", "")), field_count])
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
	})
	print("root 3块田切换为每块独立 4次/秒：总耗时=%.2f秒" % float(per_field_flow.get("total_seconds", 0.0)))
	_check(bool(per_field_flow.get("completed", false)), "每块灵田独立点击模式完成突破")

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
		expected_full_rows += CropConfig.get_unlocked(realm).size() * BalanceConfig.SEASONS.size() * SimulationSystem.talent_profiles(gs).size() * gs.fields.size() * (realm + 1)
	_check(realm_rows.size() == RealmConfig.realm_count() * gs.fields.size(), "境界矩阵覆盖全部境界和田数")
	_check(crop_rows.size() == CropConfig.get_unlocked(max_realm).size(), "作物矩阵覆盖金丹全部作物")
	_check(season_rows.size() == BalanceConfig.SEASONS.size(), "四季矩阵覆盖全部时节")
	_check(talent_rows.size() == SimulationSystem.talent_profiles(gs).size(), "天赋矩阵读取天赋树预设")
	_check(event_rows.size() == SimulationSystem.event_profiles(gs).size(), "事件矩阵覆盖全部事件")
	_check(progression_rows.size() == RealmConfig.realm_count(), "境界总表覆盖全部境界")
	_check(breakthrough_rows.size() == 1 and bool(breakthrough_rows[0].get("completed", false)), "突破流程矩阵完成从凡人到金丹")
	_check(proficiency_rows.size() == CropConfig.get_all().size() * (BalanceConfig.CROP_PROFICIENCY_THRESHOLDS.size() + 1), "熟练度矩阵覆盖全部作物和档位")
	_check(full_rows.size() == expected_full_rows, "全量核心矩阵覆盖境界/作物/四季/天赋/田数/档位")
	_check_section_one(gs)
	_check_achievements(gs)
	_check_frenzy_pill(gs)
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


func _check_section_one(gs: Node) -> void:
	print("=== 第 1 节数值规则 ===")
	_check(is_equal_approx(float(BalanceConfig.LIFESPAN_DECAY_PER_SECOND), 0.5), "寿元衰减为 0.5 年/秒")
	_check(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM == [0, 3, 7, 15], "突破天赋点表为 [0,3,7,15]")
	_check(is_equal_approx(60.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 120.0), "凡人一轮寿元为 2 分钟")
	_check(is_equal_approx(120.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 240.0), "炼气一轮寿元为 4 分钟")
	_check(is_equal_approx(200.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 400.0), "筑基一轮寿元约 6.7 分钟")
	_check(is_equal_approx(500.0 / BalanceConfig.LIFESPAN_DECAY_PER_SECOND, 1000.0), "金丹一轮寿元约 16.7 分钟")

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
	_check(BalanceConfig.CROP_PROFICIENCY_TOTAL_TALENT_POINTS == 44, "四种作物熟练度天赋点总计 44")
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
		var before: int = gs.talent_points
		_check(gs.breakthrough(), "实际突破到 %s" % String(BalanceConfig.REALMS[realm].get("name", "")))
		breakthrough_points.append(gs.talent_points - before)
	_check(breakthrough_points == [3, 7, 15], "实际突破发放 3/7/15 点")
	_check(gs.promotion_count == 3, "实际突破累计晋级次数")

	gs.initialize_new_game()
	gs.crop_proficiency["gathering_grass"] = 400
	gs.total_harvest_count = 400
	gs.promotion_count = 2
	gs.lifespan_depleted = true
	_check(gs.start_new_run(), "大限后可以开始新局")
	_check(gs.reincarnation_count == 1, "开始新局增加轮回次数")
	_check(int(gs.crop_proficiency.get("gathering_grass", 0)) == 400, "开始新局保留作物熟练度")
	_check(gs.total_harvest_count == 400 and gs.promotion_count == 2, "开始新局保留长期计数")

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
	_check(gs.start_new_run(), "成就测试可开始新局")
	_check(gs.achievements.has("first_new_run"), "开始新局成就自动解锁")
	_check(gs.achievement_points == points_after_first_refresh + 2, "新局成就点只发放一次")


# 狂暴丹：递进价格、buff 效果、购买次数与跨局保留。
func _check_frenzy_pill(gs: Node) -> void:
	var shop: ShopSystem = gs.shop
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 0), 100.0), "狂暴丹第 1 次价格 100")
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 1), 150.0), "狂暴丹第 2 次价格 150")
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 2), 230.0), "狂暴丹第 3 次价格 230（225 四舍五入到 10）")
	_check(is_equal_approx(shop.get_cost("frenzy_pill", 3), 340.0), "狂暴丹第 4 次价格 340")
	_check(shop.get_cost("longevity_pill", 999) == 100.0, "固定价格商品不受购买次数影响")
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
	_check(gs.start_new_run(), "大限后开始新局")
	_check(int(gs.shop_purchase_counts.get("frenzy_pill", 0)) == before_count + 1, "狂暴丹购买次数跨新局保留")
	gs.spirit_stones = 100000.0
	_check(is_equal_approx(shop.get_cost("frenzy_pill", before_count + 1), 150.0), "新局价格按累计购买次数递进")
	_check(gs.buy_shop_item("frenzy_pill"), "新局可继续购买狂暴丹")


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
