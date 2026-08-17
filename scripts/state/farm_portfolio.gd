class_name FarmPortfolio
extends RefCounted

var field_level := BalanceConfig.INITIAL_FIELD_LEVEL
var soil_tier := BalanceConfig.INITIAL_SOIL_TIER
var array_level := BalanceConfig.INITIAL_ARRAY_LEVEL
var plan_version := 1
var cohorts: Array = [{
	"crop_id": "gathering_grass", "allocation_ratio": 1.0,
	"field_grade": 1, "upgrade_tier": 0, "plan_version": 1,
}]


func set_plan(plan: Dictionary) -> bool:
	var cleaned := {}
	var total := 0.0
	for crop_id in plan:
		var ratio := maxf(0.0, float(plan[crop_id]))
		if ratio <= 0.0 or BalanceConfig.crop(String(crop_id)).is_empty():
			continue
		cleaned[String(crop_id)] = ratio
		total += ratio
	if total <= 0.0:
		return false
	cohorts.clear()
	plan_version += 1
	for crop_id in cleaned:
		var crop := BalanceConfig.crop(String(crop_id))
		cohorts.append({
			"crop_id": String(crop_id),
			"allocation_ratio": float(cleaned[crop_id]) / total,
			"field_grade": int(crop.get("grade", 1)),
			"upgrade_tier": soil_tier,
			"plan_version": plan_version,
		})
	return true


func plan() -> Dictionary:
	var output := {}
	for cohort in cohorts:
		output[String(cohort.get("crop_id", ""))] = float(cohort.get("allocation_ratio", 0.0))
	return output


func normalize() -> void:
	var total := 0.0
	for cohort in cohorts:
		total += maxf(0.0, float(cohort.get("allocation_ratio", 0.0)))
	if total <= 0.0:
		set_plan({"gathering_grass": 1.0})
		return
	for cohort in cohorts:
		cohort["allocation_ratio"] = maxf(0.0, float(cohort.get("allocation_ratio", 0.0))) / total


func to_dict() -> Dictionary:
	return {
		"field_level": field_level,
		"soil_tier": soil_tier,
		"array_level": array_level,
		"plan_version": plan_version,
		"cohorts": cohorts.duplicate(true),
	}


func load_dict(data: Dictionary) -> void:
	field_level = maxi(1, int(data.get("field_level", 1)))
	soil_tier = maxi(0, int(data.get("soil_tier", 0)))
	array_level = maxi(0, int(data.get("array_level", 0)))
	plan_version = maxi(1, int(data.get("plan_version", 1)))
	cohorts = data.get("cohorts", []) if data.get("cohorts", []) is Array else []
	if cohorts.is_empty():
		cohorts = [{"crop_id": "gathering_grass", "allocation_ratio": 1.0, "field_grade": 1, "upgrade_tier": soil_tier, "plan_version": plan_version}]
	normalize()
