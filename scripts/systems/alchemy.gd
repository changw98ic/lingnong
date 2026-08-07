class_name AlchemySystem
extends RefCounted
## 炼丹炉系统
## 负责筑基丹 / 金元丹配方的查询与炼制校验。
##
## 注意：聚气丹(qi_gathering_pill)属于"花灵石购买"的旧手工业流程，
## 由 GameState 直接处理，不在本模块配方中。本模块只管筑基丹 / 金元丹。
##
## 本模块不修改任何外部状态（不扣草、不加丹），仅做查询与结果计算，
## 由 GameState 负责根据 brew() 返回值实际应用扣草与加丹。

# 配方表（只读 const）。
#   key   = 配方ID（同时也是产出的丹药ID）
#   value = 配方属性字典：
#     - id:           配方ID（== 产出丹药ID）
#     - name:         丹药名称
#     - grass_cost:   炼制所需灵草数量
#     - cultivation:  服用后提供的修为
#     - unlock_realm: 解锁境界索引（与 GameState.REALMS 对齐：2=筑基, 3=金丹）
const RECIPES: Dictionary = {
	"foundation_pill": {
		"id": "foundation_pill",
		"name": "筑基丹",
		"grass_cost": 10,
		"cultivation": 1000,
		"unlock_realm": 2,
	},
	"golden_pill": {
		"id": "golden_pill",
		"name": "金元丹",
		"grass_cost": 100,
		"cultivation": 30000,
		"unlock_realm": 3,
	},
}


## 返回全部配方定义。
func get_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in RECIPES:
		result.append(RECIPES[key] as Dictionary)
	return result


## 返回当前境界已解锁的配方列表。
func get_unlocked_recipes(realm_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in RECIPES:
		var recipe: Dictionary = RECIPES[key] as Dictionary
		if realm_index >= int(recipe["unlock_realm"]):
			result.append(recipe)
	return result


## 判断当前是否可以炼制指定配方：
## 配方存在、境界达标、灵草数量足够。
func can_brew(recipe_id: String, grass_count: int, realm_index: int) -> bool:
	var recipe: Dictionary = _get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if realm_index < int(recipe["unlock_realm"]):
		return false
	if grass_count < int(recipe["grass_cost"]):
		return false
	return true


## 计算炼制结果，不修改任何外部状态。
## 返回 { ok: bool, grass_cost: int, pill_id: String }：
##   - 成功：ok=true，grass_cost 为本次应扣除的灵草数，pill_id 为产出丹药ID（与配方ID相同）。
##   - 失败：ok=false，grass_cost=0，pill_id=""。
## GameState 收到成功结果后自行扣草、加丹。
func brew(recipe_id: String, grass_count: int, realm_index: int) -> Dictionary:
	if not can_brew(recipe_id, grass_count, realm_index):
		return {"ok": false, "grass_cost": 0, "pill_id": ""}
	var recipe: Dictionary = _get_recipe(recipe_id)
	return {
		"ok": true,
		"grass_cost": int(recipe["grass_cost"]),
		"pill_id": recipe_id,
	}


## 根据配方ID获取配方定义；不存在则返回空 Dictionary。
func _get_recipe(recipe_id: String) -> Dictionary:
	if RECIPES.has(recipe_id):
		return RECIPES[recipe_id] as Dictionary
	return {}
