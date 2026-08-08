## BalanceConfig
##
## 游戏全部可调数值的唯一来源。
##
## 这里保存境界、作物、灵田、天赋、成就、自动化、商店、事件和操作参数。
## 其它模块只负责规则和状态，不再复制这些数值。真实结算、游戏内模拟器和
## headless 探针都通过同一份配置读取，改动平衡时只需要修改本文件。
class_name BalanceConfig
extends RefCounted


# ───────────────────────── 运行结构 ─────────────────────────

const FIELD_COUNT := 3
const INITIAL_REALM_INDEX := 0
const INITIAL_UNLOCKED_FIELDS := 1
const INITIAL_SEASON_INDEX := 0
const DEFAULT_MULTIPLIER := 1.0
const DEFAULT_PEST_LEVEL := 0
const MIN_LIFESPAN_YEARS := 1.0
const DEFAULT_PLAYER_CLICKS_PER_SECOND := 4.0


# ───────────────────────── 境界 / 突破 ─────────────────────────

const REALMS: Array[Dictionary] = [
	{"name": "凡人", "required_cultivation": 0.0, "production": 1.0, "cultivation": 1.0},
	{"name": "炼气", "required_cultivation": 200.0, "production": 3.0, "cultivation": 3.0},
	{"name": "筑基", "required_cultivation": 2000.0, "production": 8.0, "cultivation": 8.0},
	{"name": "金丹", "required_cultivation": 50000.0, "production": 20.0, "cultivation": 20.0},
]

const BREAKTHROUGH_REWARDS: Dictionary = {
	1: {
		"unlock_spirit_rain": true,
	},
	2: {
		"unlock_auto_cultivation": true,
		"unlock_mind_flower": true,
	},
	3: {
		"unlock_sun_fruit": true,
		"unlock_heaven_lotus": true,
	},
}


# ───────────────────────── 作物 / 季节 / 灵田 ─────────────────────────

const CROPS: Dictionary = {
	# cultivation 是每株作物的直接修为基值；灵田收获不再产生灵气。
	"gathering_grass": {"name": "聚灵草", "growth": 5.0, "cultivation": 3.0, "sell_price": 5.0, "unlock_realm": 0},
	"mind_flower": {"name": "凝神花", "growth": 30.0, "cultivation": 10.0, "sell_price": 20.0, "unlock_realm": 2},
	"sun_fruit": {"name": "赤阳果", "growth": 120.0, "cultivation": 50.0, "sell_price": 100.0, "unlock_realm": 3},
	"heaven_lotus": {"name": "天道莲", "growth": 1800.0, "cultivation": 500.0, "sell_price": 1000.0, "unlock_realm": 3},
}

# 灵植熟练度是跨大限、跨新局保留的长期进度。
# 门槛共享，产量/时间奖励按灵植定义。每一档的产量是“当前档位总加成”，
# 不是把前几档的产量重复相加；天赋点则按首次跨过门槛逐档累加。
const CROP_PROFICIENCY_THRESHOLDS: Array[int] = [10, 50, 150, 400]
const CROP_PROFICIENCY_REWARDS: Dictionary = {
	"gathering_grass": [
		{"yield_bonus": 1, "growth_reduction": 0.0, "talent_points": 1},
		{"yield_bonus": 1, "growth_reduction": 1.0, "talent_points": 2},
		{"yield_bonus": 2, "growth_reduction": 0.0, "talent_points": 3},
		{"yield_bonus": 3, "growth_reduction": 1.0, "talent_points": 5},
	],
	"mind_flower": [
		{"yield_bonus": 1, "growth_reduction": 0.0, "talent_points": 1},
		{"yield_bonus": 1, "growth_reduction": 2.0, "talent_points": 2},
		{"yield_bonus": 2, "growth_reduction": 0.0, "talent_points": 3},
		{"yield_bonus": 3, "growth_reduction": 2.0, "talent_points": 5},
	],
	"sun_fruit": [
		{"yield_bonus": 1, "growth_reduction": 0.0, "talent_points": 1},
		{"yield_bonus": 1, "growth_reduction": 5.0, "talent_points": 2},
		{"yield_bonus": 2, "growth_reduction": 0.0, "talent_points": 3},
		{"yield_bonus": 3, "growth_reduction": 5.0, "talent_points": 5},
	],
	"heaven_lotus": [
		{"yield_bonus": 1, "growth_reduction": 0.0, "talent_points": 1},
		{"yield_bonus": 1, "growth_reduction": 60.0, "talent_points": 2},
		{"yield_bonus": 2, "growth_reduction": 0.0, "talent_points": 3},
		{"yield_bonus": 3, "growth_reduction": 60.0, "talent_points": 5},
	],
}
const CROP_PROFICIENCY_TOTAL_TALENT_POINTS := 44

const SEASONS: Array[Dictionary] = [
	{"name": "春·万物萌发", "growth": 1.25, "yield": 1.0},
	{"name": "夏·灵气鼎盛", "growth": 1.0, "yield": 1.0},
	{"name": "秋·五谷丰登", "growth": 1.0, "yield": 1.25},
	{"name": "冬·蛰伏养息", "growth": 1.0, "yield": 1.0},
]

const FIELD_TIER_NAMES: Array[String] = ["凡田", "灵田", "宝田", "仙田"]
const FIELD_TIER_MULTS: Array[float] = [1.0, 10.0, 100.0, 1000.0]
const FIELD_SLOT_COSTS: Array[Dictionary] = [
	{"spirit_stones": 0.0},
	{"spirit_stones": 100.0},
	{"spirit_stones": 500.0},
]
const FIELD_TIER_UPGRADE_COSTS: Array[Dictionary] = [
	{"spirit_stones": 4000.0, "required_realm": 1},
	{"spirit_stones": 120000.0, "required_realm": 2},
	{"spirit_stones": 3000000.0, "required_realm": 3},
]
const SPIRIT_RAIN_GROWTH_MULT := 8.0
const FIELD_PEST_REDUCTION_PER_LEVEL := 0.25
const MAX_PEST_LEVEL := 3


# ───────────────────────── 寿元 / 灵气 / 天赋里程碑 ─────────────────────────

const LIFESPAN_YEARS_BY_REALM: Array[float] = [60.0, 120.0, 200.0, 500.0]
const LIFESPAN_DECAY_PER_SECOND := 0.5
const QI_HARVEST_STEP := 100.0
const QI_HARVEST_BONUS_PER_STEP := 0.10
const QI_HARVEST_BASE_CAP := 3.0
const CLICK_ACCEL_BASE_SECONDS := 1.0
const TALENT_MILESTONE_POINTS := 1
const TALENT_MILESTONES: Array[float] = [
	1000.0,
	10000.0,
	100000.0,
	1000000.0,
	10000000.0,
	100000000.0,
	1000000000.0,
]
const TALENT_BREAKTHROUGH_POINTS_BY_REALM: Array[int] = [0, 3, 7, 15]


# ───────────────────────── 成就 ─────────────────────────

# 成就只记录长期目标和成就点，不直接加入修为/灵石/天赋点主经济，避免与
# 熟练度、突破和离线折算重复发放成长资源。进度条件由 AchievementSystem 读取。
const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_harvest", "name": "初入灵田", "category": "灵田", "desc": "完成 1 次灵田收获。", "metric": "total_harvest_count", "target": 1.0, "points": 1},
	{"id": "harvest_100", "name": "熟能生巧", "category": "灵田", "desc": "累计完成 100 次灵田收获。", "metric": "total_harvest_count", "target": 100.0, "points": 2},
	{"id": "harvest_1000", "name": "灵田老手", "category": "灵田", "desc": "累计完成 1,000 次灵田收获。", "metric": "total_harvest_count", "target": 1000.0, "points": 3},
	{"id": "cultivation_1000", "name": "初窥修途", "category": "修行", "desc": "累计获得 1,000 点修为。", "metric": "total_cultivation_earned", "target": 1000.0, "points": 2},
	{"id": "cultivation_1m", "name": "厚积薄发", "category": "修行", "desc": "累计获得 1,000,000 点修为。", "metric": "total_cultivation_earned", "target": 1000000.0, "points": 5},
	{"id": "reach_qi", "name": "踏入炼气", "category": "境界", "desc": "首次达到炼气境。", "metric": "realm_index", "target": 1.0, "points": 2},
	{"id": "reach_foundation", "name": "筑基有成", "category": "境界", "desc": "首次达到筑基境。", "metric": "realm_index", "target": 2.0, "points": 3},
	{"id": "reach_golden", "name": "金丹初成", "category": "境界", "desc": "首次达到金丹境。", "metric": "realm_index", "target": 3.0, "points": 5},
	{"id": "buy_second_field", "name": "开垦新田", "category": "灵田", "desc": "购买第 2 块灵田。", "metric": "unlocked_fields", "target": 2.0, "points": 2},
	{"id": "buy_third_field", "name": "三田并立", "category": "灵田", "desc": "解锁全部 3 块灵田。", "metric": "unlocked_fields", "target": 3.0, "points": 3},
	{"id": "grass_proficiency_10", "name": "识草入门", "category": "熟练度", "desc": "聚灵草熟练度达到 10 次。", "metric": "crop_proficiency", "crop_id": "gathering_grass", "target": 10.0, "points": 1},
	{"id": "mind_proficiency_10", "name": "凝神入门", "category": "熟练度", "desc": "凝神花熟练度达到 10 次。", "metric": "crop_proficiency", "crop_id": "mind_flower", "target": 10.0, "points": 1},
	{"id": "sun_proficiency_10", "name": "赤阳入门", "category": "熟练度", "desc": "赤阳果熟练度达到 10 次。", "metric": "crop_proficiency", "crop_id": "sun_fruit", "target": 10.0, "points": 1},
	{"id": "lotus_proficiency_10", "name": "莲心初悟", "category": "熟练度", "desc": "天道莲熟练度达到 10 次。", "metric": "crop_proficiency", "crop_id": "heaven_lotus", "target": 10.0, "points": 1},
	{"id": "grass_master", "name": "聚灵草宗师", "category": "熟练度", "desc": "聚灵草熟练度达到 400 次。", "metric": "crop_proficiency", "crop_id": "gathering_grass", "target": 400.0, "points": 4},
	{"id": "lotus_master", "name": "天道莲宗师", "category": "熟练度", "desc": "天道莲熟练度达到 400 次。", "metric": "crop_proficiency", "crop_id": "heaven_lotus", "target": 400.0, "points": 4},
	{"id": "first_new_run", "name": "再起一局", "category": "轮回", "desc": "大限后开始第 1 次新局。", "metric": "reincarnation_count", "target": 1.0, "points": 2},
	{"id": "new_run_3", "name": "三世求道", "category": "轮回", "desc": "累计开始 3 次新局。", "metric": "reincarnation_count", "target": 3.0, "points": 4},
	{"id": "talent_5", "name": "道心渐明", "category": "天赋", "desc": "解锁 5 个天赋节点。", "metric": "talent_nodes", "target": 5.0, "points": 3},
]


# ───────────────────────── 事件 / 计时 ─────────────────────────

const SEASON_DURATION_SECONDS := 180.0
const RANDOM_EVENT_COOLDOWN_SECONDS := 180.0
const EVENT_DURATIONS: Dictionary = {
	"auspicious": 60.0,
	"dao_insight": 30.0,
	"warlord_birthday": 60.0,
}
const EVENT_PROD_BONUS := 10.0
const EVENT_CULT_BONUS := 20.0
const EVENT_EVENTS: Array[String] = ["auspicious", "dao_insight", "warlord_birthday"]
const DEFAULT_EVENT_DURATION_SECONDS := 60.0
const EVENT_WARLORD_PEST_LEVEL := 1
const WORLD_STATE_EMIT_INTERVAL_SECONDS := 0.25


# ───────────────────────── 自动化 ─────────────────────────

const AUTO_BREW_INTERVAL_SECONDS := 5.0
const AUTO_CULT_RATE := 0.5
const AUTO_QI_RATE := 0.2
const AUTO_REALM_INDEX_MIN := 2
const ADVANCED_COMBAT_REALM_INDEX := 2


# ───────────────────────── 离线一次性折算 ─────────────────────────

# 离线折算与离线时长无关，只根据跨局、晋级和收获的长期计数发放一次性差额。
const OFFLINE_REINCARNATION_TALENT_CAP := 3
const OFFLINE_PROMOTION_DIVISOR := 2
const OFFLINE_PROMOTION_TALENT_CAP := 2
const OFFLINE_HARVEST_DIVISOR := 2000
const OFFLINE_HARVEST_TALENT_CAP := 2
const OFFLINE_TALENT_POINT_CAP := 7
const OFFLINE_REINCARNATION_STONES := 50.0
const OFFLINE_PROMOTION_STONES := 100.0
const OFFLINE_HARVEST_STONES := 2.0


# ───────────────────────── 法术 / 守护灵阵 / 噬金虫 ─────────────────────────

const SPIRIT_RAIN_DURATION_SECONDS := 60.0
const SPIRIT_RAIN_COST := 10.0
const GENGJIN_SWORD_COST := 20.0
const GENGJIN_SWORD_COOLDOWN_SECONDS := 120.0
const GENGJIN_SWORD_CLEAR_COOLDOWN_SECONDS := 300.0
const MIN_INSECT_CORPSES_PER_SWORD := 1
const GUARDIAN_UPGRADE_COST := 100.0
const GUARDIAN_BASE_LEVEL := 1
const GUARDIAN_BASE_CHARGES := 3
const GUARDIAN_CHARGES_BASE_OFFSET := 2
const INSECT_INITIAL_DELAY_SECONDS := 180.0
const INSECT_ATTACK_INTERVAL_SECONDS := 60.0
const INSECT_WARLORD_ATTACK_INTERVAL_SECONDS := 30.0
const INSECT_WARLORD_ATTACK_COUNT := 2
const INSECT_CORPSE_SELL_PRICE := 8.0


# ───────────────────────── 商店 ─────────────────────────

const SHOP_ITEMS: Array[Dictionary] = [
	{
		"id": "longevity_pill",
		"name": "长生丹",
		"cost": 100.0,
		"icon": "寿",
		"desc": "恢复 30 年寿元，寿元归零时也可使用。",
		"effect": "lifespan",
		"amount": 30.0,
	},
	{
		"id": "qi_jade",
		"name": "聚气玉",
		"cost": 80.0,
		"icon": "气",
		"desc": "立即获得 200 灵气，提升当前收获倍率。",
		"effect": "qi",
		"amount": 200.0,
	},
	{
		"id": "insight_scroll",
		"name": "悟道残卷",
		"cost": 500.0,
		"icon": "悟",
		"desc": "立即获得 1 天赋点，用于树形天赋加点。",
		"effect": "talent_points",
		"amount": 1.0,
	},
	{
		# 越买越贵：实际价格 = cost × escalation^已购次数，四舍五入到 10，不设上限。
		"id": "frenzy_pill",
		"name": "狂暴丹",
		"cost": 100.0,
		"escalation": 1.5,
		"icon": "狂",
		"desc": "生产 ×3，持续 5 秒；每次购买后价格 ×1.5 递增。",
		"effect": "buff",
		"mult": 3.0,
		"duration": 5.0,
	},
]


# ───────────────────────── 天赋树 ─────────────────────────

const TALENT_NODE_ORDER: Array[String] = [
	"root",
	"farming_start", "farming_yield", "farming_speed", "farming_capstone",
	"alchemy_start", "alchemy_power", "alchemy_quality", "alchemy_capstone",
	"spirit_start", "spirit_qi", "spirit_lifespan", "spirit_capstone",
]

const TALENT_NODES: Dictionary = {
	"root": {
		"name": "道心初醒", "icon": "◇", "branch": "root", "cost": 0,
		"requires": [], "requires_any": [], "desc": "开启三条修行道路。",
		"effects": {},
	},
	"farming_start": {
		"name": "农道入门", "icon": "农", "branch": "farming", "cost": 1,
		"requires": ["root"], "requires_any": [], "desc": "所有灵田产出 ×1.20。",
		"effects": {"production_mult": 1.20},
	},
	"farming_yield": {
		"name": "丰收回响", "icon": "穗", "branch": "farming", "cost": 2,
		"requires": ["farming_start"], "requires_any": [], "desc": "灵田产出再 ×1.50。",
		"effects": {"production_mult": 1.50},
	},
	"farming_speed": {
		"name": "生长法门", "icon": "芽", "branch": "farming", "cost": 2,
		"requires": ["farming_start"], "requires_any": [], "desc": "作物生长速度 ×1.40。",
		"effects": {"growth_mult": 1.40},
	},
	"farming_capstone": {
		"name": "天工收成", "icon": "仓", "branch": "farming", "cost": 5,
		"requires": [], "requires_any": ["farming_yield", "farming_speed"],
		"desc": "每次点击加速时间再 ×1.50。",
		"effects": {"click_accel_mult": 1.50},
	},
	"alchemy_start": {
		"name": "丹火入门", "icon": "丹", "branch": "alchemy", "cost": 1,
		"requires": ["root"], "requires_any": [], "desc": "灵田收获修为 ×1.25。",
		"effects": {"cultivation_mult": 1.25},
	},
	"alchemy_power": {
		"name": "丹火淬炼", "icon": "火", "branch": "alchemy", "cost": 2,
		"requires": ["alchemy_start"], "requires_any": [], "desc": "灵田收获修为再 ×1.60。",
		"effects": {"cultivation_mult": 1.60},
	},
	"alchemy_quality": {
		"name": "灵植品鉴", "icon": "鉴", "branch": "alchemy", "cost": 2,
		"requires": ["alchemy_start"], "requires_any": [], "desc": "灵田收获修为再 ×1.25。",
		"effects": {"cultivation_mult": 1.25},
	},
	"alchemy_capstone": {
		"name": "丹道循环", "icon": "炉", "branch": "alchemy", "cost": 5,
		"requires": [], "requires_any": ["alchemy_power", "alchemy_quality"],
		"desc": "灵田收获修为再 ×1.80。",
		"effects": {"cultivation_mult": 1.80},
	},
	"spirit_start": {
		"name": "灵根入门", "icon": "灵", "branch": "spirit", "cost": 1,
		"requires": ["root"], "requires_any": [], "desc": "收获灵气 ×1.30。",
		"effects": {"qi_gain_mult": 1.30},
	},
	"spirit_qi": {
		"name": "聚气潮汐", "icon": "潮", "branch": "spirit", "cost": 2,
		"requires": ["spirit_start"], "requires_any": [], "desc": "自动修炼效率 ×1.60。",
		"effects": {"auto_cultivation_mult": 1.60},
	},
	"spirit_lifespan": {
		"name": "长生印", "icon": "寿", "branch": "spirit", "cost": 2,
		"requires": ["spirit_start"], "requires_any": [], "desc": "寿元流逝速度 ×0.65。",
		"effects": {"lifespan_decay_mult": 0.65},
	},
	"spirit_capstone": {
		"name": "灵根化田", "icon": "田", "branch": "spirit", "cost": 5,
		"requires": [], "requires_any": ["spirit_qi", "spirit_lifespan"],
		"desc": "灵气收获加成效果 ×1.50。",
		"effects": {"qi_harvest_mult": 1.50},
	},
}


# 返回某作物在指定累计收获次数下已经达到的熟练度档位（0..4）。
static func crop_proficiency_stage(harvest_count: int) -> int:
	var safe_count := maxi(0, harvest_count)
	var stage := 0
	for threshold in CROP_PROFICIENCY_THRESHOLDS:
		if safe_count >= int(threshold):
			stage += 1
	return stage


# 返回当前档位的产量加成、累计时间减免和下一门槛。
# 产量与时间减免取最高已达档位，天赋点另由跨门槛记录函数累计。
static func crop_proficiency_reward(crop_id: String, harvest_count: int) -> Dictionary:
	var safe_count := maxi(0, harvest_count)
	var stage := crop_proficiency_stage(safe_count)
	var rewards_variant: Variant = CROP_PROFICIENCY_REWARDS.get(crop_id, [])
	var rewards: Array = rewards_variant if rewards_variant is Array else []
	var yield_bonus := 0
	var growth_reduction := 0.0
	var talent_points := 0
	for index in range(mini(stage, rewards.size())):
		var reward: Dictionary = rewards[index]
		# 产量显示为当前最高档位；时间减免取已达档位中的最大值。
		yield_bonus = int(reward.get("yield_bonus", yield_bonus))
		growth_reduction = maxf(growth_reduction, float(reward.get("growth_reduction", 0.0)))
		talent_points += int(reward.get("talent_points", 0))
	var next_threshold := -1
	if stage < CROP_PROFICIENCY_THRESHOLDS.size():
		next_threshold = int(CROP_PROFICIENCY_THRESHOLDS[stage])
	return {
		"crop_id": crop_id,
		"harvest_count": safe_count,
		"stage": stage,
		"yield_bonus": yield_bonus,
		"growth_reduction": growth_reduction,
		"talent_points": talent_points,
		"next_threshold": next_threshold,
		"complete": stage >= CROP_PROFICIENCY_THRESHOLDS.size(),
	}


# 只发放本次从 previous_count 到 new_count 新跨过的门槛奖励，避免读档/重复结算重复给点。
static func crop_proficiency_talent_points(crop_id: String, previous_count: int, new_count: int) -> int:
	var old_count := maxi(0, previous_count)
	var current_count := maxi(old_count, new_count)
	var rewards_variant: Variant = CROP_PROFICIENCY_REWARDS.get(crop_id, [])
	var rewards: Array = rewards_variant if rewards_variant is Array else []
	var points := 0
	for index in range(CROP_PROFICIENCY_THRESHOLDS.size()):
		var threshold := int(CROP_PROFICIENCY_THRESHOLDS[index])
		if old_count < threshold and current_count >= threshold and index < rewards.size():
			var reward: Dictionary = rewards[index]
			points += int(reward.get("talent_points", 0))
	return points


# 返回某作物在当前熟练度下的基础成熟时间；倍率由 SimulationSystem 继续处理。
static func crop_base_growth_seconds(crop_id: String, harvest_count: int) -> float:
	var crop: Variant = CROPS.get(crop_id, null)
	if crop == null or not crop is Dictionary:
		return 0.0
	var reward := crop_proficiency_reward(crop_id, harvest_count)
	return maxf(0.001, float(crop.get("growth", 0.0)) - float(reward.get("growth_reduction", 0.0)))


## 为没有保存解锁字段的旧存档计算当前规则下的默认解锁状态。
## 解锁门槛仍只定义在 BREAKTHROUGH_REWARDS，避免 SaveManager 再复制一份境界数字。
static func default_unlock_flags(realm_index: int) -> Dictionary:
	var flags := {
		"spirit_rain_unlocked": false,
		"unlock_auto_cultivation": false,
		"unlock_mind_flower": false,
		"unlock_sun_fruit": false,
		"unlock_heaven_lotus": false,
	}
	for reward_realm in BREAKTHROUGH_REWARDS:
		if int(reward_realm) > realm_index:
			continue
		var rewards: Dictionary = BREAKTHROUGH_REWARDS[reward_realm]
		for reward_key in rewards:
			var state_key := "spirit_rain_unlocked" if reward_key == "unlock_spirit_rain" else String(reward_key)
			if flags.has(state_key):
				flags[state_key] = bool(flags[state_key]) or bool(rewards[reward_key])
	return flags
