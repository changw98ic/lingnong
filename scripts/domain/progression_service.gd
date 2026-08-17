class_name ProgressionService
extends RefCounted

static func choose_target(run: RunState, policy: AutomationPolicyState, target_id: String) -> Dictionary:
	if not BalanceConfig.legal_node(target_id, run.inherited_history):
		return {"ok": false, "reason": "NO_LEGAL_REALM_TARGET"}
	if run.inherited_history.has(target_id) or run.completed_nodes.has(target_id):
		return {"ok": false, "reason": "ALREADY_DISCOVERED"}
	if not run.pending_tribulation.is_empty() or not run.pending_breakthrough_id.is_empty():
		return {"ok": false, "reason": "BREAKTHROUGH_IN_PROGRESS"}
	run.active_target_id = target_id
	run.target_selected_cultivation = run.total_cultivation.duplicate_value()
	return {"ok": true, "reason": ""}


static func ensure_target(run: RunState, policy: AutomationPolicyState) -> String:
	if not run.active_target_id.is_empty() and BalanceConfig.legal_node(run.active_target_id, run.inherited_history) and not run.inherited_history.has(run.active_target_id) and not run.completed_nodes.has(run.active_target_id):
		return run.active_target_id
	var preferred := {}
	for stage in policy.realm_plan_by_stage:
		preferred[String(policy.realm_plan_by_stage[stage])] = true
	var target := BalanceConfig.default_target(run.inherited_history, preferred, run.completed_nodes)
	if not target.is_empty():
		run.active_target_id = target
		run.target_selected_cultivation = run.total_cultivation.duplicate_value()
	return target


static func add_training_credit(ledger: MaterialLedger, run: RunState, cultivation_delta: BigMagnitude) -> void:
	if run.active_target_id.is_empty() or cultivation_delta.is_zero():
		return
	var definition := BalanceConfig.node(run.active_target_id)
	var weights: Dictionary = definition.get("materials", {})
	var credit_pool := cultivation_delta.multiply_scalar(0.015)
	for material_id in weights:
		ledger.add_target_credit(run.active_target_id, String(material_id), credit_pool.multiply_scalar(float(weights[material_id])))


static func target_status(run: RunState, lineage: LineageState) -> Dictionary:
	var node_id := run.active_target_id
	if node_id.is_empty():
		return {"id": "", "name": "无目标", "requirement": BigMagnitude.zero(), "eligible": false, "reason": "NO_TARGET"}
	var definition := BalanceConfig.node(node_id)
	var requirement := BalanceConfig.node_requirement(node_id)
	var failures := int(lineage.breakthrough_failures.get(node_id, 0))
	return {
		"id": node_id,
		"name": String(definition.get("name", node_id)),
		"requirement": requirement,
		"current": run.total_cultivation,
		"eligible": run.total_cultivation.compare(requirement) >= 0,
		"probability": BalanceConfig.node_probability(node_id, failures),
		"failures": failures,
		"hard_pity": int(definition.get("hard_pity", 1)),
		"hard_pity_remaining": maxi(0, int(definition.get("hard_pity", 1)) - failures - 1),
		"materials": BalanceConfig.material_requirements(node_id),
		"golden": bool(definition.get("golden", false)),
	}


static func update_birth_automation(run: RunState, lineage: LineageState, legacy: LegacyState) -> void:
	var unlocks := {}
	for node_id in run.inherited_history:
		for reward in BalanceConfig.AUTOMATION_REWARDS.get(String(node_id), []):
			unlocks[String(reward)] = true
	for key in unlocks:
		if not legacy.automation_blueprints.has(key):
			legacy.automation_blueprints.append(key)


static func apply_birth_plan(run: RunState, farm: FarmPortfolio, policy: AutomationPolicyState) -> void:
	run.active_inherited_path = _select_inherited_path(run.inherited_history, policy)
	var filtered := {}
	for crop_id in policy.production_plan:
		var crop := BalanceConfig.crop(String(crop_id))
		if crop.is_empty():
			continue
		var unlock_node := String(crop.get("unlock_node", ""))
		if unlock_node.is_empty() or run.inherited_history.has(unlock_node):
			filtered[String(crop_id)] = float(policy.production_plan[crop_id])
	if filtered.is_empty():
		filtered = {"gathering_grass": 1.0}
	farm.set_plan(filtered)
	policy.production_plan = farm.plan()


static func _select_inherited_path(history: Array, policy: AutomationPolicyState) -> Dictionary:
	var output := {}
	for major in ["qi", "foundation", "golden"]:
		var requested := String(policy.realm_plan_by_stage.get(major, ""))
		if not requested.is_empty() and history.has(requested):
			output[major] = requested
			continue
		var best_id := ""
		var best_h := -1
		for node_id in history:
			var definition := BalanceConfig.node(String(node_id))
			if String(definition.get("major", "")) != major:
				continue
			var node_h := int(definition.get("H", 0))
			if node_h > best_h:
				best_h = node_h
				best_id = String(node_id)
		if not best_id.is_empty():
			output[major] = best_id
	return output
