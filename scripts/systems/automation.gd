class_name AutomationSystem
extends RefCounted

## 灵气浓度和在线自动修炼的纯计算模块。
## 永久成长由 TalentTree 计算后作为倍率传入，不依赖运行重置次数。

## 灵气浓度 = 正在种植的灵田数量与档位之和。
static func compute_qi_density(fields: Array, unlocked_fields: int) -> float:
	var density := 0.0
	var limit := maxi(0, mini(unlocked_fields, fields.size()))
	for i in range(limit):
		var field: Dictionary = fields[i]
		if String(field.get("crop_id", "")) == "":
			continue
		var tier := maxi(0, int(field.get("tier", 0)))
		density += 1.0 + float(tier)
	return density


## 计算当前每秒自动修炼收益。
	## event_production_mult 只作用于自动获得的灵气，event_cultivation_mult 只作用于修为。
static func auto_rates(
		qi_density: float,
		realm_index: int,
		event_production_mult: float,
		event_cultivation_mult: float,
	realm_production: float,
	realm_cultivation: float,
	auto_talent_mult: float = 1.0,
	qi_talent_mult: float = 1.0
		) -> Dictionary:
	if realm_index < BalanceConfig.AUTO_REALM_INDEX_MIN:
		return {"cultivation_per_sec": 0.0, "qi_per_sec": 0.0}
	var density := maxf(0.0, qi_density)
	var event_prod := maxf(0.0, event_production_mult)
	var event_cult := maxf(0.0, event_cultivation_mult)
	var production := maxf(0.0, realm_production)
	var cultivation := maxf(0.0, realm_cultivation)
	var talent_mult := maxf(0.0, auto_talent_mult)
	var qi_mult := maxf(0.0, qi_talent_mult)
	return {
		"cultivation_per_sec": density * BalanceConfig.AUTO_CULT_RATE * cultivation * event_cult * talent_mult,
		"qi_per_sec": density * BalanceConfig.AUTO_QI_RATE * production * event_prod * qi_mult,
	}
