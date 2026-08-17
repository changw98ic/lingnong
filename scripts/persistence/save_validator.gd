class_name SaveValidator
extends RefCounted

## v20 快照的边界校验器。它在内存状态被替换前拒绝非法大数、库存、
## 路线和 pending 事务，避免“能解析 JSON”被误当成“能恢复游戏”。

const TOP_LEVEL_KEYS := [
	"save_version", "content_version", "revision", "saved_at_unix", "simulation_cursor",
	"offline_time_bank", "offline_policy_hash", "last_offline_tx_id",
	"run", "lineage", "legacy", "farm_portfolio", "automation", "receipts",
	"rng_streams", "committed_commands", "migration_report", "checksum",
]


static func validate(data: Dictionary, require_checksum := false) -> Dictionary:
	var errors: Array = []
	for key in data:
		if not TOP_LEVEL_KEYS.has(String(key)):
			errors.append("UNKNOWN_TOP_LEVEL:%s" % String(key))
	if int(data.get("save_version", 0)) != BalanceConfig.SAVE_VERSION:
		errors.append("SAVE_VERSION")
	if String(data.get("content_version", "")) != BalanceConfig.CONTENT_VERSION:
		errors.append("CONTENT_VERSION")
	if require_checksum:
		if String(data.get("checksum", "")).is_empty():
			errors.append("CHECKSUM_MISSING")
		elif String(data.get("checksum")) != checksum_for(data):
			errors.append("CHECKSUM_MISMATCH")
	_validate_run(data.get("run", {}), errors)
	_validate_lineage(data.get("lineage", {}), errors)
	_validate_legacy(data.get("legacy", {}), errors)
	_validate_farm(data.get("farm_portfolio", {}), errors)
	_validate_automation(data.get("automation", {}), errors)
	_validate_cross_state(data, errors)
	if not data.get("receipts", {}) is Dictionary:
		errors.append("RECEIPTS_TYPE")
	if not data.get("rng_streams", {}) is Dictionary:
		errors.append("RNG_TYPE")
	if not data.get("committed_commands", {}) is Dictionary:
		errors.append("COMMANDS_TYPE")
	if not data.get("migration_report", {}) is Dictionary:
		errors.append("MIGRATION_REPORT_TYPE")
	if not _valid_counter(String(data.get("revision", ""))):
		errors.append("REVISION")
	if not _valid_nonnegative_float(data.get("saved_at_unix", -1)):
		errors.append("SAVED_AT")
	if not _valid_nonnegative_float(data.get("offline_time_bank", 0.0)):
		errors.append("OFFLINE_TIME_BANK")
	if not String(data.get("offline_policy_hash", "")).is_empty() and String(data.get("offline_policy_hash", "")).length() > 256:
		errors.append("OFFLINE_POLICY_HASH")
	if String(data.get("last_offline_tx_id", "")).length() > 256:
		errors.append("OFFLINE_TX_ID")
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_cross_state(data: Dictionary, errors: Array) -> void:
	var run: Variant = data.get("run", {})
	var lineage: Variant = data.get("lineage", {})
	if not run is Dictionary or not lineage is Dictionary:
		return
	var run_data: Dictionary = run
	var lineage_data: Dictionary = lineage
	var history: Array = lineage_data.get("historical_realm_unlocks", []) if lineage_data.get("historical_realm_unlocks", []) is Array else []
	var inherited: Array = run_data.get("inherited_history", []) if run_data.get("inherited_history", []) is Array else []
	if history != inherited:
		errors.append("HISTORY_SNAPSHOT_MISMATCH")
	var completed: Array = run_data.get("completed_nodes", []) if run_data.get("completed_nodes", []) is Array else []
	var discoveries: Array = run_data.get("discoveries", []) if run_data.get("discoveries", []) is Array else []
	for node_id in history:
		_validate_prerequisites(String(node_id), history, "HISTORY", errors)
	for node_id in completed:
		_validate_prerequisites(String(node_id), history, "COMPLETED", errors)
	if not _array_is_subset(discoveries, completed):
		errors.append("DISCOVERIES_NOT_COMPLETED")
	for node_id in discoveries:
		if history.has(node_id):
			errors.append("DISCOVERY_ALREADY_IN_HISTORY:%s" % String(node_id))
	var target_id := String(run_data.get("active_target_id", ""))
	if not target_id.is_empty() and (history.has(target_id) or completed.has(target_id) or not BalanceConfig.legal_node(target_id, history)):
		errors.append("TARGET_NOT_LEGAL:%s" % target_id)
	var pending: Variant = run_data.get("pending_tribulation", {})
	if pending is Dictionary and not pending.is_empty():
		var pending_id := String(pending.get("node_id", ""))
		if pending_id != target_id or completed.has(pending_id) or history.has(pending_id):
			errors.append("PENDING_TARGET_MISMATCH")
	var selected := BigMagnitude.from_dict(run_data.get("target_selected_cultivation", {}))
	var cultivation := BigMagnitude.from_dict(run_data.get("total_cultivation", {}))
	if selected.compare(cultivation) > 0:
		errors.append("TARGET_SELECTED_AFTER_CULTIVATION")
	var max_hp := BigCounter.from_string(String(run_data.get("max_hp", "0")))
	var current_hp := BigCounter.from_string(String(run_data.get("current_hp", "0")))
	if current_hp.compare(max_hp) > 0:
		errors.append("CURRENT_HP_EXCEEDS_MAX")
	if pending is Dictionary and not pending.is_empty():
		var locked_hp := String(pending.get("locked_hp", ""))
		if not locked_hp.is_empty() and BigCounter.from_string(locked_hp).compare(max_hp) > 0:
			errors.append("LOCKED_HP_EXCEEDS_MAX")


static func _validate_prerequisites(node_id: String, available: Array, label: String, errors: Array) -> void:
	var definition := BalanceConfig.node(node_id)
	for prerequisite in definition.get("prerequisites", []):
		if not available.has(String(prerequisite)):
			errors.append("%s_PREREQUISITE:%s->%s" % [label, node_id, String(prerequisite)])


static func _array_is_subset(values: Array, container: Array) -> bool:
	for value in values:
		if not container.has(value):
			return false
	return true


static func checksum_for(data: Dictionary) -> String:
	var payload := data.duplicate(true)
	payload.erase("checksum")
	# JSON.parse_string normalizes integer JSON values to the same numeric
	# representation used after a disk round-trip. Without this step a fresh
	# in-memory snapshot and the identical parsed snapshot hash differently.
	var canonical = JSON.parse_string(JSON.stringify(payload))
	if canonical is Dictionary:
		payload = canonical
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(payload).to_utf8_buffer())
	return context.finish().hex_encode()


static func _validate_run(value: Variant, errors: Array) -> void:
	if not value is Dictionary:
		errors.append("RUN_TYPE")
		return
	var data: Dictionary = value
	for key in ["total_cultivation", "spirit_stones", "body_power", "spirit_power", "target_selected_cultivation"]:
		if not _valid_magnitude(data.get(key, {})):
			errors.append("RUN_MAGNITUDE:%s" % key)
	for key in ["max_hp", "current_hp"]:
		if not _valid_counter(data.get(key, "")):
			errors.append("RUN_COUNTER:%s" % key)
	if not _valid_nonnegative_float(data.get("elapsed_seconds", -1.0)):
		errors.append("RUN_ELAPSED")
	var production_efficiency := float(data.get("production_efficiency", -1.0))
	if not _valid_nonnegative_float(production_efficiency) or production_efficiency > 1.0:
		errors.append("RUN_EFFICIENCY")
	for key in ["inherited_history", "completed_nodes", "discoveries"]:
		if not _valid_node_array(data.get(key, []), key, errors):
			pass
	var active_path = data.get("active_inherited_path", {})
	if not active_path is Dictionary:
		errors.append("RUN_PATH")
	else:
		for major in active_path:
			if not ["qi", "foundation", "golden"].has(String(major)) or BalanceConfig.node(String(active_path[major])).is_empty():
				errors.append("RUN_PATH_VALUE:%s" % String(major))
	var target := String(data.get("active_target_id", ""))
	if not target.is_empty() and BalanceConfig.node(target).is_empty():
		errors.append("RUN_TARGET")
	var pending = data.get("pending_tribulation", {})
	if not pending is Dictionary:
		errors.append("RUN_PENDING_TYPE")
	elif not pending.is_empty():
		var node_id := String(pending.get("node_id", ""))
		var definition := BalanceConfig.node(node_id)
		if definition.is_empty() or not bool(definition.get("golden", false)):
			errors.append("RUN_PENDING_NODE")
		if not _valid_counter(String(pending.get("total_damage", ""))):
			errors.append("RUN_PENDING_DAMAGE")
		elif String(pending.get("total_damage", "")) != String(definition.get("damage", "")):
			errors.append("RUN_PENDING_DAMAGE_MISMATCH")
		if int(pending.get("strike_count", -1)) != int(definition.get("strikes", -2)):
			errors.append("RUN_PENDING_STRIKES_MISMATCH")
		var locked := String(pending.get("locked_hp", ""))
		if not locked.is_empty() and not _valid_counter(locked):
			errors.append("RUN_PENDING_HP")
		if not (pending.get("started", false) is bool):
			errors.append("RUN_PENDING_STARTED")
		if String(data.get("pending_breakthrough_id", "")) != node_id:
			errors.append("RUN_PENDING_ID")
	else:
		if not String(data.get("pending_breakthrough_id", "")).is_empty():
			errors.append("RUN_PENDING_ID")


static func _validate_lineage(value: Variant, errors: Array) -> void:
	if not value is Dictionary:
		errors.append("LINEAGE_TYPE")
		return
	var data: Dictionary = value
	if not _valid_node_array(data.get("historical_realm_unlocks", []), "history", errors):
		pass
	for key in ["total_dao", "lifetime_cultivation"]:
		if not _valid_magnitude(data.get(key, {})):
			errors.append("LINEAGE_MAGNITUDE:%s" % key)
	var materials = data.get("materials", {})
	if not materials is Dictionary:
		errors.append("MATERIALS_TYPE")
	else:
		_validate_materials(materials, errors)
	var treasure = data.get("treasure", {})
	if not treasure is Dictionary:
		errors.append("TREASURE_TYPE")
	else:
		var work_credit = treasure.get("work_credit", {})
		var chests = treasure.get("chests", {})
		if not work_credit is Dictionary:
			errors.append("TREASURE_WORK_TYPE")
			work_credit = {}
		if not chests is Dictionary:
			errors.append("TREASURE_CHEST_TYPE")
			chests = {}
		for tier in ["common", "elite", "rare"]:
			if not _valid_magnitude(work_credit.get(tier, {})):
				errors.append("TREASURE_WORK:%s" % tier)
			if not _valid_counter(String(chests.get(tier, "0"))):
				errors.append("TREASURE_CHEST:%s" % tier)
		for key in ["rare_chest_credit", "dao_mark_count", "next_dao_mark_requirement"]:
			if not _valid_counter(String(treasure.get(key, "0"))):
				errors.append("TREASURE_COUNTER:%s" % key)
		for section in ["entropy_credit", "total_granted"]:
			var values = treasure.get(section, {})
			if not values is Dictionary:
				errors.append("TREASURE_SECTION:%s" % section)
				continue
			for key in values:
				if not _valid_counter(String(values[key])):
					errors.append("TREASURE_VALUE:%s" % String(key))
				elif section == "entropy_credit" and BigCounter.from_string(String(values[key])).compare(BigCounter.from_int(BalanceConfig.ENTROPY_SCALE)) >= 0:
					errors.append("ENTROPY_NOT_NORMALIZED:%s" % String(key))


static func _validate_materials(data: Dictionary, errors: Array) -> void:
	for section in ["on_hand", "reserved", "escrow", "lifetime_earned", "lifetime_spent"]:
		var values = data.get(section, {})
		if not values is Dictionary:
			errors.append("MATERIAL_SECTION:%s" % section)
			continue
		for material_id in values:
			if not BalanceConfig.MATERIALS.has(String(material_id)) or not _valid_counter(String(values[material_id])):
				errors.append("MATERIAL_VALUE:%s" % String(material_id))
	var on_hand = data.get("on_hand", {})
	var reserved = data.get("reserved", {})
	var escrow = data.get("escrow", {})
	if on_hand is Dictionary and reserved is Dictionary:
		for material_id in reserved:
			if not on_hand.has(material_id) or BigCounter.from_string(String(reserved[material_id])).compare(BigCounter.from_string(String(on_hand[material_id]))) > 0:
				errors.append("RESERVED_EXCEEDS_ON_HAND:%s" % String(material_id))
	if escrow is Dictionary:
		for material_id in escrow:
			if not BigCounter.from_string(String(escrow[material_id])).is_zero():
				errors.append("ESCROW_PENDING:%s" % String(material_id))
	var credits = data.get("target_credits", {})
	if credits is Dictionary:
		for node_id in credits:
			if BalanceConfig.node(String(node_id)).is_empty() or not credits[node_id] is Dictionary:
				errors.append("CREDIT_NODE:%s" % String(node_id))
				continue
			for material_id in credits[node_id]:
				if not BalanceConfig.MATERIALS.has(String(material_id)) or not _valid_magnitude(credits[node_id][material_id]):
					errors.append("CREDIT_VALUE:%s" % String(material_id))
	else:
		errors.append("CREDIT_TYPE")


static func _validate_legacy(value: Variant, errors: Array) -> void:
	if not value is Dictionary:
		errors.append("LEGACY_TYPE")
		return
	var data: Dictionary = value
	if not _valid_counter(String(data.get("total_laws", "0"))):
		errors.append("LAWS")
	if not data.get("automation_blueprints", []) is Array:
		errors.append("BLUEPRINTS")


static func _validate_farm(value: Variant, errors: Array) -> void:
	if not value is Dictionary:
		errors.append("FARM_TYPE")
		return
	var data: Dictionary = value
	for key in ["field_level", "soil_tier", "array_level", "plan_version"]:
		if int(data.get(key, -1)) < 0:
			errors.append("FARM_COUNTER:%s" % key)
	var cohorts = data.get("cohorts", [])
	if not cohorts is Array or cohorts.is_empty():
		errors.append("COHORTS")
		return
	var total := 0.0
	for cohort in cohorts:
		if not cohort is Dictionary:
			errors.append("COHORT_TYPE")
			continue
		var crop_id := String(cohort.get("crop_id", ""))
		var ratio := float(cohort.get("allocation_ratio", -1.0))
		if BalanceConfig.crop(crop_id).is_empty() or not _valid_ratio(ratio):
			errors.append("COHORT_VALUE:%s" % crop_id)
		total += ratio
	if is_nan(total) or absf(total - 1.0) > 0.000001:
		errors.append("COHORT_RATIO")


static func _validate_automation(value: Variant, errors: Array) -> void:
	if not value is Dictionary:
		errors.append("AUTOMATION_TYPE")
		return
	var data: Dictionary = value
	var budget := float(data.get("purchase_budget_ratio", -1.0))
	if not _valid_ratio(budget, true):
		errors.append("AUTOMATION_BUDGET")
	var mode := String(data.get("tribulation_mode", ""))
	if not ["safe", "exact", "manual"].has(mode):
		errors.append("AUTOMATION_TRIBULATION_MODE")
	var plan = data.get("production_plan", {})
	if not plan is Dictionary:
		errors.append("AUTOMATION_PLAN")
	else:
		for crop_id in plan:
			var ratio := float(plan[crop_id])
			if BalanceConfig.crop(String(crop_id)).is_empty() or not _valid_ratio(ratio):
				errors.append("AUTOMATION_CROP:%s" % String(crop_id))
	var stored_hash := String(data.get("policy_hash", ""))
	if not stored_hash.is_empty():
		var policy := AutomationPolicyState.new()
		policy.load_dict(data)
		if stored_hash != policy.policy_hash():
			errors.append("POLICY_HASH")


static func _valid_node_array(value: Variant, label: String, errors: Array) -> bool:
	if not value is Array:
		errors.append("NODE_ARRAY:%s" % label)
		return false
	var seen := {}
	for node_id in value:
		var id := String(node_id)
		if BalanceConfig.node(id).is_empty() or seen.has(id):
			errors.append("NODE_VALUE:%s" % id)
		seen[id] = true
	return true


static func _valid_counter(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for index in range(value.length()):
		if "0123456789".find(value[index]) < 0:
			return false
	return true


static func _valid_magnitude(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if not data.has("m") or not data.has("e"):
		return false
	var mantissa := float(data.get("m", 0.0))
	if is_nan(mantissa) or is_inf(mantissa) or mantissa < 0.0:
		return false
	if mantissa > 0.0 and (mantissa < 1.0 or mantissa >= 10.0):
		return false
	var exponent_value := float(data.get("e", INF))
	if is_nan(exponent_value) or is_inf(exponent_value) or exponent_value != floor(exponent_value):
		return false
	if data.has("d"):
		var digits := String(data.get("d", ""))
		if digits.is_empty():
			return mantissa == 0.0 and exponent_value == 0.0
		if not _valid_counter(digits):
			return false
		if digits.length() > 1 and digits.ends_with("0"):
			return false
		if mantissa <= 0.0:
			return false
		var canonical := BigMagnitude.from_dict({"d": digits, "e": int(exponent_value)})
		if canonical.exponent != int(exponent_value) or absf(canonical.mantissa - mantissa) > 0.000000000001:
			return false
	elif mantissa > 0.0:
		return false
	else:
		return exponent_value == 0.0
	return true


static func _valid_nonnegative_float(value: Variant) -> bool:
	var number := float(value)
	return not is_nan(number) and not is_inf(number) and number >= 0.0


static func _valid_ratio(value: float, allow_zero := false) -> bool:
	if is_nan(value) or is_inf(value):
		return false
	if allow_zero:
		return value >= 0.0 and value <= 1.0
	return value > 0.0 and value <= 1.0
