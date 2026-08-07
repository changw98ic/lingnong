## RealmConfig
## 境界与突破奖励的纯数据 / 查询模块。
## 仅提供数据表与查询接口，所有状态变更与数值应用一律由 GameState 协调执行。
class_name RealmConfig
extends RefCounted

## 灵雨诀生长乘数（旧版基线 1.5，新版基线 8.0）。
const SPIRIT_RAIN_GROWTH_MULT := 8.0

## 境界表：name 为境界名，required_cultivation 为突破到该境界所需的累计修为。
## 数组索引即境界序号：0 凡人 / 1 炼气 / 2 筑基 / 3 金丹。
## 该常量为只读配置，调用方不应就地修改。
const REALMS: Array[Dictionary] = [
	{"name": "凡人", "required_cultivation": 0},
	{"name": "炼气", "required_cultivation": 100},
	{"name": "筑基", "required_cultivation": 1500},
	{"name": "金丹", "required_cultivation": 30000},
]

## 返回境界表。结果引用内部只读常量，调用方不得修改。
static func get_realms() -> Array[Dictionary]:
	return REALMS

## 返回境界总数。
static func realm_count() -> int:
	return REALMS.size()

## 返回突破到 new_realm_index 这次应发放的奖励描述（纯数据，GameState 负责应用）。
## 字段含义：
##   field_delta            本次新增灵田数量
##   unlock_spirit_rain     是否解锁灵雨诀
##   qi_gen_mult            灵气产出乘数（1.0 表示无变化）
##   auto_harvest           是否开启自动收获
##   unlock_alchemy         是否解锁炼丹炉
##   unlock_foundation_pill 是否解锁筑基丹配方
##   unlock_golden_pill     是否解锁金元丹配方
##   unlock_spirit_vein     是否解锁灵脉
##   global_mult_delta      全局产出乘数增量（1.0 表示无变化，乘法语义）
## 未知索引返回全默认值的空奖励。
static func breakthrough_rewards(new_realm_index: int) -> Dictionary:
	var rewards := {
		"field_delta": 0,
		"unlock_spirit_rain": false,
		"qi_gen_mult": 1.0,
		"auto_harvest": false,
		"unlock_alchemy": false,
		"unlock_foundation_pill": false,
		"unlock_golden_pill": false,
		"unlock_spirit_vein": false,
		"global_mult_delta": 1.0,
	}
	match new_realm_index:
		1:  # 炼气
			rewards["field_delta"] = 1
			rewards["unlock_spirit_rain"] = true
			rewards["qi_gen_mult"] = 2.0
			rewards["auto_harvest"] = true
		2:  # 筑基（庚金剑诀 / 守护灵阵沿用现有实现，此处不重复声明）
			rewards["field_delta"] = 1
			rewards["unlock_alchemy"] = true
			rewards["unlock_foundation_pill"] = true
		3:  # 金丹
			rewards["unlock_spirit_vein"] = true
			rewards["unlock_golden_pill"] = true
			rewards["global_mult_delta"] = 2.0
		_:
			pass  # 其它索引：空奖励（全默认值）
	return rewards
