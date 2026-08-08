## 天赋树数据与解锁规则。
##
## 天赋点来自境界突破和修为里程碑，玩家在有前置关系的节点之间选择路线，
## 不再是三条互相独立、按固定等级重复点击的数值条。节点数据统一由
## BalanceConfig 管理，本模块只实现解锁规则和效果汇总。
class_name TalentTree
extends RefCounted

static func node_ids() -> Array[String]:
	return BalanceConfig.TALENT_NODE_ORDER.duplicate()


static func node_def(node_id: String) -> Dictionary:
	if not BalanceConfig.TALENT_NODES.has(node_id):
		return {}
	return BalanceConfig.TALENT_NODES[node_id] as Dictionary


static func branch_name(branch: String) -> String:
	match branch:
		"farming":
			return "农道"
		"alchemy":
			return "丹道"
		"spirit":
			return "灵根"
	return "道心"


static func is_unlocked(node_id: String, unlocked_nodes: Dictionary) -> bool:
	return bool(unlocked_nodes.get(node_id, false))


static func can_unlock(node_id: String, unlocked_nodes: Dictionary, points: int) -> bool:
	var node := node_def(node_id)
	if node.is_empty() or is_unlocked(node_id, unlocked_nodes):
		return false
	var cost := int(node.get("cost", 0))
	if points < cost:
		return false
	for required in node.get("requires", []):
		if not is_unlocked(String(required), unlocked_nodes):
			return false
	var any_requirements: Array = node.get("requires_any", [])
	if not any_requirements.is_empty():
		var any_ready := false
		for required_any in any_requirements:
			if is_unlocked(String(required_any), unlocked_nodes):
				any_ready = true
				break
		if not any_ready:
			return false
	return true


## 汇总一类倍率。倍率节点相乘，未购买时返回 1。
static func multiplier(effect_key: String, unlocked_nodes: Dictionary) -> float:
	var result := 1.0
	for node_id in BalanceConfig.TALENT_NODE_ORDER:
		if not is_unlocked(node_id, unlocked_nodes):
			continue
		var node := node_def(node_id)
		var effects: Dictionary = node.get("effects", {})
		if effects.has(effect_key):
			result *= float(effects[effect_key])
	return result


## 汇总加法效果，例如极品概率加成。
static func bonus(effect_key: String, unlocked_nodes: Dictionary) -> float:
	var result := 0.0
	for node_id in BalanceConfig.TALENT_NODE_ORDER:
		if not is_unlocked(node_id, unlocked_nodes):
			continue
		var node := node_def(node_id)
		var effects: Dictionary = node.get("effects", {})
		if effects.has(effect_key):
			result += float(effects[effect_key])
	return result
