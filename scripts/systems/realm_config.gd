## RealmConfig
## 境界与突破奖励的纯数据 / 查询模块。
## 仅提供数据表与查询接口，所有状态变更与数值应用一律由 GameState 协调执行。
## 境界同时是 Gate（突破门槛）与 Modifier（production / cultivation 乘数）。
##   production   作用于：收获数量、灵石产出、自动修炼的灵气部分。（生长速度已与境界解耦，仅受季节/灵雨诀/木灵根影响）
##   cultivation  作用于：灵田直接修为、自动修炼的修为部分。
## production / cultivation 乘数不在 breakthrough_rewards 中发放，而是按当前境界实时查表获得。
## 数值由 BalanceConfig 统一管理；本模块只保留境界查询和奖励规则。
class_name RealmConfig
extends RefCounted

## 返回境界总数。
static func realm_count() -> int:
	return BalanceConfig.REALMS.size()

## 返回境界表。配置统一来自 BalanceConfig。
static func get_realms() -> Array[Dictionary]:
	return BalanceConfig.REALMS

## 返回指定境界的生产乘数（生长 / 产量 / 灵石 / 自动修炼灵气）。
## 索引越界（任意方向）时返回最高境界的生产乘数。
static func production_mult(realm_index: int) -> float:
	var n := BalanceConfig.REALMS.size()
	if realm_index < 0 or realm_index >= n:
		return float(BalanceConfig.REALMS[n - 1]["production"])
	return float(BalanceConfig.REALMS[realm_index]["production"])

## 返回指定境界的修炼乘数（灵田修为 / 自动修炼修为）。
## 索引越界（任意方向）时返回最高境界的修炼乘数。
static func cultivation_mult(realm_index: int) -> float:
	var n := BalanceConfig.REALMS.size()
	if realm_index < 0 or realm_index >= n:
		return float(BalanceConfig.REALMS[n - 1]["cultivation"])
	return float(BalanceConfig.REALMS[realm_index]["cultivation"])

## 返回突破到 new_realm_index 这次应发放的奖励描述（纯数据，GameState 负责应用）。
## 字段含义：
##   unlock_spirit_rain      是否解锁灵雨诀
##   unlock_auto_cultivation 是否解锁自动修炼（灵气浓度驱动，筑基起生效）
##   unlock_mind_flower      是否解锁凝神花种植
##   unlock_sun_fruit        是否解锁赤阳果种植
##   unlock_heaven_lotus     是否解锁天道莲种植
## 注意：production / cultivation 乘数不在此处发放，它们按当前境界实时查表获得。
## 庚金剑诀 / 守护灵阵 沿用现有解锁路径，此处不重复声明。
## 未知索引返回全默认值的空奖励。
static func breakthrough_rewards(new_realm_index: int) -> Dictionary:
	var rewards := {
		"unlock_spirit_rain": false,
		"unlock_auto_cultivation": false,
		"unlock_mind_flower": false,
		"unlock_sun_fruit": false,
		"unlock_heaven_lotus": false,
	}
	var configured: Variant = BalanceConfig.BREAKTHROUGH_REWARDS.get(new_realm_index, {})
	if configured is Dictionary:
		for key in configured:
			rewards[key] = bool(configured[key])
	return rewards
