class_name SaveMigrator
extends RefCounted

## v18/v19 平铺存档的一次性安全迁移器。
##
## 迁移先生成候选 v20 字典，再由 SaveValidator 校验；它不直接触碰
## GameState，也不在迁移阶段扣材料、重掷概率、渡劫或轮回。

const LEGACY_REALM_PATH := ["", "qi_common", "foundation_dan", "golden_one"]


static func migrate_legacy(data: Dictionary) -> Dictionary:
	var report := {
		"source_version": int(data.get("version", data.get("save_version", 0))),
		"mapped_fields": [],
		"mapped_materials": [],
		"dormant_materials": [],
		"unknown_materials": [],
		"cancelled_pending": [],
		"discarded_fields": [],
		"warnings": [],
	}
	var run := RunState.new()
	var lineage := LineageState.new()
	var legacy := LegacyState.new()
	var farm := FarmPortfolio.new()
	var policy := AutomationPolicyState.new()
	var receipts := ReceiptState.new()

	var realm_index := clampi(int(data.get("realm_index", 0)), 0, LEGACY_REALM_PATH.size() - 1)
	var history := _legacy_history(realm_index)
	lineage.historical_realm_unlocks = history.duplicate()
	for node_id in history:
		legacy.lifetime_discoveries[String(node_id)] = true
	_append_report(report, "mapped_fields", "realm_index", history)

	var generation := maxi(1, int(data.get("reincarnation_count", 0)) + 1)
	lineage.generation = generation
	lineage.lineage_seed = 731927 + generation
	var lifetime_cultivation := _legacy_magnitude(data.get("total_cultivation_earned", data.get("cultivation", "0")))
	lineage.lifetime_cultivation = lifetime_cultivation
	lineage.total_dao = lifetime_cultivation.divide(BigMagnitude.from_exact_integer("1000"))
	_append_report(report, "mapped_fields", "total_cultivation_earned", lifetime_cultivation.to_dict())

	run.reset_for_birth(history, generation)
	# The old linear realm index represented already reached content in the
	# current run. Keep that path as completed as well as inherited, while
	# leaving discoveries empty so migration cannot award a second first-clear.
	run.completed_nodes = history.duplicate()
	run.total_cultivation = _legacy_magnitude(data.get("cultivation", "0"))
	run.spirit_stones = _legacy_magnitude(data.get("spirit_stones", "0"))
	run.body_power = _legacy_magnitude(data.get("qi", "0"))
	run.spirit_power = _legacy_magnitude(data.get("spirit_power", "0"))
	run.elapsed_seconds = 0.0
	run.production_efficiency = 1.0
	run.max_hp = run.body_power.sqrt_value().floor_to_big_counter().add(BigCounter.from_int(100))
	run.current_hp = run.max_hp.duplicate_value()
	_append_report(report, "mapped_fields", "cultivation", run.total_cultivation.to_dict())
	_append_report(report, "mapped_fields", "spirit_stones", run.spirit_stones.to_dict())
	_append_report(report, "mapped_fields", "qi", run.body_power.to_dict())

	_migrate_material_map(lineage.materials, data.get("breakthrough_materials", {}), report)
	_migrate_named_material(lineage.materials, data, "healing_pills", "body_pill", report)
	_migrate_named_material(lineage.materials, data, "resistance_pills", "fu_qi_dan", report)
	_migrate_named_material(lineage.materials, data, "enhancement_pills", "spirit_pill", report)
	_migrate_treasure(lineage.treasure, data, report)
	for legacy_key in ["treasure_production_bonus", "treasure_crit_bonus", "fate_permanent_production", "lifespan_max_years", "lifespan_years", "random_event", "reincarnation_boon"]:
		if data.has(legacy_key):
			(report["warnings"] as Array).append({"field": legacy_key, "reason": "RETIRED_RULE_NOT_IMPORTED"})

	var plan := _migrate_farm_plan(farm, data.get("fields", []), report)
	farm.set_plan(plan)
	var old_unlocked_fields := int(data.get("unlocked_fields", 1))
	farm.field_level = maxi(1, old_unlocked_fields)
	var old_field_tier := 0
	var fields = data.get("fields", [])
	if fields is Array:
		for field in fields:
			if field is Dictionary:
				old_field_tier = maxi(old_field_tier, int(field.get("tier", 0)))
	farm.soil_tier = maxi(0, old_field_tier)
	for cohort in farm.cohorts:
		cohort["upgrade_tier"] = farm.soil_tier
	_append_report(report, "mapped_fields", "fields", {"cohorts": farm.cohorts.size(), "field_level": farm.field_level, "soil_tier": farm.soil_tier})

	# A legacy save never implicitly opts into the new high-level automation.
	policy.enabled_blueprints = []
	policy.allow_offline_reincarnation = false
	policy.explicit_offline_authorization = false
	policy.production_plan = farm.plan()
	ProgressionService.apply_birth_plan(run, farm, policy)
	ProgressionService.ensure_target(run, policy)
	_migrate_pending_tribulation(run, data, report)
	_report_unmapped_fields(data, report)

	return {
		"save_version": BalanceConfig.SAVE_VERSION,
		"content_version": BalanceConfig.CONTENT_VERSION,
		"revision": "0",
		"saved_at_unix": int(data.get("saved_at_unix", data.get("saved_at", Time.get_unix_time_from_system()))),
		"offline_time_bank": 0.0,
		"offline_policy_hash": policy.policy_hash(),
		"last_offline_tx_id": "",
		"simulation_cursor": "migrated:%d:%d" % [generation, run.action_seq],
		"run": run.to_dict(),
		"lineage": lineage.to_dict(),
		"legacy": legacy.to_dict(),
		"farm_portfolio": farm.to_dict(),
		"automation": policy.to_dict(),
		"receipts": receipts.to_dict(),
		"rng_streams": {
			"stream_version": 1,
			"generation": generation,
			"breakthrough_seed": str(lineage.lineage_seed),
		},
		"committed_commands": {},
		"migration_report": report,
	}


static func _legacy_history(realm_index: int) -> Array:
	var history: Array = []
	for index in range(1, realm_index + 1):
		var node_id := String(LEGACY_REALM_PATH[index])
		if not node_id.is_empty():
			history.append(node_id)
	return history


static func _legacy_magnitude(value: Variant) -> BigMagnitude:
	if value is BigMagnitude:
		return (value as BigMagnitude).duplicate_value()
	if value is Dictionary:
		return BigMagnitude.from_dict(value)
	var text := String(value if value != null else "0").strip_edges()
	if text.is_empty():
		text = "0"
	return BigMagnitude.from_string(text)


static func _legacy_counter(value: Variant) -> BigCounter:
	var magnitude := _legacy_magnitude(value)
	return magnitude.floor_to_big_counter()


static func _migrate_material_map(ledger: MaterialLedger, values: Variant, report: Dictionary) -> void:
	if not values is Dictionary:
		return
	for old_id_variant in values:
		var old_id := String(old_id_variant)
		var amount := _legacy_counter(values[old_id_variant])
		if amount.is_zero():
			continue
		var mapped := _map_material(old_id)
		if mapped.is_empty():
			(report["unknown_materials"] as Array).append({"from": old_id, "amount": amount.digits})
			continue
		ledger.add(mapped, amount)
		var entry := {"from": old_id, "to": mapped, "amount": amount.digits}
		if bool(BalanceConfig.MATERIALS.get(mapped, {}).get("dormant", false)):
			(report["dormant_materials"] as Array).append(entry)
		else:
			(report["mapped_materials"] as Array).append(entry)


static func _migrate_named_material(ledger: MaterialLedger, data: Dictionary, old_key: String, material_id: String, report: Dictionary) -> void:
	if not data.has(old_key):
		return
	var amount := _legacy_counter(data.get(old_key, "0"))
	if amount.is_zero():
		return
	ledger.add(material_id, amount)
	(report["mapped_materials"] as Array).append({"from": old_key, "to": material_id, "amount": amount.digits})


static func _migrate_farm_plan(farm: FarmPortfolio, values: Variant, report: Dictionary) -> Dictionary:
	var plan := {}
	if values is Array:
		for field in values:
			if not field is Dictionary:
				continue
			var old_crop := String(field.get("crop_id", ""))
			var mapped_crop := _map_crop(old_crop)
			if mapped_crop.is_empty():
				if not old_crop.is_empty():
					(report["discarded_fields"] as Array).append({"crop_id": old_crop, "reason": "UNKNOWN_CROP"})
				continue
			plan[mapped_crop] = float(plan.get(mapped_crop, 0.0)) + 1.0
			if field.has("ready_at") or field.has("planted_at"):
				(report["discarded_fields"] as Array).append({"crop_id": old_crop, "reason": "MATURE_PROGRESS_NOT_CARRIED"})
	if plan.is_empty():
		plan = {"gathering_grass": 1.0}
	return plan


static func _migrate_pending_tribulation(run: RunState, data: Dictionary, report: Dictionary) -> void:
	if not bool(data.get("tribulation_active", false)):
		return
	var old_target := int(data.get("tribulation_target_realm", -1))
	var node_id := String(LEGACY_REALM_PATH[old_target]) if old_target >= 0 and old_target < LEGACY_REALM_PATH.size() else ""
	var definition := BalanceConfig.node(node_id)
	if definition.is_empty() or not bool(definition.get("golden", false)) or not bool(definition.get("content_enabled", false)):
		(report["cancelled_pending"] as Array).append({"target": old_target, "reason": "UNKNOWN_OR_DISABLED_PENDING"})
		return
	run.pending_tribulation = {
		"node_id": node_id,
		"total_damage": String(definition.get("damage", "0")),
		"strike_count": int(definition.get("strikes", 1)),
		"locked_hp": "",
		"started": false,
	}
	run.pending_breakthrough_id = node_id
	(report["mapped_fields"] as Array).append({"pending_tribulation": node_id, "result": "PENDING_RESTORED_WITHOUT_REROLL"})


static func _migrate_treasure(treasure: TreasureState, data: Dictionary, report: Dictionary) -> void:
	var source: Variant = data.get("treasure", {})
	if not source is Dictionary:
		return
	var values: Dictionary = source
	for tier in TreasureState.TIERS:
		var value_key := "%s_chests" % tier
		var count_key := "%s_chest_count" % tier
		var raw: Variant = values.get(value_key, values.get(count_key, null))
		if raw == null:
			continue
		var count := _legacy_counter(raw)
		treasure.chests[tier] = count
		(report["mapped_fields"] as Array).append({"field": value_key, "value": count.digits})
	var entropy: Variant = values.get("entropy_credit", {})
	if entropy is Dictionary:
		for key in entropy:
			var credit := _legacy_counter(entropy[key])
			var normalized := credit.divide_int(BalanceConfig.ENTROPY_SCALE)
			treasure.entropy_credit[String(key)] = BigCounter.from_int(int(normalized["remainder"]))
		(report["mapped_fields"] as Array).append({"field": "treasure.entropy_credit", "value": "fixed_point"})


static func _report_unmapped_fields(data: Dictionary, report: Dictionary) -> void:
	var handled := {
		"version": true, "save_version": true, "realm_index": true, "reincarnation_count": true,
		"total_cultivation_earned": true, "cultivation": true, "spirit_stones": true, "qi": true,
		"spirit_power": true, "breakthrough_materials": true, "healing_pills": true,
		"resistance_pills": true, "enhancement_pills": true, "fields": true, "unlocked_fields": true,
		"saved_at_unix": true, "saved_at": true, "tribulation_active": true,
		"tribulation_target_realm": true, "treasure": true,
		"treasure_production_bonus": true, "treasure_crit_bonus": true, "fate_permanent_production": true,
		"lifespan_max_years": true, "lifespan_years": true, "random_event": true, "reincarnation_boon": true,
	}
	var already_reported := {}
	for item in report.get("warnings", []):
		if item is Dictionary:
			already_reported[String(item.get("field", ""))] = true
	for item in report.get("discarded_fields", []):
		if item is Dictionary:
			already_reported[String(item.get("crop_id", ""))] = true
	for key in data:
		var field := String(key)
		if handled.has(field) or already_reported.has(field):
			continue
		(report["discarded_fields"] as Array).append({"field": field, "reason": "UNMAPPED_LEGACY_FIELD"})


static func _map_material(old_id: String) -> String:
	if BalanceConfig.MATERIALS.has(old_id):
		return old_id
	var aliases := {
		"recovery_pill": "body_pill",
		"healing_pill": "body_pill",
		"anti_thunder_pill": "fu_qi_dan",
		"resistance_pill": "fu_qi_dan",
		"breakthrough_pill": "spirit_pill",
		"enhancement_pill": "spirit_pill",
	}
	return String(aliases.get(old_id, ""))


static func _map_crop(old_id: String) -> String:
	var aliases := {
		"gathering_grass": "gathering_grass",
		"mind_flower": "mind_flower",
		"sun_fruit": "sun_fruit",
		"heaven_lotus": "heaven_lotus",
		"zi_zhi": "purple_mushroom",
		"purple_mushroom": "purple_mushroom",
	}
	return String(aliases.get(old_id, "gathering_grass" if old_id.is_empty() else ""))


static func _append_report(report: Dictionary, key: String, field: String, value: Variant) -> void:
	var list: Array = report.get(key, [])
	list.append({"field": field, "value": value})
	report[key] = list
