class_name RunState
extends RefCounted

var total_cultivation: BigMagnitude = BigMagnitude.zero()
var spirit_stones: BigMagnitude = BigMagnitude.zero()
var body_power: BigMagnitude = BigMagnitude.zero()
var spirit_power: BigMagnitude = BigMagnitude.zero()
var max_hp: BigCounter = BigCounter.from_int(100)
var current_hp: BigCounter = BigCounter.from_int(100)
var elapsed_seconds := 0.0
var production_efficiency := 1.0
var status := "RUNNING"
var generation := 1
var inherited_history: Array = []
var active_inherited_path: Dictionary = {}
var completed_nodes: Array = []
var discoveries: Array = []
var active_target_id := ""
var target_selected_cultivation: BigMagnitude = BigMagnitude.zero()
var pending_tribulation: Dictionary = {}
var pending_breakthrough_id := ""
var action_seq := 0


func reset_for_birth(history: Array, new_generation: int) -> void:
	total_cultivation = BigMagnitude.zero()
	spirit_stones = BigMagnitude.zero()
	body_power = BigMagnitude.zero()
	spirit_power = BigMagnitude.zero()
	max_hp = BigCounter.from_int(100)
	current_hp = BigCounter.from_int(100)
	elapsed_seconds = 0.0
	production_efficiency = 1.0
	status = "RUNNING"
	generation = new_generation
	inherited_history = history.duplicate()
	active_inherited_path = {}
	completed_nodes = []
	discoveries = []
	active_target_id = ""
	target_selected_cultivation = BigMagnitude.zero()
	pending_tribulation = {}
	pending_breakthrough_id = ""
	action_seq = 0


func to_dict() -> Dictionary:
	return {
		"total_cultivation": total_cultivation.to_dict(),
		"spirit_stones": spirit_stones.to_dict(),
		"body_power": body_power.to_dict(),
		"spirit_power": spirit_power.to_dict(),
		"max_hp": max_hp.digits,
		"current_hp": current_hp.digits,
		"elapsed_seconds": elapsed_seconds,
		"production_efficiency": production_efficiency,
		"status": status,
		"generation": generation,
		"inherited_history": inherited_history.duplicate(),
		"active_inherited_path": active_inherited_path.duplicate(true),
		"completed_nodes": completed_nodes.duplicate(),
		"discoveries": discoveries.duplicate(),
		"active_target_id": active_target_id,
		"target_selected_cultivation": target_selected_cultivation.to_dict(),
		"pending_tribulation": pending_tribulation.duplicate(true),
		"pending_breakthrough_id": pending_breakthrough_id,
		"action_seq": action_seq,
	}


func load_dict(data: Dictionary) -> void:
	total_cultivation = BigMagnitude.from_dict(data.get("total_cultivation", 0.0))
	spirit_stones = BigMagnitude.from_dict(data.get("spirit_stones", 0.0))
	body_power = BigMagnitude.from_dict(data.get("body_power", 0.0))
	spirit_power = BigMagnitude.from_dict(data.get("spirit_power", 0.0))
	max_hp = BigCounter.from_string(String(data.get("max_hp", "100")))
	current_hp = BigCounter.from_string(String(data.get("current_hp", max_hp.digits)))
	elapsed_seconds = maxf(0.0, float(data.get("elapsed_seconds", 0.0)))
	production_efficiency = clampf(float(data.get("production_efficiency", 1.0)), 0.0, 1.0)
	status = String(data.get("status", "RUNNING"))
	generation = maxi(1, int(data.get("generation", 1)))
	inherited_history = _string_array(data.get("inherited_history", []))
	active_inherited_path = data.get("active_inherited_path", {}) if data.get("active_inherited_path", {}) is Dictionary else {}
	completed_nodes = _string_array(data.get("completed_nodes", []))
	discoveries = _string_array(data.get("discoveries", []))
	active_target_id = String(data.get("active_target_id", ""))
	target_selected_cultivation = BigMagnitude.from_dict(data.get("target_selected_cultivation", 0.0))
	pending_tribulation = data.get("pending_tribulation", {}) if data.get("pending_tribulation", {}) is Dictionary else {}
	pending_breakthrough_id = String(data.get("pending_breakthrough_id", ""))
	action_seq = maxi(0, int(data.get("action_seq", 0)))


func _string_array(value: Variant) -> Array:
	var output: Array = []
	if value is Array:
		for item in value:
			output.append(String(item))
	return output
