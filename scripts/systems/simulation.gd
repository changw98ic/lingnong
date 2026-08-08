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
		"click": _click_report(source, scenario, representative),
		"multipliers": _multiplier_report(source, scenario, representative),
	}


## 按玩家点击频率模拟“种植 → 收获直接获得修为和灵石 → 突破”的完整流程。
## 默认把 clicks_per_second 视为玩家全局点击频率，click_scope=per_field 时才按每块
## 启用灵田独立计算。灵田收获不产生灵气；自动修炼的灵气仍按独立规则结算。
## 默认点击频率来自 BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND。
static func simulate_breakthrough_flow(source: Node, options: Dictionary = {}) -> Dictionary:
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
		"realm_index": start_realm,
	}
	var state := {
		"seconds": 0.0,
		"cultivation": maxf(0.0, float(options.get("start_cultivation", source.cultivation))),
		"spirit_stones": maxf(0.0, float(options.get("start_spirit_stones", source.spirit_stones))),
		"qi": maxf(0.0, float(options.get("start_qi", source.qi))),
		"harvest_cycles": 0,
		"clicks": 0,
		"auto_cultivation": 0.0,
		"auto_qi": 0.0,
		"harvested": {},
		"crop_proficiency": source.crop_proficiency.duplicate(true),
		"total_harvest_count": 0,
	}
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
		}

		if crop_id == "" or not bool(preview.get("active", false)):
			blocked_reason = "当前境界没有可用灵植"
		elif float(preview.get("cultivation_gain", 0.0)) <= 0.0:
			blocked_reason = "灵植没有有效修为产出"
		else:
			while float(state.get("cultivation", 0.0)) < required_cultivation:
				var cycle := _timeline_harvest_cycle(source, state, model, crop_id)
				if not bool(cycle.get("ok", false)):
					blocked_reason = String(cycle.get("reason", "收获模拟失败"))
					break

		stage["harvest_cycles"] = int(state.get("harvest_cycles", 0)) - harvest_cycles_before
		stage["clicks"] = int(state.get("clicks", 0)) - clicks_before
		stage["seconds"] = float(state.get("seconds", 0.0)) - stage_start_seconds
		stage["duration_seconds"] = stage["seconds"]
		stage["cultivation_after"] = float(state.get("cultivation", 0.0))
		stage["spirit_stones_after"] = float(state.get("spirit_stones", 0.0))
		stage["qi_after"] = float(state.get("qi", 0.0))
		stage["auto_cultivation"] = float(state.get("auto_cultivation", 0.0)) - auto_cultivation_before
		stage["auto_qi"] = float(state.get("auto_qi", 0.0)) - auto_qi_before
		stage["completed"] = blocked_reason == "" and float(state.get("cultivation", 0.0)) >= required_cultivation
		stages.append(stage)
		if blocked_reason != "":
			break

	var completed := blocked_reason == "" and target_realm <= start_realm + stages.size()
	return {
		"completed": completed,
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
		"season_index": int(model.get("season_index", 0)),
		"season_name": String(BalanceConfig.SEASONS[int(model.get("season_index", 0))].get("name", "")),
		"talent_nodes": talent_nodes,
		"total_seconds": float(state.get("seconds", 0.0)),
		"total_clicks": int(state.get("clicks", 0)),
		"final_cultivation": float(state.get("cultivation", 0.0)),
		"final_spirit_stones": float(state.get("spirit_stones", 0.0)),
		"final_qi": float(state.get("qi", 0.0)),
		"harvest_cycles": int(state.get("harvest_cycles", 0)),
		"total_harvest_count": int(state.get("total_harvest_count", 0)),
		"auto_cultivation": float(state.get("auto_cultivation", 0.0)),
		"auto_qi": float(state.get("auto_qi", 0.0)),
		"harvested": state.get("harvested", {}),
		"crop_proficiency": state.get("crop_proficiency", {}),
		"stages": stages,
		"cultivation_mode": "灵田收获直接结算修为",
	}


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
	state["cultivation"] = float(state.get("cultivation", 0.0)) + cultivation_gain
	state["spirit_stones"] = float(state.get("spirit_stones", 0.0)) + stones_gain
	state["harvest_cycles"] = int(state.get("harvest_cycles", 0)) + 1
	var click_count := int(ceil(minf(cycle_seconds * available_click_rate, float(total_clicks_needed)))) if available_click_rate > 0.0 else 0
	state["clicks"] = int(state.get("clicks", 0)) + click_count
	var harvested: Dictionary = state.get("harvested", {})
	harvested[crop_id] = int(harvested.get(crop_id, 0)) + amount
	state["harvested"] = harvested
	var proficiency: Dictionary = state.get("crop_proficiency", {})
	proficiency[crop_id] = int(proficiency.get(crop_id, 0)) + field_count
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
	state["cultivation"] = float(state.get("cultivation", 0.0)) + cultivation_gain
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
