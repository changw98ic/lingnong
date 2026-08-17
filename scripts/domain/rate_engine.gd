class_name RateEngine
extends RefCounted

## 所有在线、离线、ETA 和界面展示都调用同一套速率计算。

static func calculate(run: RunState, lineage: LineageState, legacy: LegacyState, farm: FarmPortfolio, policy: AutomationPolicyState) -> Dictionary:
	var h_total := BalanceConfig.h_total(run.inherited_history, run.completed_nodes)
	var dao_multiplier := BalanceConfig.dao_multiplier(lineage.total_dao)
	var law_multiplier := _law_multiplier(legacy)
	var field_power := _field_power(farm)
	var efficiency := BalanceConfig.soft_wall_efficiency(run.elapsed_seconds)
	var route := _route_layers(run, lineage)
	var cultivation := BigMagnitude.zero()
	var stones := BigMagnitude.zero()
	var body := BigMagnitude.zero()
	var spirit := BigMagnitude.zero()
	var treasure_by_tier := {"common": BigMagnitude.zero(), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}
	var source_stones_by_tier := {"common": BigMagnitude.zero(), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}
	var source_cultivation := BigMagnitude.zero()
	var breakdown: Array = []

	for cohort in farm.cohorts:
		var crop_id := String(cohort.get("crop_id", ""))
		var crop := BalanceConfig.crop(crop_id)
		if crop.is_empty():
			continue
		var ratio := clampf(float(cohort.get("allocation_ratio", 0.0)), 0.0, 1.0)
		var work := field_power.multiply_scalar(ratio)
		var crop_cult := work.multiply_scalar(float(crop.get("cultivation_per_work", 0.0)))
		var crop_stones := work.multiply_scalar(float(crop.get("stone_per_work", 0.0)))
		var cult_contribution := crop_cult.multiply(BigMagnitude.pow10(h_total)).multiply(dao_multiplier).multiply(law_multiplier)
		cult_contribution = cult_contribution.multiply_scalar(efficiency * route["cultivation_mult"])
		var stone_contribution := crop_stones.multiply(BigMagnitude.pow10(h_total).pow_value(0.25)).multiply(dao_multiplier.sqrt_value()).multiply(law_multiplier)
		stone_contribution = stone_contribution.multiply_scalar(efficiency * route["stone_mult"])
		cultivation = cultivation.add(cult_contribution)
		stones = stones.add(stone_contribution)
		source_cultivation = source_cultivation.add(crop_cult)
		var target_node := BalanceConfig.node(run.active_target_id)
		var body_share := float(target_node.get("body_share", 0.0))
		var spirit_share := float(target_node.get("spirit_share", 0.0))
		body = body.add(cult_contribution.multiply_scalar(body_share * float(crop.get("body_factor", 1.0)) * route["body_mult"]))
		spirit = spirit.add(cult_contribution.multiply_scalar(spirit_share * float(crop.get("spirit_factor", 1.0)) * route["spirit_mult"]))
		var tier := String(crop.get("treasure_tier", "common"))
		var treasure_work := work.multiply_scalar(float(crop.get("treasure_work_ratio", 1.0)))
		treasure_work = treasure_work.multiply(BigMagnitude.pow10(h_total).pow_value(0.5)).multiply(dao_multiplier.sqrt_value())
		treasure_work = treasure_work.multiply_scalar(efficiency * route["treasure_mult"])
		treasure_by_tier[tier] = (treasure_by_tier[tier] as BigMagnitude).add(treasure_work)
		source_stones_by_tier[tier] = (source_stones_by_tier[tier] as BigMagnitude).add(stone_contribution)

	# 宝箱的必得灵石计入展示速率，但只按箱级通道计算一次，不递归使用箱子灵石。
	var base_stones := stones.duplicate_value()
	for tier in treasure_by_tier:
		var rule: Dictionary = BalanceConfig.TREASURE_RULES.get(tier, {})
		stones = stones.add((source_stones_by_tier[tier] as BigMagnitude).multiply_scalar(float(rule.get("stone_ratio", 0.0))))

	breakdown.append({"id": "farm", "label": "灵田农力", "log10": field_power.log10()})
	breakdown.append({"id": "realm", "label": "境界 H 乘区", "log10": float(h_total)})
	breakdown.append({"id": "dao", "label": "道蕴乘区", "log10": dao_multiplier.log10()})
	breakdown.append({"id": "law", "label": "法则乘区", "log10": law_multiplier.log10()})
	breakdown.append({"id": "route", "label": "路线层", "log10": log(route["cultivation_mult"]) / log(10.0)})
	return {
		"base_farm_work_per_second": field_power,
		"cultivation_per_second": cultivation,
		"stone_per_second": stones,
		"base_stone_per_second": base_stones,
		"body_per_second": body,
		"spirit_per_second": spirit,
		"treasure_work_per_second_by_tier": treasure_by_tier,
		"source_stones_by_tier": source_stones_by_tier,
		"source_cultivation_before_realm": source_cultivation,
		"multiplier_breakdown": breakdown,
		"h_total": h_total,
		"field_power": field_power,
		"efficiency": efficiency,
		"route_layers": route,
		"hp_layers": BalanceConfig.hp_layers(run, lineage, legacy),
	}


static func _field_power(farm: FarmPortfolio) -> BigMagnitude:
	var field_level := maxi(1, farm.field_level)
	var power := BigMagnitude.from_exact_integer(str(field_level)).multiply(BigMagnitude.from_exact_integer(str(int(BalanceConfig.SHARED_FARM_LAYERS))))
	var milestone_level := int(field_level / 25)
	power = power.multiply(BigMagnitude.from_float(2.0).pow_value(float(milestone_level)))
	power = power.multiply(BigMagnitude.pow10(farm.soil_tier))
	power = power.multiply(BigMagnitude.from_float(1.15).pow_value(float(farm.array_level)))
	return power


static func _law_multiplier(legacy: LegacyState) -> BigMagnitude:
	return BalanceConfig.law_multiplier(legacy.total_laws)


static func _route_layers(run: RunState, lineage: LineageState) -> Dictionary:
	var all_nodes := run.inherited_history + run.completed_nodes
	var layers := {"cultivation_mult": 1.0, "stone_mult": 1.0, "treasure_mult": 1.0, "body_mult": 1.0, "spirit_mult": 1.0}
	if all_nodes.has("foundation_dan"):
		layers["treasure_mult"] *= 100.0
	if all_nodes.has("foundation_human"):
		var body_log := maxf(0.0, float(run.body_power.log10()))
		layers["cultivation_mult"] *= pow(10.0, minf(3.0, body_log * 0.02))
	if all_nodes.has("foundation_heaven"):
		layers["cultivation_mult"] *= 1000.0
		layers["body_mult"] *= 1000.0
		layers["spirit_mult"] *= 1000.0
	if all_nodes.has("qi_heaven"):
		layers["body_mult"] *= pow(10.0, minf(3.0, run.body_power.log10() * 0.10))
		layers["spirit_mult"] *= pow(10.0, minf(3.0, run.spirit_power.log10() * 0.10))
	if all_nodes.has("foundation_five"):
		layers["cultivation_mult"] *= 10.0
	return layers
