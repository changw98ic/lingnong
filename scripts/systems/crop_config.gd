## CropConfig
## 作物种类的纯数据 / 查询模块。
## 仅提供作物表与查询接口，所有状态变更与数值应用一律由 GameState 协调执行。
## v3 架构：作物字段统一由 BalanceConfig 管理，本模块只提供查询。
##   CROPS[id] 字段含义：
##     name         作物中文名
##     growth       生长所需秒数（planted_at + growth = ready_at）
##     cultivation  单株收获直接结算的修为基值
##     sell_price   单株出售所得灵石基值
##     unlock_realm 解锁境界序号：0 凡人 / 1 炼气 / 2 筑基 / 3 金丹
class_name CropConfig
extends RefCounted

## 返回所有作物 id 数组。结果引用内部只读常量的键，调用方不得修改键集合。
static func get_all() -> Array:
	return BalanceConfig.CROPS.keys()

## 返回当前境界已解锁的作物 id 数组（unlock_realm <= realm_index）。
## 新解锁的作物排在已解锁作物之后，顺序与 CROPS 定义一致。
static func get_unlocked(realm_index: int) -> Array:
	var out: Array = []
	for id in BalanceConfig.CROPS.keys():
		if int(BalanceConfig.CROPS[id]["unlock_realm"]) <= realm_index:
			out.append(id)
	return out

## 按 id 取单个作物配置字典，id 不存在时返回 null。
## 返回的是内部只读常量的引用，调用方不得就地修改字段。
## 注：原契约接口名为 get(id)，但 Godot 4.7 中名为 get 的方法会与 Object.get(StringName)
## 冲突（warning-as-error），故重命名为 get_crop。行为与契约一致。
static func get_crop(id: String) -> Variant:
	if BalanceConfig.CROPS.has(id):
		return BalanceConfig.CROPS[id]
	return null
