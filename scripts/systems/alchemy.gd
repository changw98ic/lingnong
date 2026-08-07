class_name AlchemySystem
extends RefCounted
## 炼丹炉系统（v2 泛化 Recipe schema）
## 负责配方的查询、解锁判断、可炼制校验与炼制结果计算。
##
## 配方 schema：
##   {
##     "id": String,                  # 配方ID（== 产出丹药ID）
##     "name": String,                # 丹药名称
##     "inputs": {crop_id: count},    # 投料映射，支持多种作物
##     "output_cultivation": float,   # 服用后提供的修为（buff 丹为 0）
##     "output_buff": null 或 {"mult": float, "duration": float},
##     "unlock_realm": int            # 解锁境界索引（2=筑基, 3=金丹）
##   }
##
## 注意：聚气丹(qi_gathering_pill)属于"花灵石购买"的旧手工业流程，
## 由 GameState 直接处理，不在本模块配方中。本模块只管
## foundation_pill / golden_pill / frenzy_pill 三种炉炼配方。
##
## 本模块不修改任何外部状态（不扣草、不加丹），仅做查询与结果计算。
## GameState 收到 brew() 成功返回后，按返回的 inputs 扣减 crop_inventory，
## 按 pill_id 累加 pills，并在服用时根据 output_cultivation / output_buff 结算。

# 配方表（只读 const）。key = 配方ID，value = 配方属性字典。
const RECIPES: Dictionary = {
	"foundation_pill": {
		"id": "foundation_pill",
		"name": "筑基丹",
		"inputs": {"gathering_grass": 10},
		"output_cultivation": 1000.0,
		"output_buff": null,
		"unlock_realm": 2,
	},
	"golden_pill": {
		"id": "golden_pill",
		"name": "金元丹",
		"inputs": {"gathering_grass": 100},
		"output_cultivation": 30000.0,
		"output_buff": null,
		"unlock_realm": 3,
	},
	"frenzy_pill": {
		"id": "frenzy_pill",
		"name": "狂暴丹",
		"inputs": {"gathering_grass": 30},
		"output_cultivation": 0.0,
		"output_buff": {"mult": 3.0, "duration": 60.0},
		"unlock_realm": 2,
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


## 根据配方ID获取配方定义；不存在则返回空 Dictionary。
func get_recipe(recipe_id: String) -> Dictionary:
	if RECIPES.has(recipe_id):
		return RECIPES[recipe_id] as Dictionary
	return {}


## 判断配方是否为 buff 类（output_buff 为 Dictionary）。
## 配方不存在时返回 false。
func is_buff_recipe(recipe_id: String) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var output_buff: Variant = recipe.get("output_buff", null)
	return output_buff != null and output_buff is Dictionary


## 获取配方的 buff 信息。
## 返回 {"mult": float, "duration": float}；
## 非 buff 配方或配方不存在时返回空 Dictionary。
func get_buff(recipe_id: String) -> Dictionary:
	if not is_buff_recipe(recipe_id):
		return {}
	var recipe: Dictionary = get_recipe(recipe_id)
	var output_buff: Dictionary = recipe["output_buff"] as Dictionary
	return {
		"mult": float(output_buff["mult"]),
		"duration": float(output_buff["duration"]),
	}


## 判断当前是否可以炼制指定配方：
## 配方存在、境界达标、inputs 中每种作物库存均足够。
## crop_inventory 形如 {"gathering_grass": 12, ...}。
func can_brew(recipe_id: String, crop_inventory: Dictionary, realm_index: int) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if realm_index < int(recipe["unlock_realm"]):
		return false
	var inputs: Dictionary = recipe["inputs"] as Dictionary
	for crop_id in inputs:
		var need: int = int(inputs[crop_id])
		var have: int = int(crop_inventory.get(crop_id, 0))
		if have < need:
			return false
	return true


## 计算炼制结果，不修改任何外部状态。
## 返回 { ok: bool, inputs: Dictionary, pill_id: String }：
##   - 成功：ok=true，inputs 为本次应扣减的作物映射（与配方 inputs 一致），
##     pill_id 为产出丹药ID（== 配方ID）。
##   - 失败：ok=false，inputs={}，pill_id=""。
## GameState 收到成功结果后自行扣减 crop_inventory、累加 pills。
func brew(recipe_id: String, crop_inventory: Dictionary, realm_index: int) -> Dictionary:
	if not can_brew(recipe_id, crop_inventory, realm_index):
		return {"ok": false, "inputs": {}, "pill_id": ""}
	var recipe: Dictionary = get_recipe(recipe_id)
	var inputs: Dictionary = recipe["inputs"] as Dictionary
	var inputs_to_deduct: Dictionary = {}
	for crop_id in inputs:
		inputs_to_deduct[crop_id] = int(inputs[crop_id])
	return {
		"ok": true,
		"inputs": inputs_to_deduct,
		"pill_id": recipe_id,
	}
