class_name BreakthroughService
extends RefCounted

static func preview(run: RunState, lineage: LineageState) -> Dictionary:
	var status := ProgressionService.target_status(run, lineage)
	if String(status.get("id", "")).is_empty():
		return status
	var requirements: Dictionary = status.get("materials", {})
	var main_material := String(requirements.keys()[0]) if not requirements.is_empty() else ""
	var missing := {}
	for material_id in requirements:
		var required: BigCounter = requirements[material_id]
		var available := lineage.materials.available(String(material_id))
		missing[String(material_id)] = required.subtract(available)
	return {
		"id": status["id"],
		"name": status["name"],
		"requirement": status["requirement"],
		"current": status["current"],
		"cultivation_ready": bool(status["eligible"]),
		"materials_ready": lineage.materials.can_afford(requirements),
		"probability": status["probability"],
		"failures": status["failures"],
		"failure_count": status["failures"],
		"hard_pity_remaining": status["hard_pity_remaining"],
		"materials": requirements,
		"missing": missing,
		"main_material": main_material,
		"failure_loss": (requirements[main_material] as BigCounter).ceil_div_int(20) if not main_material.is_empty() else BigCounter.zero(),
		"golden": bool(status.get("golden", false)),
	}


static func attempt_batch(run: RunState, lineage: LineageState, rng: RandomNumberGenerator, max_attempts: int = 9, continue_after_probability_failure := true, reserve_for_hard_pity := true) -> Dictionary:
	var output := {"attempts": [], "success": false, "reason": ""}
	var target_id := run.active_target_id
	if target_id.is_empty():
		output["reason"] = "NO_LEGAL_REALM_TARGET"
		return output
	if not run.pending_tribulation.is_empty() or not run.pending_breakthrough_id.is_empty():
		output["reason"] = "BREAKTHROUGH_IN_PROGRESS"
		return output
	var definition := BalanceConfig.node(target_id)
	if not BalanceConfig.legal_node(target_id, run.inherited_history):
		output["reason"] = "NO_LEGAL_REALM_TARGET"
		return output
	if run.inherited_history.has(target_id) or run.completed_nodes.has(target_id):
		output["reason"] = "ALREADY_DISCOVERED"
		return output
	if not bool(definition.get("content_enabled", false)):
		output["reason"] = "CONTENT_DISABLED"
		return output
	if run.total_cultivation.compare(BalanceConfig.node_requirement(target_id)) < 0:
		output["reason"] = "CULTIVATION_BELOW_REQUIREMENT"
		return output
	var requirements := BalanceConfig.material_requirements(target_id)
	if requirements.is_empty():
		output["reason"] = "MATERIAL_SOURCE_NOT_UNLOCKED"
		return output
	var main_material := String(requirements.keys()[0])
	var attempts_limit := clampi(max_attempts, 1, 9)
	if reserve_for_hard_pity:
		lineage.materials.refresh_hard_pity_reservation(requirements, int(definition.get("hard_pity", 1)), int(lineage.breakthrough_failures.get(target_id, 0)))
	for _index in range(attempts_limit):
		if not lineage.materials.can_afford(requirements):
			output["reason"] = "MATERIAL_SOURCE_NOT_UNLOCKED"
			break
		var failure_count := int(lineage.breakthrough_failures.get(target_id, 0))
		var probability := BalanceConfig.node_probability(target_id, failure_count)
		if not lineage.materials.begin_escrow(requirements):
			output["reason"] = "MATERIAL_SOURCE_NOT_UNLOCKED"
			break
		var success := rng.randf() < probability
		var receipt := {"attempt": _index + 1, "probability": probability, "success": success, "failure_count_before": failure_count}
		if success:
			lineage.materials.settle_escrow_success(requirements)
			lineage.materials.clear_hard_pity_reservation(requirements)
			lineage.breakthrough_failures[target_id] = 0
			output["success"] = true
			receipt["result"] = "SUCCESS"
			output["attempts"].append(receipt)
			if bool(definition.get("golden", false)):
				run.pending_tribulation = {
					"node_id": target_id,
					"total_damage": String(definition.get("damage", "0")),
					"strike_count": int(definition.get("strikes", 1)),
					"locked_hp": "",
					"started": false,
				}
				run.pending_breakthrough_id = target_id
			else:
				_finalize_discovery(run, target_id)
			output["reason"] = "SUCCESS"
			break
		lineage.materials.settle_escrow_failure(requirements, main_material)
		lineage.breakthrough_failures[target_id] = failure_count + 1
		if reserve_for_hard_pity:
			lineage.materials.refresh_hard_pity_reservation(requirements, int(definition.get("hard_pity", 1)), failure_count + 1)
		receipt["result"] = "FAILURE"
		receipt["failure_loss"] = requirements[main_material].ceil_div_int(20).digits
		output["attempts"].append(receipt)
		if not continue_after_probability_failure:
			break
		if _index + 1 >= attempts_limit:
			output["reason"] = "BATCH_LIMIT"
	if output["attempts"].is_empty() and String(output["reason"]).is_empty():
		output["reason"] = "NO_ATTEMPT"
	return output


static func complete_tribulation(run: RunState) -> Dictionary:
	if run.pending_tribulation.is_empty():
		return {"success": false, "reason": "NO_PENDING_TRIBULATION"}
	var locked_hp := BigCounter.from_string(String(run.pending_tribulation.get("locked_hp", "0")))
	var damage := BigCounter.from_string(String(run.pending_tribulation.get("total_damage", "0")))
	if locked_hp.is_zero():
		return {"success": false, "reason": "HP_NOT_LOCKED"}
	var outcome := TribulationService.evaluate(locked_hp, damage)
	if bool(outcome["success"]):
		_finalize_discovery(run, String(run.pending_tribulation.get("node_id", "")))
		run.pending_tribulation = {}
		run.pending_breakthrough_id = ""
	return outcome


static func lock_tribulation_hp(run: RunState) -> Dictionary:
	if run.pending_tribulation.is_empty():
		return {"ok": false, "reason": "NO_PENDING_TRIBULATION"}
	if String(run.pending_tribulation.get("locked_hp", "")).is_empty():
		run.pending_tribulation["locked_hp"] = run.max_hp.digits
		run.pending_tribulation["started"] = true
	return {"ok": true, "locked_hp": run.max_hp}


static func _finalize_discovery(run: RunState, node_id: String) -> void:
	if node_id.is_empty() or run.completed_nodes.has(node_id):
		return
	run.completed_nodes.append(node_id)
	if not run.discoveries.has(node_id):
		run.discoveries.append(node_id)
	run.active_target_id = ""
	run.target_selected_cultivation = run.total_cultivation.duplicate_value()
