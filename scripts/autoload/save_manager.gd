extends Node

const SAVE_VERSION := 20
var save_path := "user://lingnong_save.json"
var backup_path := "user://lingnong_save.json.bak"
var temp_path := "user://lingnong_save.json.tmp"


func save_game(preserve_backup := false) -> bool:
	GameState.saved_at_unix = int(Time.get_unix_time_from_system())
	var data := GameState.to_save_dict()
	data["checksum"] = SaveValidator.checksum_for(data)
	var json := JSON.stringify(data)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 v20 临时存档")
		return false
	file.store_string(json)
	file.flush()
	file.close()
	if not _validate_file(temp_path, true):
		DirAccess.remove_absolute(temp_path)
		return false
	if preserve_backup:
		return _commit_save_preserving_backup()
	var displaced_backup_path := "%s.previous.%d" % [backup_path, Time.get_ticks_usec()]
	var displaced_backup := false
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(backup_path):
			if DirAccess.rename_absolute(backup_path, displaced_backup_path) != OK:
				DirAccess.remove_absolute(temp_path)
				return false
			displaced_backup = true
		if DirAccess.rename_absolute(save_path, backup_path) != OK:
			if displaced_backup and FileAccess.file_exists(displaced_backup_path):
				DirAccess.rename_absolute(displaced_backup_path, backup_path)
			DirAccess.remove_absolute(temp_path)
			return false
	if DirAccess.rename_absolute(temp_path, save_path) != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, save_path)
		if displaced_backup and FileAccess.file_exists(displaced_backup_path):
			DirAccess.rename_absolute(displaced_backup_path, backup_path)
		return false
	if displaced_backup and FileAccess.file_exists(displaced_backup_path):
		DirAccess.remove_absolute(displaced_backup_path)
	return true


func load_game() -> bool:
	var candidates: Array[String] = []
	if FileAccess.file_exists(save_path):
		candidates.append(save_path)
	if FileAccess.file_exists(backup_path) and backup_path != save_path:
		candidates.append(backup_path)
	if candidates.is_empty():
		return false

	# load_save_dict() replaces state before it reports success. Keep object
	# references so a malformed candidate can be rolled back without going
	# through another save/load cycle (which could normalize the live state).
	var original_state: Dictionary = _capture_runtime_state()
	for source in candidates:
		var candidate: Dictionary = _read_candidate(source)
		if not bool(candidate.get("ok", false)):
			continue
		var candidate_data: Variant = candidate.get("data", {})
		if not candidate_data is Dictionary:
			continue
		if not GameState.load_save_dict(candidate_data as Dictionary):
			_restore_runtime_state(original_state, true)
			continue

		var data: Dictionary = candidate_data as Dictionary
		var used_backup: bool = source == backup_path
		GameState.saved_at_unix = maxi(0, int(data.get("saved_at_unix", Time.get_unix_time_from_system())))
		var now_unix: int = int(Time.get_unix_time_from_system())
		var wall_seconds: float = maxf(0.0, float(now_unix - GameState.saved_at_unix))
		if wall_seconds > 0.0:
			GameState.advance_offline(wall_seconds, "load:%d" % GameState.saved_at_unix, GameState.revision)
		if bool(candidate.get("migrated", false)) or wall_seconds > 0.0:
			# The loaded state is committed only after offline settlement. If the
			# replacement cannot be completed, restore the pre-load state too.
			if not save_game(used_backup):
				_restore_runtime_state(original_state, true)
				return false
		return true

	# Neither the primary save nor its backup was usable. The live state is
	# unchanged for parse/validation failures; this also repairs any partial
	# mutation from a failed GameState.load_save_dict() call.
	_restore_runtime_state(original_state, true)
	return false


func _commit_save_preserving_backup() -> bool:
	# The backup was the candidate that loaded successfully. Never rotate it
	# away: displace the rejected primary to a unique rollback name, install the
	# validated temp file, and then remove only the rejected copy.
	var displaced_path: String = "%s.invalid.%d" % [save_path, Time.get_ticks_usec()]
	var displaced_primary: bool = false
	if FileAccess.file_exists(save_path):
		if DirAccess.rename_absolute(save_path, displaced_path) != OK:
			return false
		displaced_primary = true
	if DirAccess.rename_absolute(temp_path, save_path) != OK:
		if displaced_primary and FileAccess.file_exists(displaced_path):
			DirAccess.rename_absolute(displaced_path, save_path)
		return false
	if displaced_primary and FileAccess.file_exists(displaced_path):
		DirAccess.remove_absolute(displaced_path)
	return true


func _read_candidate(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "OPEN_FAILED"}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "reason": "JSON_INVALID"}

	var raw_data: Dictionary = parsed as Dictionary
	var version: int = int(raw_data.get("save_version", raw_data.get("version", 0)))
	var migrated: bool = version < SAVE_VERSION
	var data: Dictionary = raw_data
	if migrated:
		if not _looks_like_legacy_save(raw_data):
			return {"ok": false, "reason": "LEGACY_SHAPE_UNRECOGNIZED"}
		data = SaveMigrator.migrate_legacy(raw_data)
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		return {"ok": false, "reason": "VERSION_UNSUPPORTED"}

	var validation: Dictionary = SaveValidator.validate(data, not migrated)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "reason": "VALIDATION_FAILED", "errors": validation.get("errors", [])}
	return {"ok": true, "data": data, "migrated": migrated}


func _looks_like_legacy_save(data: Dictionary) -> bool:
	for key in ["version", "realm_index", "cultivation", "spirit_stones", "qi", "fields", "breakthrough_materials", "total_cultivation_earned"]:
		if data.has(key):
			return true
	return false


func _capture_runtime_state() -> Dictionary:
	return {
		"run": GameState.run,
		"lineage": GameState.lineage,
		"legacy": GameState.legacy,
		"farm": GameState.farm,
		"policy": GameState.policy,
		"receipts": GameState.receipts,
		"rng_seed": GameState.rng.seed,
		"rng_state": GameState.rng.state,
		"treasure_rng_seed": GameState.treasure_rng.seed,
		"treasure_rng_state": GameState.treasure_rng.state,
		"revision": GameState.revision,
		"saved_at_unix": GameState.saved_at_unix,
		"offline_time_bank": GameState.offline_time_bank,
		"offline_policy_hash": GameState.offline_policy_hash,
		"last_offline_tx_id": GameState.last_offline_tx_id,
		"last_offline_report": GameState.last_offline_report,
		"last_command_receipts": GameState.last_command_receipts,
		"last_migration_report": GameState.last_migration_report,
	}


func _restore_runtime_state(snapshot: Dictionary, emit_state: bool = false) -> bool:
	var run_value: Variant = snapshot.get("run")
	var lineage_value: Variant = snapshot.get("lineage")
	var legacy_value: Variant = snapshot.get("legacy")
	var farm_value: Variant = snapshot.get("farm")
	var policy_value: Variant = snapshot.get("policy")
	var receipts_value: Variant = snapshot.get("receipts")
	if not run_value is RunState or not lineage_value is LineageState or not legacy_value is LegacyState:
		return false
	if not farm_value is FarmPortfolio or not policy_value is AutomationPolicyState or not receipts_value is ReceiptState:
		return false

	GameState.run = run_value as RunState
	GameState.lineage = lineage_value as LineageState
	GameState.legacy = legacy_value as LegacyState
	GameState.farm = farm_value as FarmPortfolio
	GameState.policy = policy_value as AutomationPolicyState
	GameState.receipts = receipts_value as ReceiptState
	GameState.rng.seed = int(snapshot.get("rng_seed", GameState.rng.seed))
	GameState.rng.state = int(snapshot.get("rng_state", GameState.rng.state))
	GameState.treasure_rng.seed = int(snapshot.get("treasure_rng_seed", GameState.treasure_rng.seed))
	GameState.treasure_rng.state = int(snapshot.get("treasure_rng_state", GameState.treasure_rng.state))
	GameState.revision = int(snapshot.get("revision", GameState.revision))
	GameState.saved_at_unix = int(snapshot.get("saved_at_unix", GameState.saved_at_unix))
	GameState.offline_time_bank = maxf(0.0, float(snapshot.get("offline_time_bank", GameState.offline_time_bank)))
	GameState.offline_policy_hash = String(snapshot.get("offline_policy_hash", GameState.offline_policy_hash))
	GameState.last_offline_tx_id = String(snapshot.get("last_offline_tx_id", GameState.last_offline_tx_id))

	var offline_value: Variant = snapshot.get("last_offline_report", {})
	if offline_value is Dictionary:
		GameState.last_offline_report = offline_value as Dictionary
	else:
		GameState.last_offline_report = {}
	var command_value: Variant = snapshot.get("last_command_receipts", {})
	if command_value is Dictionary:
		GameState.last_command_receipts = command_value as Dictionary
	else:
		GameState.last_command_receipts = {}
	var migration_value: Variant = snapshot.get("last_migration_report", {})
	if migration_value is Dictionary:
		GameState.last_migration_report = migration_value as Dictionary
	else:
		GameState.last_migration_report = {}
	if emit_state:
		GameState._emit_state()
	return true


func _validate_file(path: String, require_checksum := false) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("save_version", 0)) != SAVE_VERSION:
		return false
	return bool(SaveValidator.validate(parsed, require_checksum).get("ok", false))
