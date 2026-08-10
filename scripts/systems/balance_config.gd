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
	{"name": "炼气", "required_cultivation": 1000.0, "production": 3.0, "cultivation": 3.0},
	{"name": "筑基", "required_cultivation": 80000.0, "production": 8.0, "cultivation": 8.0},
	{"name": "金丹", "required_cultivation": 2000000.0, "production": 20.0, "cultivation": 20.0},
	{"name": "元婴", "required_cultivation": 100000000.0, "production": 100.0, "cultivation": 100.0},
]

const BREAKTHROUGH_REWARDS: Dictionary = {
	1: {
		"unlock_spirit_rain": true,
	},
	2: {
		"unlock_auto_cultivation": true,
	},
	3: {},
}

# 突破材料只能在商店兑换，绝不进入 CROPS。
# required_realm 表示当前境界达到后，商店才开放该材料兑换。
const BREAKTHROUGH_MATERIALS: Dictionary = {
	"fu_qi_dan": {
		"name": "服气丹", "icon": "丹", "cost": 20.0, "required_realm": 0,
		"desc": "炼气突破材料，只能在商店兑换。",
	},
	"jin_yang_hua": {
		"name": "金阳花", "icon": "阳", "cost": 100.0, "required_realm": 1,
		"desc": "筑基突破材料，只能在商店兑换。",
	},
	"zi_mu_gen": {
		"name": "紫木根", "icon": "木", "cost": 100.0, "required_realm": 1,
		"desc": "筑基突破材料，只能在商店兑换。",
	},
	"bi_shui_lian": {
		"name": "碧水莲", "icon": "水", "cost": 100.0, "required_realm": 1,
		"desc": "筑基突破材料，只能在商店兑换。",
	},
	"yan_ling_shu_xin": {
		"name": "炎灵树心", "icon": "火", "cost": 100.0, "required_realm": 1,
		"desc": "筑基突破材料，只能在商店兑换。",
	},
	"da_di_ku_cao": {
		"name": "大地苦草", "icon": "土", "cost": 100.0, "required_realm": 1,
		"desc": "筑基突破材料，只能在商店兑换。",
	},
	"lei_ji_tao_mu": {
		"name": "雷击桃木", "icon": "雷", "cost": 500.0, "required_realm": 2,
		"desc": "金丹突破材料，只能在商店兑换。",
	},
	"fu_lu_zhou": {
		"name": "福禄咒", "icon": "符", "cost": 500.0, "required_realm": 2,
		"desc": "金丹突破材料，只能在商店兑换。",
	},
	"san_qing_chi_ling": {
		"name": "三清敕令", "icon": "令", "cost": 500.0, "required_realm": 2,
		"desc": "金丹突破材料，只能在商店兑换。",
	},
	"yang_ji_di_xin": {
		"name": "阳极地心", "icon": "阳", "cost": 500.0, "required_realm": 2,
		"desc": "金丹突破材料，只能在商店兑换。",
	},
	"yin_ji_yue_hua": {
		"name": "阴极月华", "icon": "阴", "cost": 500.0, "required_realm": 2,
		"desc": "金丹突破材料，只能在商店兑换。",
	},
	"cang_tian_zi_qi": {
		"name": "苍天紫气", "icon": "紫", "cost": 500.0, "required_realm": 2,
		"desc": "金丹突破材料，只能在商店兑换。",
	},
	"zi_fu_yu_sui": {
		"name": "紫府玉髓", "icon": "髓", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
	"yuan_ying_dao_guo": {
		"name": "元婴道果", "icon": "婴", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
	"lei_jie_cui_ti": {
		"name": "雷劫淬体", "icon": "雷", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
	"tian_jie_lei_jing": {
		"name": "天劫雷晶", "icon": "晶", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
	"tai_xu_yi_qi": {
		"name": "太虚一气", "icon": "虚", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
	"jiu_zhuan_huan_hun_cao": {
		"name": "九转还魂草", "icon": "魂", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
	"tian_ji_fu_shi": {
		"name": "天机符石", "icon": "机", "cost": 2000000.0, "required_realm": 3,
		"desc": "元婴突破材料，只能在商店兑换。",
	},
}

# 每种材料默认各 1 份；服气丹需要 10 颗。数量也集中在这里，突破逻辑不写死。
const BREAKTHROUGH_REQUIREMENTS: Dictionary = {
	1: [
		{"material_id": "fu_qi_dan", "amount": 10},
	],
	2: [
		{"material_id": "jin_yang_hua", "amount": 1},
		{"material_id": "zi_mu_gen", "amount": 1},
		{"material_id": "bi_shui_lian", "amount": 1},
		{"material_id": "yan_ling_shu_xin", "amount": 1},
		{"material_id": "da_di_ku_cao", "amount": 1},
	],
	3: [
		{"material_id": "lei_ji_tao_mu", "amount": 1},
		{"material_id": "fu_lu_zhou", "amount": 1},
		{"material_id": "san_qing_chi_ling", "amount": 1},
		{"material_id": "yang_ji_di_xin", "amount": 1},
		{"material_id": "yin_ji_yue_hua", "amount": 1},
		{"material_id": "cang_tian_zi_qi", "amount": 1},
	],
	4: [
		{"material_id": "zi_fu_yu_sui", "amount": 1},
		{"material_id": "yuan_ying_dao_guo", "amount": 1},
		{"material_id": "lei_jie_cui_ti", "amount": 1},
		{"material_id": "tian_jie_lei_jing", "amount": 1},
		{"material_id": "tai_xu_yi_qi", "amount": 1},
		{"material_id": "jiu_zhuan_huan_hun_cao", "amount": 1},
		{"material_id": "tian_ji_fu_shi", "amount": 1},
	],
}


# ───────────────────────── 作物 / 季节 / 灵田 ─────────────────────────

const CROPS: Dictionary = {
	# cultivation 是每株作物的直接修为基值；灵田收获不再产生灵气。
	"gathering_grass": {"name": "聚灵草", "growth": 5.0, "cultivation": 3.0, "sell_price": 5.0, "unlock_realm": 0},
	"mind_flower": {"name": "凝神花", "growth": 30.0, "cultivation": 10.0, "sell_price": 20.0, "unlock_realm": 2},
	"sun_fruit": {"name": "赤阳果", "growth": 120.0, "cultivation": 50.0, "sell_price": 100.0, "unlock_realm": 3},
	"heaven_lotus": {"name": "天道莲", "growth": 1800.0, "cultivation": 500.0, "sell_price": 1000.0, "unlock_realm": 3},
	"zi_zhi": {"name": "紫芝", "growth": 900.0, "cultivation": 2000.0, "sell_price": 5000.0, "unlock_realm": 4},
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
	"zi_zhi": [
		{"yield_bonus": 1, "growth_reduction": 0.0, "talent_points": 1},
		{"yield_bonus": 1, "growth_reduction": 30.0, "talent_points": 2},
		{"yield_bonus": 2, "growth_reduction": 0.0, "talent_points": 3},
		{"yield_bonus": 3, "growth_reduction": 30.0, "talent_points": 5},
	],
}
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

const LIFESPAN_YEARS_BY_REALM: Array[float] = [80.0, 120.0, 300.0, 1000.0, 3000.0]
const LIFESPAN_DECAY_PER_SECOND := 0.2
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
const TALENT_BREAKTHROUGH_POINTS_BY_REALM: Array[int] = [0, 3, 7, 15, 31]


# ───────────────────────── 天劫（生产体系检测） ─────────────────────────

# 突破不再是挨雷劈，而是检测 3 道“生产体系”检查；全部通过才进入下一境界。
# 天劫期间暂停灵田、事件和自动修炼，避免玩家一边渡劫一边继续生产。
# 检查失败不损失修为，获得永久雷劫淬体（生产/修为 +5%，跨局保留）。
const TRIBULATION_TOTAL_CHECKS := 3
const TRIBULATION_CHECK_INTERVAL_SECONDS := 5.0
# 第一劫·灵气：当前灵气 ≥ 需求（治疗丹使需求减半）。
# 灵气需求按目标境界缩放：固定 10,000 在初局无灵气产出、只能靠聚气玉的时代无法达成，
# 所以炼气只需 500（治疗丹后 250 ≈ 2 颗聚气玉），元婴回到文档标定的 10,000。
const TRIBULATION_CHECK_QI_REQUIREMENT := 10000.0
# 按“目标境界”索引：index 0 为占位，炼气（目标 1）500 → 元婴（目标 4）10,000。
const TRIBULATION_QI_REQUIREMENT_BY_REALM: Array[float] = [0.0, 500.0, 1500.0, 4000.0, 10000.0]
# 第二劫·底蕴：本世累计收获 ≥ 1,000（抗性丹使需求减半）。
const TRIBULATION_CHECK_HARVEST_REQUIREMENT := 1000
# 第三劫·气运：本世触发过随机事件 ≥1 或拥有幸运系天赋（强化丹直接通过）。
const TRIBULATION_REFINE_BONUS := 0.05
const TRIBULATION_HEAL_REQUIREMENT_MULT := 0.5
const TRIBULATION_RESISTANCE_REQUIREMENT_MULT := 0.5


static func tribulation_qi_requirement(target_realm: int) -> float:
	return TRIBULATION_QI_REQUIREMENT_BY_REALM[clampi(target_realm, 1, TRIBULATION_QI_REQUIREMENT_BY_REALM.size() - 1)]


## 三道检查的定义（顺序固定）：name 用于 UI，requirement 描述用于失败提示。
static func tribulation_checks() -> Array[Dictionary]:
	return [
		{"index": 0, "name": "第一劫·灵气", "desc": "灵气储备", "requirement": "当前灵气达标（治疗丹需求减半）"},
		{"index": 1, "name": "第二劫·底蕴", "desc": "生产底蕴", "requirement": "本世累计收获 ≥ %d 次" % TRIBULATION_CHECK_HARVEST_REQUIREMENT},
		{"index": 2, "name": "第三劫·气运", "desc": "气运", "requirement": "本世触发过随机事件，或拥有幸运系天赋"},
	]


# ───────────────────────── 轮回 / 天人五衰 ─────────────────────────

# 转世奖励：保留未用天赋点 + 本世新跨修为里程碑 ×2 + 本世突破境界 ×1。
# 提前轮回（寿元 > 20%）奖励 ×80%；天人五衰立即轮回 ×100%。
const REINCARNATION_MILESTONE_POINTS := 2
const REINCARNATION_BREAKTHROUGH_POINTS := 1
const REINCARNATION_EARLY_PENALTY := 0.8
const DECAY_THRESHOLD_RATIO := 0.20
# 天人五衰·继续修炼：生产 -50% 至寿元耗尽，每 60 秒 roll 一次天命奇遇。
const DECAY_PRODUCTION_PENALTY := 0.50
const FATE_OPPORTUNITY_INTERVAL_SECONDS := 60.0
# 天人五衰·渡劫续命：消耗 3 种渡劫丹各 1 + 当前境界寿元上限 20% 的灵石。
# 成功寿元 +50 年并解除衰败；失败寿元归零、强制轮回且奖励 ×80%。
const LIFESPAN_TRIBULATION_SUCCESS_YEARS := 50.0
const LIFESPAN_TRIBULATION_STONE_RATIO := 0.20
const LIFESPAN_TRIBULATION_SUCCESS_RATE := 0.70
# 天命奇遇池（继续修炼期间 roll）：gift_id → 效果说明。
const FATE_OPPORTUNITIES: Array[Dictionary] = [
	{"id": "insight_scroll", "name": "悟道残卷", "desc": "立即获得 1 天赋点。", "weight": 40, "amount": 1},
	{"id": "qi_jade", "name": "聚气玉", "desc": "立即获得 500 灵气。", "weight": 40, "amount": 500.0},
	{"id": "permanent_production", "name": "灵光乍现", "desc": "永久生产倍率 +2%。", "weight": 15, "amount": 0.02},
	{"id": "lifespan_max", "name": "延寿机缘", "desc": "寿元上限 +20 年。", "weight": 5, "amount": 20.0},
]
const FATE_PERMANENT_PRODUCTION_BONUS := 0.02

# 转世天赋三选一：轮回后本世生效、跨世不保留。
const REINCARNATION_BOONS: Array[Dictionary] = [
	{"id": "wood_spirit", "name": "青木神通", "desc": "本世灵田产量 +50%。", "production_mult": 1.50, "cultivation_mult": 1.0, "fate_mult": 1.0},
	{"id": "dan_heart", "name": "丹心", "desc": "本世收获修为 +20%。", "production_mult": 1.0, "cultivation_mult": 1.20, "fate_mult": 1.0},
	{"id": "heaven_fate", "name": "天命", "desc": "本世宝箱/奇遇概率 ×5。", "production_mult": 1.0, "cultivation_mult": 1.0, "fate_mult": 5.0},
]


## 按 id 查转世天赋；未找到返回空字典。
static func reincarnation_boon(boon_id: String) -> Dictionary:
	for boon in REINCARNATION_BOONS:
		if String(boon.get("id", "")) == boon_id:
			return boon
	return {}


# ───────────────────────── 突破成功率 / 碎丹经验 ─────────────────────────

const BREAKTHROUGH_STABLE_MATERIAL_MULT := 1.5
const BREAKTHROUGH_STABLE_SUCCESS_RATE := 0.95
const BREAKTHROUGH_FORCED_SUCCESS_RATE := 0.50
const BROKEN_DAN_SUCCESS_BONUS := 0.15
const BROKEN_DAN_SUCCESS_CAP := 0.45


# ───────────────────────── 宝箱 / 奇遇 ─────────────────────────

# 每次收获时 roll：木箱 5% / 玉箱 1% / 仙箱 0.1% / 古修遗物 1%（玉/仙池随机）。
# 仙箱与遗物的永久强化跨局保留、累计无上限。
const TREASURE_WOOD_CHANCE := 0.05
const TREASURE_JADE_CHANCE := 0.01
const TREASURE_IMMORTAL_CHANCE := 0.001
const TREASURE_RELIC_CHANCE := 0.01
const TREASURE_WOOD_STONES_RATIO := 10.0
const TREASURE_WOOD_QI := 200.0
const TREASURE_IMMORTAL_PRODUCTION_BONUS := 0.02
const TREASURE_IMMORTAL_LIFESPAN_BONUS := 20.0
const TREASURE_IMMORTAL_CRIT_BONUS := 0.01


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
	{"id": "harvest_5000", "name": "千锤百炼", "category": "灵田", "desc": "累计完成 5,000 次灵田收获。", "metric": "total_harvest_count", "target": 5000.0, "points": 5},
	{"id": "harvest_10000", "name": "万顷良田", "category": "灵田", "desc": "累计完成 10,000 次灵田收获。", "metric": "total_harvest_count", "target": 10000.0, "points": 8},
	{"id": "field_all_immortal", "name": "三田成仙", "category": "灵田", "desc": "3 块灵田全部升至仙田。", "metric": "all_fields_max_tier", "target": 1.0, "points": 6},
	{"id": "cultivation_100m", "name": "修海无涯", "category": "修行", "desc": "累计获得 100,000,000 点修为。", "metric": "total_cultivation_earned", "target": 100000000.0, "points": 8},
	{"id": "cultivation_1b", "name": "道贯十亿", "category": "修行", "desc": "累计获得 1,000,000,000 点修为。", "metric": "total_cultivation_earned", "target": 1000000000.0, "points": 12},
	{"id": "reach_yuanying", "name": "元婴出世", "category": "境界", "desc": "首次达到元婴境。", "metric": "realm_index", "target": 4.0, "points": 10},
	{"id": "mind_master", "name": "凝神花宗师", "category": "熟练度", "desc": "凝神花熟练度达到 400 次。", "metric": "crop_proficiency", "crop_id": "mind_flower", "target": 400.0, "points": 4},
	{"id": "sun_master", "name": "赤阳果宗师", "category": "熟练度", "desc": "赤阳果熟练度达到 400 次。", "metric": "crop_proficiency", "crop_id": "sun_fruit", "target": 400.0, "points": 4},
	{"id": "grass_grandmaster", "name": "聚灵草大宗师", "category": "熟练度", "desc": "聚灵草熟练度达到 1,000 次。", "metric": "crop_proficiency", "crop_id": "gathering_grass", "target": 1000.0, "points": 6},
	{"id": "mind_grandmaster", "name": "凝神花大宗师", "category": "熟练度", "desc": "凝神花熟练度达到 1,000 次。", "metric": "crop_proficiency", "crop_id": "mind_flower", "target": 1000.0, "points": 6},
	{"id": "sun_grandmaster", "name": "赤阳果大宗师", "category": "熟练度", "desc": "赤阳果熟练度达到 1,000 次。", "metric": "crop_proficiency", "crop_id": "sun_fruit", "target": 1000.0, "points": 6},
	{"id": "lotus_grandmaster", "name": "天道莲大宗师", "category": "熟练度", "desc": "天道莲熟练度达到 1,000 次。", "metric": "crop_proficiency", "crop_id": "heaven_lotus", "target": 1000.0, "points": 6},
	{"id": "zi_zhi_proficiency_10", "name": "紫芝入门", "category": "熟练度", "desc": "紫芝熟练度达到 10 次。", "metric": "crop_proficiency", "crop_id": "zi_zhi", "target": 10.0, "points": 1},
	{"id": "crit_10", "name": "福星初照", "category": "幸运", "desc": "触发 10 次收获暴击。", "metric": "crit_count", "target": 10.0, "points": 3},
	{"id": "crit_500", "name": "暴击如潮", "category": "幸运", "desc": "触发 500 次收获暴击。", "metric": "crit_count", "target": 500.0, "points": 6},
	{"id": "rare_crit_50", "name": "天眷一击", "category": "幸运", "desc": "触发 50 次稀有暴击。", "metric": "rare_crit_count", "target": 50.0, "points": 5},
	{"id": "windfall_50", "name": "横财连连", "category": "幸运", "desc": "触发 50 次天降横财。", "metric": "windfall_count", "target": 50.0, "points": 5},
	{"id": "new_run_10", "name": "十世修行", "category": "轮回", "desc": "累计开始 10 次新局。", "metric": "reincarnation_count", "target": 10.0, "points": 6},
	{"id": "talent_10", "name": "天赋异禀", "category": "天赋", "desc": "解锁 10 个天赋节点。", "metric": "talent_nodes", "target": 10.0, "points": 5},
	{"id": "frenzy_pill_10", "name": "狂丹常客", "category": "商店", "desc": "累计购买 10 次狂暴丹。", "metric": "shop_purchase_count", "item_id": "frenzy_pill", "target": 10.0, "points": 4},
]


# ───────────────────────── 事件 / 计时 ─────────────────────────

const SEASON_DURATION_SECONDS := 180.0
const RANDOM_EVENT_COOLDOWN_SECONDS := 180.0
const EVENT_DURATIONS: Dictionary = {
	"auspicious": 60.0,
	"dao_insight": 30.0,
	"warlord_birthday": 60.0,
	"ancient_cave": 60.0,
	"heavenly_seed": 30.0,
	"demon_qi": 90.0,
	"insect_king": 60.0,
}
const EVENT_PROD_BONUS := 10.0
const EVENT_CULT_BONUS := 20.0
const EVENT_EVENTS: Array[String] = ["auspicious", "dao_insight", "warlord_birthday", "ancient_cave", "heavenly_seed", "demon_qi", "insect_king"]
const DEFAULT_EVENT_DURATION_SECONDS := 60.0
const EVENT_WARLORD_PEST_LEVEL := 1
const WORLD_STATE_EMIT_INTERVAL_SECONDS := 0.25
# 新交互事件参数。
const ANCIENT_CAVE_STONES := 5000.0
const ANCIENT_CAVE_TALENT_POINTS := 1
const HEAVENLY_SEED_CROP := "zi_zhi"
const DEMON_QI_PRODUCTION_PENALTY := 0.50
const DEMON_QI_PURIFY_COST_RATIO := 0.10
const INSECT_KING_CORPSE_REWARD := 10


# ───────────────────────── 自动化 ─────────────────────────

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


# ───────────────────────── 幸运系 / 收获暴击 ─────────────────────────

# 暴击在真实收获时 roll：普通暴击产量 ×2，稀有暴击产量 ×5。
# 概率由幸运系天赋提供（bonus 相加语义），模拟器按期望值展示。
const LUCK_CRIT_MULT := 2.0
const LUCK_RARE_CRIT_MULT := 5.0
# 天降横财：收获时按 windfall_chance 额外获得本次灵石 × windfall_ratio。
const LUCK_WINDFALL_RATIO := 0.5


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
# 种下作物 30 秒后先出现虫灾预警，再过 30 秒首次攻击；凡人 120 秒寿元内可见。
const INSECT_INITIAL_DELAY_SECONDS := 30.0
const INSECT_ATTACK_INTERVAL_SECONDS := 30.0
const INSECT_WARLORD_ATTACK_INTERVAL_SECONDS := 15.0
const INSECT_WARLORD_ATTACK_COUNT := 2
const INSECT_CORPSE_SELL_PRICE := 8.0


# ───────────────────────── 商店 ─────────────────────────

const SHOP_ITEMS: Array[Dictionary] = [
	{
		"id": "longevity_pill",
		"name": "长生丹",
		"cost": 1000.0,
		"icon": "寿",
		"desc": "恢复 30 年寿元，寿元归零时也可使用。",
		"effect": "lifespan",
		"amount": 30.0,
	},
	{
		"id": "qi_jade",
		"name": "聚气玉",
		"cost": 1000.0,
		"icon": "气",
		"desc": "立即获得 200 灵气，提升当前收获倍率。",
		"effect": "qi",
		"amount": 200.0,
	},
	{
		"id": "healing_pill",
		"name": "治疗丹",
		"cost": 1500.0,
		"icon": "疗",
		"desc": "渡劫准备：第一劫·灵气需求减半。",
		"effect": "tribulation_healing",
		"amount": 1.0,
	},
	{
		"id": "resistance_pill",
		"name": "抗性丹",
		"cost": 2000.0,
		"icon": "抗",
		"desc": "渡劫准备：第二劫·底蕴需求减半。",
		"effect": "tribulation_resistance",
		"amount": 1.0,
	},
	{
		"id": "enhancement_pill",
		"name": "强化丹",
		"cost": 2500.0,
		"icon": "强",
		"desc": "渡劫准备：第三劫·气运直接通过。",
		"effect": "tribulation_enhancement",
		"amount": 1.0,
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
	"farming_start", "farming_yield", "farming_speed", "farming_capstone", "farming_grand",
	"alchemy_start", "alchemy_power", "alchemy_quality", "alchemy_capstone", "alchemy_grand",
	"spirit_start", "spirit_qi", "spirit_lifespan", "spirit_capstone", "spirit_grand",
	"luck_start", "luck_wealth", "luck_crit", "luck_capstone",
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
	# 三系加深：顶点之后的元婴级终点，需要先完成各系顶点。
	"farming_grand": {
		"name": "丰收大道", "icon": "丰", "branch": "farming", "cost": 5,
		"requires": ["farming_capstone"], "requires_any": [],
		"desc": "所有灵田产出再 ×2.00。",
		"effects": {"production_mult": 2.00},
	},
	"alchemy_grand": {
		"name": "问道丹心", "icon": "问", "branch": "alchemy", "cost": 5,
		"requires": ["alchemy_capstone"], "requires_any": [],
		"desc": "灵田收获修为再 ×2.00。",
		"effects": {"cultivation_mult": 2.00},
	},
	"spirit_grand": {
		"name": "紫府开辟", "icon": "紫", "branch": "spirit", "cost": 5,
		"requires": ["spirit_capstone"], "requires_any": [],
		"desc": "自动修炼效率 ×2.00。",
		"effects": {"auto_cultivation_mult": 2.00},
	},
	# 第四系·幸运系：概率效果用相加语义（TalentTree.bonus）。
	"luck_start": {
		"name": "幸运入门", "icon": "运", "branch": "luck", "cost": 1,
		"requires": ["root"], "requires_any": [], "desc": "收获暴击率 +5%。",
		"effects": {"crit_chance": 0.05},
	},
	"luck_wealth": {
		"name": "天降横财", "icon": "财", "branch": "luck", "cost": 2,
		"requires": ["luck_start"], "requires_any": [], "desc": "收获时 10% 概率额外获得本次灵石 ×50%。",
		"effects": {"windfall_chance": 0.10},
	},
	"luck_crit": {
		"name": "福星高照", "icon": "福", "branch": "luck", "cost": 2,
		"requires": ["luck_start"], "requires_any": [], "desc": "暴击时 20% 概率升级为稀有暴击（产量 ×5）。",
		"effects": {"rare_crit_chance": 0.20},
	},
	"luck_capstone": {
		"name": "天道眷顾", "icon": "眷", "branch": "luck", "cost": 5,
		"requires": [], "requires_any": ["luck_wealth", "luck_crit"],
		"desc": "暴击率再 +10%，稀有暴击概率再 +15%。",
		"effects": {"crit_chance": 0.10, "rare_crit_chance": 0.15},
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
