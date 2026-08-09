## 商店商品数据。
## GameState 负责扣除灵石和应用效果，本模块只提供商品查询。
class_name ShopSystem
extends RefCounted

func get_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = BalanceConfig.SHOP_ITEMS.duplicate(true)
	for material_id_variant in BalanceConfig.BREAKTHROUGH_MATERIALS:
		var material_id := String(material_id_variant)
		var material: Dictionary = BalanceConfig.BREAKTHROUGH_MATERIALS[material_id_variant]
		items.append({
			"id": "breakthrough_%s" % material_id,
			"name": String(material.get("name", material_id)),
			"icon": String(material.get("icon", "材")),
			"cost": float(material.get("cost", 0.0)),
			"desc": String(material.get("desc", "突破材料，只能在商店兑换。")),
			"effect": "breakthrough_material",
			"material_id": material_id,
			"amount": 1.0,
			"required_realm": int(material.get("required_realm", 0)),
		})
	return items


func get_item(item_id: String) -> Dictionary:
	for item in get_items():
		if String(item.get("id", "")) == item_id:
			return item
	return {}


## 返回商品当前价格。带 escalation 的商品越买越贵：
## 价格 = cost × escalation^已购次数，四舍五入到 10，不设上限。
## 没有 escalation 字段的商品返回固定 cost。
func get_cost(item_id: String, purchases: int) -> float:
	var item := get_item(item_id)
	if item.is_empty():
		return 0.0
	var base := float(item.get("cost", 0.0))
	var escalation := float(item.get("escalation", 1.0))
	var price := base * pow(escalation, maxi(0, purchases))
	return roundf(price / 10.0) * 10.0
