class_name ResetService
extends RefCounted

static func preview(run: RunState, lineage: LineageState) -> Dictionary:
	var dao_gain := BalanceConfig.dao_gain(run.total_cultivation, run.discoveries)
	var before := BalanceConfig.dao_multiplier(lineage.total_dao)
	var after := BalanceConfig.dao_multiplier(lineage.total_dao.add(dao_gain))
	return {
		"dao_gain": dao_gain,
		"dao_multiplier_before": before,
		"dao_multiplier_after": after,
		"new_discoveries": run.discoveries.duplicate(),
		"can_reset": not run.discoveries.is_empty() or dao_gain.compare(BigMagnitude.one()) >= 0,
		"reason": "" if (not run.discoveries.is_empty() or dao_gain.compare(BigMagnitude.one()) >= 0) else "RESET_GAIN_ZERO",
		"compression_hint": 0.20 if not run.discoveries.is_empty() else 1.0,
	}


static func commit(run: RunState, lineage: LineageState, legacy: LegacyState, farm: FarmPortfolio, policy: AutomationPolicyState) -> Dictionary:
	var result := preview(run, lineage)
	if not bool(result["can_reset"]):
		return result
	lineage.total_dao = lineage.total_dao.add(result["dao_gain"])
	lineage.lifetime_cultivation = lineage.lifetime_cultivation.add(run.total_cultivation)
	for node_id in run.discoveries:
		if not lineage.historical_realm_unlocks.has(node_id):
			lineage.historical_realm_unlocks.append(node_id)
		legacy.lifetime_discoveries[String(node_id)] = true
	lineage.generation += 1
	lineage.breakthrough_failures = lineage.breakthrough_failures
	var next_history := lineage.historical_realm_unlocks.duplicate()
	run.reset_for_birth(next_history, lineage.generation)
	farm.field_level = BalanceConfig.INITIAL_FIELD_LEVEL
	farm.soil_tier = BalanceConfig.INITIAL_SOIL_TIER
	farm.array_level = BalanceConfig.INITIAL_ARRAY_LEVEL
	ProgressionService.apply_birth_plan(run, farm, policy)
	ProgressionService.update_birth_automation(run, lineage, legacy)
	ProgressionService.ensure_target(run, policy)
	return result
