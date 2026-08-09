## SimulationSystem
##
## 游戏内数值模拟的唯一计算入口。
##
## 这个模块不保存一份“模拟专用数值”。调用方必须传入 GameState，所有境界、
## 作物、灵田、天赋、季节、事件和自动化参数都从现有模型读取。GameState 的
## 实际收获结算也通过这里计算，避免面板模拟和真实游戏各算一套。
class_name SimulationSystem
extends RefCounted


const MODE_LIVE := "live"
const MODE_UNIFORM := "uniform"


## 下面这些是实时游戏和模拟场景共用的倍率接口。
## GameState 的查询方法也委托到这里，保证 UI、实际结算和模拟不会各自连乘。
static func live_production_multiplier(source: Node, field_index: int) -> float:
	var scenario := _scenario(source, {"mode": MODE_UNIFORM})
	var tier := 0
	if field_index >= 0 and field_index < source.fields.size():
		tier = int(source.fields[field_index].get("tier", 0))
	return production_multiplier(source, scenario, tier)


static func live_cultivation_multiplier(source: Node) -> float:
	var scenario := _scenario(source, {"mode": MODE_UNIFORM})
	return cultivation_multiplier(scenario)


static func live_qi_harvest_multiplier(source: Node) -> float:
	var scenario := _scenario(source, {"mode": MODE_UNIFORM})
	return qi_harvest_multiplier(source, float(scenario.get("qi", 0.0)), scenario.get("talent_nodes", {}))


static func live_click_accel_seconds(source: Node) -> float:
	return click_accel_seconds(source, source.talent_nodes)


static func live_growth_multiplier(source: Node, field_index: int) -> float:
	var scenario := _scenario(source, {"mode": MODE_UNIFORM})
	var rain_active := false
	if field_index >= 0 and source.has_method("is_spirit_rain_active"):
		rain_active = bool(source.is_spirit_rain_active(field_index))
	return growth_multiplier(source, scenario, rain_active)


static func live_crop_growth_seconds(source: Node, field_index: int, crop_id: String) -> float:
	var scenario := _scenario(source, {"mode": MODE_UNIFORM})
	var rain_active := false
	if field_index >= 0 and source.has_method("is_spirit_rain_active"):
		rain_active = bool(source.is_spirit_rain_active(field_index))
	return crop_growth_seconds(source, scenario, crop_id, rain_active)


static func live_lifespan_decay_per_second(source: Node) -> float:
	return lifespan_decay_per_second(source, source.talent_nodes)


static func lifespan_decay_per_second(source: Node, talent_nodes: Dictionary) -> float:
	return float(BalanceConfig.LIFESPAN_DECAY_PER_SECOND) * TalentTree.multiplier("lifespan_decay_mult", talent_nodes)


static func production_multiplier(source: Node, scenario: Dictionary, tier: int) -> float:
	var safe_realm := clampi(int(scenario.get("realm_index", 0)), 0, RealmConfig.realm_count() - 1)
	var safe_tier := clampi(tier, 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	var talent_nodes: Dictionary = scenario.get("talent_nodes", {"root": true})
	return MultiplierStack.production(
		safe_realm,
		TalentTree.multiplier("production_mult", talent_nodes),
		float(BalanceConfig.FIELD_TIER_MULTS[safe_tier]),
		maxf(0.0, float(scenario.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		maxf(0.0, float(scenario.get("buff_mult", BalanceConfig.DEFAULT_MULTIPLIER)))
	)


static func cultivation_multiplier(scenario: Dictionary) -> float:
	var realm := clampi(int(scenario.get("realm_index", 0)), 0, RealmConfig.realm_count() - 1)
	var talent_nodes: Dictionary = scenario.get("talent_nodes", {"root": true})
	return MultiplierStack.cultivation(
		realm,
		TalentTree.multiplier("cultivation_mult", talent_nodes),
		maxf(0.0, float(scenario.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		BalanceConfig.DEFAULT_MULTIPLIER
	)


static func growth_multiplier(source: Node, scenario: Dictionary, spirit_rain_active: bool) -> float:
	var season_index := clampi(int(scenario.get("season_index", 0)), 0, BalanceConfig.SEASONS.size() - 1)
	var talent_nodes: Dictionary = scenario.get("talent_nodes", {"root": true})
	var multiplier := float(BalanceConfig.SEASONS[season_index].get("growth", BalanceConfig.DEFAULT_MULTIPLIER))
	multiplier *= TalentTree.multiplier("growth_mult", talent_nodes)
	if spirit_rain_active:
		multiplier *= BalanceConfig.SPIRIT_RAIN_GROWTH_MULT
	return multiplier


static func crop_growth_seconds(source: Node, scenario: Dictionary, crop_id: String, spirit_rain_active: bool) -> float:
	var proficiency: Dictionary = scenario.get("crop_proficiency", {})
	var harvest_count := int(proficiency.get(crop_id, 0))
	var base_seconds := BalanceConfig.crop_base_growth_seconds(crop_id, harvest_count)
	if base_seconds <= 0.0:
		return 0.0
	return maxf(0.001, base_seconds / maxf(0.001, growth_multiplier(source, scenario, spirit_rain_active)))


static func click_accel_seconds(source: Node, talent_nodes: Dictionary) -> float:
	return float(BalanceConfig.CLICK_ACCEL_BASE_SECONDS) * TalentTree.multiplier("click_accel_mult", talent_nodes)


static func qi_harvest_multiplier(source: Node, qi: float, talent_nodes: Dictionary) -> float:
	var steps := floorf(maxf(0.0, qi) / float(BalanceConfig.QI_HARVEST_STEP))
	var stock_mult := minf(float(BalanceConfig.QI_HARVEST_BASE_CAP), BalanceConfig.DEFAULT_MULTIPLIER + steps * float(BalanceConfig.QI_HARVEST_BONUS_PER_STEP))
	var talent_mult := TalentTree.multiplier("qi_harvest_mult", talent_nodes)
	return BalanceConfig.DEFAULT_MULTIPLIER + (stock_mult - BalanceConfig.DEFAULT_MULTIPLIER) * talent_mult


## 根据当前 GameState 建立一个不修改原状态的场景报告。
## options 可覆盖 realm_index / talent_nodes / season_index / crop_id / tier /
## field_count / qi / event_prod_mult / event_cult_mult / buff_mult /
## spirit_rain_active / pest_level / auto_cultivation_enabled。
static func report(source: Node, options: Dictionary = {}) -> Dictionary:
	var scenario := _scenario(source, options)
	var field_results: Array = []
	var field_specs: Array = scenario.get("field_specs", [])
	for spec in field_specs:
		var active := bool(spec.get("active", true))
		if not active:
			field_results.append(_empty_field_result(int(spec.get("field_index", field_results.size()))))
			continue
		field_results.append(field_result(
			source,
			scenario,
			String(spec.get("crop_id", scenario.get("crop_id", ""))),
			int(spec.get("tier", scenario.get("tier", 0))),
			int(spec.get("field_index", field_results.size())),
			int(spec.get("pest_level", scenario.get("pest_level", 0))),
			bool(spec.get("spirit_rain_active", scenario.get("spirit_rain_active", false)))
		))

	var total_stones_per_sec := 0.0
	var total_cultivation_per_sec := 0.0
	var total_qi_per_sec := 0.0
	var total_harvest_per_cycle := 0
	var active_fields := 0
	var density_fields: Array = []
	for result in field_results:
		var density_field := {
			"crop_id": String(result.get("crop_id", "")) if bool(result.get("active", false)) else "",
			"tier": int(result.get("tier", 0)),
		}
		density_fields.append(density_field)
		if not bool(result.get("active", false)):
			continue
		active_fields += 1
		total_stones_per_sec += float(result.get("spirit_stones_per_sec", 0.0))
		total_cultivation_per_sec += float(result.get("cultivation_per_sec", 0.0))
		total_qi_per_sec += float(result.get("qi_per_sec", 0.0))
		total_harvest_per_cycle += int(result.get("amount", 0))
	var density := AutomationSystem.compute_qi_density(density_fields, density_fields.size())

	var auto_rates := _auto_rates(source, scenario, density)
	var representative := _representative_field(source, scenario, field_results)
	var slot_rows := _slot_rows(source, scenario, representative)
	var upgrade_rows := _upgrade_rows(source, scenario, representative)
	var offline_settlement := _offline_report(source, scenario, density)
	var tribulation: Dictionary = {}
	if source.has_method("get_tribulation_status"):
		tribulation = source.get_tribulation_status()

	return {
		"scenario": scenario,
		"fields": field_results,
		"active_fields": active_fields,
		"total_harvest_per_cycle": total_harvest_per_cycle,
		"total_spirit_stones_per_sec": total_stones_per_sec,
		"total_cultivation_per_sec": total_cultivation_per_sec,
		"total_qi_per_sec": total_qi_per_sec,
		"qi_density": density,
		"auto_rates": auto_rates,
		"representative": representative,
		"slot_rows": slot_rows,
		"upgrade_rows": upgrade_rows,
		"offline_settlement": offline_settlement,
		"tribulation": tribulation,
		"click": _click_report(source, scenario, representative),
		"multipliers": _multiplier_report(source, scenario, representative),
	}


## 返回某次突破需要的商店材料状态；真实库存来自 GameState，场景模拟可传入覆盖库存。
static func breakthrough_material_report(source: Node, target_realm: int, inventory: Dictionary = {}) -> Dictionary:
	var stock: Dictionary = {}
	if source.get("breakthrough_materials") is Dictionary:
		stock = source.breakthrough_materials.duplicate(true)
	if not inventory.is_empty():
		stock = inventory.duplicate(true)
	var rows: Array[Dictionary] = []
	var ready := true
	var total_cost := 0.0
	var configured: Variant = BalanceConfig.BREAKTHROUGH_REQUIREMENTS.get(target_realm, [])
	if configured is Array:
		for requirement in configured:
			if not requirement is Dictionary:
				continue
			var material_id := String(requirement.get("material_id", ""))
			var required_amount := maxi(0, int(requirement.get("amount", 0)))
			var owned_amount := maxi(0, int(stock.get(material_id, 0)))
			var material: Variant = BalanceConfig.BREAKTHROUGH_MATERIALS.get(material_id, {})
			var material_name := material_id if not material is Dictionary else String(material.get("name", material_id))
			var unit_cost := float(material.get("cost", 0.0)) if material is Dictionary else 0.0
			var missing_amount := maxi(0, required_amount - owned_amount)
			if missing_amount > 0:
				ready = false
			total_cost += float(missing_amount) * unit_cost
			rows.append({
				"material_id": material_id,
				"material_name": material_name,
				"required": required_amount,
				"owned": owned_amount,
				"missing": missing_amount,
				"unit_cost": unit_cost,
			})
	return {
		"target_realm": target_realm,
		"ready": ready,
		"total_shop_cost": total_cost,
		"rows": rows,
	}


## 按玩家点击频率模拟“种植 → 收获直接获得修为和灵石 → 材料校验 → 突破”的完整流程。
## 默认把 clicks_per_second 视为玩家全局点击频率，click_scope=per_field 时才按每块
## 启用灵田独立计算。灵田收获不产生灵气；自动修炼的灵气仍按独立规则结算。
## 默认点击频率来自 BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND。
static func simulate_breakthrough_flow(source: Node, options: Dictionary = {}) -> Dictionary:
	if bool(options.get("maximize_progression", false)):
		return _simulate_maximized_breakthrough_flow(source, options)
	var max_realm := RealmConfig.realm_count() - 1
	var start_realm := clampi(
		int(options.get("start_realm", options.get("realm_index", source.realm_index))),
		0,
		max_realm
	)
	var target_realm := clampi(
		int(options.get("target_realm", max_realm)),
		start_realm,
		max_realm
	)
	var click_rate := maxf(0.0, float(options.get("clicks_per_second", BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND)))
	var click_scope := String(options.get("click_scope", "global"))
	if click_scope != "per_field":
		click_scope = "global"
	var field_count := clampi(int(options.get("field_count", source.unlocked_fields)), 1, source.fields.size())
	var tier := clampi(int(options.get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	# 模拟器默认按真实突破规则校验材料和渡劫丹药。做平衡估算时必须显式关闭
	# 对应门槛，结果会标记为 estimate，避免把“假设能过”显示成真实完成。
	var enforce_material_gate := bool(options.get("enforce_breakthrough_materials", true))
	var include_tribulation := bool(options.get("include_tribulation", true))
	var enforce_tribulation_supplies := bool(options.get("enforce_tribulation_supplies", true))
	var auto_use_tribulation_pills := bool(options.get("auto_use_tribulation_pills", true))
	var flow_is_actual := enforce_material_gate and (not include_tribulation or enforce_tribulation_supplies)
	var talent_nodes := _timeline_talent_nodes(source, options)
	var model := {
		"clicks_per_second": click_rate,
		"click_scope": click_scope,
		"field_count": field_count,
		"tier": tier,
		"crop_id": String(options.get("crop_id", "")),
		"talent_nodes": talent_nodes,
		"season_index": clampi(int(options.get("season_index", source.season_index)), 0, BalanceConfig.SEASONS.size() - 1),
		"event_prod_mult": maxf(0.0, float(options.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		"event_cult_mult": maxf(0.0, float(options.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		"buff_mult": maxf(0.0, float(options.get("buff_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		"spirit_rain_active": bool(options.get("spirit_rain_active", false)),
		"pest_level": maxi(0, int(options.get("pest_level", BalanceConfig.DEFAULT_PEST_LEVEL))),
		"include_auto_cultivation": bool(options.get("include_auto_cultivation", true)),
		"include_tribulation": include_tribulation,
		"realm_index": start_realm,
	}
	var start_cultivation := maxf(0.0, float(options.get("start_cultivation", source.cultivation)))
	var start_total_cultivation := maxf(
		start_cultivation,
		float(options.get("start_total_cultivation_earned", source.total_cultivation_earned))
	)
	var initial_points := maxi(0, int(options.get("tribulation_talent_points", source.talent_points)))
	var initial_spent_points := _talent_nodes_cost(talent_nodes)
	var source_earned_points := int(source.get("talent_points_earned")) if source.get("talent_points_earned") != null else initial_points + initial_spent_points
	var initial_earned_points := maxi(
		initial_points + initial_spent_points,
		int(options.get("start_talent_points_earned", source_earned_points))
	)
	var state := {
		"seconds": 0.0,
		"cultivation": start_cultivation,
		"total_cultivation_earned": start_total_cultivation,
		"talent_milestone_index": clampi(
			int(options.get("start_talent_milestone_index", source.talent_milestone_index)),
			0,
			BalanceConfig.TALENT_MILESTONES.size()
		),
		"spirit_stones": maxf(0.0, float(options.get("start_spirit_stones", source.spirit_stones))),
		"qi": maxf(0.0, float(options.get("start_qi", source.qi))),
		"harvest_cycles": 0,
		"clicks": 0,
		"auto_cultivation": 0.0,
		"auto_qi": 0.0,
		"harvested": {},
		"crop_proficiency": source.crop_proficiency.duplicate(true),
		"breakthrough_materials": source.breakthrough_materials.duplicate(true),
		"talent_points": initial_points,
		"talent_points_earned": initial_earned_points,
		"healing_pills": maxi(0, int(options.get("start_healing_pills", source.get("healing_pills")))),
		"resistance_pills": maxi(0, int(options.get("start_resistance_pills", source.get("resistance_pills")))),
		"enhancement_pills": maxi(0, int(options.get("start_enhancement_pills", source.get("enhancement_pills")))),
		"total_harvest_count": 0,
		"tribulation_seconds": 0.0,
		"tribulation_strikes": 0,
	}
	if options.get("start_breakthrough_materials", {}) is Dictionary and not (options.get("start_breakthrough_materials", {}) as Dictionary).is_empty():
		state["breakthrough_materials"] = (options.get("start_breakthrough_materials", {}) as Dictionary).duplicate(true)
	_award_simulated_milestones(state)
	var stages: Array = []
	var blocked_reason := ""

	for realm in range(start_realm, target_realm):
		model["realm_index"] = realm
		var required_cultivation := float(BalanceConfig.REALMS[realm + 1].get("required_cultivation", 0.0))
		var stage_start_seconds := float(state.get("seconds", 0.0))
		var cultivation_before := float(state.get("cultivation", 0.0))
		var harvest_cycles_before := int(state.get("harvest_cycles", 0))
		var clicks_before := int(state.get("clicks", 0))
		var auto_cultivation_before := float(state.get("auto_cultivation", 0.0))
		var auto_qi_before := float(state.get("auto_qi", 0.0))
		var crop_id := _timeline_crop(source, state, model, realm)
		var preview := _timeline_preview(source, state, model, crop_id)
		var stage := {
			"from_realm": realm,
			"to_realm": realm + 1,
			"from_realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
			"to_realm_name": String(BalanceConfig.REALMS[realm + 1].get("name", "")),
			"required_cultivation": required_cultivation,
			"cultivation_before": cultivation_before,
			"crop_id": crop_id,
			"crop_name": String(preview.get("crop_name", crop_id)),
			"cultivation_per_cycle": float(preview.get("cultivation_gain", 0.0)) * float(field_count),
			"spirit_stones_per_cycle": float(preview.get("spirit_stones_per_cycle", 0.0)) * float(field_count),
			"harvest_cycles": 0,
			"clicks": 0,
			"tribulation_name": "—",
			"tribulation_strikes": 0,
			"tribulation_seconds": 0.0,
			"talent_points_before_tribulation": int(state.get("talent_points", 0)),
			"talent_points_earned_before_tribulation": int(state.get("talent_points_earned", 0)),
		}
		var material_report := breakthrough_material_report(source, realm + 1, state.get("breakthrough_materials", {}))
		stage["breakthrough_materials"] = material_report.get("rows", [])
		stage["materials_ready"] = bool(material_report.get("ready", false))
		stage["material_shop_cost"] = float(material_report.get("total_shop_cost", 0.0))

		if enforce_material_gate and not bool(material_report.get("ready", false)):
			blocked_reason = "突破材料不足"
		elif crop_id == "" or not bool(preview.get("active", false)):
			blocked_reason = "当前境界没有可用灵植"
		elif float(preview.get("cultivation_gain", 0.0)) <= 0.0:
			blocked_reason = "灵植没有有效修为产出"
		else:
			while float(state.get("cultivation", 0.0)) < required_cultivation:
				var cycle := _timeline_harvest_cycle(source, state, model, crop_id)
				if not bool(cycle.get("ok", false)):
					blocked_reason = String(cycle.get("reason", "收获模拟失败"))
					break

		# 突破成功后还要完整经历天劫；天劫档位按累计获得点数读取，
		# 模拟完成一段后再把该境界的突破天赋点加入下一段。
		if blocked_reason == "" and float(state.get("cultivation", 0.0)) >= required_cultivation:
			stage["talent_points_before_tribulation"] = int(state.get("talent_points", 0))
			stage["talent_points_earned_before_tribulation"] = int(state.get("talent_points_earned", 0))
			if include_tribulation:
				var tribulation_strikes := BalanceConfig.tribulation_strikes_for_talent(int(state.get("talent_points_earned", 0)))
				var tribulation_report := _simulate_tribulation(state, tribulation_strikes, auto_use_tribulation_pills)
				var tribulation_success := bool(tribulation_report.get("success", false))
				var elapsed_strikes := tribulation_strikes if tribulation_success or not enforce_tribulation_supplies else int(tribulation_report.get("resolved_strikes", 0))
				var tribulation_seconds := float(elapsed_strikes) * BalanceConfig.TRIBULATION_INTERVAL_SECONDS
				state["seconds"] = float(state.get("seconds", 0.0)) + tribulation_seconds
				state["tribulation_seconds"] = float(state.get("tribulation_seconds", 0.0)) + tribulation_seconds
				state["tribulation_strikes"] = int(state.get("tribulation_strikes", 0)) + elapsed_strikes
				stage["tribulation_name"] = _tribulation_name(tribulation_strikes)
				stage["tribulation_strikes"] = elapsed_strikes
				stage["tribulation_seconds"] = tribulation_seconds
				stage["tribulation_total_strikes"] = tribulation_strikes
				stage["tribulation_success"] = tribulation_success
				stage["tribulation_supplies_ready"] = tribulation_success
				stage["tribulation_assumed_success"] = not enforce_tribulation_supplies
				stage["tribulation_estimate_only"] = not enforce_tribulation_supplies
				stage["tribulation_failed_strike"] = int(tribulation_report.get("failed_strike", 0))
				stage["tribulation_used_healing_pills"] = int(tribulation_report.get("used_healing_pills", 0))
				stage["tribulation_used_resistance_pills"] = int(tribulation_report.get("used_resistance_pills", 0))
				stage["tribulation_used_enhancement_pills"] = int(tribulation_report.get("used_enhancement_pills", 0))
				stage["tribulation_recommended_healing_pills"] = int(tribulation_report.get("recommended_healing_pills", 0))
				if enforce_tribulation_supplies and not tribulation_success:
					blocked_reason = "渡劫丹药不足"
			var reward_index := mini(realm + 1, BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM.size() - 1)
			if blocked_reason == "" or not enforce_tribulation_supplies:
				_add_simulated_talent_points(state, int(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM[reward_index]))

		stage["talent_points_after_tribulation"] = int(state.get("talent_points", 0))
		stage["talent_points_earned_after_tribulation"] = int(state.get("talent_points_earned", 0))

		stage["harvest_cycles"] = int(state.get("harvest_cycles", 0)) - harvest_cycles_before
		stage["clicks"] = int(state.get("clicks", 0)) - clicks_before
		stage["seconds"] = float(state.get("seconds", 0.0)) - stage_start_seconds
		stage["duration_seconds"] = stage["seconds"]
		stage["cultivation_seconds"] = stage["seconds"] - float(stage.get("tribulation_seconds", 0.0))
		stage["cultivation_after"] = float(state.get("cultivation", 0.0))
		stage["spirit_stones_after"] = float(state.get("spirit_stones", 0.0))
		stage["qi_after"] = float(state.get("qi", 0.0))
		stage["auto_cultivation"] = float(state.get("auto_cultivation", 0.0)) - auto_cultivation_before
		stage["auto_qi"] = float(state.get("auto_qi", 0.0)) - auto_qi_before
		stage["estimated_completed"] = blocked_reason == "" and float(state.get("cultivation", 0.0)) >= required_cultivation
		stage["completed"] = flow_is_actual and bool(stage["estimated_completed"])
		stage["completion_mode"] = "actual" if flow_is_actual else "estimate"
		if bool(stage["estimated_completed"]) and enforce_material_gate:
			_consume_simulated_breakthrough_materials(state, realm + 1)
		stages.append(stage)
		if blocked_reason != "":
			break

	var estimated_completed := blocked_reason == "" and target_realm <= start_realm + stages.size()
	var completed := flow_is_actual and estimated_completed
	var materials_ready := true
	var material_shop_cost := 0.0
	var tribulation_supplies_ready := true
	for stage in stages:
		materials_ready = materials_ready and bool(stage.get("materials_ready", true))
		material_shop_cost += float(stage.get("material_shop_cost", 0.0))
		tribulation_supplies_ready = tribulation_supplies_ready and bool(stage.get("tribulation_supplies_ready", true))
	return {
		"completed": completed,
		"estimated_completed": estimated_completed,
		"completion_mode": "actual" if flow_is_actual else "estimate",
		"blocked_reason": blocked_reason,
		"start_realm": start_realm,
		"target_realm": target_realm,
		"start_realm_name": String(BalanceConfig.REALMS[start_realm].get("name", "")),
		"target_realm_name": String(BalanceConfig.REALMS[target_realm].get("name", "")),
		"clicks_per_second": click_rate,
		"click_scope": click_scope,
		"click_mode": "每块灵田独立点击" if click_scope == "per_field" else "全局共用点击频率",
		"field_count": field_count,
		"tier": tier,
		"enforce_breakthrough_materials": enforce_material_gate,
		"breakthrough_materials_ready": materials_ready,
		"breakthrough_material_shop_cost": material_shop_cost,
		"enforce_tribulation_supplies": enforce_tribulation_supplies,
		"tribulation_supplies_ready": tribulation_supplies_ready,
		"season_index": int(model.get("season_index", 0)),
		"season_name": String(BalanceConfig.SEASONS[int(model.get("season_index", 0))].get("name", "")),
		"talent_nodes": talent_nodes,
		"talent_points": int(state.get("talent_points", 0)),
		"talent_points_earned": int(state.get("talent_points_earned", 0)),
		"talent_points_spent": _talent_nodes_cost(talent_nodes),
		"total_seconds": float(state.get("seconds", 0.0)),
		"total_clicks": int(state.get("clicks", 0)),
		"final_cultivation": float(state.get("cultivation", 0.0)),
		"final_spirit_stones": float(state.get("spirit_stones", 0.0)),
		"final_qi": float(state.get("qi", 0.0)),
		"harvest_cycles": int(state.get("harvest_cycles", 0)),
		"total_harvest_count": int(state.get("total_harvest_count", 0)),
		"tribulation_seconds": float(state.get("tribulation_seconds", 0.0)),
		"tribulation_strikes": int(state.get("tribulation_strikes", 0)),
		"tribulation_talent_points": int(state.get("talent_points", 0)),
		"tribulation_talent_points_earned": int(state.get("talent_points_earned", 0)),
		"total_cultivation_earned": float(state.get("total_cultivation_earned", 0.0)),
		"talent_milestone_index": int(state.get("talent_milestone_index", 0)),
		"auto_cultivation": float(state.get("auto_cultivation", 0.0)),
		"auto_qi": float(state.get("auto_qi", 0.0)),
		"harvested": state.get("harvested", {}),
		"crop_proficiency": state.get("crop_proficiency", {}),
		"breakthrough_materials": state.get("breakthrough_materials", {}),
		"stages": stages,
		"cultivation_mode": "灵田收获直接结算修为",
		"tribulation_mode": "材料齐备后开始天劫；完成全部劫数才进入下一境界",
		"include_tribulation": include_tribulation,
		"auto_use_tribulation_pills": auto_use_tribulation_pills,
	}


## 最大化流程：把模拟当成一个真实玩家的自动决策过程。
##
## 每次收获后立即处理熟练度/里程碑天赋点，按当前境界的修为收益选择可用节点；
## 灵石先保证寿元、突破材料和渡劫物资，再购买能实际提高收获数量的聚气玉。
## 这条路径仍然只读取 BalanceConfig、TalentTree、ShopSystem 和现有收获公式，
## 不维护一套模拟专用数值。
static func _simulate_maximized_breakthrough_flow(source: Node, options: Dictionary) -> Dictionary:
	var max_realm := RealmConfig.realm_count() - 1
	var start_realm := clampi(
		int(options.get("start_realm", options.get("realm_index", source.realm_index))),
		0,
		max_realm
	)
	var target_realm := clampi(
		int(options.get("target_realm", max_realm)),
		start_realm,
		max_realm
	)
	var click_rate := maxf(0.0, float(options.get("clicks_per_second", BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND)))
	var click_scope := String(options.get("click_scope", "global"))
	if click_scope != "per_field":
		click_scope = "global"
	var field_count := clampi(int(options.get("field_count", source.unlocked_fields)), 1, source.fields.size())
	var tier := clampi(int(options.get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	var include_tribulation := bool(options.get("include_tribulation", true))
	var enforce_material_gate := bool(options.get("enforce_breakthrough_materials", true))
	var enforce_tribulation_supplies := bool(options.get("enforce_tribulation_supplies", true))
	var auto_buy_resources := bool(options.get("auto_buy_shop_resources", true))
	var auto_use_tribulation_pills := bool(options.get("auto_use_tribulation_pills", true))
	var flow_is_actual := enforce_material_gate and (not include_tribulation or enforce_tribulation_supplies)

	var talent_nodes := _timeline_talent_nodes(source, options)
	var initial_points := maxi(0, int(options.get("tribulation_talent_points", source.talent_points)))
	var initial_spent_points := _talent_nodes_cost(talent_nodes)
	var source_earned_points := int(source.get("talent_points_earned")) if source.get("talent_points_earned") != null else initial_points + initial_spent_points
	var initial_earned_points := maxi(
		initial_points + initial_spent_points,
		int(options.get("start_talent_points_earned", source_earned_points))
	)
	var source_shop_counts_variant: Variant = source.get("shop_purchase_counts")
	var source_shop_counts: Dictionary = source_shop_counts_variant as Dictionary if source_shop_counts_variant is Dictionary else {}
	var source_lifespan_max := float(options.get(
		"start_lifespan_max_years",
		BalanceConfig.LIFESPAN_YEARS_BY_REALM[start_realm]
	))
	var source_lifespan := float(options.get("start_lifespan_years", source.get("lifespan_years")))
	var state := {
		"seconds": 0.0,
		"cultivation": maxf(0.0, float(options.get("start_cultivation", source.cultivation))),
		"total_cultivation_earned": maxf(
			maxf(0.0, float(options.get("start_cultivation", source.cultivation))),
			float(options.get("start_total_cultivation_earned", source.total_cultivation_earned))
		),
		"talent_milestone_index": clampi(
			int(options.get("start_talent_milestone_index", source.talent_milestone_index)),
			0,
			BalanceConfig.TALENT_MILESTONES.size()
		),
		"talent_points": initial_points,
		"talent_points_earned": initial_earned_points,
		"talent_nodes": talent_nodes.duplicate(true),
		"spirit_stones": maxf(0.0, float(options.get("start_spirit_stones", source.spirit_stones))),
		"qi": maxf(0.0, float(options.get("start_qi", source.qi))),
		"harvest_cycles": 0,
		"total_harvest_count": 0,
		"clicks": 0,
		"auto_cultivation": 0.0,
		"auto_qi": 0.0,
		"harvested": {},
		"crop_proficiency": source.crop_proficiency.duplicate(true),
		"breakthrough_materials": source.breakthrough_materials.duplicate(true),
		"shop_purchase_counts": source_shop_counts.duplicate(true),
		"healing_pills": maxi(0, int(options.get("start_healing_pills", source.get("healing_pills")))),
		"resistance_pills": maxi(0, int(options.get("start_resistance_pills", source.get("resistance_pills")))),
		"enhancement_pills": maxi(0, int(options.get("start_enhancement_pills", source.get("enhancement_pills")))),
		"lifespan_max_years": maxf(0.0, source_lifespan_max),
		"lifespan_years": clampf(source_lifespan, 0.0, maxf(0.0, source_lifespan_max)),
		"lifespan_depleted": source_lifespan <= 0.0,
		"tribulation_seconds": 0.0,
		"tribulation_strikes": 0,
		"talent_unlocks": [],
		"purchase_log": [],
		"spirit_stones_spent": 0.0,
	}
	if options.get("start_breakthrough_materials", {}) is Dictionary and not (options.get("start_breakthrough_materials", {}) as Dictionary).is_empty():
		state["breakthrough_materials"] = (options.get("start_breakthrough_materials", {}) as Dictionary).duplicate(true)
	if options.get("start_shop_purchase_counts", {}) is Dictionary and not (options.get("start_shop_purchase_counts", {}) as Dictionary).is_empty():
		state["shop_purchase_counts"] = (options.get("start_shop_purchase_counts", {}) as Dictionary).duplicate(true)
	var model := {
		"clicks_per_second": click_rate,
		"click_scope": click_scope,
		"field_count": field_count,
		"tier": tier,
		"crop_id": String(options.get("crop_id", "")),
		"talent_nodes": state["talent_nodes"],
		"season_index": clampi(int(options.get("season_index", source.season_index)), 0, BalanceConfig.SEASONS.size() - 1),
		"event_prod_mult": maxf(0.0, float(options.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		"event_cult_mult": maxf(0.0, float(options.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		"buff_mult": maxf(0.0, float(options.get("buff_mult", BalanceConfig.DEFAULT_MULTIPLIER))),
		"spirit_rain_active": bool(options.get("spirit_rain_active", false)),
		"pest_level": maxi(0, int(options.get("pest_level", BalanceConfig.DEFAULT_PEST_LEVEL))),
		"include_auto_cultivation": bool(options.get("include_auto_cultivation", true)),
		"include_tribulation": include_tribulation,
		"enforce_tribulation_supplies": enforce_tribulation_supplies,
		"realm_index": start_realm,
	}
	var stages: Array = []
	var blocked_reason := ""
	var max_cycle_guard := 200000

	for realm in range(start_realm, target_realm):
		model["realm_index"] = realm
		state["realm_index"] = realm
		var required_cultivation := float(BalanceConfig.REALMS[realm + 1].get("required_cultivation", 0.0))
		var stage_start_seconds := float(state.get("seconds", 0.0))
		var cultivation_before := float(state.get("cultivation", 0.0))
		var harvest_cycles_before := int(state.get("harvest_cycles", 0))
		var clicks_before := int(state.get("clicks", 0))
		var auto_cultivation_before := float(state.get("auto_cultivation", 0.0))
		var auto_qi_before := float(state.get("auto_qi", 0.0))
		var unlock_before := int((state.get("talent_unlocks", []) as Array).size())
		var purchase_before := int((state.get("purchase_log", []) as Array).size())
		var life_before := float(state.get("lifespan_years", 0.0))
		var stage_crop_id := _timeline_crop(source, state, model, realm)
		var stage_preview := _timeline_preview(source, state, model, stage_crop_id)
		var stage := {
			"from_realm": realm,
			"to_realm": realm + 1,
			"from_realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
			"to_realm_name": String(BalanceConfig.REALMS[realm + 1].get("name", "")),
			"required_cultivation": required_cultivation,
			"cultivation_before": cultivation_before,
			"crop_id": stage_crop_id,
			"crop_name": String(stage_preview.get("crop_name", stage_crop_id)),
			"cultivation_per_cycle": float(stage_preview.get("cultivation_gain", 0.0)) * float(field_count),
			"spirit_stones_per_cycle": float(stage_preview.get("spirit_stones_per_cycle", 0.0)) * float(field_count),
			"harvest_cycles": 0,
			"clicks": 0,
			"tribulation_name": "—",
			"tribulation_strikes": 0,
			"tribulation_seconds": 0.0,
			"talent_points_before_tribulation": int(state.get("talent_points", 0)),
			"talent_points_earned_before_tribulation": int(state.get("talent_points_earned", 0)),
			"lifespan_before_years": life_before,
		}
		var stage_ready := false
		var cycle_count := 0
		while not stage_ready:
			if cycle_count > max_cycle_guard:
				blocked_reason = "最大化模拟超过安全步数"
				break
			_maximized_unlock_talents(source, state, model)
			stage_crop_id = _timeline_crop(source, state, model, realm)
			stage_preview = _timeline_preview(source, state, model, stage_crop_id)
			if stage_crop_id == "" or not bool(stage_preview.get("active", false)):
				blocked_reason = "当前境界没有可用灵植"
				break
			if float(stage_preview.get("cultivation_gain", 0.0)) <= 0.0:
				blocked_reason = "灵植没有有效修为产出"
				break
			if float(state.get("cultivation", 0.0)) >= required_cultivation:
				if enforce_material_gate:
					if auto_buy_resources:
						_maximized_buy_breakthrough_materials(state, realm + 1)
					var material_report := breakthrough_material_report(source, realm + 1, state.get("breakthrough_materials", {}))
					stage["breakthrough_materials"] = material_report.get("rows", [])
					stage["materials_ready"] = bool(material_report.get("ready", false))
					stage["material_shop_cost"] = float(material_report.get("total_shop_cost", 0.0))
					if not bool(material_report.get("ready", false)):
						# 材料未齐时继续种植，直到有足够灵石兑换。
						pass
					else:
						stage["materials_ready"] = true
						stage["material_shop_cost"] = 0.0
				else:
					stage["materials_ready"] = true
				if not include_tribulation:
					stage_ready = bool(stage.get("materials_ready", true))
				elif not enforce_tribulation_supplies:
					stage_ready = bool(stage.get("materials_ready", true))
				else:
					var strikes_for_plan := BalanceConfig.tribulation_strikes_for_talent(int(state.get("talent_points_earned", 0)))
					if auto_buy_resources:
						_maximized_prepare_tribulation_supplies(state, strikes_for_plan)
					var trib_plan := _maximized_find_tribulation_plan(state, strikes_for_plan)
					stage["tribulation_supplies_ready"] = bool(trib_plan.get("success", false))
					stage_ready = bool(stage.get("materials_ready", true)) and bool(trib_plan.get("success", false))
			if stage_ready:
				break
			if not auto_buy_resources:
				blocked_reason = "商店资源不足"
				break
			_maximized_buy_qi_if_profitable(source, state, model, realm + 1, required_cultivation)
			var cycle := _maximized_harvest_cycle(source, state, model, stage_crop_id)
			if not bool(cycle.get("ok", false)):
				blocked_reason = String(cycle.get("reason", "最大化收获模拟失败"))
				break
			cycle_count += 1

		if blocked_reason != "":
			stage["blocked_reason"] = blocked_reason
		else:
			stage["talent_points_before_tribulation"] = int(state.get("talent_points", 0))
			stage["talent_points_earned_before_tribulation"] = int(state.get("talent_points_earned", 0))
			if include_tribulation:
				var tribulation_strikes := BalanceConfig.tribulation_strikes_for_talent(int(state.get("talent_points_earned", 0)))
				if enforce_tribulation_supplies and auto_buy_resources:
					_maximized_prepare_tribulation_supplies(state, tribulation_strikes)
				var tribulation_report := _simulate_tribulation(state, tribulation_strikes, auto_use_tribulation_pills)
				var tribulation_success := bool(tribulation_report.get("success", false))
				if enforce_tribulation_supplies and not tribulation_success:
					blocked_reason = "渡劫丹药不足"
				else:
					var tribulation_seconds := float(tribulation_strikes) * BalanceConfig.TRIBULATION_INTERVAL_SECONDS
					if not _maximized_ensure_lifespan(source, state, model, tribulation_seconds):
						blocked_reason = "寿元和灵石不足"
					else:
						_maximized_advance_time(source, state, model, tribulation_seconds, false)
						state["tribulation_seconds"] = float(state.get("tribulation_seconds", 0.0)) + tribulation_seconds
						state["tribulation_strikes"] = int(state.get("tribulation_strikes", 0)) + tribulation_strikes
						stage["tribulation_name"] = _tribulation_name(tribulation_strikes)
						stage["tribulation_strikes"] = tribulation_strikes
						stage["tribulation_seconds"] = tribulation_seconds
						stage["tribulation_total_strikes"] = tribulation_strikes
						stage["tribulation_success"] = tribulation_success or not enforce_tribulation_supplies
						stage["tribulation_supplies_ready"] = tribulation_success
						stage["tribulation_assumed_success"] = not enforce_tribulation_supplies
						stage["tribulation_used_healing_pills"] = int(tribulation_report.get("used_healing_pills", 0))
						stage["tribulation_used_resistance_pills"] = int(tribulation_report.get("used_resistance_pills", 0))
						stage["tribulation_used_enhancement_pills"] = int(tribulation_report.get("used_enhancement_pills", 0))
						stage["tribulation_recommended_healing_pills"] = int(tribulation_report.get("recommended_healing_pills", 0))
			else:
				stage["tribulation_success"] = true
				stage["tribulation_supplies_ready"] = true
			if blocked_reason == "":
				if enforce_material_gate:
					_consume_simulated_breakthrough_materials(state, realm + 1)
				var reward_index := mini(realm + 1, BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM.size() - 1)
				_maximized_add_talent_points(state, int(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM[reward_index]))
				state["realm_index"] = realm + 1
				model["realm_index"] = realm + 1
				state["lifespan_max_years"] = float(BalanceConfig.LIFESPAN_YEARS_BY_REALM[mini(realm + 1, BalanceConfig.LIFESPAN_YEARS_BY_REALM.size() - 1)])
				state["lifespan_years"] = float(state.get("lifespan_max_years", 0.0))
				state["lifespan_depleted"] = false
				_maximized_unlock_talents(source, state, model)

		stage["crop_id"] = stage_crop_id
		stage["crop_name"] = String(stage_preview.get("crop_name", stage_crop_id))
		stage["cultivation_per_cycle"] = float(stage_preview.get("cultivation_gain", 0.0)) * float(field_count)
		stage["spirit_stones_per_cycle"] = float(stage_preview.get("spirit_stones_per_cycle", 0.0)) * float(field_count)
		stage["harvest_cycles"] = int(state.get("harvest_cycles", 0)) - harvest_cycles_before
		stage["clicks"] = int(state.get("clicks", 0)) - clicks_before
		stage["seconds"] = float(state.get("seconds", 0.0)) - stage_start_seconds
		stage["duration_seconds"] = stage["seconds"]
		stage["cultivation_seconds"] = stage["seconds"] - float(stage.get("tribulation_seconds", 0.0))
		stage["cultivation_after"] = float(state.get("cultivation", 0.0))
		stage["spirit_stones_after"] = float(state.get("spirit_stones", 0.0))
		stage["qi_after"] = float(state.get("qi", 0.0))
		stage["auto_cultivation"] = float(state.get("auto_cultivation", 0.0)) - auto_cultivation_before
		stage["auto_qi"] = float(state.get("auto_qi", 0.0)) - auto_qi_before
		stage["lifespan_after_years"] = float(state.get("lifespan_years", 0.0))
		stage["lifespan_purchases"] = _maximized_count_purchases(state, purchase_before, "longevity_pill")
		stage["qi_purchases"] = _maximized_count_purchases(state, purchase_before, "qi_jade")
		stage["material_purchases"] = _maximized_count_purchase_prefix(state, purchase_before, "breakthrough_")
		stage["material_purchase_cost"] = _maximized_sum_purchase_prefix(state, purchase_before, "breakthrough_")
		stage["talent_unlocks"] = ((state.get("talent_unlocks", []) as Array).slice(unlock_before))
		stage["purchases"] = ((state.get("purchase_log", []) as Array).slice(purchase_before))
		stage["talent_points_after_tribulation"] = int(state.get("talent_points", 0))
		stage["talent_points_earned_after_tribulation"] = int(state.get("talent_points_earned", 0))
		stage["talent_nodes_after"] = state.get("talent_nodes", {}).duplicate(true)
		stage["estimated_completed"] = blocked_reason == "" and float(state.get("cultivation", 0.0)) >= required_cultivation
		stage["completed"] = flow_is_actual and bool(stage["estimated_completed"])
		stage["completion_mode"] = "maximized_actual" if flow_is_actual else "maximized_estimate"
		stages.append(stage)
		if blocked_reason != "":
			break

	var estimated_completed := blocked_reason == "" and target_realm <= start_realm + stages.size()
	var completed := flow_is_actual and estimated_completed
	var materials_ready := true
	var tribulation_supplies_ready := true
	var material_shop_cost := 0.0
	for stage_variant in stages:
		var stage: Dictionary = stage_variant
		materials_ready = materials_ready and bool(stage.get("materials_ready", true))
		tribulation_supplies_ready = tribulation_supplies_ready and bool(stage.get("tribulation_supplies_ready", true))
		material_shop_cost += float(stage.get("material_purchase_cost", 0.0))
	return {
		"completed": completed,
		"estimated_completed": estimated_completed,
		"completion_mode": "maximized_actual" if flow_is_actual else "maximized_estimate",
		"blocked_reason": blocked_reason,
		"maximize_progression": true,
		"auto_buy_shop_resources": auto_buy_resources,
		"start_realm": start_realm,
		"target_realm": target_realm,
		"start_realm_name": String(BalanceConfig.REALMS[start_realm].get("name", "")),
		"target_realm_name": String(BalanceConfig.REALMS[target_realm].get("name", "")),
		"clicks_per_second": click_rate,
		"click_scope": click_scope,
		"click_mode": "每块灵田独立点击" if click_scope == "per_field" else "全局共用点击频率",
		"field_count": field_count,
		"tier": tier,
		"enforce_breakthrough_materials": enforce_material_gate,
		"breakthrough_materials_ready": materials_ready,
		"breakthrough_material_shop_cost": material_shop_cost,
		"enforce_tribulation_supplies": enforce_tribulation_supplies,
		"tribulation_supplies_ready": tribulation_supplies_ready,
		"season_index": int(model.get("season_index", 0)),
		"season_name": String(BalanceConfig.SEASONS[int(model.get("season_index", 0))].get("name", "")),
		"talent_nodes": state.get("talent_nodes", {}),
		"talent_points": int(state.get("talent_points", 0)),
		"talent_points_earned": int(state.get("talent_points_earned", 0)),
		"talent_points_spent": _talent_nodes_cost(state.get("talent_nodes", {})),
		"total_seconds": float(state.get("seconds", 0.0)),
		"total_clicks": int(state.get("clicks", 0)),
		"final_cultivation": float(state.get("cultivation", 0.0)),
		"final_spirit_stones": float(state.get("spirit_stones", 0.0)),
		"final_qi": float(state.get("qi", 0.0)),
		"final_lifespan_years": float(state.get("lifespan_years", 0.0)),
		"lifespan_depleted": bool(state.get("lifespan_depleted", false)),
		"harvest_cycles": int(state.get("harvest_cycles", 0)),
		"total_harvest_count": int(state.get("total_harvest_count", 0)),
		"tribulation_seconds": float(state.get("tribulation_seconds", 0.0)),
		"tribulation_strikes": int(state.get("tribulation_strikes", 0)),
		"tribulation_talent_points": int(state.get("talent_points", 0)),
		"total_cultivation_earned": float(state.get("total_cultivation_earned", 0.0)),
		"talent_milestone_index": int(state.get("talent_milestone_index", 0)),
		"auto_cultivation": float(state.get("auto_cultivation", 0.0)),
		"auto_qi": float(state.get("auto_qi", 0.0)),
		"harvested": state.get("harvested", {}),
		"crop_proficiency": state.get("crop_proficiency", {}),
		"breakthrough_materials": state.get("breakthrough_materials", {}),
		"shop_purchases": state.get("purchase_log", []),
		"talent_unlocks": state.get("talent_unlocks", []),
		"spirit_stones_spent": float(state.get("spirit_stones_spent", 0.0)),
		"stages": stages,
		"cultivation_mode": "灵田收获直接结算修为；天赋点实时解锁",
		"tribulation_mode": "材料和渡劫物资由灵石自动兑换；天劫时间计入寿元",
		"include_tribulation": include_tribulation,
		"auto_use_tribulation_pills": auto_use_tribulation_pills,
	}


static func _talent_nodes_cost(nodes: Dictionary) -> int:
	var total := 0
	for node_id_variant in nodes:
		if not bool(nodes[node_id_variant]):
			continue
		var node := TalentTree.node_def(String(node_id_variant))
		total += int(node.get("cost", 0))
	return total


static func _maximized_add_talent_points(state: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	state["talent_points"] = int(state.get("talent_points", 0)) + amount
	state["talent_points_earned"] = int(state.get("talent_points_earned", 0)) + amount


static func _maximized_add_cultivation(state: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	state["cultivation"] = float(state.get("cultivation", 0.0)) + amount
	state["total_cultivation_earned"] = float(state.get("total_cultivation_earned", 0.0)) + amount
	var milestone_index := clampi(
		int(state.get("talent_milestone_index", 0)),
		0,
		BalanceConfig.TALENT_MILESTONES.size()
	)
	var total_cultivation := float(state.get("total_cultivation_earned", 0.0))
	while milestone_index < BalanceConfig.TALENT_MILESTONES.size() and total_cultivation >= float(BalanceConfig.TALENT_MILESTONES[milestone_index]):
		_maximized_add_talent_points(state, BalanceConfig.TALENT_MILESTONE_POINTS)
		milestone_index += 1
	state["talent_milestone_index"] = milestone_index


## 选择当前可用、对“完成下一段突破”收益最高的节点，并把能支付的点数全部花掉。
static func _maximized_unlock_talents(source: Node, state: Dictionary, model: Dictionary) -> void:
	var nodes: Dictionary = (state.get("talent_nodes", {}) as Dictionary).duplicate(true)
	var points := maxi(0, int(state.get("talent_points", 0)))
	while true:
		var best_id := ""
		var best_score := -INF
		var current_rate := _maximized_progress_rate(source, state, model, nodes)
		for node_id_variant in TalentTree.node_ids():
			var node_id := String(node_id_variant)
			if not TalentTree.can_unlock(node_id, nodes, points):
				continue
			var trial_nodes := nodes.duplicate(true)
			trial_nodes[node_id] = true
			var trial_rate := _maximized_progress_rate(source, state, model, trial_nodes)
			var cost := maxi(1, int(TalentTree.node_def(node_id).get("cost", 1)))
			# 速率是主目标；同速率时优先低成本节点，保证获得点数立即进入已解锁节点。
			var score := (trial_rate - current_rate) / float(cost)
			if score > best_score + 0.000001:
				best_score = score
				best_id = node_id
		if best_id == "":
			break
		var best_cost := int(TalentTree.node_def(best_id).get("cost", 0))
		points -= best_cost
		nodes[best_id] = true
		var unlocks: Array = state.get("talent_unlocks", [])
		unlocks.append({
			"node_id": best_id,
			"node_name": String(TalentTree.node_def(best_id).get("name", best_id)),
			"cost": best_cost,
			"points_after": points,
			"seconds": float(state.get("seconds", 0.0)),
			"realm_index": int(model.get("realm_index", 0)),
		})
		state["talent_unlocks"] = unlocks
	state["talent_points"] = points
	state["talent_nodes"] = nodes
	model["talent_nodes"] = nodes


static func _maximized_progress_rate(source: Node, state: Dictionary, model: Dictionary, talent_nodes: Dictionary) -> float:
	var trial_model: Dictionary = model.duplicate(true)
	trial_model["talent_nodes"] = talent_nodes
	var realm := int(trial_model.get("realm_index", 0))
	var crop_id := _timeline_crop(source, state, trial_model, realm)
	var preview := _timeline_preview(source, state, trial_model, crop_id)
	var field_count := int(trial_model.get("field_count", 1))
	var rate := float(preview.get("cultivation_per_sec", 0.0)) * float(field_count)
	if bool(trial_model.get("include_auto_cultivation", true)) and realm >= BalanceConfig.AUTO_REALM_INDEX_MIN:
		var density := float(field_count * (int(trial_model.get("tier", 0)) + 1))
		var auto_rates := AutomationSystem.auto_rates(
			density,
			realm,
			float(trial_model.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
			float(trial_model.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
			RealmConfig.production_mult(realm),
			RealmConfig.cultivation_mult(realm),
			TalentTree.multiplier("auto_cultivation_mult", talent_nodes),
			TalentTree.multiplier("qi_gain_mult", talent_nodes)
		)
		rate += float(auto_rates.get("cultivation_per_sec", 0.0))
	return rate


static func _maximized_harvest_cycle(source: Node, state: Dictionary, model: Dictionary, crop_id: String) -> Dictionary:
	var preview := _timeline_preview(source, state, model, crop_id)
	if not bool(preview.get("active", false)):
		return {"ok": false, "reason": "找不到作物：%s" % crop_id}
	var growth_seconds := float(preview.get("growth_seconds", 0.0))
	var clicks_to_finish := int(preview.get("clicks_to_finish", 0))
	var field_count := int(model.get("field_count", 1))
	var clicks_per_second := maxf(0.0, float(model.get("clicks_per_second", 0.0)))
	var click_scope := String(model.get("click_scope", "global"))
	var available_click_rate := clicks_per_second * field_count if click_scope == "per_field" else clicks_per_second
	var total_clicks_needed := clicks_to_finish * field_count
	var cycle_seconds := growth_seconds
	if available_click_rate > 0.0 and total_clicks_needed > 0:
		cycle_seconds = minf(growth_seconds, float(total_clicks_needed) / available_click_rate)
	if not _maximized_ensure_lifespan(source, state, model, cycle_seconds):
		return {"ok": false, "reason": "寿元和灵石不足"}
	_maximized_advance_time(source, state, model, cycle_seconds, true)

	# 收获时重新读取当前灵气和刚刚解锁的天赋，让节点/聚气玉从下一轮立即生效。
	var result := _timeline_preview(source, state, model, crop_id)
	var amount := int(result.get("amount", 0)) * field_count
	var cultivation_gain := float(result.get("cultivation_gain", 0.0)) * float(field_count)
	var stones_gain := float(result.get("spirit_stones_per_cycle", 0.0)) * float(field_count)
	_maximized_add_cultivation(state, cultivation_gain)
	state["spirit_stones"] = float(state.get("spirit_stones", 0.0)) + stones_gain
	state["harvest_cycles"] = int(state.get("harvest_cycles", 0)) + 1
	var click_count := int(ceil(minf(cycle_seconds * available_click_rate, float(total_clicks_needed)))) if available_click_rate > 0.0 else 0
	state["clicks"] = int(state.get("clicks", 0)) + click_count
	var harvested: Dictionary = state.get("harvested", {}) as Dictionary
	harvested[crop_id] = int(harvested.get(crop_id, 0)) + amount
	state["harvested"] = harvested
	var proficiency: Dictionary = state.get("crop_proficiency", {}) as Dictionary
	var previous_proficiency := int(proficiency.get(crop_id, 0))
	var current_proficiency := previous_proficiency + field_count
	proficiency[crop_id] = current_proficiency
	_maximized_add_talent_points(
		state,
		BalanceConfig.crop_proficiency_talent_points(crop_id, previous_proficiency, current_proficiency)
	)
	state["crop_proficiency"] = proficiency
	state["total_harvest_count"] = int(state.get("total_harvest_count", 0)) + field_count
	_maximized_unlock_talents(source, state, model)
	return {
		"ok": true,
		"seconds": cycle_seconds,
		"amount": amount,
		"cultivation_gain": cultivation_gain,
		"spirit_stones_gain": stones_gain,
		"clicks": click_count,
	}


static func _maximized_advance_time(source: Node, state: Dictionary, model: Dictionary, seconds: float, allow_auto: bool) -> void:
	if seconds <= 0.0:
		return
	state["seconds"] = float(state.get("seconds", 0.0)) + seconds
	var nodes: Dictionary = state.get("talent_nodes", {}) as Dictionary
	var decay := lifespan_decay_per_second(source, nodes)
	state["lifespan_years"] = maxf(0.0, float(state.get("lifespan_years", 0.0)) - decay * seconds)
	state["lifespan_depleted"] = float(state.get("lifespan_years", 0.0)) <= 0.0
	var realm := int(model.get("realm_index", 0))
	if not allow_auto or not bool(model.get("include_auto_cultivation", true)) or realm < BalanceConfig.AUTO_REALM_INDEX_MIN:
		return
	var field_count := int(model.get("field_count", 1))
	var tier := int(model.get("tier", 0))
	var density := float(field_count * (tier + 1))
	var rates := AutomationSystem.auto_rates(
		density,
		realm,
		float(model.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		float(model.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		RealmConfig.production_mult(realm),
		RealmConfig.cultivation_mult(realm),
		TalentTree.multiplier("auto_cultivation_mult", nodes),
		TalentTree.multiplier("qi_gain_mult", nodes)
	)
	var cultivation_gain := float(rates.get("cultivation_per_sec", 0.0)) * seconds
	var qi_gain := float(rates.get("qi_per_sec", 0.0)) * seconds
	_maximized_add_cultivation(state, cultivation_gain)
	state["qi"] = float(state.get("qi", 0.0)) + qi_gain
	state["auto_cultivation"] = float(state.get("auto_cultivation", 0.0)) + cultivation_gain
	state["auto_qi"] = float(state.get("auto_qi", 0.0)) + qi_gain


static func _maximized_shop_item_cost(state: Dictionary, item_id: String) -> float:
	var shop_instance := ShopSystem.new()
	var counts: Dictionary = state.get("shop_purchase_counts", {}) as Dictionary
	return shop_instance.get_cost(item_id, int(counts.get(item_id, 0)))


static func _maximized_buy_item(state: Dictionary, item_id: String) -> bool:
	var shop_instance := ShopSystem.new()
	var item := shop_instance.get_item(item_id)
	if item.is_empty():
		return false
	var current_realm := int(state.get("realm_index", 0))
	if current_realm < int(item.get("required_realm", 0)):
		return false
	var counts: Dictionary = state.get("shop_purchase_counts", {}) as Dictionary
	var purchases := int(counts.get(item_id, 0))
	var cost := shop_instance.get_cost(item_id, purchases)
	if cost <= 0.0 or float(state.get("spirit_stones", 0.0)) < cost:
		return false
	var effect := String(item.get("effect", ""))
	var amount := float(item.get("amount", 0.0))
	if effect == "lifespan" and float(state.get("lifespan_years", 0.0)) >= float(state.get("lifespan_max_years", 0.0)) - 0.000001:
		return false
	state["spirit_stones"] = float(state.get("spirit_stones", 0.0)) - cost
	state["spirit_stones_spent"] = float(state.get("spirit_stones_spent", 0.0)) + cost
	match effect:
		"lifespan":
			state["lifespan_years"] = minf(float(state.get("lifespan_max_years", 0.0)), float(state.get("lifespan_years", 0.0)) + amount)
			state["lifespan_depleted"] = float(state.get("lifespan_years", 0.0)) <= 0.0
		"qi":
			state["qi"] = float(state.get("qi", 0.0)) + amount
		"tribulation_healing":
			state["healing_pills"] = int(state.get("healing_pills", 0)) + 1
		"tribulation_resistance":
			state["resistance_pills"] = int(state.get("resistance_pills", 0)) + 1
		"tribulation_enhancement":
			state["enhancement_pills"] = int(state.get("enhancement_pills", 0)) + 1
		"breakthrough_material":
			var material_id := String(item.get("material_id", ""))
			if material_id == "" or not BalanceConfig.BREAKTHROUGH_MATERIALS.has(material_id):
				state["spirit_stones"] = float(state.get("spirit_stones", 0.0)) + cost
				state["spirit_stones_spent"] = float(state.get("spirit_stones_spent", 0.0)) - cost
				return false
			var materials: Dictionary = state.get("breakthrough_materials", {}) as Dictionary
			materials[material_id] = int(materials.get(material_id, 0)) + maxi(1, int(amount))
			state["breakthrough_materials"] = materials
		_:
			state["spirit_stones"] = float(state.get("spirit_stones", 0.0)) + cost
			state["spirit_stones_spent"] = float(state.get("spirit_stones_spent", 0.0)) - cost
			return false
	counts[item_id] = purchases + 1
	state["shop_purchase_counts"] = counts
	var log: Array = state.get("purchase_log", [])
	log.append({
		"item_id": item_id,
		"item_name": String(item.get("name", item_id)),
		"cost": cost,
		"seconds": float(state.get("seconds", 0.0)),
		"realm_index": current_realm,
	})
	state["purchase_log"] = log
	return true


static func _maximized_buy_breakthrough_materials(state: Dictionary, target_realm: int) -> bool:
	var configured: Variant = BalanceConfig.BREAKTHROUGH_REQUIREMENTS.get(target_realm, [])
	var ready := true
	if configured is Array:
		for requirement_variant in configured:
			if not requirement_variant is Dictionary:
				continue
			var requirement: Dictionary = requirement_variant
			var material_id := String(requirement.get("material_id", ""))
			var amount := maxi(0, int(requirement.get("amount", 0)))
			var materials: Dictionary = state.get("breakthrough_materials", {}) as Dictionary
			while int(materials.get(material_id, 0)) < amount:
				if not _maximized_buy_item(state, "breakthrough_%s" % material_id):
					ready = false
					break
				materials = state.get("breakthrough_materials", {}) as Dictionary
	return ready


static func _maximized_prepare_tribulation_supplies(state: Dictionary, strikes: int) -> bool:
	var plan := _maximized_find_tribulation_plan(state, strikes)
	if not bool(plan.get("success", false)):
		return false
	for _i in range(int(plan.get("extra_enhancement_pills", 0))):
		if not _maximized_buy_item(state, "enhancement_pill"):
			return false
	for _i in range(int(plan.get("extra_resistance_pills", 0))):
		if not _maximized_buy_item(state, "resistance_pill"):
			return false
	for _i in range(int(plan.get("extra_healing_pills", 0))):
		if not _maximized_buy_item(state, "healing_pill"):
			return false
	return true


static func _maximized_find_tribulation_plan(state: Dictionary, strikes: int) -> Dictionary:
	if strikes <= 0:
		return {"success": true, "cost": 0.0, "extra_enhancement_pills": 0, "extra_resistance_pills": 0, "extra_healing_pills": 0}
	var best: Dictionary = {}
	var max_healing := maxi(8, ceili(float(strikes * BalanceConfig.TRIBULATION_STRIKE_DAMAGE) / BalanceConfig.TRIBULATION_HEAL_AMOUNT) + 4)
	for enhancement in range(2):
		for resistance in range(3):
			for healing in range(max_healing + 1):
				var trial: Dictionary = state.duplicate(true)
				trial["enhancement_pills"] = int(trial.get("enhancement_pills", 0)) + enhancement
				trial["resistance_pills"] = int(trial.get("resistance_pills", 0)) + resistance
				trial["healing_pills"] = int(trial.get("healing_pills", 0)) + healing
				var result := _simulate_tribulation(trial, strikes, true)
				if not bool(result.get("success", false)):
					continue
				var cost := float(enhancement) * _maximized_shop_item_cost(state, "enhancement_pill")
				cost += float(resistance) * _maximized_shop_item_cost(state, "resistance_pill")
				cost += float(healing) * _maximized_shop_item_cost(state, "healing_pill")
				if best.is_empty() or cost < float(best.get("cost", INF)) - 0.000001:
					best = {
						"success": true,
						"cost": cost,
						"extra_enhancement_pills": enhancement,
						"extra_resistance_pills": resistance,
						"extra_healing_pills": healing,
					}
	return best if not best.is_empty() else {"success": false, "cost": INF}


static func _maximized_ensure_lifespan(source: Node, state: Dictionary, model: Dictionary, seconds: float) -> bool:
	if seconds <= 0.0:
		return true
	var nodes: Dictionary = state.get("talent_nodes", {}) as Dictionary
	var decay := lifespan_decay_per_second(source, nodes)
	var required_years := decay * seconds
	while float(state.get("lifespan_years", 0.0)) + 0.000001 < required_years:
		if not _maximized_buy_item(state, "longevity_pill"):
			return false
	return true


static func _maximized_missing_material_cost(state: Dictionary, target_realm: int) -> float:
	var total := 0.0
	var configured: Variant = BalanceConfig.BREAKTHROUGH_REQUIREMENTS.get(target_realm, [])
	if configured is Array:
		for requirement_variant in configured:
			if not requirement_variant is Dictionary:
				continue
			var requirement: Dictionary = requirement_variant
			var material_id := String(requirement.get("material_id", ""))
			var amount := maxi(0, int(requirement.get("amount", 0)))
			var materials: Dictionary = state.get("breakthrough_materials", {}) as Dictionary
			var missing := maxi(0, amount - int(materials.get(material_id, 0)))
			total += float(missing) * _maximized_shop_item_cost(state, "breakthrough_%s" % material_id)
	return total


static func _maximized_lifespan_reserve(source: Node, state: Dictionary, model: Dictionary, required_cultivation: float, target_realm: int, include_tribulation: bool) -> float:
	var rate := _maximized_progress_rate(source, state, model, state.get("talent_nodes", {}) as Dictionary)
	if rate <= 0.0:
		return 0.0
	var remaining := maxf(0.0, required_cultivation - float(state.get("cultivation", 0.0)))
	var expected_seconds := remaining / rate
	if include_tribulation:
		var strikes := BalanceConfig.tribulation_strikes_for_talent(int(state.get("talent_points_earned", 0)))
		expected_seconds += float(strikes) * BalanceConfig.TRIBULATION_INTERVAL_SECONDS
	var decay := lifespan_decay_per_second(source, state.get("talent_nodes", {}) as Dictionary)
	var available_seconds := float(state.get("lifespan_years", 0.0)) / maxf(0.001, decay)
	var pill_seconds := float(_maximized_shop_item_amount("longevity_pill")) / maxf(0.001, decay)
	var required_pills := ceili(maxf(0.0, expected_seconds - available_seconds) / maxf(0.001, pill_seconds))
	return float(required_pills) * _maximized_shop_item_cost(state, "longevity_pill")


static func _maximized_shop_item_amount(item_id: String) -> float:
	var item := ShopSystem.new().get_item(item_id)
	return float(item.get("amount", 0.0)) if not item.is_empty() else 0.0


static func _maximized_resource_reserve(source: Node, state: Dictionary, model: Dictionary, target_realm: int, required_cultivation: float, include_tribulation: bool) -> float:
	var reserve := _maximized_missing_material_cost(state, target_realm)
	if include_tribulation and bool(model.get("enforce_tribulation_supplies", true)):
		var strikes := BalanceConfig.tribulation_strikes_for_talent(int(state.get("talent_points_earned", 0)))
		reserve += float(_maximized_find_tribulation_plan(state, strikes).get("cost", 0.0))
	reserve += _maximized_lifespan_reserve(source, state, model, required_cultivation, target_realm, include_tribulation)
	return reserve


static func _maximized_buy_qi_if_profitable(source: Node, state: Dictionary, model: Dictionary, target_realm: int, required_cultivation: float) -> bool:
	var base_rate := _maximized_progress_rate(source, state, model, state.get("talent_nodes", {}) as Dictionary)
	var jade_cost := _maximized_shop_item_cost(state, "qi_jade")
	if jade_cost <= 0.0:
		return false
	var best_count := 0
	for count in range(1, 21):
		var trial: Dictionary = state.duplicate(true)
		trial["qi"] = float(trial.get("qi", 0.0)) + float(count) * _maximized_shop_item_amount("qi_jade")
		var trial_rate := _maximized_progress_rate(source, trial, model, trial.get("talent_nodes", {}) as Dictionary)
		if trial_rate > base_rate + 0.000001:
			best_count = count
			break
	if best_count <= 0:
		return false
	var reserve := _maximized_resource_reserve(
		source,
		state,
		model,
		target_realm,
		required_cultivation,
		bool(model.get("include_tribulation", true))
	)
	var total_cost := float(best_count) * jade_cost
	if float(state.get("spirit_stones", 0.0)) < reserve + total_cost:
		return false
	for _i in range(best_count):
		if not _maximized_buy_item(state, "qi_jade"):
			return false
	return true


static func _maximized_count_purchases(state: Dictionary, start_index: int, item_id: String) -> int:
	var count := 0
	var log: Array = state.get("purchase_log", [])
	for i in range(clampi(start_index, 0, log.size()), log.size()):
		var entry: Dictionary = log[i]
		if String(entry.get("item_id", "")) == item_id:
			count += 1
	return count


static func _maximized_count_purchase_prefix(state: Dictionary, start_index: int, prefix: String) -> int:
	var count := 0
	var log: Array = state.get("purchase_log", [])
	for i in range(clampi(start_index, 0, log.size()), log.size()):
		var entry: Dictionary = log[i]
		if String(entry.get("item_id", "")).begins_with(prefix):
			count += 1
	return count


static func _maximized_sum_purchase_prefix(state: Dictionary, start_index: int, prefix: String) -> float:
	var total := 0.0
	var log: Array = state.get("purchase_log", [])
	for i in range(clampi(start_index, 0, log.size()), log.size()):
		var entry: Dictionary = log[i]
		if String(entry.get("item_id", "")).begins_with(prefix):
			total += float(entry.get("cost", 0.0))
	return total


static func _tribulation_name(strikes: int) -> String:
	match strikes:
		BalanceConfig.TRIBULATION_THREE_NINE_STRIKES:
			return "三九天劫"
		BalanceConfig.TRIBULATION_SIX_NINE_STRIKES:
			return "六九天劫"
		BalanceConfig.TRIBULATION_BASE_STRIKES:
			return "九九天劫"
	return "%d道天劫" % strikes


static func _simulate_tribulation(state: Dictionary, strikes: int, auto_use_pills: bool) -> Dictionary:
	var health_max := BalanceConfig.TRIBULATION_BASE_HEALTH
	var health := health_max
	var resistance_charges := 0
	var used_healing := 0
	var used_resistance := 0
	var used_enhancement := 0
	if auto_use_pills and int(state.get("enhancement_pills", 0)) > 0:
		state["enhancement_pills"] = int(state.get("enhancement_pills", 0)) - 1
		used_enhancement = 1
		health_max += BalanceConfig.TRIBULATION_ENHANCEMENT_HEALTH_BONUS
		health += BalanceConfig.TRIBULATION_ENHANCEMENT_HEALTH_BONUS
	if auto_use_pills and int(state.get("resistance_pills", 0)) > 0:
		state["resistance_pills"] = int(state.get("resistance_pills", 0)) - 1
		used_resistance = 1
		resistance_charges = BalanceConfig.TRIBULATION_RESISTANCE_CHARGES
	var damage_per_strike := BalanceConfig.TRIBULATION_STRIKE_DAMAGE
	if used_enhancement > 0:
		damage_per_strike *= BalanceConfig.TRIBULATION_ENHANCEMENT_DAMAGE_MULT
	var recommended_damage := float(strikes) * damage_per_strike
	if used_resistance > 0:
		recommended_damage -= float(BalanceConfig.TRIBULATION_RESISTANCE_CHARGES) * damage_per_strike * (1.0 - BalanceConfig.TRIBULATION_RESISTANCE_DAMAGE_MULT)
	var recommended_healing := maxi(0, ceili(maxf(0.0, recommended_damage - health_max) / BalanceConfig.TRIBULATION_HEAL_AMOUNT))
	for strike in range(strikes):
		var damage := damage_per_strike
		if resistance_charges > 0:
			damage *= BalanceConfig.TRIBULATION_RESISTANCE_DAMAGE_MULT
			resistance_charges -= 1
		health = maxf(0.0, health - damage)
		if health <= 0.0:
			return {
				"success": false,
				"resolved_strikes": strike + 1,
				"failed_strike": strike + 1,
				"used_healing_pills": used_healing,
				"used_resistance_pills": used_resistance,
				"used_enhancement_pills": used_enhancement,
				"recommended_healing_pills": recommended_healing,
			}
		if auto_use_pills and health <= BalanceConfig.TRIBULATION_HEAL_AMOUNT and int(state.get("healing_pills", 0)) > 0:
			state["healing_pills"] = int(state.get("healing_pills", 0)) - 1
			used_healing += 1
			health = minf(health_max, health + BalanceConfig.TRIBULATION_HEAL_AMOUNT)
	return {
		"success": true,
		"resolved_strikes": strikes,
		"failed_strike": 0,
		"used_healing_pills": used_healing,
		"used_resistance_pills": used_resistance,
		"used_enhancement_pills": used_enhancement,
		"recommended_healing_pills": recommended_healing,
	}


static func _consume_simulated_breakthrough_materials(state: Dictionary, target_realm: int) -> void:
	var stock: Dictionary = state.get("breakthrough_materials", {})
	var configured: Variant = BalanceConfig.BREAKTHROUGH_REQUIREMENTS.get(target_realm, [])
	if configured is Array:
		for requirement in configured:
			if not requirement is Dictionary:
				continue
			var material_id := String(requirement.get("material_id", ""))
			var amount := maxi(0, int(requirement.get("amount", 0)))
			stock[material_id] = maxi(0, int(stock.get(material_id, 0)) - amount)
	state["breakthrough_materials"] = stock


## 每个境界阶段选择当前直接修为/秒最高的灵植；可用 options.crop_id 固定比较对象。
static func _timeline_crop(source: Node, state: Dictionary, model: Dictionary, realm: int) -> String:
	var requested := String(model.get("crop_id", ""))
	var unlocked := CropConfig.get_unlocked(realm)
	if requested != "" and unlocked.has(requested):
		return requested
	var best_id := ""
	var best_rate := -INF
	for crop_id_variant in unlocked:
		var crop_id := String(crop_id_variant)
		var result := _timeline_preview(source, state, model, crop_id)
		var rate := float(result.get("cultivation_per_sec", 0.0))
		if rate > best_rate:
			best_rate = rate
			best_id = crop_id
	return best_id


static func _timeline_talent_nodes(source: Node, options: Dictionary) -> Dictionary:
	if options.has("talent_nodes") and options.get("talent_nodes") is Dictionary:
		return (options.get("talent_nodes") as Dictionary).duplicate(true)
	var profile_id := String(options.get("profile_id", "current"))
	for profile in talent_profiles(source):
		if String(profile.get("id", "")) == profile_id:
			return (profile.get("nodes", {"root": true}) as Dictionary).duplicate(true)
	return source.talent_nodes.duplicate(true)


static func _timeline_preview(source: Node, state: Dictionary, model: Dictionary, crop_id: String) -> Dictionary:
	var realm := int(model.get("realm_index", 0))
	var talent_nodes: Dictionary = model.get("talent_nodes", {"root": true})
	var scenario := {
		"mode": MODE_UNIFORM,
		"realm_index": realm,
		"talent_nodes": talent_nodes,
		"season_index": int(model.get("season_index", 0)),
		"crop_id": crop_id,
		"tier": int(model.get("tier", 0)),
		"qi": float(state.get("qi", 0.0)),
		"crop_proficiency": state.get("crop_proficiency", {}).duplicate(true),
		"event_prod_mult": float(model.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		"event_cult_mult": float(model.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		"buff_mult": float(model.get("buff_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
	}
	return field_result(
		source,
		scenario,
		crop_id,
		int(model.get("tier", 0)),
		0,
		int(model.get("pest_level", BalanceConfig.DEFAULT_PEST_LEVEL)),
		bool(model.get("spirit_rain_active", false))
	)


static func _award_simulated_milestones(state: Dictionary) -> void:
	var milestone_index := clampi(
		int(state.get("talent_milestone_index", 0)),
		0,
		BalanceConfig.TALENT_MILESTONES.size()
	)
	var total_cultivation := float(state.get("total_cultivation_earned", 0.0))
	while milestone_index < BalanceConfig.TALENT_MILESTONES.size() and total_cultivation >= float(BalanceConfig.TALENT_MILESTONES[milestone_index]):
		_add_simulated_talent_points(state, BalanceConfig.TALENT_MILESTONE_POINTS)
		milestone_index += 1
	state["talent_milestone_index"] = milestone_index


static func _add_simulated_talent_points(state: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	state["talent_points"] = int(state.get("talent_points", 0)) + amount
	state["talent_points_earned"] = int(state.get("talent_points_earned", 0)) + amount


static func _add_simulated_cultivation(state: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	state["cultivation"] = float(state.get("cultivation", 0.0)) + amount
	state["total_cultivation_earned"] = float(state.get("total_cultivation_earned", 0.0)) + amount
	_award_simulated_milestones(state)


static func _timeline_harvest_cycle(
	source: Node,
	state: Dictionary,
	model: Dictionary,
	crop_id: String,
	active_field_count := -1
	) -> Dictionary:
	var preview := _timeline_preview(source, state, model, crop_id)
	if not bool(preview.get("active", false)):
		return {"ok": false, "reason": "找不到作物：%s" % crop_id}
	var growth_seconds := float(preview.get("growth_seconds", 0.0))
	var clicks_to_finish := int(preview.get("clicks_to_finish", 0))
	var field_count := int(model.get("field_count", 1))
	if active_field_count > 0:
		field_count = clampi(active_field_count, 1, field_count)
	var cycle_seconds := growth_seconds
	var clicks_per_second := maxf(0.0, float(model.get("clicks_per_second", 0.0)))
	var click_scope := String(model.get("click_scope", "global"))
	var available_click_rate := clicks_per_second * field_count if click_scope == "per_field" else clicks_per_second
	var total_clicks_needed := clicks_to_finish * field_count
	if available_click_rate > 0.0 and total_clicks_needed > 0:
		cycle_seconds = minf(growth_seconds, float(total_clicks_needed) / available_click_rate)
	_timeline_advance(source, state, model, cycle_seconds)

	# 实际收获时重新计算一次，让本轮生长期间的灵气库存影响收获数量。
	var result := _timeline_preview(source, state, model, crop_id)
	var amount := int(result.get("amount", 0)) * field_count
	var cultivation_gain := float(result.get("cultivation_gain", 0.0)) * float(field_count)
	var stones_gain := float(result.get("spirit_stones_per_cycle", 0.0)) * float(field_count)
	_add_simulated_cultivation(state, cultivation_gain)
	state["spirit_stones"] = float(state.get("spirit_stones", 0.0)) + stones_gain
	state["harvest_cycles"] = int(state.get("harvest_cycles", 0)) + 1
	var click_count := int(ceil(minf(cycle_seconds * available_click_rate, float(total_clicks_needed)))) if available_click_rate > 0.0 else 0
	state["clicks"] = int(state.get("clicks", 0)) + click_count
	var harvested: Dictionary = state.get("harvested", {})
	harvested[crop_id] = int(harvested.get(crop_id, 0)) + amount
	state["harvested"] = harvested
	var proficiency: Dictionary = state.get("crop_proficiency", {})
	var previous_proficiency := int(proficiency.get(crop_id, 0))
	var current_proficiency := previous_proficiency + field_count
	proficiency[crop_id] = current_proficiency
	_add_simulated_talent_points(
		state,
		BalanceConfig.crop_proficiency_talent_points(crop_id, previous_proficiency, current_proficiency)
	)
	state["crop_proficiency"] = proficiency
	state["total_harvest_count"] = int(state.get("total_harvest_count", 0)) + field_count
	return {
		"ok": true,
		"seconds": cycle_seconds,
		"amount": amount,
		"cultivation_gain": cultivation_gain,
		"spirit_stones_gain": stones_gain,
		"clicks": click_count,
	}


static func _timeline_advance(source: Node, state: Dictionary, model: Dictionary, seconds: float) -> void:
	if seconds <= 0.0:
		return
	state["seconds"] = float(state.get("seconds", 0.0)) + seconds
	var realm := int(model.get("realm_index", 0))
	if not bool(model.get("include_auto_cultivation", true)) or realm < BalanceConfig.AUTO_REALM_INDEX_MIN:
		return
	var field_count := int(model.get("field_count", 1))
	var tier := int(model.get("tier", 0))
	var density := float(field_count * (tier + 1))
	var rates := AutomationSystem.auto_rates(
		density,
		realm,
		float(model.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		float(model.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		RealmConfig.production_mult(realm),
		RealmConfig.cultivation_mult(realm),
		TalentTree.multiplier("auto_cultivation_mult", model.get("talent_nodes", {})),
		TalentTree.multiplier("qi_gain_mult", model.get("talent_nodes", {}))
	)
	var cultivation_gain := float(rates.get("cultivation_per_sec", 0.0)) * seconds
	var qi_gain := float(rates.get("qi_per_sec", 0.0)) * seconds
	_add_simulated_cultivation(state, cultivation_gain)
	state["qi"] = float(state.get("qi", 0.0)) + qi_gain
	state["auto_cultivation"] = float(state.get("auto_cultivation", 0.0)) + cultivation_gain
	state["auto_qi"] = float(state.get("auto_qi", 0.0)) + qi_gain


## 真实收获结算和模拟都使用的单块灵田计算。
## 返回 amount / cultivation_gain / growth_seconds / 灵石每秒等完整中间结果。
static func field_result(
	source: Node,
	scenario: Dictionary,
	crop_id: String,
	tier: int,
	field_index := 0,
	pest_level := 0,
	spirit_rain_active := false
	) -> Dictionary:
	var crop: Variant = CropConfig.get_crop(crop_id)
	if crop == null:
		return _empty_field_result(field_index)
	var safe_tier := clampi(tier, 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	var season_index := clampi(int(scenario.get("season_index", 0)), 0, BalanceConfig.SEASONS.size() - 1)
	var talent_nodes: Dictionary = scenario.get("talent_nodes", {"root": true})
	var season: Dictionary = BalanceConfig.SEASONS[season_index]
	var production_mult := production_multiplier(source, scenario, safe_tier)
	var proficiency: Dictionary = scenario.get("crop_proficiency", {})
	var proficiency_count := int(proficiency.get(crop_id, 0))
	var proficiency_data := BalanceConfig.crop_proficiency_reward(crop_id, proficiency_count)

	var qi_harvest_mult := qi_harvest_multiplier(source, float(scenario.get("qi", 0.0)), talent_nodes)
	var pest_factor := maxf(0.0, 1.0 - float(maxi(0, pest_level)) * BalanceConfig.FIELD_PEST_REDUCTION_PER_LEVEL)
	var harvest_factor := float(season.get("yield", BalanceConfig.DEFAULT_MULTIPLIER)) * pest_factor * qi_harvest_mult
	var base_amount := maxi(1, int(floor(production_mult * harvest_factor)))
	var amount := base_amount + int(proficiency_data.get("yield_bonus", 0))
	var growth_mult := maxf(0.001, growth_multiplier(source, scenario, spirit_rain_active))
	var growth_seconds := crop_growth_seconds(source, scenario, crop_id, spirit_rain_active)
	var sell_price := float(crop.get("sell_price", 0.0))
	var cultivation_base := float(crop.get("cultivation", 0.0))
	var cultivation_mult := cultivation_multiplier(scenario)
	var cultivation_gain := cultivation_base * float(amount) * cultivation_mult
	var stones_per_sec := float(amount) * sell_price / growth_seconds
	var cultivation_per_sec := cultivation_gain / growth_seconds
	var click_accel := click_accel_seconds(source, talent_nodes)
	var clicks_to_finish := int(ceil(growth_seconds / maxf(0.001, click_accel)))
	# 幸运系期望倍率：真实收获在 GameState.harvest_crop 里 roll，模拟器只展示期望。
	# 暴击：概率 crit_chance，普通 ×2 / 稀有 ×5；横财：概率 windfall_chance，额外灵石 ×50%。
	var crit_chance := TalentTree.bonus("crit_chance", talent_nodes)
	var rare_chance := TalentTree.bonus("rare_crit_chance", talent_nodes)
	var windfall_chance := TalentTree.bonus("windfall_chance", talent_nodes)
	var expected_crit_mult := 1.0 + crit_chance * (
		BalanceConfig.LUCK_CRIT_MULT * (1.0 - rare_chance) + BalanceConfig.LUCK_RARE_CRIT_MULT * rare_chance
	)
	var expected_stones_mult := expected_crit_mult + windfall_chance * BalanceConfig.LUCK_WINDFALL_RATIO

	return {
		"active": true,
		"field_index": field_index,
		"crop_id": crop_id,
		"crop_name": String(crop.get("name", crop_id)),
		"tier": safe_tier,
		"tier_mult": float(BalanceConfig.FIELD_TIER_MULTS[safe_tier]),
		"amount": amount,
		"base_amount": base_amount,
		"sell_price": sell_price,
		"spirit_stones_per_cycle": float(amount) * sell_price,
		"cultivation_gain": cultivation_gain,
		"growth_seconds": growth_seconds,
		"spirit_stones_per_sec": stones_per_sec,
		"cultivation_per_sec": cultivation_per_sec,
		"production_mult": production_mult,
		"cultivation_mult": cultivation_mult,
		"growth_mult": growth_mult,
		"crit_chance": crit_chance,
		"rare_crit_chance": rare_chance,
		"windfall_chance": windfall_chance,
		"expected_crit_mult": expected_crit_mult,
		"expected_stones_mult": expected_stones_mult,
		"proficiency_count": proficiency_count,
		"proficiency_stage": int(proficiency_data.get("stage", 0)),
		"proficiency_yield_bonus": int(proficiency_data.get("yield_bonus", 0)),
		"proficiency_growth_reduction": float(proficiency_data.get("growth_reduction", 0.0)),
		"proficiency_talent_points": int(proficiency_data.get("talent_points", 0)),
		"proficiency_next_threshold": int(proficiency_data.get("next_threshold", -1)),
		"qi_harvest_mult": qi_harvest_mult,
		"pest_factor": pest_factor,
		"click_accel_seconds": click_accel,
		"clicks_to_finish": clicks_to_finish,
		"spirit_rain_active": spirit_rain_active,
	}


## GameState.harvest_crop() 的实时适配器。它只读取当前状态，不改变状态。
static func live_field_result(source: Node, field_index: int, crop_id: String, tier: int, pest_level := 0) -> Dictionary:
	var scenario := _scenario(source, {"mode": MODE_UNIFORM})
	var rain_active := false
	if source.has_method("is_spirit_rain_active"):
		rain_active = bool(source.is_spirit_rain_active(field_index))
	return field_result(source, scenario, crop_id, tier, field_index, pest_level, rain_active)


## 返回指定境界下的槽位价格。基准值来自 BalanceConfig.FIELD_SLOT_COSTS。
static func slot_cost(source: Node, realm_index: int, field_index: int) -> float:
	if field_index < 0 or field_index >= BalanceConfig.FIELD_SLOT_COSTS.size():
		return 0.0
	return float(BalanceConfig.FIELD_SLOT_COSTS[field_index].get("spirit_stones", 0.0)) * RealmConfig.production_mult(realm_index)


## 返回预设天赋路线。节点 id 来自 TalentTree，效果仍由 TalentTree 统一计算。
static func talent_profiles(source: Node) -> Array:
	var all_nodes: Array = TalentTree.node_ids()
	return [
		{"id": "current", "name": "当前天赋", "nodes": source.talent_nodes.duplicate()},
		{"id": "root", "name": "仅根节点", "nodes": {"root": true}},
		{"id": "farming_core", "name": "农道核心", "nodes": _nodes(["root", "farming_start", "farming_yield", "farming_speed"])},
		{"id": "alchemy_core", "name": "丹道核心", "nodes": _nodes(["root", "alchemy_start", "alchemy_power", "alchemy_quality"])},
		{"id": "spirit_core", "name": "灵根核心", "nodes": _nodes(["root", "spirit_start", "spirit_qi", "spirit_lifespan"])},
		{"id": "all_nodes", "name": "全部节点", "nodes": _nodes(all_nodes)},
	]


## 返回事件矩阵。事件倍率直接读取 GameState 常量，不复制事件数值。
static func event_profiles(source: Node) -> Array:
	return [
		{"id": "normal", "name": "无事件", "prod": BalanceConfig.DEFAULT_MULTIPLIER, "cult": BalanceConfig.DEFAULT_MULTIPLIER, "pest_level": BalanceConfig.DEFAULT_PEST_LEVEL},
		{"id": "auspicious", "name": "祥瑞降世", "prod": float(BalanceConfig.EVENT_PROD_BONUS), "cult": BalanceConfig.DEFAULT_MULTIPLIER, "pest_level": BalanceConfig.DEFAULT_PEST_LEVEL},
		{"id": "dao_insight", "name": "天道感悟", "prod": BalanceConfig.DEFAULT_MULTIPLIER, "cult": float(BalanceConfig.EVENT_CULT_BONUS), "pest_level": BalanceConfig.DEFAULT_PEST_LEVEL},
		{"id": "warlord_birthday", "name": "兵主诞辰（虫害压力）", "prod": BalanceConfig.DEFAULT_MULTIPLIER, "cult": BalanceConfig.DEFAULT_MULTIPLIER, "pest_level": BalanceConfig.EVENT_WARLORD_PEST_LEVEL},
	]


## 生成可供 UI 展示的矩阵。矩阵行都包含 report，调用方不需要重新计算。
static func matrix(source: Node, kind: String, options: Dictionary = {}) -> Array:
	match kind:
		"realm":
			return _realm_matrix(source, options)
		"crop":
			return _crop_matrix(source, options)
		"season":
			return _season_matrix(source, options)
		"talent":
			return _talent_matrix(source, options)
		"proficiency":
			return _proficiency_matrix(source, options)
		"event":
			return _event_matrix(source, options)
		"progression":
			return _progression_matrix(source, options)
		"breakthrough":
			return _breakthrough_matrix(source, options)
		"full":
			return _full_matrix(source, options)
	return []


static func _breakthrough_matrix(source: Node, options: Dictionary) -> Array:
	var flow := simulate_breakthrough_flow(source, options)
	var profile_id := String(options.get("profile_id", "current"))
	var profile_name := profile_id
	for profile in talent_profiles(source):
		if String(profile.get("id", "")) == profile_id:
			profile_name = String(profile.get("name", profile_id))
			break
	return [{
		"profile_id": profile_id,
		"profile_name": profile_name,
		"clicks_per_second": float(flow.get("clicks_per_second", 0.0)),
		"field_count": int(flow.get("field_count", 0)),
		"tier": int(flow.get("tier", 0)),
		"total_seconds": float(flow.get("total_seconds", 0.0)),
		"completed": bool(flow.get("completed", false)),
		"estimated_completed": bool(flow.get("estimated_completed", false)),
		"completion_mode": String(flow.get("completion_mode", "actual")),
		"flow": flow,
	}]


## 全量核心矩阵：境界 × 已解锁作物 × 四季 × 天赋路线 × 田数 × 可用档位。
## 事件/灵气/灵雨/虫害作为独立修正矩阵展示，避免把爆发状态混成基础成长曲线。
static func _full_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	var profiles := talent_profiles(source)
	var selected_event: Dictionary = _selected_event(source, options)
	var qi := float(options.get("qi", 0.0))
	for realm in range(RealmConfig.realm_count()):
		var crop_ids: Array = CropConfig.get_unlocked(realm)
		for crop_id_variant in crop_ids:
			var crop_id := String(crop_id_variant)
			for season in range(BalanceConfig.SEASONS.size()):
				for profile in profiles:
					for field_count in range(1, source.fields.size() + 1):
						for tier in range(mini(realm + 1, BalanceConfig.FIELD_TIER_MULTS.size())):
							var report_options := _uniform_options(source, options, {
								"realm_index": realm,
								"talent_nodes": profile.get("nodes", {"root": true}),
								"season_index": season,
								"crop_id": crop_id,
								"field_count": field_count,
								"tier": tier,
								"qi": qi,
								"event_prod_mult": selected_event.get("prod", BalanceConfig.DEFAULT_MULTIPLIER),
								"event_cult_mult": selected_event.get("cult", BalanceConfig.DEFAULT_MULTIPLIER),
								"pest_level": selected_event.get("pest_level", 0),
							})
							var report_data := report(source, report_options)
							rows.append({
								"realm_index": realm,
								"realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
								"crop_id": crop_id,
								"crop_name": String(CropConfig.get_crop(crop_id).get("name", crop_id)),
								"season_index": season,
								"season_name": String(BalanceConfig.SEASONS[season].get("name", "")),
								"profile_id": String(profile.get("id", "")),
								"profile_name": String(profile.get("name", "")),
								"field_count": field_count,
								"tier": tier,
								"report": report_data,
							})
	return rows


static func _realm_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	for realm in range(RealmConfig.realm_count()):
		var crop_id := _crop_for_realm(options, realm, source)
		var max_tier := mini(realm, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
		var tier := clampi(int(options.get("tier", 0)), 0, max_tier)
		for field_count in range(1, source.fields.size() + 1):
			var report_data := report(source, _uniform_options(source, options, {
				"realm_index": realm,
				"crop_id": crop_id,
				"tier": tier,
				"field_count": field_count,
			}))
			rows.append(_matrix_row(report_data, {
				"realm_index": realm,
				"realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
				"field_count": field_count,
				"crop_id": crop_id,
				"crop_name": String(CropConfig.get_crop(crop_id).get("name", crop_id)),
				"tier": tier,
			}))
	return rows


static func _crop_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	var realm := clampi(int(options.get("realm_index", source.realm_index)), 0, RealmConfig.realm_count() - 1)
	var field_count := clampi(int(options.get("field_count", source.unlocked_fields)), 1, source.fields.size())
	var tier := clampi(int(options.get("tier", 0)), 0, mini(realm, BalanceConfig.FIELD_TIER_MULTS.size() - 1))
	for crop_id_variant in CropConfig.get_unlocked(realm):
		var crop_id := String(crop_id_variant)
		var report_data := report(source, _uniform_options(source, options, {
			"realm_index": realm,
			"crop_id": crop_id,
			"field_count": field_count,
			"tier": tier,
		}))
		rows.append(_matrix_row(report_data, {
			"crop_id": crop_id,
			"crop_name": String(CropConfig.get_crop(crop_id).get("name", crop_id)),
			"realm_index": realm,
			"realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
			"field_count": field_count,
			"tier": tier,
		}))
	return rows


static func _season_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	for season in range(BalanceConfig.SEASONS.size()):
		var report_data := report(source, _uniform_options(source, options, {"season_index": season}))
		rows.append(_matrix_row(report_data, {
			"season_index": season,
			"season_name": String(BalanceConfig.SEASONS[season].get("name", "")),
		}))
	return rows


static func _talent_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	for profile in talent_profiles(source):
		var report_data := report(source, _uniform_options(source, options, {"talent_nodes": profile.get("nodes", {})}))
		rows.append(_matrix_row(report_data, {
			"profile_id": String(profile.get("id", "")),
			"profile_name": String(profile.get("name", "")),
		}))
	return rows


static func _proficiency_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	var realm := clampi(int(options.get("realm_index", source.realm_index)), 0, RealmConfig.realm_count() - 1)
	var field_count := clampi(int(options.get("field_count", source.unlocked_fields)), 1, source.fields.size())
	var tier := clampi(int(options.get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	for crop_id_variant in CropConfig.get_all():
		var crop_id := String(crop_id_variant)
		var crop: Dictionary = CropConfig.get_crop(crop_id)
		for stage in range(BalanceConfig.CROP_PROFICIENCY_THRESHOLDS.size() + 1):
			var harvest_count := 0
			if stage > 0:
				harvest_count = int(BalanceConfig.CROP_PROFICIENCY_THRESHOLDS[stage - 1])
			var proficiency: Dictionary = source.crop_proficiency.duplicate(true)
			proficiency[crop_id] = harvest_count
			var report_data := report(source, _uniform_options(source, options, {
				"realm_index": realm,
				"crop_id": crop_id,
				"field_count": field_count,
				"tier": tier,
				"crop_proficiency": proficiency,
			}))
			var reward := BalanceConfig.crop_proficiency_reward(crop_id, harvest_count)
			rows.append({
				"crop_id": crop_id,
				"crop_name": String(crop.get("name", crop_id)),
				"realm_index": realm,
				"realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
				"stage": stage,
				"harvest_count": harvest_count,
				"threshold": int(BalanceConfig.CROP_PROFICIENCY_THRESHOLDS[stage - 1]) if stage > 0 else 0,
				"yield_bonus": int(reward.get("yield_bonus", 0)),
				"growth_reduction": float(reward.get("growth_reduction", 0.0)),
				"talent_points": int(reward.get("talent_points", 0)),
				"report": report_data,
			})
	return rows


static func _event_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	for event in event_profiles(source):
		var report_data := report(source, _uniform_options(source, options, {
			"event_prod_mult": event.get("prod", BalanceConfig.DEFAULT_MULTIPLIER),
			"event_cult_mult": event.get("cult", BalanceConfig.DEFAULT_MULTIPLIER),
			"pest_level": event.get("pest_level", 0),
		}))
		rows.append(_matrix_row(report_data, {
			"event_id": String(event.get("id", "")),
			"event_name": String(event.get("name", "")),
		}))
	return rows


## 境界总表：把境界倍率、寿元、解锁内容和自动修炼速率放在同一份真实配置上。
static func _progression_matrix(source: Node, options: Dictionary) -> Array:
	var rows: Array = []
	var profiles := talent_profiles(source)
	var profile_id := String(options.get("profile_id", "current"))
	var selected_profile: Dictionary = profiles[0]
	for profile in profiles:
		if String(profile.get("id", "")) == profile_id:
			selected_profile = profile
			break
	for realm in range(RealmConfig.realm_count()):
		var crop_id := _crop_for_realm(options, realm, source)
		var report_data := report(source, _uniform_options(source, options, {
			"realm_index": realm,
			"talent_nodes": selected_profile.get("nodes", {"root": true}),
			"crop_id": crop_id,
			"field_count": source.fields.size(),
			"tier": mini(realm, BalanceConfig.FIELD_TIER_MULTS.size() - 1),
			"qi": float(options.get("qi", 0.0)),
		}))
		var rewards := RealmConfig.breakthrough_rewards(realm)
		var unlocks := PackedStringArray()
		for key in rewards:
			if bool(rewards[key]):
				unlocks.append(String(key).replace("unlock_", ""))
		for crop_id_variant in CropConfig.get_all():
			var unlocked_crop_id := String(crop_id_variant)
			var crop: Variant = CropConfig.get_crop(unlocked_crop_id)
			if crop is Dictionary and int(crop.get("unlock_realm", -1)) == realm:
				unlocks.append(String(crop.get("name", unlocked_crop_id)))
		var breakthrough_points := int(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM[mini(realm, BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM.size() - 1)])
		var lifespan_max := float(BalanceConfig.LIFESPAN_YEARS_BY_REALM[mini(realm, BalanceConfig.LIFESPAN_YEARS_BY_REALM.size() - 1)])
		rows.append({
			"realm_index": realm,
			"realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
			"required_cultivation": float(BalanceConfig.REALMS[realm].get("required_cultivation", 0.0)),
			"production_mult": RealmConfig.production_mult(realm),
			"cultivation_mult": RealmConfig.cultivation_mult(realm),
			"lifespan_max_years": lifespan_max,
			"lifespan_decay_per_second": float(BalanceConfig.LIFESPAN_DECAY_PER_SECOND),
			"lifespan_duration_seconds": lifespan_max / maxf(0.001, float(BalanceConfig.LIFESPAN_DECAY_PER_SECOND)),
			"breakthrough_talent_points": breakthrough_points,
			"unlocks": ", ".join(unlocks) if not unlocks.is_empty() else "—",
			"report": report_data,
		})
	return rows


static func _matrix_row(report_data: Dictionary, labels: Dictionary = {}) -> Dictionary:
	var row := labels.duplicate()
	row["report"] = report_data
	row["stones_per_sec"] = float(report_data.get("total_spirit_stones_per_sec", 0.0))
	row["qi_per_sec"] = float(report_data.get("total_qi_per_sec", 0.0))
	row["cultivation_per_sec"] = float(report_data.get("total_cultivation_per_sec", 0.0)) + float(report_data.get("auto_rates", {}).get("cultivation_per_sec", 0.0))
	row["density"] = float(report_data.get("qi_density", 0.0))
	return row


static func _scenario(source: Node, options: Dictionary) -> Dictionary:
	var mode := String(options.get("mode", MODE_UNIFORM))
	var realm := clampi(int(options.get("realm_index", source.realm_index)), 0, RealmConfig.realm_count() - 1)
	var talent_nodes: Dictionary = options.get("talent_nodes", source.talent_nodes)
	var season := clampi(int(options.get("season_index", source.season_index)), 0, BalanceConfig.SEASONS.size() - 1)
	var default_crop := _crop_for_realm(options, realm, source)
	var proficiency: Dictionary = options.get("crop_proficiency", source.crop_proficiency)
	var scenario := {
		"mode": mode,
		"realm_index": realm,
		"realm_name": String(BalanceConfig.REALMS[realm].get("name", "")),
		"talent_nodes": talent_nodes.duplicate(),
		"season_index": season,
		"season_name": String(BalanceConfig.SEASONS[season].get("name", "")),
		"crop_id": String(options.get("crop_id", default_crop)),
		"tier": clampi(int(options.get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1),
		"field_count": clampi(int(options.get("field_count", source.unlocked_fields)), 1, source.fields.size()),
		"clicks_per_second": maxf(0.0, float(options.get("clicks_per_second", BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND))),
		"click_scope": String(options.get("click_scope", "global")),
		"qi": maxf(0.0, float(options.get("qi", source.qi))),
		"crop_proficiency": proficiency.duplicate(true),
		"event_prod_mult": maxf(0.0, float(options.get("event_prod_mult", source.event_prod_mult))),
		"event_cult_mult": maxf(0.0, float(options.get("event_cult_mult", source.event_cult_mult))),
		"buff_mult": maxf(0.0, float(options.get("buff_mult", source.active_buff_mult if source.is_active_buff() else BalanceConfig.DEFAULT_MULTIPLIER))),
		"spirit_rain_active": bool(options.get("spirit_rain_active", false)),
		"pest_level": maxi(0, int(options.get("pest_level", 0))),
		"auto_cultivation_enabled": bool(options.get("auto_cultivation_enabled", source.unlock_auto_cultivation)),
		"field_specs": [],
	}

	if mode == MODE_LIVE:
		scenario["field_specs"] = _live_field_specs(source)
	else:
		for field_index in range(scenario.field_count):
			scenario.field_specs.append({
				"active": true,
				"field_index": field_index,
				"crop_id": scenario.crop_id,
				"tier": scenario.tier,
				"pest_level": scenario.pest_level,
				"spirit_rain_active": scenario.spirit_rain_active,
			})
	return scenario


static func _live_field_specs(source: Node) -> Array:
	var specs: Array = []
	var limit := clampi(int(source.unlocked_fields), 0, source.fields.size())
	for field_index in range(limit):
		var data: Dictionary = source.fields[field_index]
		var crop_id := String(data.get("crop_id", ""))
		var pest_level := 0
		if field_index < source.insect_events.size():
			pest_level = int(source.insect_events[field_index].get("pest_level", 0))
		specs.append({
			"active": crop_id != "",
			"field_index": field_index,
			"crop_id": crop_id,
			"tier": int(data.get("tier", 0)),
			"pest_level": pest_level,
			"spirit_rain_active": source.is_spirit_rain_active(field_index),
		})
	return specs


static func _uniform_options(source: Node, base: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	out["mode"] = MODE_UNIFORM
	for key in overrides:
		out[key] = overrides[key]
	return out


static func _representative_field(source: Node, scenario: Dictionary, field_results: Array) -> Dictionary:
	for result in field_results:
		if bool(result.get("active", false)):
			return result
	var crop_id := String(scenario.get("crop_id", _crop_for_realm({}, int(scenario.get("realm_index", 0)), source)))
	return field_result(
		source,
		scenario,
		crop_id,
		int(scenario.get("tier", 0)),
		0,
		int(scenario.get("pest_level", 0)),
		bool(scenario.get("spirit_rain_active", false))
	)


static func _slot_rows(source: Node, scenario: Dictionary, representative: Dictionary) -> Array:
	var rows: Array = []
	var realm := int(scenario.get("realm_index", 0))
	var marginal_rate := float(representative.get("spirit_stones_per_sec", 0.0))
	for field_index in range(1, BalanceConfig.FIELD_SLOT_COSTS.size()):
		var cost := slot_cost(source, realm, field_index)
		rows.append({
			"field_index": field_index,
			"cost": cost,
			"marginal_rate": marginal_rate,
			"payback_seconds": cost / marginal_rate if marginal_rate > 0.0 else INF,
		})
	return rows


static func _upgrade_rows(source: Node, scenario: Dictionary, representative: Dictionary) -> Array:
	var rows: Array = []
	var realm := int(scenario.get("realm_index", 0))
	var crop_id := String(representative.get("crop_id", scenario.get("crop_id", "")))
	for tier in range(BalanceConfig.FIELD_TIER_UPGRADE_COSTS.size()):
		var cost_data: Dictionary = BalanceConfig.FIELD_TIER_UPGRADE_COSTS[tier]
		var from_result := field_result(source, scenario, crop_id, tier, 0, int(scenario.get("pest_level", 0)), bool(scenario.get("spirit_rain_active", false)))
		var to_result := field_result(source, scenario, crop_id, tier + 1, 0, int(scenario.get("pest_level", 0)), bool(scenario.get("spirit_rain_active", false)))
		var from_rate := float(from_result.get("spirit_stones_per_sec", 0.0))
		var to_rate := float(to_result.get("spirit_stones_per_sec", 0.0))
		var delta := to_rate - from_rate
		var required_realm := int(cost_data.get("required_realm", tier + 1))
		rows.append({
			"from_tier": tier,
			"to_tier": tier + 1,
			"cost": float(cost_data.get("spirit_stones", 0.0)),
			"required_realm": required_realm,
			"available": realm >= required_realm,
			"from_rate": from_rate,
			"to_rate": to_rate,
			"delta_rate": delta,
			"payback_seconds": float(cost_data.get("spirit_stones", 0.0)) / delta if delta > 0.0 else INF,
		})
	return rows


static func _auto_rates(source: Node, scenario: Dictionary, density: float) -> Dictionary:
	if not bool(scenario.get("auto_cultivation_enabled", false)):
		return {"cultivation_per_sec": 0.0, "qi_per_sec": 0.0}
	var realm := int(scenario.get("realm_index", 0))
	return AutomationSystem.auto_rates(
		density,
		realm,
		float(scenario.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		float(scenario.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		RealmConfig.production_mult(realm),
		RealmConfig.cultivation_mult(realm),
		TalentTree.multiplier("auto_cultivation_mult", scenario.get("talent_nodes", {})),
		TalentTree.multiplier("qi_gain_mult", scenario.get("talent_nodes", {}))
	)


static func _offline_report(source: Node, scenario: Dictionary, _density: float) -> Dictionary:
	var realm := int(scenario.get("realm_index", 0))
	if not source.has_method("get_offline_settlement_preview"):
		return {
			"seconds": 0.0,
			"cultivation": 0.0,
			"qi": 0.0,
			"talent_points": 0,
			"spirit_stones": 0.0,
			"duration_independent": true,
			"active": false,
		}
	var preview: Dictionary = source.get_offline_settlement_preview(realm)
	return {
		"seconds": 0.0,
		"cultivation": 0.0,
		"qi": 0.0,
		"talent_points": int(preview.get("talent_points", 0)),
		"spirit_stones": float(preview.get("spirit_stones", 0.0)),
		"spirit_stone_units": float(preview.get("spirit_stone_units", 0.0)),
		"production_mult": float(preview.get("production_mult", 1.0)),
		"duration_independent": true,
		"active": bool(preview.get("active", false)),
	}


static func _click_report(source: Node, scenario: Dictionary, representative: Dictionary) -> Dictionary:
	var growth := float(representative.get("growth_seconds", 0.0))
	var accel := float(representative.get("click_accel_seconds", 0.0))
	var clicks_to_finish := int(ceil(growth / maxf(0.001, accel))) if growth > 0.0 else 0
	var clicks_per_second := maxf(0.0, float(scenario.get("clicks_per_second", BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND)))
	var click_cycle_seconds := growth
	if clicks_per_second > 0.0 and clicks_to_finish > 0:
		click_cycle_seconds = minf(growth, float(clicks_to_finish) / clicks_per_second)
	return {
		"growth_seconds": growth,
		"click_accel_seconds": accel,
		"clicks_to_finish": clicks_to_finish,
		"clicks_per_second": clicks_per_second,
		"click_cycle_seconds": click_cycle_seconds,
		"after_one_click_seconds": maxf(0.0, growth - accel),
	}


static func _multiplier_report(source: Node, scenario: Dictionary, representative: Dictionary) -> Dictionary:
	var talents: Dictionary = scenario.get("talent_nodes", {})
	return {
		"realm_production": RealmConfig.production_mult(int(scenario.get("realm_index", 0))),
		"realm_cultivation": RealmConfig.cultivation_mult(int(scenario.get("realm_index", 0))),
		"talent_production": TalentTree.multiplier("production_mult", talents),
		"talent_growth": TalentTree.multiplier("growth_mult", talents),
		"talent_auto_cultivation": TalentTree.multiplier("auto_cultivation_mult", talents),
		"talent_qi_harvest": TalentTree.multiplier("qi_harvest_mult", talents),
		"talent_qi_gain": TalentTree.multiplier("qi_gain_mult", talents),
		"field_tier": float(representative.get("tier_mult", 1.0)),
		"event_production": float(scenario.get("event_prod_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		"event_cultivation": float(scenario.get("event_cult_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		"buff": float(scenario.get("buff_mult", BalanceConfig.DEFAULT_MULTIPLIER)),
		"qi_harvest": float(representative.get("qi_harvest_mult", 1.0)),
	}


static func _selected_event(source: Node, options: Dictionary) -> Dictionary:
	var selected_id := String(options.get("event_id", "normal"))
	for event in event_profiles(source):
		if String(event.get("id", "")) == selected_id:
			return event
	return event_profiles(source)[0]


static func _crop_for_realm(options: Dictionary, realm: int, source: Node) -> String:
	var requested := String(options.get("crop_id", ""))
	if requested != "" and CropConfig.get_unlocked(realm).has(requested):
		return requested
	var unlocked := CropConfig.get_unlocked(realm)
	if not unlocked.is_empty():
		return String(unlocked[0])
	return ""


static func _nodes(ids: Array) -> Dictionary:
	var result := {}
	for node_id in ids:
		result[String(node_id)] = true
	return result


static func _empty_field_result(field_index: int) -> Dictionary:
	return {
		"active": false,
		"field_index": field_index,
		"crop_id": "",
		"crop_name": "空闲",
		"tier": 0,
		"tier_mult": 1.0,
		"amount": 0,
		"base_amount": 0,
		"spirit_stones_per_cycle": 0.0,
		"cultivation_gain": 0.0,
		"growth_seconds": 0.0,
		"spirit_stones_per_sec": 0.0,
		"cultivation_per_sec": 0.0,
		"production_mult": 0.0,
		"growth_mult": 0.0,
		"proficiency_count": 0,
		"proficiency_stage": 0,
		"proficiency_yield_bonus": 0,
		"proficiency_growth_reduction": 0.0,
		"proficiency_talent_points": 0,
		"proficiency_next_threshold": -1,
		"qi_harvest_mult": 1.0,
		"pest_factor": 1.0,
		"click_accel_seconds": 0.0,
		"clicks_to_finish": 0,
		"spirit_rain_active": false,
	}
