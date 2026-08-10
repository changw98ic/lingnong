## TreasureSystem
## 宝箱 / 奇遇的随机结算模块。
##
## 掉落概率集中在 BalanceConfig，本模块只做 roll 与奖励描述；
## GameState 收到奖励描述后负责应用（入账灵石/灵气/材料/天赋点/永久强化）。
## 真实收获与模拟器共用同一份概率表。
class_name TreasureSystem
extends RefCounted


## 调试开关：探针测试关闭随机宝箱，避免污染精确资源断言。
static var enabled := true


## 对一次收获 roll 宝箱。返回 {found: false} 或带奖励描述：
##   {"found": true, "tier": "wood"/"jade"/"immortal"/"relic", "name": String,
##    "reward": {"kind": "stones"/"qi"/"material"/"talent_points"/"permanent_production"/"lifespan_max", ...}}
## fate_mult：天命转世天赋的奇遇倍率（默认 1.0）。
static func roll(fate_mult: float = 1.0) -> Dictionary:
	if not enabled:
		return {"found": false}
	var mult := maxf(1.0, fate_mult)
	var r := randf()
	if r < BalanceConfig.TREASURE_IMMORTAL_CHANCE * mult:
		return _immortal()
	if r < (BalanceConfig.TREASURE_IMMORTAL_CHANCE + BalanceConfig.TREASURE_JADE_CHANCE) * mult:
		return _jade()
	if r < (BalanceConfig.TREASURE_IMMORTAL_CHANCE + BalanceConfig.TREASURE_JADE_CHANCE + BalanceConfig.TREASURE_WOOD_CHANCE) * mult:
		return _wood()
	# 古修遗物与宝箱独立 roll，从玉/仙池随机一件。
	if randf() < BalanceConfig.TREASURE_RELIC_CHANCE * mult:
		if randf() < 0.5:
			return _jade()
		return _immortal()
	return {"found": false}


static func _wood() -> Dictionary:
	if randf() < 0.5:
		var amount := randf_range(50.0, 500.0)
		return {"found": true, "tier": "wood", "name": "木箱", "reward": {"kind": "stones", "amount": amount}}
	return {"found": true, "tier": "wood", "name": "木箱", "reward": {"kind": "qi", "amount": BalanceConfig.TREASURE_WOOD_QI}}


static func _jade() -> Dictionary:
	var materials: Array = BalanceConfig.BREAKTHROUGH_MATERIALS.keys()
	var material_id := String(materials[randi() % materials.size()])
	match randi() % 3:
		0:
			return {"found": true, "tier": "jade", "name": "玉箱", "reward": {"kind": "material", "material_id": material_id, "amount": 1}}
		1:
			return {"found": true, "tier": "jade", "name": "玉箱", "reward": {"kind": "talent_points", "amount": 1}}
		_:
			return {"found": true, "tier": "jade", "name": "玉箱", "reward": {"kind": "qi", "amount": 500.0}}


static func _immortal() -> Dictionary:
	match randi() % 3:
		0:
			return {"found": true, "tier": "immortal", "name": "仙箱", "reward": {"kind": "permanent_production", "amount": BalanceConfig.TREASURE_IMMORTAL_PRODUCTION_BONUS}}
		1:
			return {"found": true, "tier": "immortal", "name": "仙箱", "reward": {"kind": "lifespan_max", "amount": BalanceConfig.TREASURE_IMMORTAL_LIFESPAN_BONUS}}
		_:
			return {"found": true, "tier": "immortal", "name": "仙箱", "reward": {"kind": "permanent_crit", "amount": BalanceConfig.TREASURE_IMMORTAL_CRIT_BONUS}}
