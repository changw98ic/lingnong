## MultiplierStack
## v3 统一倍率系统（纯函数模块）。
## 单次产出计算集中走这里；生长速度另叠加季节、灵雨和生长天赋。
##
## 设计：本模块不持有任何状态、不读写单例；所有分量由 GameState 计算后作为参数传入，
## 函数仅做确定性连乘并返回结果。两个函数对应两类产出：
##   production   作用于：收获数量、灵石产出、自动修炼的灵气部分。
##   cultivation  作用于：灵田直接修为、自动修炼的修为部分。
##
## 分量定义（由 GameState 维护，调用本模块时传入）：
##   permanent_prod   = TalentTree.production_mult
##   permanent_cult   = TalentTree.cultivation_mult
##   field_tier_mult  灵田档位乘数：凡田 1 / 灵田 10 / 宝田 100 / 仙田 1000
##   event_prod_mult  默认 1.0；祥瑞降世期间 = 10.0（持续 60 秒）
##   event_cult_mult  默认 1.0；天道感悟期间 = 20.0（持续 30 秒）
##   buff_mult        默认 1.0；狂暴丹生效 = 3.0（按设计仅作用于 production）
class_name MultiplierStack
extends RefCounted


## 计算生产类产出的综合倍率。
## 公式：RealmConfig.production_mult(realm_index) * permanent_prod * field_tier_mult
##       * event_prod_mult * buff_mult
## 所有参数均为 GameState 已计算好的分量，本函数仅做确定性连乘。
static func production(
	realm_index: int,
	permanent_prod: float,
	field_tier_mult: float,
	event_prod_mult: float,
	buff_mult: float
) -> float:
	return (
		RealmConfig.production_mult(realm_index)
		* permanent_prod
		* field_tier_mult
		* event_prod_mult
		* buff_mult
	)


## 计算修炼类产出的综合倍率。
## 公式：RealmConfig.cultivation_mult(realm_index) * permanent_cult * event_cult_mult
##       * buff_mult
## 注意：按设计 buff 仅作用于 production；调用方在修为场景通常传入 buff_mult = 1.0。
## 此处保留该参数以严格匹配契约签名，函数本身仅做确定性连乘。
static func cultivation(
	realm_index: int,
	permanent_cult: float,
	event_cult_mult: float,
	buff_mult: float
) -> float:
	return (
		RealmConfig.cultivation_mult(realm_index)
		* permanent_cult
		* event_cult_mult
		* buff_mult
	)
