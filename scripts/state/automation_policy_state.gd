class_name AutomationPolicyState
extends RefCounted

var production_plan: Dictionary = {"gathering_grass": 1.0}
var enabled_blueprints: Array = []
var purchase_budget_ratio := 0.75
var purchase_priority: Array = ["field_level", "soil_tier", "array_level"]
var realm_plan_by_stage: Dictionary = {"qi": "qi_body", "foundation": "foundation_dan", "golden": "golden_one"}
var target_fallbacks: Dictionary = {"qi": ["qi_heaven", "qi_body", "qi_common"], "foundation": ["foundation_five", "foundation_dan"], "golden": ["golden_three", "golden_one"]}
var reserve_for_hard_pity := true
var continue_after_probability_failure := true
var max_attempts_per_batch := 9
var tribulation_mode := "safe"
var tribulation_hp_margin := 1.10
var reset_rules: Array = [{"new_discovery": true}, {"dao_gain_at_least": 1}]
var allow_offline_reincarnation := false
var next_run_plan_id := "default"
var explicit_offline_authorization := false
var policy_version := 1
var persisted_policy_hash := ""


func policy_hash() -> String:
	var canonical = JSON.parse_string(JSON.stringify(_hash_payload()))
	return str(hash(JSON.stringify(canonical)))


func to_dict() -> Dictionary:
	var output := _hash_payload()
	output["policy_hash"] = policy_hash()
	return output


func _hash_payload() -> Dictionary:
	return {
		"production_plan": production_plan.duplicate(true),
		"enabled_blueprints": enabled_blueprints.duplicate(),
		"purchase_budget_ratio": purchase_budget_ratio,
		"purchase_priority": purchase_priority.duplicate(),
		"realm_plan_by_stage": realm_plan_by_stage.duplicate(true),
		"target_fallbacks": target_fallbacks.duplicate(true),
		"reserve_for_hard_pity": reserve_for_hard_pity,
		"continue_after_probability_failure": continue_after_probability_failure,
		"max_attempts_per_batch": max_attempts_per_batch,
		"tribulation_mode": tribulation_mode,
		"tribulation_hp_margin": tribulation_hp_margin,
		"reset_rules": reset_rules.duplicate(true),
		"allow_offline_reincarnation": allow_offline_reincarnation,
		"next_run_plan_id": next_run_plan_id,
		"explicit_offline_authorization": explicit_offline_authorization,
		"policy_version": policy_version,
	}


func load_dict(data: Dictionary) -> void:
	production_plan = data.get("production_plan", production_plan) if data.get("production_plan", production_plan) is Dictionary else production_plan
	enabled_blueprints = data.get("enabled_blueprints", enabled_blueprints) if data.get("enabled_blueprints", enabled_blueprints) is Array else enabled_blueprints
	purchase_budget_ratio = clampf(float(data.get("purchase_budget_ratio", purchase_budget_ratio)), 0.0, 1.0)
	purchase_priority = data.get("purchase_priority", purchase_priority) if data.get("purchase_priority", purchase_priority) is Array else purchase_priority
	realm_plan_by_stage = data.get("realm_plan_by_stage", realm_plan_by_stage) if data.get("realm_plan_by_stage", realm_plan_by_stage) is Dictionary else realm_plan_by_stage
	target_fallbacks = data.get("target_fallbacks", target_fallbacks) if data.get("target_fallbacks", target_fallbacks) is Dictionary else target_fallbacks
	reserve_for_hard_pity = bool(data.get("reserve_for_hard_pity", reserve_for_hard_pity))
	continue_after_probability_failure = bool(data.get("continue_after_probability_failure", continue_after_probability_failure))
	max_attempts_per_batch = clampi(int(data.get("max_attempts_per_batch", max_attempts_per_batch)), 1, 9)
	tribulation_mode = String(data.get("tribulation_mode", tribulation_mode))
	tribulation_hp_margin = maxf(1.0, float(data.get("tribulation_hp_margin", tribulation_hp_margin)))
	reset_rules = data.get("reset_rules", reset_rules) if data.get("reset_rules", reset_rules) is Array else reset_rules
	allow_offline_reincarnation = bool(data.get("allow_offline_reincarnation", allow_offline_reincarnation))
	next_run_plan_id = String(data.get("next_run_plan_id", next_run_plan_id))
	explicit_offline_authorization = bool(data.get("explicit_offline_authorization", explicit_offline_authorization))
	policy_version = maxi(1, int(data.get("policy_version", policy_version)))
	persisted_policy_hash = String(data.get("policy_hash", ""))
