class_name AutomationSystem
extends RefCounted

## 灵气浓度 + 自动修炼模块（v2）。
##
## 取代旧的“灵脉 per-sec”二态模型：不再有 spirit_vein_active / BASE_CULTIVATION_PER_SEC，
## 改为由“种植中的灵田”驱动 qi_density（灵气浓度），再由 qi_density 派生自动修炼的
## 修为 / 灵气每秒产出。筑基（realm_index >= 2）起生效，金丹的灵脉化田把浓度贡献从
## +1 提升到 +10，从而把“灵脉”概念统一进 qi_density。
##
## 本模块不读写任何全局单例（不直接引用 RealmConfig / GameState），所有外部数据
## 通过参数传入、结果以 Dictionary 返回，由 GameState 协调应用到自身货币字段。

# 离线收益结算封顶：8 小时 = 28800 秒。
const OFFLINE_CAP_SECONDS := 28800.0

# 自动修炼修为速率系数。
# auto_cultivation_per_sec = qi_density * AUTO_CULT_RATE * realm_cultivation * reincarnation_mult。
const AUTO_CULT_RATE := 0.5

# 自动修炼灵气速率系数。
# auto_qi_per_sec = qi_density * AUTO_QI_RATE * realm_production * reincarnation_mult * event_production_mult。
const AUTO_QI_RATE := 0.2

# 解锁自动修炼的最低境界序号（2 = 筑基）。
const AUTO_REALM_INDEX_MIN := 2


## 计算当前灵气浓度。
## 已解锁灵田中：普通田种植中（crop_id 非空且未灵脉化）+1；灵脉化田（spirit_vein 为真）+10。
## 灵脉化田即便未种植也贡献浓度（其本身即灵脉），且不与“普通种植中”叠加，
## 以匹配契约公式 qi_density = (种植中的普通田数)*1 + (灵脉化田数)*10。
## fields: 与 GameState.fields 同构的灵田字典数组；
## unlocked_fields: 当前解锁灵田数量，超出该数量的尾部灵田不计入。
static func compute_qi_density(fields: Array, unlocked_fields: int) -> float:
	var density := 0.0
	var limit := maxi(0, mini(unlocked_fields, fields.size()))
	for i in range(limit):
		var field: Dictionary = fields[i]
		if bool(field.get("spirit_vein", false)):
			density += 10.0
		elif String(field.get("crop_id", "")) != "":
			density += 1.0
	return density


## 计算自动修炼的每秒产出。
## qi_density: 由 compute_qi_density 得到的灵气浓度；
## realm_index: 当前境界序号（< AUTO_REALM_INDEX_MIN 表示尚未解锁，返回 0）；
## reincarnation_mult: 转世全局产出倍率；
## event_production_mult: 事件爆发窗产出倍率（祥瑞降世期间为 5.0）——仅作用于灵气；
## realm_production: 当前境界的 production 乘数（RealmConfig.production_mult）；
## realm_cultivation: 当前境界的 cultivation 乘数（RealmConfig.cultivation_mult）。
## 返回 {"cultivation_per_sec": float, "qi_per_sec": float}。筑基前两项均为 0。
## 注：契约规定 event_production_mult 只接入“自动修炼灵气”，不接入修为部分。
func auto_rates(
		qi_density: float,
		realm_index: int,
		reincarnation_mult: float,
		event_production_mult: float,
		realm_production: float,
		realm_cultivation: float
		) -> Dictionary:
	if realm_index < AUTO_REALM_INDEX_MIN:
		return {"cultivation_per_sec": 0.0, "qi_per_sec": 0.0}
	var density := maxf(0.0, qi_density)
	var reinc := maxf(0.0, reincarnation_mult)
	var event_mult := maxf(0.0, event_production_mult)
	var production := maxf(0.0, realm_production)
	var cultivation_mult := maxf(0.0, realm_cultivation)
	return {
		"cultivation_per_sec": density * AUTO_CULT_RATE * cultivation_mult * reinc,
		"qi_per_sec": density * AUTO_QI_RATE * production * reinc * event_mult,
	}


## 结算离线期间的自动修炼产出。
## 参数语义同 auto_rates；额外 elapsed: 离线时长（秒）。
## 时长封顶 OFFLINE_CAP_SECONDS（8 小时）；筑基前产出为 0，但仍如实返回
## capped / credited_seconds 以便 UI 展示。
## 返回 {"cultivation": float, "qi": float, "capped": bool, "credited_seconds": float}。
func compute_offline(
		qi_density: float,
		realm_index: int,
		reincarnation_mult: float,
		event_production_mult: float,
		realm_production: float,
		realm_cultivation: float,
		elapsed: float
		) -> Dictionary:
	var elapsed_clamped := maxf(0.0, elapsed)
	var capped := elapsed_clamped > OFFLINE_CAP_SECONDS
	var credited_seconds := minf(elapsed_clamped, OFFLINE_CAP_SECONDS)
	var rates := auto_rates(
		qi_density,
		realm_index,
		reincarnation_mult,
		event_production_mult,
		realm_production,
		realm_cultivation
	)
	return {
		"cultivation": float(rates.get("cultivation_per_sec", 0.0)) * credited_seconds,
		"qi": float(rates.get("qi_per_sec", 0.0)) * credited_seconds,
		"capped": capped,
		"credited_seconds": credited_seconds,
	}
