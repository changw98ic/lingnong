extends Node

signal state_changed
signal realm_changed

## GameState 只做应用层门面：保存状态、接受命令、调用领域服务、发出聚合收据。

var run: RunState = RunState.new()
var lineage: LineageState = LineageState.new()
var legacy: LegacyState = LegacyState.new()
var farm: FarmPortfolio = FarmPortfolio.new()
var policy: AutomationPolicyState = AutomationPolicyState.new()
var receipts: ReceiptState = ReceiptState.new()
var rng := RandomNumberGenerator.new()
var treasure_rng := RandomNumberGenerator.new()

var revision := 0
var saved_at_unix := 0
var last_offline_report: Dictionary = {}
var last_command_receipts: Dictionary = {}
var last_migration_report: Dictionary = {}
var offline_time_bank := 0.0
var offline_policy_hash := ""
var last_offline_tx_id := ""

const MAX_COMMAND_RECEIPTS := 2048
const OFFLINE_FULL_RATE_SECONDS := 8.0 * 3600.0
const OFFLINE_HALF_RATE_SECONDS := 16.0 * 3600.0
const TREASURE_SEED_SALT := 104729


func _ready() -> void:
	initialize_new_game()


func initialize_new_game() -> void:
	run = RunState.new()
	lineage = LineageState.new()
	legacy = LegacyState.new()
	farm = FarmPortfolio.new()
	policy = AutomationPolicyState.new()
	policy.enabled_blueprints = []
	receipts = ReceiptState.new()
	run.reset_for_birth([], 1)
	run.active_target_id = "qi_common"
	run.target_selected_cultivation = BigMagnitude.zero()
	rng.seed = lineage.lineage_seed
	revision = 0
	saved_at_unix = int(Time.get_unix_time_from_system())
	last_offline_report = {}
	last_command_receipts = {}
	last_migration_report = {}
	offline_time_bank = 0.0
	offline_policy_hash = policy.policy_hash()
	last_offline_tx_id = ""
	_reseed_for_generation()
	lineage.treasure.initialize_entropy(treasure_rng)
	_emit_state()


func to_save_dict() -> Dictionary:
	var data := {
		"save_version": BalanceConfig.SAVE_VERSION,
		"content_version": BalanceConfig.CONTENT_VERSION,
		"revision": str(revision),
		"saved_at_unix": saved_at_unix if saved_at_unix > 0 else int(Time.get_unix_time_from_system()),
		"offline_time_bank": offline_time_bank,
		"offline_policy_hash": offline_policy_hash if not offline_policy_hash.is_empty() else policy.policy_hash(),
		"last_offline_tx_id": last_offline_tx_id,
		"simulation_cursor": "%d:%d" % [run.generation, run.action_seq],
		"run": run.to_dict(),
		"lineage": lineage.to_dict(),
		"legacy": legacy.to_dict(),
		"farm_portfolio": farm.to_dict(),
		"automation": policy.to_dict(),
		"receipts": receipts.to_dict(),
		"rng_streams": {
			"stream_version": 1,
			"generation": lineage.generation,
			"breakthrough_seed": str(lineage.lineage_seed),
			"breakthrough_state": str(rng.state),
			"treasure_seed": str(treasure_rng.seed),
			"treasure_state": str(treasure_rng.state),
		},
		"committed_commands": _encode_json_value(last_command_receipts),
	}
	if not last_migration_report.is_empty():
		data["migration_report"] = last_migration_report.duplicate(true)
	return data


func load_save_dict(data: Dictionary) -> bool:
	if int(data.get("save_version", 0)) != BalanceConfig.SAVE_VERSION:
		return false
	var validation := SaveValidator.validate(data, false)
	if not bool(validation.get("ok", false)):
		return false
	run = RunState.new()
	run.load_dict(data.get("run", {}) if data.get("run", {}) is Dictionary else {})
	lineage = LineageState.new()
	lineage.load_dict(data.get("lineage", {}) if data.get("lineage", {}) is Dictionary else {})
	legacy = LegacyState.new()
	legacy.load_dict(data.get("legacy", {}) if data.get("legacy", {}) is Dictionary else {})
	farm = FarmPortfolio.new()
	farm.load_dict(data.get("farm_portfolio", {}) if data.get("farm_portfolio", {}) is Dictionary else {})
	policy = AutomationPolicyState.new()
	policy.load_dict(data.get("automation", {}) if data.get("automation", {}) is Dictionary else {})
	receipts = ReceiptState.new()
	receipts.load_dict(data.get("receipts", {}) if data.get("receipts", {}) is Dictionary else {})
	revision = maxi(0, int(data.get("revision", 0)))
	saved_at_unix = maxi(0, int(data.get("saved_at_unix", Time.get_unix_time_from_system())))
	last_command_receipts = _decode_json_value(data.get("committed_commands", {})) if data.get("committed_commands", {}) is Dictionary else {}
	last_migration_report = data.get("migration_report", {}) if data.get("migration_report", {}) is Dictionary else {}
	last_offline_report = {}
	offline_time_bank = maxf(0.0, float(data.get("offline_time_bank", 0.0)))
	offline_policy_hash = String(data.get("offline_policy_hash", ""))
	last_offline_tx_id = String(data.get("last_offline_tx_id", ""))
	var rng_streams: Dictionary = data.get("rng_streams", {}) if data.get("rng_streams", {}) is Dictionary else {}
	var seed_value := int(rng_streams.get("breakthrough_seed", lineage.lineage_seed))
	rng.seed = seed_value
	if rng_streams.has("breakthrough_state"):
		rng.state = int(rng_streams.get("breakthrough_state", 0))
	var treasure_seed := int(rng_streams.get("treasure_seed", lineage.lineage_seed + TREASURE_SEED_SALT))
	treasure_rng.seed = treasure_seed
	if rng_streams.has("treasure_state"):
		treasure_rng.state = int(rng_streams.get("treasure_state", 0))
	else:
		lineage.treasure.initialize_entropy(treasure_rng)
	if run.inherited_history != lineage.historical_realm_unlocks:
		run.inherited_history = lineage.historical_realm_unlocks.duplicate()
	ProgressionService.apply_birth_plan(run, farm, policy)
	ProgressionService.update_birth_automation(run, lineage, legacy)
	ProgressionService.ensure_target(run, policy)
	if offline_policy_hash.is_empty():
		offline_policy_hash = policy.policy_hash()
	_emit_state()
	return true


func update_world(delta: float) -> Dictionary:
	var safe_delta := clampf(delta, 0.0, 5.0)
	if safe_delta <= 0.0:
		return {}
	var report := WorldSimulator.advance(run, lineage, legacy, farm, policy, receipts, rng, safe_delta, policy.allow_offline_reincarnation)
	run.action_seq += 1
	revision += 1
	_emit_state()
	return report


func advance_offline(wall_seconds: float, offline_tx_id := "", expected_revision := -1) -> Dictionary:
	var requested_wall := maxf(0.0, wall_seconds)
	var fingerprint := "offline|%s|%.6f" % [String(offline_tx_id), requested_wall]
	var guard := _command_guard(offline_tx_id, expected_revision, "offline:", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	var current_policy_hash := policy.policy_hash()
	if offline_time_bank > 0.000001 and not offline_policy_hash.is_empty() and offline_policy_hash != current_policy_hash:
		var policy_block := {"seconds": 0.0, "boundaries": 0, "auto_actions": 0, "breakthroughs": [], "tribulations": [], "resets": 0, "stopped_reason": "POLICY_HASH_MISMATCH", "wall_seconds": maxf(0.0, wall_seconds), "effective_seconds": 0.0, "time_bank_seconds": offline_time_bank}
		last_offline_report = policy_block
		if not String(offline_tx_id).is_empty():
			_commit_command("offline:" + String(offline_tx_id), policy_block, fingerprint)
		_emit_state()
		return policy_block
	var wall := clampf(requested_wall, 0.0, BalanceConfig.MAX_OFFLINE_WALL_SECONDS)
	var effective := minf(wall, OFFLINE_FULL_RATE_SECONDS) + 0.5 * minf(maxf(wall - OFFLINE_FULL_RATE_SECONDS, 0.0), OFFLINE_HALF_RATE_SECONDS)
	effective = minf(effective, BalanceConfig.MAX_OFFLINE_EFFECTIVE_SECONDS)
	var available_effective := minf(BalanceConfig.MAX_OFFLINE_EFFECTIVE_SECONDS, offline_time_bank + effective)
	offline_time_bank = 0.0
	offline_policy_hash = current_policy_hash
	last_offline_tx_id = String(offline_tx_id)
	if available_effective <= 0.0:
		var empty_report := {"seconds": 0.0, "boundaries": 0, "auto_actions": 0, "breakthroughs": [], "tribulations": [], "resets": 0, "stopped_reason": "", "wall_seconds": wall, "effective_seconds": 0.0, "time_bank_seconds": offline_time_bank}
		last_offline_report = empty_report
		if not String(offline_tx_id).is_empty():
			_commit_command("offline:" + String(offline_tx_id), empty_report, fingerprint)
		_emit_state()
		return empty_report
	var report := WorldSimulator.advance(run, lineage, legacy, farm, policy, receipts, rng, available_effective, policy.allow_offline_reincarnation)
	offline_policy_hash = policy.policy_hash()
	report["wall_seconds"] = wall
	report["effective_seconds"] = available_effective
	offline_time_bank = maxf(0.0, available_effective - float(report.get("seconds", 0.0)))
	report["time_bank_seconds"] = offline_time_bank
	last_offline_report = report
	revision += 1
	run.action_seq += 1
	if not String(offline_tx_id).is_empty():
		_commit_command("offline:" + String(offline_tx_id), report, fingerprint)
	_emit_state()
	return report


func get_rate_snapshot() -> Dictionary:
	return RateEngine.calculate(run, lineage, legacy, farm, policy)


func get_summary() -> Dictionary:
	var rates := get_rate_snapshot()
	var target := BreakthroughService.preview(run, lineage)
	var reset := ResetService.preview(run, lineage)
	var eta := _eta_summary(rates, target)
	return {
		"revision": revision,
		"generation": run.generation,
		"elapsed_seconds": run.elapsed_seconds,
		"status": run.status,
		"cultivation": run.total_cultivation,
		"cultivation_per_second": rates["cultivation_per_second"],
		"spirit_stones": run.spirit_stones,
		"stone_per_second": rates["stone_per_second"],
		"body_power": run.body_power,
		"spirit_power": run.spirit_power,
		"max_hp": run.max_hp,
		"efficiency": rates["efficiency"],
		"h_total": rates["h_total"],
		"target": target,
		"target_eta_seconds": eta["target"],
		"material_eta_seconds": eta["materials"],
		"hp_eta_seconds": eta["hp"],
		"reset": reset,
		"history": lineage.historical_realm_unlocks.duplicate(),
		"completed": run.completed_nodes.duplicate(),
		"plan": farm.plan(),
	}


func _eta_summary(rates: Dictionary, target: Dictionary) -> Dictionary:
	var target_eta := INF
	var cult_rate: BigMagnitude = rates.get("cultivation_per_second", BigMagnitude.zero())
	if not cult_rate.is_zero() and target.has("requirement"):
		var requirement: BigMagnitude = target["requirement"]
		if run.total_cultivation.compare(requirement) >= 0:
			target_eta = 0.0
		else:
			target_eta = requirement.subtract(run.total_cultivation).divide(cult_rate).to_float()
	var material_eta := 0.0
	var material_found := false
	if target.has("materials"):
		var definition := BalanceConfig.node(run.active_target_id)
		var weights: Dictionary = definition.get("materials", {})
		for material_id in target["materials"]:
			var required: BigCounter = target["materials"][material_id]
			var held := lineage.materials.amount(String(material_id))
			var missing := required.subtract(held)
			if missing.is_zero():
				continue
			var credit_rate := cult_rate.multiply_scalar(0.015 * float(weights.get(material_id, 0.0)))
			if credit_rate.is_zero():
				material_eta = INF
				material_found = true
				break
			var current_credit := lineage.materials.target_credit(run.active_target_id, String(material_id))
			var credit_gap := missing.to_magnitude().subtract(current_credit)
			var item_eta := 0.0 if credit_gap.is_zero() else credit_gap.divide(credit_rate).to_float()
			material_eta = maxf(material_eta, item_eta)
			material_found = true
		if not material_found:
			material_eta = 0.0
	var hp_eta := 0.0
	if not run.pending_tribulation.is_empty():
		var damage := BigCounter.from_string(String(run.pending_tribulation.get("total_damage", "0")))
		var required_body := damage.to_magnitude().multiply_scalar(policy.tribulation_hp_margin).pow_value(2.0)
		var body_gap := required_body.subtract(run.body_power)
		var body_rate: BigMagnitude = rates.get("body_per_second", BigMagnitude.zero())
		hp_eta = INF if body_gap.is_positive() and body_rate.is_zero() else (body_gap.divide(body_rate).to_float() if body_gap.is_positive() else 0.0)
	return {"target": target_eta, "materials": material_eta, "hp": hp_eta}


func get_realm_name() -> String:
	var candidates := run.inherited_history + run.completed_nodes
	var best_name := "凡人"
	var best_e := -1
	for node_id in candidates:
		var definition := BalanceConfig.node(String(node_id))
		if int(definition.get("E", 0)) > best_e:
			best_e = int(definition.get("E", 0))
			best_name = String(definition.get("name", "凡人"))
	return best_name


func get_available_crops() -> Array:
	var result: Array = []
	for crop_id in BalanceConfig.CROPS:
		var definition: Dictionary = BalanceConfig.CROPS[crop_id]
		var unlock_node := String(definition.get("unlock_node", ""))
		if unlock_node.is_empty() or lineage.historical_realm_unlocks.has(unlock_node):
			result.append({"id": String(crop_id), "name": String(definition.get("name", crop_id)), "tier": String(definition.get("treasure_tier", "common")), "cultivation": float(definition.get("cultivation_per_work", 0.0)), "stones": float(definition.get("stone_per_work", 0.0))})
	return result


func set_production_plan(plan_value: Dictionary) -> bool:
	var allowed := {}
	for crop in get_available_crops():
		allowed[String(crop["id"])] = true
	var filtered := {}
	for crop_id in plan_value:
		if allowed.has(String(crop_id)):
			filtered[String(crop_id)] = float(plan_value[crop_id])
	if not farm.set_plan(filtered):
		return false
	policy.production_plan = farm.plan()
	_sync_offline_policy_hash()
	revision += 1
	_emit_state()
	return true


func set_production_preset(preset: String) -> bool:
	var available := get_available_crops()
	if available.is_empty():
		return false
	var plan_value := {}
	match preset:
		"cultivation":
			var best_cult: Dictionary = available[0]
			for crop in available:
				if float(crop["cultivation"]) > float(best_cult["cultivation"]):
					best_cult = crop
			plan_value[String(best_cult["id"])] = 1.0
		"stones":
			var best_stones: Dictionary = available[0]
			for crop in available:
				if float(crop["stones"]) > float(best_stones["stones"]):
					best_stones = crop
			plan_value[String(best_stones["id"])] = 1.0
		"balanced":
			var count := mini(3, available.size())
			for index in range(count):
				plan_value[String(available[index]["id"])] = 1.0
		"rare":
			for crop in available:
				if String(crop["tier"]) == "rare":
					plan_value[String(crop["id"])] = 1.0
			if plan_value.is_empty():
				plan_value[String(available[0]["id"])] = 1.0
		_:
			plan_value[String(available[0]["id"])] = 1.0
	return set_production_plan(plan_value)


func buy_upgrade(upgrade_id: String, buy_max := true, command_id := "", expected_revision := -1) -> Dictionary:
	var fingerprint := "buy_upgrade|%s|%s" % [upgrade_id, str(buy_max)]
	var guard := _command_guard(command_id, expected_revision, "", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	var result := FarmEconomyService.buy_max(farm, run.spirit_stones, upgrade_id) if buy_max else FarmEconomyService.buy_one(farm, run.spirit_stones, upgrade_id)
	var count := int(result.get("bought", 0)) if buy_max else (1 if bool(result.get("bought", false)) else 0)
	if count <= 0:
		_commit_command(command_id, result, fingerprint)
		return result
	run.spirit_stones = run.spirit_stones.subtract(result["spent"] if buy_max else result["cost"])
	revision += 1
	_commit_command(command_id, result, fingerprint)
	_emit_state()
	return result


func choose_target(target_id: String, command_id := "", expected_revision := -1) -> Dictionary:
	var fingerprint := "choose_target|%s" % target_id
	var guard := _command_guard(command_id, expected_revision, "", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	var result := ProgressionService.choose_target(run, policy, target_id)
	if bool(result.get("ok", false)):
		revision += 1
		_commit_command(command_id, result, fingerprint)
		_emit_state()
	else:
		_commit_command(command_id, result, fingerprint)
	return result


func attempt_breakthrough(max_attempts := 9, command_id := "", expected_revision := -1) -> Dictionary:
	var fingerprint := "attempt_breakthrough|%d" % mini(max_attempts, policy.max_attempts_per_batch)
	var guard := _command_guard(command_id, expected_revision, "", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	var target_id := run.active_target_id
	var transaction_snapshot := SaveManager._capture_runtime_state()
	var result := BreakthroughService.attempt_batch(run, lineage, rng, mini(max_attempts, policy.max_attempts_per_batch), policy.continue_after_probability_failure, policy.reserve_for_hard_pity)
	if not result.get("attempts", []).is_empty():
		receipts.append_receipt({"kind": "breakthrough_batch", "node_id": target_id, "attempts": result["attempts"]})
		revision += 1
		if bool(result.get("success", false)):
			# The next target is selected only after the discovery has been
			# committed to this run. It is then eligible for future production,
			# but its material credit starts at this boundary.
			ProgressionService.ensure_target(run, policy)
		_commit_command(command_id, result, fingerprint)
		if not _persist_critical(transaction_snapshot):
			return {"success": false, "attempts": [], "reason": "SAVE_FAILED"}
		if bool(result.get("success", false)):
			realm_changed.emit()
	else:
		_commit_command(command_id, result, fingerprint)
	_emit_state()
	return result


func begin_tribulation(auto_mode := false, command_id := "", expected_revision := -1) -> Dictionary:
	var fingerprint := "begin_tribulation|%s" % str(auto_mode)
	var guard := _command_guard(command_id, expected_revision, "", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	if run.pending_tribulation.is_empty():
		var no_pending := {"success": false, "reason": "NO_PENDING_TRIBULATION"}
		_commit_command(command_id, no_pending, fingerprint)
		return no_pending
	var transaction_snapshot := SaveManager._capture_runtime_state()
	var lock := BreakthroughService.lock_tribulation_hp(run)
	if not bool(lock.get("ok", false)):
		_commit_command(command_id, lock, fingerprint)
		return lock
	var outcome := TribulationService.evaluate(BigCounter.from_string(String(run.pending_tribulation.get("locked_hp", "0"))), BigCounter.from_string(String(run.pending_tribulation.get("total_damage", "0"))))
	if bool(outcome["success"]):
		var node_id := String(run.pending_tribulation.get("node_id", ""))
		BreakthroughService.complete_tribulation(run)
		ProgressionService.ensure_target(run, policy)
		receipts.append_receipt({"kind": "tribulation", "node_id": node_id, "result": outcome})
	else:
		# 失败不提供奖励，也不消耗或重掷；气血继续增长后可重新锁定。
		run.pending_tribulation["locked_hp"] = ""
	revision += 1
	_commit_command(command_id, outcome, fingerprint)
	if not _persist_critical(transaction_snapshot):
		return {"success": false, "reason": "SAVE_FAILED"}
	if bool(outcome["success"]):
		realm_changed.emit()
	_emit_state()
	return outcome


func reincarnate_now(command_id := "", expected_revision := -1) -> Dictionary:
	var fingerprint := "reincarnate_now"
	var guard := _command_guard(command_id, expected_revision, "", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	var preview := ResetService.preview(run, lineage)
	if not bool(preview.get("can_reset", false)):
		_commit_command(command_id, preview, fingerprint)
		return preview
	var transaction_snapshot := SaveManager._capture_runtime_state()
	var result := ResetService.commit(run, lineage, legacy, farm, policy)
	revision += 1
	_reseed_for_generation()
	_commit_command(command_id, result, fingerprint)
	receipts.append_receipt({"kind": "reincarnation", "dao_gain": result["dao_gain"].to_dict(), "discoveries": result["new_discoveries"]})
	if not _persist_critical(transaction_snapshot):
		return {"can_reset": false, "reason": "SAVE_FAILED"}
	_emit_state()
	return result


func get_ascension_preview() -> Dictionary:
	var required_dao := BigCounter.from_string(BalanceConfig.ASCENSION_DAO_THRESHOLD)
	var history_ready := lineage.historical_realm_unlocks.has("golden_nine") and lineage.historical_realm_unlocks.has("foundation_heaven")
	var cultivation_ready := run.total_cultivation.compare(BigMagnitude.pow10(BalanceConfig.ASCENSION_CULTIVATION_EXPONENT)) >= 0
	var dao_ready := lineage.total_dao.floor_to_big_counter().compare(required_dao) >= 0
	return {
		"history_ready": history_ready,
		"cultivation_ready": cultivation_ready,
		"dao_ready": dao_ready,
		"law_gain": BalanceConfig.ascension_law_gain(lineage.lifetime_cultivation.add(run.total_cultivation)),
		"ready": history_ready and cultivation_ready and dao_ready,
	}


func ascend(command_id := "", expected_revision := -1) -> Dictionary:
	var fingerprint := "ascend"
	var guard := _command_guard(command_id, expected_revision, "", fingerprint)
	if bool(guard.get("duplicate", false)) or bool(guard.get("conflict", false)):
		return guard["result"]
	var preview := get_ascension_preview()
	if not bool(preview["ready"]):
		preview["reason"] = "ASCENSION_PREREQUISITE"
		_commit_command(command_id, preview, fingerprint)
		return preview
	var transaction_snapshot := SaveManager._capture_runtime_state()
	var gain: BigCounter = preview["law_gain"]
	legacy.total_laws = legacy.total_laws.add(gain)
	legacy.law_nodes["first_ascension"] = true
	lineage.reset_for_ascension()
	run.reset_for_birth([], 1)
	farm = FarmPortfolio.new()
	policy.production_plan = farm.plan()
	policy.enabled_blueprints = []
	run.active_target_id = "qi_common"
	offline_time_bank = 0.0
	_reseed_for_generation()
	lineage.treasure.initialize_entropy(treasure_rng)
	_sync_offline_policy_hash()
	receipts.append_receipt({"kind": "ascension", "law_gain": gain.digits})
	revision += 1
	_commit_command(command_id, {"ready": true, "law_gain": gain, "reason": "ASCENSION_SUCCESS"}, fingerprint)
	if not _persist_critical(transaction_snapshot):
		return {"ready": false, "law_gain": BigCounter.zero(), "reason": "SAVE_FAILED"}
	_emit_state()
	return {"ready": true, "law_gain": gain, "reason": "ASCENSION_SUCCESS"}


func set_automation_enabled(enabled: bool) -> void:
	if enabled:
		for key in ["auto_purchase_max", "auto_breakthrough", "auto_tribulation", "auto_reincarnation"]:
			if legacy.automation_blueprints.has(key) and not policy.enabled_blueprints.has(key):
				policy.enabled_blueprints.append(key)
	else:
		policy.enabled_blueprints.clear()
	policy.explicit_offline_authorization = enabled and policy.enabled_blueprints.has("auto_reincarnation")
	policy.allow_offline_reincarnation = policy.explicit_offline_authorization
	_sync_offline_policy_hash()
	revision += 1
	_emit_state()


func set_blueprint_enabled(blueprint_id: String, enabled: bool) -> bool:
	if not legacy.automation_blueprints.has(blueprint_id):
		return false
	if enabled and not policy.enabled_blueprints.has(blueprint_id):
		policy.enabled_blueprints.append(blueprint_id)
	elif not enabled:
		policy.enabled_blueprints.erase(blueprint_id)
	if blueprint_id == "auto_reincarnation":
		policy.explicit_offline_authorization = enabled
		policy.allow_offline_reincarnation = enabled
	_sync_offline_policy_hash()
	revision += 1
	_emit_state()
	return true


func set_automation_option(option_id: String, enabled: bool) -> bool:
	match option_id:
		"reserve_for_hard_pity":
			policy.reserve_for_hard_pity = enabled
		"continue_after_probability_failure":
			policy.continue_after_probability_failure = enabled
		"offline_reincarnation":
			if enabled and not policy.enabled_blueprints.has("auto_reincarnation"):
				return false
			policy.explicit_offline_authorization = enabled
			policy.allow_offline_reincarnation = enabled
		_:
			return false
	_sync_offline_policy_hash()
	revision += 1
	_emit_state()
	return true


func set_purchase_budget_ratio(ratio: float) -> void:
	policy.purchase_budget_ratio = clampf(ratio, 0.0, 1.0)
	_sync_offline_policy_hash()
	revision += 1
	_emit_state()


func set_tribulation_mode(mode: String) -> bool:
	if not ["safe", "exact", "manual"].has(mode):
		return false
	policy.tribulation_mode = mode
	_sync_offline_policy_hash()
	revision += 1
	_emit_state()
	return true


func get_automation_summary() -> Dictionary:
	return {
		"unlocked": legacy.automation_blueprints.duplicate(),
		"enabled": policy.enabled_blueprints.duplicate(),
		"purchase_budget_ratio": policy.purchase_budget_ratio,
		"reserve_for_hard_pity": policy.reserve_for_hard_pity,
		"continue_after_probability_failure": policy.continue_after_probability_failure,
		"tribulation_mode": policy.tribulation_mode,
		"tribulation_hp_margin": policy.tribulation_hp_margin,
		"allow_offline_reincarnation": policy.allow_offline_reincarnation,
		"explicit_offline_authorization": policy.explicit_offline_authorization,
		"offline_time_bank": offline_time_bank,
		"offline_policy_hash": offline_policy_hash,
	}


func get_treasure_summary() -> Dictionary:
	return {
		"work_credit": lineage.treasure.work_credit.duplicate(),
		"chests": lineage.treasure.chests.duplicate(),
		"rare_chest_credit": lineage.treasure.rare_chest_credit,
		"dao_mark_count": lineage.treasure.dao_mark_count,
		"next_dao_mark_requirement": lineage.treasure.next_dao_mark_requirement,
	}


func get_node_rows() -> Array:
	var rows: Array = []
	for definition in BalanceConfig.REALM_NODES:
		var node_id := String(definition["id"])
		var inherited := lineage.historical_realm_unlocks.has(node_id)
		var current := run.completed_nodes.has(node_id)
		var legal := BalanceConfig.legal_node(node_id, run.inherited_history)
		var requirements := BalanceConfig.material_requirements(node_id)
		var is_legal_target := legal and not inherited and not current
		var ready := is_legal_target and lineage.materials.can_afford(requirements) and run.total_cultivation.compare(BalanceConfig.node_requirement(node_id)) >= 0
		var failure_count := int(lineage.breakthrough_failures.get(node_id, 0))
		var hard_pity := int(definition.get("hard_pity", 0))
		var missing := {}
		for material_id in requirements:
			missing[String(material_id)] = requirements[material_id].subtract(lineage.materials.available(String(material_id)))
		rows.append({"id": node_id, "name": String(definition["name"]), "major": String(definition["major"]), "E": int(definition["E"]), "H": int(definition["H"]), "inherited": inherited, "completed": current, "legal": is_legal_target, "ready": ready, "probability": BalanceConfig.node_probability(node_id, failure_count), "failure_count": failure_count, "hard_pity": hard_pity, "hard_pity_remaining": maxi(0, hard_pity - failure_count), "prerequisites": definition.get("prerequisites", []), "requirement": BalanceConfig.node_requirement(node_id), "materials": requirements, "missing": missing})
	return rows


func get_material_rows() -> Array:
	var rows: Array = []
	var target := BreakthroughService.preview(run, lineage)
	var requirements: Dictionary = target.get("materials", {})
	for material_id in requirements:
		var required: BigCounter = requirements[material_id]
		var held := lineage.materials.amount(String(material_id))
		var credit := lineage.materials.target_credit(run.active_target_id, String(material_id))
		rows.append({
			"id": String(material_id),
			"name": String(BalanceConfig.MATERIALS.get(String(material_id), {}).get("name", material_id)),
			"held": held,
			"reserved": lineage.materials.reserved.get(String(material_id), BigCounter.zero()),
			"escrow": lineage.materials.escrow.get(String(material_id), BigCounter.zero()),
			"available": lineage.materials.available(String(material_id)),
			"required": required,
			"credit": credit,
			"lifetime_earned": lineage.materials.lifetime_earned.get(String(material_id), BigCounter.zero()),
			"lifetime_spent": lineage.materials.lifetime_spent.get(String(material_id), BigCounter.zero()),
			"tier": BalanceConfig.material_tier(String(material_id)),
		})
	return rows


func get_receipts(limit := 20) -> Array:
	return receipts.recent(limit)


func get_reset_preview() -> Dictionary:
	return ResetService.preview(run, lineage)


func _command_guard(command_id: String, expected_revision: int, prefix := "", fingerprint := "") -> Dictionary:
	var key := String(command_id)
	if not prefix.is_empty() and not key.is_empty():
		key = prefix + key
	if not key.is_empty() and last_command_receipts.has(key):
		var stored = last_command_receipts[key]
		if stored is Dictionary and bool(stored.get("__command_receipt__", false)):
			var stored_fingerprint := String(stored.get("fingerprint", ""))
			if not fingerprint.is_empty() and not stored_fingerprint.is_empty() and stored_fingerprint != fingerprint:
				return {"duplicate": false, "conflict": true, "result": {"ok": false, "success": false, "reason": "COMMAND_ID_REUSE_MISMATCH", "revision": revision}}
			return {"duplicate": true, "result": _clone_json_value(stored.get("result", {}))}
		return {"duplicate": true, "result": _clone_json_value(stored)}
	if expected_revision >= 0 and expected_revision != revision:
		return {"conflict": true, "result": {"ok": false, "success": false, "reason": "REVISION_CONFLICT", "revision": revision}}
	return {"duplicate": false, "conflict": false}


func _commit_command(command_id: String, result: Variant, fingerprint := "") -> void:
	if String(command_id).is_empty():
		return
	last_command_receipts[String(command_id)] = {
		"__command_receipt__": true,
		"fingerprint": fingerprint,
		"revision": revision,
		"result": _clone_json_value(result),
	}
	while last_command_receipts.size() > MAX_COMMAND_RECEIPTS:
		var keys := last_command_receipts.keys()
		if keys.is_empty():
			break
		last_command_receipts.erase(keys[0])


func _reseed_for_generation() -> void:
	lineage.lineage_seed = 731927 + lineage.generation
	rng.seed = lineage.lineage_seed
	treasure_rng.seed = lineage.lineage_seed + TREASURE_SEED_SALT


func _sync_offline_policy_hash() -> void:
	offline_policy_hash = policy.policy_hash()


func _encode_json_value(value: Variant) -> Variant:
	if value is BigMagnitude:
		return {"__type": "magnitude", "value": value.to_dict()}
	if value is BigCounter:
		return {"__type": "counter", "value": value.digits}
	if value is Dictionary:
		var output := {}
		for key in value:
			output[String(key)] = _encode_json_value(value[key])
		return output
	if value is Array:
		var output_array: Array = []
		for item in value:
			output_array.append(_encode_json_value(item))
		return output_array
	return value


func _decode_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		if String(value.get("__type", "")) == "magnitude":
			return BigMagnitude.from_dict(value.get("value", 0.0))
		if String(value.get("__type", "")) == "counter":
			return BigCounter.from_string(String(value.get("value", "0")))
		var output := {}
		for key in value:
			output[String(key)] = _decode_json_value(value[key])
		return output
	if value is Array:
		var output_array: Array = []
		for item in value:
			output_array.append(_decode_json_value(item))
		return output_array
	return value


func _clone_json_value(value: Variant) -> Variant:
	return _decode_json_value(_encode_json_value(value))


func _persist_critical(snapshot: Dictionary) -> bool:
	if SaveManager.save_game():
		return true
	SaveManager._restore_runtime_state(snapshot, false)
	return false


func _emit_state() -> void:
	state_changed.emit()
