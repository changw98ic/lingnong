class_name LineageState
extends RefCounted

var historical_realm_unlocks: Array = []
var total_dao: BigMagnitude = BigMagnitude.zero()
var materials: MaterialLedger = MaterialLedger.new()
var treasure: TreasureState = TreasureState.new()
var breakthrough_failures: Dictionary = {}
var generation := 1
var lineage_seed := 731927
var lifetime_cultivation: BigMagnitude = BigMagnitude.zero()


func reset_for_ascension() -> void:
	historical_realm_unlocks = []
	total_dao = BigMagnitude.zero()
	materials = MaterialLedger.new()
	treasure = TreasureState.new()
	breakthrough_failures = {}
	generation = 1
	lifetime_cultivation = BigMagnitude.zero()


func to_dict() -> Dictionary:
	return {
		"historical_realm_unlocks": historical_realm_unlocks.duplicate(),
		"total_dao": total_dao.to_dict(),
		"materials": materials.to_dict(),
		"treasure": treasure.to_dict(),
		"breakthrough_failures": breakthrough_failures.duplicate(true),
		"generation": generation,
		"lineage_seed": lineage_seed,
		"lifetime_cultivation": lifetime_cultivation.to_dict(),
	}


func load_dict(data: Dictionary) -> void:
	historical_realm_unlocks = _string_array(data.get("historical_realm_unlocks", []))
	total_dao = BigMagnitude.from_dict(data.get("total_dao", 0.0))
	materials = MaterialLedger.new()
	materials.load_dict(data.get("materials", {}))
	treasure = TreasureState.new()
	treasure.load_dict(data.get("treasure", {}))
	breakthrough_failures = data.get("breakthrough_failures", {}) if data.get("breakthrough_failures", {}) is Dictionary else {}
	generation = maxi(1, int(data.get("generation", 1)))
	lineage_seed = int(data.get("lineage_seed", 731927))
	lifetime_cultivation = BigMagnitude.from_dict(data.get("lifetime_cultivation", 0.0))


func _string_array(value: Variant) -> Array:
	var output: Array = []
	if value is Array:
		for item in value:
			output.append(String(item))
	return output
