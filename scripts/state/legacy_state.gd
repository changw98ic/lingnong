class_name LegacyState
extends RefCounted

var lifetime_discoveries: Dictionary = {}
var claimed_first_rewards: Dictionary = {}
var total_laws: BigCounter = BigCounter.zero()
var law_nodes: Dictionary = {}
var automation_blueprints: Array = []
var settings: Dictionary = {"scientific_notation": true, "reduce_effects": false}


func to_dict() -> Dictionary:
	return {
		"lifetime_discoveries": lifetime_discoveries.duplicate(true),
		"claimed_first_rewards": claimed_first_rewards.duplicate(true),
		"total_laws": total_laws.digits,
		"law_nodes": law_nodes.duplicate(true),
		"automation_blueprints": automation_blueprints.duplicate(true),
		"settings": settings.duplicate(true),
	}


func load_dict(data: Dictionary) -> void:
	lifetime_discoveries = data.get("lifetime_discoveries", {}) if data.get("lifetime_discoveries", {}) is Dictionary else {}
	claimed_first_rewards = data.get("claimed_first_rewards", {}) if data.get("claimed_first_rewards", {}) is Dictionary else {}
	total_laws = BigCounter.from_string(String(data.get("total_laws", "0")))
	law_nodes = data.get("law_nodes", {}) if data.get("law_nodes", {}) is Dictionary else {}
	automation_blueprints = data.get("automation_blueprints", []) if data.get("automation_blueprints", []) is Array else []
	settings = data.get("settings", settings) if data.get("settings", settings) is Dictionary else settings
