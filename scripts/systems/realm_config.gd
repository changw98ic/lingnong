## RealmConfig
## 境界与突破奖励的纯数据 / 查询模块。
## 仅提供数据表与查询接口，所有状态变更与数值应用一律由 GameState 协调执行。
## v2 架构：境界同时是 Gate（突破门槛）与 Modifier（production / cultivation 乘数）。
##   production   作用于：生长速度、收获产量、灵气产出、自动修炼的灵气部分。
##   cultivation  作用于：丹药修为、自动修炼的修为部分。
class_name RealmConfig
extends RefCounted

## 灵雨诀生长乘数（v2 基线 8.0）。
const SPIRIT_RAIN_GROWTH_MULT := 8.0

## 境界表。数组索引即境界序号：0 凡人 / 1 炼气 / 2 筑基 / 3 金丹。
## 每项字段：
##   name                 境界名
##   required_cultivation 突破到该境界所需的累计修为
##   production           生产乘数（生长 / 产量 / 灵气 / 自动修炼灵气）
##   cultivation          修炼乘数（丹药修为 / 自动修炼修为）
## 该常量为只读配置，调用方不应就地修改。
const REALMS: Array[Dictionary] = [
	{"name": "凡人", "required_cultivation": 0, "production": 1.0, "cultivation": 1.0},
	{"name": "炼气", "required_cultivation": 100, "production": 5.0, "cultivation": 2.0},
	{"name": "筑基", "required_cultivation": 1500, "production": 50.0, "cultivation": 10.0},
	{"name": "金丹", "required_cultivation": 30000, "production": 500.0, "cultivation": 100.0},
]

## 返回境界总数。
static func realm_count() -> int:
	return REALMS.size()

## 返回境界表。结果引用内部只读常量，调用方不得修改。
static func get_realms() -> Array[Dictionary]:
	return REALMS

## 返回指定境界的生产乘数（生长 / 产量 / 灵气 / 自动修炼灵气）。
## 索引越界（任意方向）时返回最高境界的生产乘数。
static func production_mult(realm_index: int) -> float:
	var n := REALMS.size()
	if realm_index < 0 or realm_index >= n:
		return float(REALMS[n - 1]["production"])
	return float(REALMS[realm_index]["production"])

## 返回指定境界的修炼乘数（丹药修为 / 自动修炼修为）。
## 索引越界（任意方向）时返回最高境界的修炼乘数。
static func cultivation_mult(realm_index: int) -> float:
	var n := REALMS.size()
	if realm_index < 0 or realm_index >= n:
		return float(REALMS[n - 1]["cultivation"])
	return float(REALMS[realm_index]["cultivation"])

## 返回突破到 new_realm_index 这次应发放的奖励描述（纯数据，GameState 负责应用）。
## 字段含义：
##   field_delta             本次新增灵田数量
##   unlock_spirit_rain      是否解锁灵雨诀
##   auto_harvest            是否开启自动收获
##   unlock_alchemy          是否解锁炼丹炉
##   unlock_foundation_pill  是否解锁筑基丹配方
##   unlock_field_upgrade    是否解锁灵田升级（upgrade_field，消耗 50*level 灵石）
##   unlock_auto_cultivation 是否解锁自动修炼（灵气浓度驱动，筑基起生效）
##   unlock_golden_pill      是否解锁金元丹配方
##   unlock_spirit_veinify   是否解锁灵脉化田（spirit_veinify_field，消耗 500 灵石）
## 注意：production / cultivation 乘数不在此处发放，它们按当前境界实时查表获得。
## 庚金剑诀 / 守护灵阵 沿用现有解锁路径，此处不重复声明。
## 未知索引返回全默认值的空奖励。
static func breakthrough_rewards(new_realm_index: int) -> Dictionary:
	var rewards := {
		"field_delta": 0,
		"unlock_spirit_rain": false,
		"auto_harvest": false,
		"unlock_alchemy": false,
		"unlock_foundation_pill": false,
		"unlock_field_upgrade": false,
		"unlock_auto_cultivation": false,
		"unlock_golden_pill": false,
		"unlock_spirit_veinify": false,
	}
	match new_realm_index:
		1:  # 炼气
			rewards["field_delta"] = 1
			rewards["unlock_spirit_rain"] = true
			rewards["auto_harvest"] = true
		2:  # 筑基（庚金剑诀 / 守护灵阵沿用现有实现，此处不重复声明）
			rewards["field_delta"] = 1
			rewards["unlock_alchemy"] = true
			rewards["unlock_foundation_pill"] = true
			rewards["unlock_field_upgrade"] = true
			rewards["unlock_auto_cultivation"] = true
		3:  # 金丹
			rewards["unlock_golden_pill"] = true
			rewards["unlock_spirit_veinify"] = true
		_:
			pass  # 其它索引：空奖励（全默认值）
	return rewards
