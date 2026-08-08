## 商店商品数据。
## GameState 负责扣除灵石和应用效果，本模块只提供商品查询。
class_name ShopSystem
extends RefCounted

func get_items() -> Array[Dictionary]:
	return BalanceConfig.SHOP_ITEMS.duplicate(true)


func get_item(item_id: String) -> Dictionary:
	for item in BalanceConfig.SHOP_ITEMS:
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
