class_name WorldSimulator
extends RefCounted

## 事件边界模拟器。它整段积分连续速率，只有在目标、软墙、自动动作和重置处切段。

const MAX_AUTOMATION_INTERVAL_SECONDS := 10.0

static func advance(run: RunState, lineage: LineageState, legacy: LegacyState, farm: FarmPortfolio, policy: AutomationPolicyState, receipts: ReceiptState, rng: RandomNumberGenerator, seconds: float, allow_auto_reset := false) -> Dictionary:
	var remaining := maxf(0.0, seconds)
	var boundaries := 0
	var zero_actions := 0
	var seen_zero_states := {}
	var report := {
		"seconds": 0.0,
		"boundaries": 0,
		"auto_actions": 0,
		"breakthroughs": [],
		"tribulations": [],
		"resets": 0,
		"stopped_reason": "",
	}
	ProgressionService.ensure_target(run, policy)
	while remaining > 0.000001 and boundaries < BalanceConfig.MAX_OFFLINE_BOUNDARIES:
		boundaries += 1
		if run.status == "AWAITING_RESET":
			if allow_auto_reset and _can_auto_reset(run, lineage, legacy, policy):
				var reset_result := ResetService.commit(run, lineage, legacy, farm, policy)
				lineage.lineage_seed = 731927 + lineage.generation
				rng.seed = lineage.lineage_seed
				report["resets"] += 1
				report["auto_actions"] += 1
				receipts.append_receipt({"kind": "reincarnation", "dao_gain": reset_result["dao_gain"].to_dict(), "discoveries": reset_result["new_discoveries"]})
				continue
			report["stopped_reason"] = "AWAITING_RESET"
			break
		var signature := _automation_signature(run, lineage, farm, policy, remaining)
		if seen_zero_states.has(signature):
			report["stopped_reason"] = "AUTOMATION_LOOP"
			break
		seen_zero_states[signature] = true

		var action := _zero_time_actions(run, lineage, legacy, farm, policy, receipts, rng)
		zero_actions += int(action.get("count", 0))
		report["auto_actions"] += int(action.get("count", 0))
		for breakthrough in action.get("breakthroughs", []):
			report["breakthroughs"].append(breakthrough)
		for tribulation in action.get("tribulations", []):
			report["tribulations"].append(tribulation)
		if bool(action.get("reset", false)):
			report["resets"] += 1
			continue
		if zero_actions > BalanceConfig.MAX_ZERO_TIME_ACTIONS:
			report["stopped_reason"] = "AUTOMATION_LOOP"
			break

		var rates := RateEngine.calculate(run, lineage, legacy, farm, policy)
		var step := remaining
		var efficiency_boundary := _next_efficiency_boundary(run.elapsed_seconds)
		if efficiency_boundary > 0.0:
			step = minf(step, efficiency_boundary)
		var target_boundary := _time_to_target(run, rates)
		if target_boundary > 0.000001:
			step = minf(step, target_boundary)
		if _has_timed_automation(run, lineage, legacy, policy):
			# Material credit and ROI purchases can become actionable inside a
			# large offline interval. Keep the batch path bounded while ensuring
			# the next automation pass does not wait until the whole interval ends.
			step = minf(step, MAX_AUTOMATION_INTERVAL_SECONDS)
		if step <= 0.000001:
			# 到达一个边界，下一轮只执行零时间动作。
			zero_actions += 1
			continue
		_apply_interval(run, lineage, legacy, farm, policy, receipts, rates, step)
		remaining -= step
		report["seconds"] += step
		zero_actions = 0
		if run.elapsed_seconds >= BalanceConfig.SOFT_WALL_END_SECONDS - 0.000001:
			run.status = "AWAITING_RESET"
			run.production_efficiency = 0.0
		report["boundaries"] = boundaries
	if boundaries >= BalanceConfig.MAX_OFFLINE_BOUNDARIES and remaining > 0.000001:
		report["stopped_reason"] = "ACTION_BUDGET"
	report["boundaries"] = boundaries
	return report


static func _apply_interval(run: RunState, lineage: LineageState, legacy: LegacyState, farm: FarmPortfolio, policy: AutomationPolicyState, receipts: ReceiptState, rates: Dictionary, seconds: float) -> void:
	var start_efficiency := float(rates.get("efficiency", 1.0))
	var average_efficiency := BalanceConfig.average_soft_wall_efficiency(run.elapsed_seconds, seconds)
	var efficiency_ratio := average_efficiency / start_efficiency if start_efficiency > 0.0 else 0.0
	var integrated_rates := _scale_rates_for_interval(rates, efficiency_ratio)
	var cultivation_delta: BigMagnitude = integrated_rates["cultivation_per_second"].multiply_scalar(seconds)
	run.total_cultivation = run.total_cultivation.add(cultivation_delta)
	run.spirit_stones = run.spirit_stones.add((integrated_rates.get("base_stone_per_second", integrated_rates["stone_per_second"]) as BigMagnitude).multiply_scalar(seconds))
	run.body_power = run.body_power.add((integrated_rates["body_per_second"] as BigMagnitude).multiply_scalar(seconds))
	run.spirit_power = run.spirit_power.add((integrated_rates["spirit_per_second"] as BigMagnitude).multiply_scalar(seconds))
	ProgressionService.add_training_credit(lineage.materials, run, cultivation_delta)
	var treasure_result := TreasureBatchService.settle(lineage.treasure, lineage.materials, run, integrated_rates, seconds)
	run.spirit_stones = run.spirit_stones.add(treasure_result["stone_gain"])
	run.body_power = run.body_power.add((treasure_result["body_essence"] as BigCounter).to_magnitude())
	run.spirit_power = run.spirit_power.add((treasure_result["spirit_essence"] as BigCounter).to_magnitude())
	if not (treasure_result["receipt"] as Dictionary).get("chests", {}).is_empty():
		receipts.append_receipt(treasure_result["receipt"])
	run.elapsed_seconds += seconds
	run.production_efficiency = BalanceConfig.soft_wall_efficiency(run.elapsed_seconds)
	_update_hp(run, lineage, legacy)


static func _zero_time_actions(run: RunState, lineage: LineageState, legacy: LegacyState, farm: FarmPortfolio, policy: AutomationPolicyState, receipts: ReceiptState, rng: RandomNumberGenerator) -> Dictionary:
	var output := {"count": 0, "breakthroughs": [], "tribulations": [], "reset": false}
	# 自动购买只在历史解锁后运行，且只改变之后的连续速率。
	if _automation_enabled(legacy, policy, "auto_purchase_max"):
		var snapshot := RateEngine.calculate(run, lineage, legacy, farm, policy)
		var purchase := FarmEconomyService.auto_purchase(farm, run.spirit_stones, policy, snapshot)
		if bool(purchase.get("changed", false)):
			run.spirit_stones = run.spirit_stones.subtract(purchase["spent"])
			output["count"] += 1

	# 自动突破只在玩家明确打开批次策略且节点尚未入史时运行。
	if _automation_enabled(legacy, policy, "auto_breakthrough") and not run.active_target_id.is_empty() and run.pending_tribulation.is_empty():
		var preview := BreakthroughService.preview(run, lineage)
		if bool(preview.get("cultivation_ready", false)) and bool(preview.get("materials_ready", false)):
			var target_id := run.active_target_id
			var batch := BreakthroughService.attempt_batch(run, lineage, rng, policy.max_attempts_per_batch, policy.continue_after_probability_failure, policy.reserve_for_hard_pity)
			if not batch.get("attempts", []).is_empty():
				receipts.append_receipt({"kind": "breakthrough_batch", "node_id": target_id, "attempts": batch["attempts"]})
				if bool(batch.get("success", false)) and run.pending_tribulation.is_empty():
					ProgressionService.ensure_target(run, policy)
				output["breakthroughs"].append(batch)
				output["count"] += 1

	# 金丹雷劫只在达到玩家安全余量时自动锁定并结算。
	if _automation_enabled(legacy, policy, "auto_tribulation") and not run.pending_tribulation.is_empty() and policy.tribulation_mode != "manual":
		var damage := BigCounter.from_string(String(run.pending_tribulation.get("total_damage", "0")))
		var required_hp := damage.add(BigCounter.one())
		if policy.tribulation_mode == "safe":
			required_hp = damage.to_magnitude().multiply_scalar(policy.tribulation_hp_margin).ceil_to_big_counter().add(BigCounter.one())
		if run.max_hp.compare(required_hp) >= 0:
			var node_id := String(run.pending_tribulation.get("node_id", ""))
			BreakthroughService.lock_tribulation_hp(run)
			var result := BreakthroughService.complete_tribulation(run)
			if bool(result.get("success", false)):
				ProgressionService.ensure_target(run, policy)
			receipts.append_receipt({"kind": "tribulation", "node_id": node_id, "result": result})
			output["tribulations"].append(result)
			output["count"] += 1

	return output


static func _time_to_target(run: RunState, rates: Dictionary) -> float:
	if run.active_target_id.is_empty():
		return INF
	var requirement := BalanceConfig.node_requirement(run.active_target_id)
	if run.total_cultivation.compare(requirement) >= 0:
		# A ready target is an action boundary only when an automation policy
		# handles it. Manual breakthrough, missing materials and pending HP
		# tribulation must keep receiving the same continuous production.
		return INF
	var rate: BigMagnitude = rates.get("cultivation_per_second", BigMagnitude.zero())
	if rate.is_zero():
		return INF
	return requirement.subtract(run.total_cultivation).divide(rate).to_float()


static func _next_efficiency_boundary(elapsed: float) -> float:
	if elapsed < BalanceConfig.SOFT_WALL_START_SECONDS:
		return BalanceConfig.SOFT_WALL_START_SECONDS - elapsed
	if elapsed < BalanceConfig.SOFT_WALL_END_SECONDS:
		return BalanceConfig.SOFT_WALL_END_SECONDS - elapsed
	return 0.0


static func _update_hp(run: RunState, lineage: LineageState, legacy: LegacyState) -> void:
	var layers := BalanceConfig.hp_layers(run, lineage, legacy)
	var body_hp_value := run.body_power.sqrt_value()
	body_hp_value = body_hp_value.multiply_scalar(float(layers.get("selected_route_hp_layer", 1.0)))
	body_hp_value = body_hp_value.multiply_scalar(float(layers.get("lineage_hp_layer", 1.0)))
	body_hp_value = body_hp_value.multiply_scalar(float(layers.get("legacy_hp_layer", 1.0)))
	var body_hp := body_hp_value.floor_to_big_counter()
	run.max_hp = body_hp.add(BigCounter.from_int(100))
	if run.pending_tribulation.is_empty() or String(run.pending_tribulation.get("locked_hp", "")).is_empty():
		run.current_hp = run.max_hp.duplicate_value()


static func _can_auto_reset(run: RunState, lineage: LineageState, legacy: LegacyState, policy: AutomationPolicyState) -> bool:
	if not _automation_enabled(legacy, policy, "auto_reincarnation"):
		return false
	if not policy.allow_offline_reincarnation or not policy.explicit_offline_authorization:
		return false
	return bool(ResetService.preview(run, lineage).get("can_reset", false))


static func _has_timed_automation(run: RunState, lineage: LineageState, legacy: LegacyState, policy: AutomationPolicyState) -> bool:
	return _automation_enabled(legacy, policy, "auto_purchase_max") or _automation_enabled(legacy, policy, "auto_breakthrough") or _automation_enabled(legacy, policy, "auto_tribulation")


static func _automation_signature(run: RunState, lineage: LineageState, farm: FarmPortfolio, policy: AutomationPolicyState, remaining: float) -> String:
	var state := {
		"run": run.to_dict(),
		"farm": farm.to_dict(),
		"materials": lineage.materials.to_dict(),
		"policy": policy.policy_hash(),
	}
	return "%s|%.9f" % [str(hash(JSON.stringify(state))), remaining]


static func _automation_enabled(legacy: LegacyState, policy: AutomationPolicyState, blueprint: String) -> bool:
	return legacy.automation_blueprints.has(blueprint) and policy.enabled_blueprints.has(blueprint)


static func _scale_rates_for_interval(rates: Dictionary, ratio: float) -> Dictionary:
	if is_equal_approx(ratio, 1.0):
		return rates
	var output := rates.duplicate(true)
	for key in ["cultivation_per_second", "stone_per_second", "base_stone_per_second", "body_per_second", "spirit_per_second", "source_cultivation_before_realm"]:
		if output.get(key) is BigMagnitude:
			output[key] = (output[key] as BigMagnitude).multiply_scalar(maxf(0.0, ratio))
	for key in ["treasure_work_per_second_by_tier", "source_stones_by_tier"]:
		var values: Dictionary = output.get(key, {})
		for tier in values:
			values[tier] = (values[tier] as BigMagnitude).multiply_scalar(maxf(0.0, ratio))
	return output
