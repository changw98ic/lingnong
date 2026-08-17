class_name BalanceConfig
extends RefCounted

## v1.2 的唯一数值目录。领域服务只读取这里，不复制玩法常量。

const SAVE_VERSION := 20
const CONTENT_VERSION := "incremental_v1_2"
const ENTROPY_SCALE := 1000000000000
const EFFECTIVE_LIFESPAN_SECONDS := 900.0
const SOFT_WALL_START_SECONDS := 720.0
const SOFT_WALL_END_SECONDS := 900.0
const DEFAULT_DT := 0.1
const MAX_OFFLINE_WALL_SECONDS := 86400.0
const MAX_OFFLINE_EFFECTIVE_SECONDS := 57600.0
const ASCENSION_CULTIVATION_EXPONENT := 140
const ASCENSION_DAO_THRESHOLD := "1000"
const MAX_ZERO_TIME_ACTIONS := 256
const MAX_OFFLINE_BOUNDARIES := 10000
const DAO_MARK_INITIAL_REQUIREMENT := "1000000"
const DAO_MARK_GROWTH := 4

const INITIAL_FIELD_LEVEL := 1
const INITIAL_SOIL_TIER := 0
const INITIAL_ARRAY_LEVEL := 0
const SHARED_FARM_LAYERS := 2000.0
const TARGET_CREDIT_RATIO := 0.015
const BASE_HP := "100"
const ROUTE_HP_LAYERS: Dictionary = {
	"qi_common": 1.00,
	"qi_body": 1.20,
	"qi_heaven": 1.35,
	"foundation_dan": 1.10,
	"foundation_human": 1.25,
	"foundation_five": 1.45,
	"foundation_heaven": 1.70,
	"golden_one": 1.15,
	"golden_three": 1.30,
	"golden_six": 1.55,
	"golden_nine": 1.85,
}

const CROPS: Dictionary = {
	"gathering_grass": {
		"name": "聚灵草", "grade": 1, "treasure_tier": "common", "cycle": 2.0,
		"cultivation_per_work": 1.0, "stone_per_work": 2.0,
		"body_factor": 1.0, "spirit_factor": 1.0, "treasure_work_ratio": 1.0,
		"unlock_node": "",
	},
	"nourishing_ginseng": {
		"name": "养元参", "grade": 2, "treasure_tier": "elite", "cycle": 4.0,
		"cultivation_per_work": 30.0, "stone_per_work": 20.0,
		"body_factor": 1.5, "spirit_factor": 1.0, "treasure_work_ratio": 1.0,
		"unlock_node": "qi_common",
	},
	"mind_flower": {
		"name": "凝神花", "grade": 2, "treasure_tier": "elite", "cycle": 6.0,
		"cultivation_per_work": 50.0, "stone_per_work": 30.0,
		"body_factor": 1.0, "spirit_factor": 2.0, "treasure_work_ratio": 1.0,
		"unlock_node": "qi_body",
	},
	"sun_fruit": {
		"name": "赤阳果", "grade": 2, "treasure_tier": "elite", "cycle": 8.0,
		"cultivation_per_work": 120.0, "stone_per_work": 150.0,
		"body_factor": 1.5, "spirit_factor": 1.0, "treasure_work_ratio": 1.0,
		"unlock_node": "qi_body",
	},
	"five_element_ear": {
		"name": "五行穗", "grade": 3, "treasure_tier": "rare", "cycle": 12.0,
		"cultivation_per_work": 10000.0, "stone_per_work": 8000.0,
		"body_factor": 1.0, "spirit_factor": 1.0, "treasure_work_ratio": 1.0,
		"unlock_node": "qi_heaven",
	},
	"heaven_lotus": {
		"name": "天道莲", "grade": 3, "treasure_tier": "rare", "cycle": 20.0,
		"cultivation_per_work": 1000000.0, "stone_per_work": 500000.0,
		"body_factor": 1.0, "spirit_factor": 1.0, "treasure_work_ratio": 2.0,
		"unlock_node": "foundation_five",
	},
	"purple_mushroom": {
		"name": "紫芝", "grade": 3, "treasure_tier": "rare", "cycle": 30.0,
		"cultivation_per_work": 100000000.0, "stone_per_work": 200000000.0,
		"body_factor": 1.0, "spirit_factor": 1.0, "treasure_work_ratio": 1.0,
		"unlock_node": "golden_one",
	},
}

const MATERIALS: Dictionary = {
	"fu_qi_dan": {"name": "服气丹精粹", "tier": "common", "is_essence": false},
	"body_pill": {"name": "锻体丹药力", "tier": "elite", "is_essence": true, "essence_key": "body", "essence_multiplier": 1},
	"spirit_pill": {"name": "凝神丸药力", "tier": "elite", "is_essence": true, "essence_key": "spirit", "essence_multiplier": 1},
	"dragon_tiger_pill": {"name": "龙虎丹药力", "tier": "rare", "is_essence": true, "essence_key": "body", "essence_multiplier": 100},
	"nourishing_spirit_pill": {"name": "养神丹药力", "tier": "rare", "is_essence": true, "essence_key": "spirit", "essence_multiplier": 100},
	"jin_yang_hua": {"name": "金阳花精粹", "tier": "elite", "is_essence": false},
	"zi_mu_gen": {"name": "紫木根精粹", "tier": "elite", "is_essence": false},
	"bi_shui_lian": {"name": "碧水莲精粹", "tier": "elite", "is_essence": false},
	"yan_ling_shu_xin": {"name": "炎灵树心精粹", "tier": "elite", "is_essence": false},
	"da_di_ku_cao": {"name": "大地苦草精粹", "tier": "elite", "is_essence": false},
	"lei_ji_tao_mu": {"name": "雷击桃木精粹", "tier": "rare", "is_essence": false},
	"fu_lu_zhou": {"name": "福禄咒精粹", "tier": "rare", "is_essence": false},
	"san_qing_chi_ling": {"name": "三清敕令精粹", "tier": "rare", "is_essence": false},
	"yang_ji_di_xin": {"name": "阳极地心精粹", "tier": "rare", "is_essence": false},
	"yin_ji_yue_hua": {"name": "阴极月华精粹", "tier": "rare", "is_essence": false},
	"cang_tian_zi_qi": {"name": "苍天紫气精粹", "tier": "rare", "is_essence": false},
	"dao_mark": {"name": "天道印记", "tier": "rare", "is_essence": false},
	# v18/v19 元婴材料保留为 dormant 定义，仅用于迁移存量显示；新档不掉落。
	"zi_fu_yu_sui": {"name": "紫府玉髓（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
	"yuan_ying_dao_guo": {"name": "元婴道果（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
	"lei_jie_cui_ti": {"name": "雷劫淬体（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
	"tian_jie_lei_jing": {"name": "天劫雷晶（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
	"tai_xu_yi_qi": {"name": "太虚一气（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
	"jiu_zhuan_huan_hun_cao": {"name": "九转还魂草（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
	"tian_ji_fu_shi": {"name": "天机符石（旧存量）", "tier": "rare", "is_essence": false, "dormant": true},
}

const REALM_NODES: Array[Dictionary] = [
	{"id": "qi_common", "name": "普通练气", "major": "qi", "grade": 1, "E": 6, "H": 2,
		"prerequisites": [], "body_share": 0.0, "spirit_share": 0.0,
		"chance": 0.90, "pity_step": 0.10, "hard_pity": 2,
		"materials": {"fu_qi_dan": 1.0}, "golden": false, "content_enabled": true},
	{"id": "qi_body", "name": "锻体练气士", "major": "qi", "grade": 6, "E": 9, "H": 5,
		"prerequisites": ["qi_common"], "body_share": 0.40, "spirit_share": 0.05,
		"chance": 0.70, "pity_step": 0.15, "hard_pity": 3,
		"materials": {"fu_qi_dan": 0.90, "body_pill": 0.10}, "golden": false, "content_enabled": true},
	{"id": "qi_heaven", "name": "天人练气士", "major": "qi", "grade": 9, "E": 17, "H": 9,
		"prerequisites": ["qi_body"], "body_share": 0.30, "spirit_share": 0.30,
		"chance": 0.45, "pity_step": 0.15, "hard_pity": 5,
		"materials": {"fu_qi_dan": 0.60, "body_pill": 0.20, "spirit_pill": 0.20}, "golden": false, "content_enabled": true},
	{"id": "foundation_dan", "name": "丹道筑基", "major": "foundation", "grade": 1, "E": 10, "H": 5,
		"prerequisites": ["qi_common"], "body_share": 0.05, "spirit_share": 0.30,
		"chance": 0.80, "pity_step": 0.10, "hard_pity": 3,
		"materials": {"jin_yang_hua": 0.60, "yan_ling_shu_xin": 0.40}, "golden": false, "content_enabled": true},
	{"id": "foundation_human", "name": "人道筑基", "major": "foundation", "grade": 3, "E": 21, "H": 10,
		"prerequisites": ["foundation_dan", "qi_body"], "body_share": 0.30, "spirit_share": 0.10,
		"chance": 0.65, "pity_step": 0.10, "hard_pity": 5,
		"materials": {"zi_mu_gen": 0.50, "da_di_ku_cao": 0.50}, "golden": false, "content_enabled": true},
	{"id": "foundation_five", "name": "五行筑基", "major": "foundation", "grade": 6, "E": 38, "H": 18,
		"prerequisites": ["foundation_human", "qi_heaven"], "body_share": 0.25, "spirit_share": 0.25,
		"chance": 0.45, "pity_step": 0.10, "hard_pity": 7,
		"materials": {"jin_yang_hua": 0.20, "zi_mu_gen": 0.20, "bi_shui_lian": 0.20, "yan_ling_shu_xin": 0.20, "da_di_ku_cao": 0.20}, "golden": false, "content_enabled": true},
	{"id": "foundation_heaven", "name": "天道筑基", "major": "foundation", "grade": 9, "E": 57, "H": 28,
		"prerequisites": ["foundation_five", "qi_heaven"], "body_share": 0.30, "spirit_share": 0.30,
		"chance": 0.25, "pity_step": 0.10, "hard_pity": 9,
		"materials": {"jin_yang_hua": 0.15, "zi_mu_gen": 0.15, "bi_shui_lian": 0.15, "yan_ling_shu_xin": 0.15, "da_di_ku_cao": 0.15, "body_pill": 0.125, "spirit_pill": 0.125}, "golden": false, "content_enabled": true},
	{"id": "golden_one", "name": "一纹金丹", "major": "golden", "grade": 1, "E": 26, "H": 12,
		"prerequisites": ["foundation_dan"], "body_share": 0.10, "spirit_share": 0.30,
		"chance": 0.70, "pity_step": 0.10, "hard_pity": 4,
		"materials": {"lei_ji_tao_mu": 0.50, "fu_lu_zhou": 0.50}, "golden": true, "strikes": 3, "damage": "2000000000000", "content_enabled": true},
	{"id": "golden_three", "name": "三纹金丹", "major": "golden", "grade": 3, "E": 46, "H": 23,
		"prerequisites": ["golden_one", "foundation_human"], "body_share": 0.15, "spirit_share": 0.25,
		"chance": 0.55, "pity_step": 0.10, "hard_pity": 6,
		"materials": {"san_qing_chi_ling": 0.50, "yang_ji_di_xin": 0.50}, "golden": true, "strikes": 6, "damage": "20000000000000000000000", "content_enabled": true},
	{"id": "golden_six", "name": "六纹金丹", "major": "golden", "grade": 6, "E": 67, "H": 38,
		"prerequisites": ["golden_three", "foundation_five"], "body_share": 0.25, "spirit_share": 0.25,
		"chance": 0.35, "pity_step": 0.10, "hard_pity": 8,
		"materials": {"yang_ji_di_xin": 0.50, "yin_ji_yue_hua": 0.50}, "golden": true, "strikes": 9, "damage": "3000000000000000000000000000000", "content_enabled": true},
	{"id": "golden_nine", "name": "九纹金丹", "major": "golden", "grade": 9, "E": 82, "H": 60,
		"prerequisites": ["golden_six", "foundation_heaven"], "body_share": 0.35, "spirit_share": 0.35,
		"chance": 0.20, "pity_step": 0.10, "hard_pity": 9,
		"materials": {"cang_tian_zi_qi": 0.40, "yang_ji_di_xin": 0.30, "yin_ji_yue_hua": 0.30}, "golden": true, "strikes": 9, "damage": "50000000000000000000000000000000000000000", "content_enabled": true},
]

const TREASURE_RULES: Dictionary = {
	"common": {"divisor_exponent": 2, "stone_ratio": 0.05, "channels": {"fu_qi_dan": 0.02}},
	"elite": {"divisor_exponent": 5, "stone_ratio": 0.12, "channels": {"breakthrough_material": 0.005, "body_pill": 0.001, "spirit_pill": 0.001}},
	"rare": {"divisor_exponent": 9, "stone_ratio": 0.25, "channels": {"golden_material": 0.002, "dragon_tiger_pill": 0.0005, "nourishing_spirit_pill": 0.0005}},
}

const FIELD_UPGRADES: Dictionary = {
	"field_level": {"base": "10", "ratio": "1.18"},
	"soil_tier": {"base_exponent": 3, "exponent_step": 2},
	"array_level": {"base": "100", "ratio": "2.2"},
}

const AUTOMATION_REWARDS: Dictionary = {
	"qi_common": ["auto_purchase_max"],
	"qi_body": ["auto_tribulation"],
	"foundation_dan": ["roi_purchase", "material_reserve"],
	"golden_one": ["auto_breakthrough"],
	"golden_three": ["auto_reincarnation", "offline_cross_run"],
}


static func crop(crop_id: String) -> Dictionary:
	return CROPS.get(crop_id, {})


static func node(node_id: String) -> Dictionary:
	for item in REALM_NODES:
		if String(item.get("id", "")) == node_id:
			return item
	return {}


static func nodes() -> Array:
	return REALM_NODES.duplicate(true)


static func node_requirement(node_id: String) -> BigMagnitude:
	var definition := node(node_id)
	return BigMagnitude.pow10(int(definition.get("E", 0)))


static func material_set_total(node_id: String) -> BigCounter:
	var definition := node(node_id)
	var exponent := maxi(0, int(definition.get("E", 0)) - 2)
	return BigCounter.from_string("1" + "0".repeat(exponent))


static func material_requirements(node_id: String) -> Dictionary:
	var definition := node(node_id)
	var weights: Dictionary = definition.get("materials", {})
	var total := material_set_total(node_id)
	var output := {}
	var remaining := total.duplicate_value()
	var keys := weights.keys()
	for index in range(keys.size()):
		var material_id := String(keys[index])
		if index == keys.size() - 1:
			output[material_id] = remaining
			break
		var amount := _weighted_floor(total, float(weights[material_id]))
		output[material_id] = amount
		remaining = remaining.subtract(amount)
	return output


static func _weighted_floor(total: BigCounter, weight: float) -> BigCounter:
	var numerator := int(round(weight * 1000000.0))
	var multiplied := total.multiply_int(numerator)
	return multiplied.divide_int(1000000)["quotient"]


static func node_major(node_id: String) -> String:
	return String(node(node_id).get("major", ""))


static func history_has(history: Array, node_id: String) -> bool:
	return history.has(node_id)


static func legal_node(node_id: String, inherited_history: Array) -> bool:
	var definition := node(node_id)
	if definition.is_empty() or not bool(definition.get("content_enabled", false)):
		return false
	for prerequisite in definition.get("prerequisites", []):
		if not inherited_history.has(String(prerequisite)):
			return false
	return true


static func legal_nodes(inherited_history: Array, completed_this_run: Array = []) -> Array:
	var output: Array = []
	for definition in REALM_NODES:
		var node_id := String(definition.get("id", ""))
		if legal_node(node_id, inherited_history) and not inherited_history.has(node_id) and not completed_this_run.has(node_id):
			output.append(definition)
	return output


static func default_target(inherited_history: Array, preferred: Dictionary = {}, completed_this_run: Array = []) -> String:
	var legal := legal_nodes(inherited_history, completed_this_run)
	if legal.is_empty():
		return ""
	var preferred_order := ["qi_heaven", "qi_body", "qi_common", "foundation_five", "foundation_dan", "golden_nine", "golden_six", "golden_three", "golden_one"]
	for item in preferred_order:
		if preferred.has(item) and bool(preferred[item]):
			if legal_node(item, inherited_history) and not inherited_history.has(item) and not completed_this_run.has(item):
				return item
	for definition in legal:
		return String(definition.get("id", ""))
	return ""


static func active_h(inherited_history: Array, completed_this_run: Array) -> Dictionary:
	var best := {"qi": 0, "foundation": 0, "golden": 0}
	for node_id in inherited_history + completed_this_run:
		var definition := node(String(node_id))
		var major := String(definition.get("major", ""))
		best[major] = maxi(int(best.get(major, 0)), int(definition.get("H", 0)))
	return best


static func h_total(inherited_history: Array, completed_this_run: Array) -> int:
	var best := active_h(inherited_history, completed_this_run)
	return int(best.get("qi", 0)) + int(best.get("foundation", 0)) + int(best.get("golden", 0))


static func node_probability(node_id: String, failure_count: int) -> float:
	var definition := node(node_id)
	var hard_pity := int(definition.get("hard_pity", 1))
	var attempt_index := maxi(1, failure_count + 1)
	if attempt_index >= hard_pity:
		return 1.0
	return minf(0.95, float(definition.get("chance", 0.0)) + float(definition.get("pity_step", 0.0)) * float(failure_count))


static func treasure_divisor(tier: String) -> BigMagnitude:
	var rule: Dictionary = TREASURE_RULES.get(tier, {})
	return BigMagnitude.pow10(int(rule.get("divisor_exponent", 99)))


static func probability_numerator(probability: float) -> int:
	return int(round(probability * float(ENTROPY_SCALE)))


static func material_tier(material_id: String) -> String:
	return String(MATERIALS.get(material_id, {}).get("tier", "common"))


static func law_multiplier(total_laws: BigCounter) -> BigMagnitude:
	if total_laws.is_zero():
		return BigMagnitude.one()
	return BigMagnitude.pow10_magnitude(total_laws.to_magnitude().sqrt_value())


static func hp_layers(run: RunState, lineage: LineageState, legacy: LegacyState) -> Dictionary:
	var route_layer := 1.0
	for major in ["qi", "foundation", "golden"]:
		var route_id := String(run.active_inherited_path.get(major, ""))
		if not route_id.is_empty():
			route_layer *= float(ROUTE_HP_LAYERS.get(route_id, 1.0))
	var historical_h := active_h(run.inherited_history, [])
	var highest_h := 0
	for major in historical_h:
		highest_h = maxi(highest_h, int(historical_h[major]))
	var lineage_layer := 1.0 + minf(2.0, float(highest_h) * 0.01)
	var law_value := legacy.total_laws.to_float()
	var law_root := 100.0 if is_inf(law_value) else sqrt(maxf(0.0, law_value))
	var legacy_layer := 1.0 + minf(1.0, law_root * 0.01)
	return {
		"selected_route_hp_layer": route_layer,
		"lineage_hp_layer": lineage_layer,
		"legacy_hp_layer": legacy_layer,
	}


static func soft_wall_efficiency(elapsed_seconds: float) -> float:
	if elapsed_seconds <= SOFT_WALL_START_SECONDS:
		return 1.0
	if elapsed_seconds >= SOFT_WALL_END_SECONDS:
		return 0.0
	var x := (elapsed_seconds - SOFT_WALL_START_SECONDS) / (SOFT_WALL_END_SECONDS - SOFT_WALL_START_SECONDS)
	return pow(10.0, -3.0 * x * x)


static func average_soft_wall_efficiency(start_seconds: float, duration_seconds: float) -> float:
	if duration_seconds <= 0.0:
		return soft_wall_efficiency(start_seconds)
	var end_seconds := start_seconds + duration_seconds
	var weighted := 0.0
	var total := 0.0
	var cursor := start_seconds
	var segment_end := minf(end_seconds, SOFT_WALL_START_SECONDS)
	if segment_end > cursor:
		weighted += segment_end - cursor
		total += segment_end - cursor
		cursor = segment_end
	if cursor < end_seconds:
		segment_end = minf(end_seconds, SOFT_WALL_END_SECONDS)
		if segment_end > cursor:
			weighted += _integrate_soft_wall(cursor, segment_end)
			total += segment_end - cursor
			cursor = segment_end
	if cursor < end_seconds:
		total += end_seconds - cursor
	if total <= 0.0:
		return 0.0
	return clampf(weighted / total, 0.0, 1.0)


static func _integrate_soft_wall(start_seconds: float, end_seconds: float) -> float:
	var span := end_seconds - start_seconds
	if span <= 0.0:
		return 0.0
	# Fixed Simpson integration keeps the interval cost independent of the
	# amount of cultivated resources and avoids a frame-sized boundary loop.
	const slices := 16
	var step := span / float(slices)
	var sum := soft_wall_efficiency(start_seconds) + soft_wall_efficiency(end_seconds)
	for index in range(1, slices):
		var weight := 4.0 if index % 2 == 1 else 2.0
		sum += weight * soft_wall_efficiency(start_seconds + step * float(index))
	return sum * step / 3.0


static func dao_gain(total_cultivation: BigMagnitude, new_discoveries: Array) -> BigMagnitude:
	var c := total_cultivation.log10()
	if c < 6.0 and new_discoveries.is_empty():
		return BigMagnitude.zero()
	var frontier_factor := 1.0 + 0.10 * float(max_node_grade(new_discoveries)) + 0.25 * float(new_discoveries.size())
	var exponent := maxf(0.0, (c - 6.0) / 4.0)
	var whole := int(floor(exponent))
	var fractional := exponent - float(whole)
	var raw := BigMagnitude.pow10(whole).multiply_scalar(pow(10.0, fractional) * frontier_factor)
	return raw.floor_to_big_counter().to_magnitude()


static func dao_multiplier(total_dao: BigMagnitude) -> BigMagnitude:
	if total_dao.is_zero():
		return BigMagnitude.one()
	var dao_log: float = log(1.0 + total_dao.to_float()) / log(10.0) if total_dao.exponent < 15 else total_dao.log10()
	return BigMagnitude.pow10(int(floor(2.0 * sqrt(maxf(0.0, dao_log))))).multiply_scalar(pow(10.0, fmod(2.0 * sqrt(maxf(0.0, dao_log)), 1.0)))


static func max_node_grade(node_ids: Array) -> int:
	var grade := 0
	for node_id in node_ids:
		grade = maxi(grade, int(node(String(node_id)).get("grade", 0)))
	return grade


static func ascension_law_gain(lifetime_cultivation: BigMagnitude) -> BigCounter:
	var exponent := maxf(0.0, (lifetime_cultivation.log10() - float(ASCENSION_CULTIVATION_EXPONENT)) / 40.0)
	var whole := int(floor(exponent))
	var fractional := exponent - float(whole)
	return BigMagnitude.pow10(whole).multiply_scalar(pow(10.0, fractional)).floor_to_big_counter()
