## AchievementSystem
##
## 成就只负责读取长期状态、计算进度和记录已完成目标。
## 成就定义集中在 BalanceConfig，GameState 保存已解锁结果和成就点；
## 成就不直接发放修为、灵石或天赋点，避免与主经济重复叠加。
class_name AchievementSystem
extends RefCounted


static func definitions() -> Array[Dictionary]:
	return BalanceConfig.ACHIEVEMENTS.duplicate(true)


static func current_value(source: Node, definition: Dictionary) -> float:
	match String(definition.get("metric", "")):
		"total_harvest_count":
			return float(source.total_harvest_count)
		"total_cultivation_earned":
			return float(source.total_cultivation_earned)
		"realm_index":
			return float(source.realm_index)
		"unlocked_fields":
			return float(source.unlocked_fields)
		"crop_proficiency":
			var crop_id := String(definition.get("crop_id", ""))
			return float(source.crop_proficiency.get(crop_id, 0))
		"reincarnation_count":
			return float(source.reincarnation_count)
		"talent_nodes":
			return float(source.talent_nodes.size())
	return 0.0


static func is_unlocked(source: Node, achievement_id: String) -> bool:
	return bool(source.achievements.get(achievement_id, false))


static func progress(source: Node, definition: Dictionary) -> Dictionary:
	var current := maxf(0.0, current_value(source, definition))
	var target := maxf(0.001, float(definition.get("target", 1.0)))
	return {
		"id": String(definition.get("id", "")),
		"name": String(definition.get("name", "")),
		"category": String(definition.get("category", "其他")),
		"desc": String(definition.get("desc", "")),
		"current": current,
		"target": target,
		"completed": is_unlocked(source, String(definition.get("id", ""))),
		"points": int(definition.get("points", 0)),
	}


static func progress_rows(source: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for definition in definitions():
		rows.append(progress(source, definition))
	return rows


## 检查全部成就并返回本次新解锁的定义。调用方负责发 state_changed。
static func refresh(source: Node) -> Array[Dictionary]:
	var unlocked_now: Array[Dictionary] = []
	for definition in definitions():
		var achievement_id := String(definition.get("id", ""))
		if achievement_id == "" or is_unlocked(source, achievement_id):
			continue
		var target := float(definition.get("target", 1.0))
		if current_value(source, definition) < target:
			continue
		source.achievements[achievement_id] = true
		source.achievement_points += int(definition.get("points", 0))
		unlocked_now.append(definition)
	return unlocked_now


static func completed_count(source: Node) -> int:
	var count := 0
	for definition in definitions():
		if is_unlocked(source, String(definition.get("id", ""))):
			count += 1
	return count
