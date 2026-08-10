extends Node

signal state_changed
signal realm_changed

# 灵农修仙 v3 中央模型 / 模拟。
# 全部可调数值来自 BalanceConfig（scripts/systems/balance_config.gd），索引与 realm_index 对齐：
# 0 凡人 / 1 炼气 / 2 筑基 / 3 金丹。境界同时是 Gate（突破门槛）与 Modifier。
# 子系统 AchievementSystem / AutomationSystem / TalentTree / CropConfig / MultiplierStack /
# BalanceConfig / RealmConfig / ShopSystem / NumberFormat 通过 class_name 全局可用，无需 preload。
#
# v3 核心变更（相对 v2）：
#   - 所有产出倍率统一走 MultiplierStack + get_production_mult/get_cultivation_mult，
#     杜绝各处自行连乘（散算）。
#   - 灵田结构改为 tier（0 凡 / 1 灵 / 2 宝 / 3 仙），删除 v2 的 level/quality/spirit_vein。
#   - 大限后可开始新局；轮回次数、灵植熟练度和长期计数跨局保留，天赋树继续承接永久成长。
#   - 灵气按库存量提供收获加成，仍可用于施放法术；灵田收获本身不产生灵气。
#   - 修为改由灵田收获直接结算；狂暴丹（生产 buff）通过商店购买，越买越贵。
#   - 随机事件扩为三选一：祥瑞降世(prod×10) / 天道感悟(cult×20) / 兵主诞辰(虫攻×2)。

# ───────────────────────── 数值配置 ─────────────────────────

# 可调参数集中在 BalanceConfig；GameState 只保存进行中的状态。

# ───────────────────────── 资源 / 本世状态 ─────────────────────────

var spirit_stones := 0.0
var qi := 0.0
var cultivation := 0.0
var breakthrough_materials := {}
var realm_index := BalanceConfig.INITIAL_REALM_INDEX
var unlocked_fields := BalanceConfig.INITIAL_UNLOCKED_FIELDS
# 灵田结构（契约[C]）：每项 {crop_id, planted_at, ready_at, tier}。tier 0..3。
var fields: Array[Dictionary] = []

var insect_corpses := 0
# 寿元（年），按境界；归零后进入大限并暂停生产。商店可购买长生丹恢复。
var lifespan_max_years: float = BalanceConfig.LIFESPAN_YEARS_BY_REALM[BalanceConfig.INITIAL_REALM_INDEX]
var lifespan_years: float = BalanceConfig.LIFESPAN_YEARS_BY_REALM[BalanceConfig.INITIAL_REALM_INDEX]
var lifespan_depleted := false
# 天人五衰·继续修炼：生产 -50% 至寿元耗尽，期间每 60 秒 roll 一次天命奇遇。
var decay_active := false
var fate_opportunity_at := 0.0
# 本世起始里程碑/晋级数：转世奖励按差值发放，避免重复计算。
var run_start_milestone_index := 0
var run_start_promotion_count := 0
# 本世转世天赋（轮回后三选一，跨世不保留）。
var reincarnation_boon := ""
# 轮回后等待选择转世天赋；选完前不再允许轮回。
var pending_reincarnation_boon := false
# 本世累计收获次数（第二劫·底蕴检查）；跨世清零。
var run_harvest_count := 0
# 本世触发过的随机事件次数（第三劫·气运检查）；跨世清零。
var run_random_event_count := 0
# 天降灵种事件解锁紫芝（本世生效）。
var heavenly_seed_unlocked := false

# 天劫是突破后的独立阶段。当前境界只有在三道生产体系检查全部通过后才递增。
var healing_pills := 0
var resistance_pills := 0
var enhancement_pills := 0
var tribulation_active := false
var tribulation_target_realm := -1
var tribulation_total_strikes := BalanceConfig.TRIBULATION_TOTAL_CHECKS
var tribulation_strikes_survived := 0
# 渡劫准备标记（治疗/抗性/强化丹依次对应三劫）：结算时自动减半需求或直接通过。
var tribulation_prepared: Array[bool] = [false, false, false]
var tribulation_next_strike_at := 0.0
var tribulation_last_result := ""

# ───────────────────────── 天赋 / 长期进度 ─────────────────────────

var talent_points := 0
# 已经获得过的天赋点总量。天劫档位按累计获得量判断，避免天赋点被立即消费后天劫又退回九九。
var talent_points_earned := 0
var talent_nodes: Dictionary = {"root": true}
var total_cultivation_earned := 0.0
var talent_milestone_index := 0
var achievements: Dictionary = {}
var achievement_points := 0

# 跨大限保留的长期统计。熟练度按“该作物实际收获次数”计数，
# 不因轮回清零；离线折算用下面三个计数器计算一次性差额。
var crop_proficiency: Dictionary = {}
var total_harvest_count := 0
var promotion_count := 0
var reincarnation_count := 0
var offline_claimed_talent_points := 0
var offline_claimed_spirit_stone_units := 0.0
# 幸运系统计：暴击 / 稀有暴击 / 天降横财触发次数，供成就进度使用。
var crit_count := 0
var rare_crit_count := 0
var windfall_count := 0
# 仙箱与天命奇遇的永久强化（跨局保留、累计无上限）。
var treasure_production_bonus := 0.0
var treasure_crit_bonus := 0.0
var fate_permanent_production := 0.0
# 碎丹经验：突破失败累计的成功率加成（封顶见 BalanceConfig）。
var broken_dan_experience := 0.0
# 雷劫淬体：渡劫检查失败获得的永久生产/修为加成。
var tribulation_refine_bonus := 0.0

# ───────────────────────── 倍率分量（事件 / buff） ─────────────────────────

# 默认 1.0；祥瑞降世期间 = 10.0。作用于 production（生长/产量/灵石/自动修炼灵气）。
var event_prod_mult := BalanceConfig.DEFAULT_MULTIPLIER
# 默认 1.0；天道感悟期间 = 20.0。作用于 cultivation（灵田修为/自动修炼修为）。
var event_cult_mult := BalanceConfig.DEFAULT_MULTIPLIER
# 狂暴丹 active_buff。active_buff_until > now 时 active_buff_mult 生效（仅作用于 production）。
var active_buff_until := 0.0
var active_buff_mult := BalanceConfig.DEFAULT_MULTIPLIER

# ───────────────────────── 解锁标志（突破奖励驱动） ─────────────────────────

var spirit_rain_unlocked := false
# 名称与 RealmConfig.breakthrough_rewards 的键严格对齐（便于通用应用）。
var unlock_auto_cultivation := false

# ───────────────────────── 子系统实例 ─────────────────────────

var automation := AutomationSystem.new()
var shop := ShopSystem.new()
# 商店商品购买次数（狂暴丹等越买越贵商品的价格依据），跨大限新局保留，新游戏重置。
var shop_purchase_counts: Dictionary = {}

# ───────────────────────── 法术 / 噬金虫 / 季节 / 事件计时 ─────────────────────────

var spirit_rain_until: Array[float] = []
var guardian_array_level: Array[int] = []
var guardian_array_charges: Array[int] = []
var insect_events: Array[Dictionary] = []
var season_index := BalanceConfig.INITIAL_SEASON_INDEX
var season_started_at := 0.0
var random_event := ""
var random_event_until := 0.0
var random_event_cooldown_until := 0.0
var sword_art_cooldown_until := 0.0
var world_state_accumulator := 0.0

# 离线结算摘要，由 SaveManager 加载后写入，供 UI 读取。
var last_offline_report: Dictionary = {}


func _ready() -> void:
	initialize_new_game()


# ───────────────────────── 初始化 / 重置 ─────────────────────────

# 新游戏：彻底重置当前进度与天赋树。
func initialize_new_game() -> void:
	talent_points = 0
	talent_points_earned = 0
	talent_nodes = {"root": true}
	total_cultivation_earned = 0.0
	talent_milestone_index = 0
	achievements = {}
	achievement_points = 0
	crop_proficiency = {}
	total_harvest_count = 0
	promotion_count = 0
	reincarnation_count = 0
	offline_claimed_talent_points = 0
	offline_claimed_spirit_stone_units = 0.0
	crit_count = 0
	rare_crit_count = 0
	windfall_count = 0
	treasure_production_bonus = 0.0
	treasure_crit_bonus = 0.0
	fate_permanent_production = 0.0
	broken_dan_experience = 0.0
	tribulation_refine_bonus = 0.0
	shop_purchase_counts = {}
	last_offline_report = {}
	_reset_run_state()
	_ensure_inventory_keys()
	emit_state_changed()


# 重置单次游戏进度。仅由新游戏或大限后的“开始新局”调用。
func _reset_run_state() -> void:
	spirit_stones = 0.0
	qi = 0.0
	cultivation = 0.0
	breakthrough_materials = {}
	realm_index = BalanceConfig.INITIAL_REALM_INDEX
	unlocked_fields = BalanceConfig.INITIAL_UNLOCKED_FIELDS
	# 灵雨、作物和自动化的初始解锁统一由 BalanceConfig 推导。
	var default_unlock_flags := BalanceConfig.default_unlock_flags(BalanceConfig.INITIAL_REALM_INDEX)
	for flag in default_unlock_flags:
		set(flag, bool(default_unlock_flags[flag]))
	# buff / 事件分量归 1（或空）。
	active_buff_until = 0.0
	active_buff_mult = BalanceConfig.DEFAULT_MULTIPLIER
	event_prod_mult = BalanceConfig.DEFAULT_MULTIPLIER
	event_cult_mult = BalanceConfig.DEFAULT_MULTIPLIER
	random_event = ""
	random_event_until = 0.0
	random_event_cooldown_until = Time.get_unix_time_from_system() + BalanceConfig.RANDOM_EVENT_COOLDOWN_SECONDS
	sword_art_cooldown_until = 0.0
	world_state_accumulator = 0.0
	insect_corpses = 0
	season_index = BalanceConfig.INITIAL_SEASON_INDEX
	season_started_at = Time.get_unix_time_from_system()
	lifespan_max_years = BalanceConfig.LIFESPAN_YEARS_BY_REALM[BalanceConfig.INITIAL_REALM_INDEX]
	lifespan_years = lifespan_max_years
	lifespan_depleted = false
	decay_active = false
	fate_opportunity_at = 0.0
	reincarnation_boon = ""
	pending_reincarnation_boon = false
	run_harvest_count = 0
	run_random_event_count = 0
	heavenly_seed_unlocked = false
	run_start_milestone_index = talent_milestone_index
	run_start_promotion_count = promotion_count
	healing_pills = 0
	resistance_pills = 0
	enhancement_pills = 0
	tribulation_active = false
	tribulation_target_realm = -1
	tribulation_total_strikes = BalanceConfig.TRIBULATION_TOTAL_CHECKS
	tribulation_strikes_survived = 0
	tribulation_prepared = [false, false, false]
	tribulation_next_strike_at = 0.0
	tribulation_last_result = ""
	# 灵田全 tier=0、作物空；保留 BalanceConfig.FIELD_COUNT 个槽位。
	fields.clear()
	spirit_rain_until.clear()
	guardian_array_level.clear()
	guardian_array_charges.clear()
	insect_events.clear()
	for _i in range(BalanceConfig.FIELD_COUNT):
		fields.append({"crop_id": "", "planted_at": 0.0, "ready_at": 0.0, "tier": 0})
		spirit_rain_until.append(0.0)
		guardian_array_level.append(BalanceConfig.GUARDIAN_BASE_LEVEL)
		guardian_array_charges.append(BalanceConfig.GUARDIAN_BASE_CHARGES)
		insect_events.append({
			"active": false,
			"attacks": 0,
			"pest_level": 0,
			"next_attack_at": Time.get_unix_time_from_system() + BalanceConfig.INSECT_INITIAL_DELAY_SECONDS,
		})


# 确保长期熟练度和突破材料字典覆盖当前配置的 id，保持结构稳定。
func _ensure_inventory_keys() -> void:
	for crop_id in CropConfig.get_all():
		if not crop_proficiency.has(crop_id):
			crop_proficiency[crop_id] = 0
	for material_id_variant in BalanceConfig.BREAKTHROUGH_MATERIALS:
		var material_id := String(material_id_variant)
		if not breakthrough_materials.has(material_id):
			breakthrough_materials[material_id] = 0


func emit_state_changed() -> void:
	# 所有已完成目标统一在状态出口检查，避免遗漏自动收获、突破、买田和新局。
	AchievementSystem.refresh(self)
	state_changed.emit()


# ───────────────────────── 境界 / 突破 ─────────────────────────

func get_realm_name() -> String:
	var safe_index := clampi(realm_index, 0, RealmConfig.realm_count() - 1)
	return String(BalanceConfig.REALMS[safe_index]["name"])


func get_next_realm_requirement() -> float:
	if realm_index < 0 or realm_index + 1 >= RealmConfig.realm_count():
		return INF
	return float(BalanceConfig.REALMS[realm_index + 1]["required_cultivation"])


func can_breakthrough() -> bool:
	if lifespan_depleted or tribulation_active or realm_index + 1 >= RealmConfig.realm_count() or cultivation < get_next_realm_requirement():
		return false
	return has_breakthrough_materials(realm_index + 1)


func get_breakthrough_requirements(target_realm: int = -1) -> Array[Dictionary]:
	var target := realm_index + 1 if target_realm < 0 else target_realm
	var configured: Variant = BalanceConfig.BREAKTHROUGH_REQUIREMENTS.get(target, [])
	var requirements: Array[Dictionary] = []
	if configured is Array:
		for item in configured:
			if item is Dictionary:
				requirements.append(item.duplicate(true))
	return requirements


func get_breakthrough_material_count(material_id: String) -> int:
	return maxi(0, int(breakthrough_materials.get(material_id, 0)))


func has_breakthrough_materials(target_realm: int = -1) -> bool:
	for requirement in get_breakthrough_requirements(target_realm):
		var material_id := String(requirement.get("material_id", ""))
		var amount := maxi(0, int(requirement.get("amount", 0)))
		if material_id == "" or get_breakthrough_material_count(material_id) < amount:
			return false
	return true


func get_breakthrough_block_reason() -> String:
	if lifespan_depleted:
		return "大限已至"
	if tribulation_active:
		return "正在渡劫：%s %d/%d" % [get_tribulation_name(), tribulation_strikes_survived, tribulation_total_strikes]
	if realm_index + 1 >= RealmConfig.realm_count():
		return "已达当前最高境界"
	if cultivation < get_next_realm_requirement():
		return "修为未达门槛"
	for requirement in get_breakthrough_requirements():
		var material_id := String(requirement.get("material_id", ""))
		var required_amount := maxi(0, int(requirement.get("amount", 0)))
		var owned_amount := get_breakthrough_material_count(material_id)
		if owned_amount < required_amount:
			return "缺少%s %d/%d" % [_breakthrough_material_name(material_id), owned_amount, required_amount]
	return "可突破"


func _breakthrough_material_name(material_id: String) -> String:
	var material: Variant = BalanceConfig.BREAKTHROUGH_MATERIALS.get(material_id, {})
	return String(material.get("name", material_id)) if material is Dictionary else material_id


# 突破前成功率选择：稳定（材料 ×1.5，95%）/ 强行（材料 ×1，50%）。
# 成功开始天劫；失败碎丹：不损失修为，获得碎丹经验（下次成功率 +15%，封顶 45%）。
func get_breakthrough_success_rate(mode: String) -> float:
	var stable := mode != "forced"
	var base := BalanceConfig.BREAKTHROUGH_STABLE_SUCCESS_RATE if stable else BalanceConfig.BREAKTHROUGH_FORCED_SUCCESS_RATE
	return minf(1.0, base + broken_dan_experience)


func get_breakthrough_mode_info(mode: String) -> Dictionary:
	var stable := mode != "forced"
	return {
		"mode": "stable" if stable else "forced",
		"material_mult": BalanceConfig.BREAKTHROUGH_STABLE_MATERIAL_MULT if stable else 1.0,
		"success_rate": get_breakthrough_success_rate(mode),
	}


# 突破：选择稳定/强行后消耗材料并 roll 成功率；成功进入天劫，失败获得碎丹经验。
# 返回 {"ok", "attempted", "success", "reason"}。ok=false 表示条件不满足（未消耗材料）。
func breakthrough(mode: String = "stable") -> Dictionary:
	if lifespan_depleted or not can_breakthrough():
		return {"ok": false, "attempted": false, "success": false, "reason": get_breakthrough_block_reason()}
	var stable := mode != "forced"
	if stable and not has_breakthrough_materials_for_mode(realm_index + 1, "stable"):
		return {"ok": false, "attempted": false, "success": false, "reason": "稳定突破需要 1.5 倍突破材料"}
	_consume_breakthrough_materials(realm_index + 1, BalanceConfig.BREAKTHROUGH_STABLE_MATERIAL_MULT if stable else 1.0)
	if randf() < get_breakthrough_success_rate(mode):
		if begin_tribulation(realm_index + 1):
			return {"ok": true, "attempted": true, "success": true, "reason": "天劫开始"}
		return {"ok": false, "attempted": true, "success": false, "reason": "天劫未能开始"}
	broken_dan_experience = minf(BalanceConfig.BROKEN_DAN_SUCCESS_CAP, broken_dan_experience + BalanceConfig.BROKEN_DAN_SUCCESS_BONUS)
	tribulation_last_result = "碎丹：突破失败，碎丹经验 +%.0f%%（下次成功率 %.0f%%）" % [
		BalanceConfig.BROKEN_DAN_SUCCESS_BONUS * 100.0,
		get_breakthrough_success_rate(mode) * 100.0,
	]
	emit_state_changed()
	return {"ok": true, "attempted": true, "success": false, "reason": "碎丹：材料已消耗，获得碎丹经验"}


func get_tribulation_name() -> String:
	return "三劫雷劫"


func begin_tribulation(target_realm: int = -1) -> bool:
	var target := realm_index + 1 if target_realm < 0 else target_realm
	if lifespan_depleted or tribulation_active or target != realm_index + 1:
		return false
	if target < 0 or target >= RealmConfig.realm_count():
		return false
	# 材料已由 breakthrough 按所选模式消耗；这里只开启三道检查。
	tribulation_active = true
	tribulation_target_realm = target
	tribulation_total_strikes = BalanceConfig.TRIBULATION_TOTAL_CHECKS
	tribulation_strikes_survived = 0
	tribulation_prepared = [false, false, false]
	tribulation_next_strike_at = Time.get_unix_time_from_system() + BalanceConfig.TRIBULATION_CHECK_INTERVAL_SECONDS
	tribulation_last_result = ""
	emit_state_changed()
	return true


func get_tribulation_status() -> Dictionary:
	var seconds_to_next := 0.0
	if tribulation_active:
		seconds_to_next = maxf(0.0, tribulation_next_strike_at - Time.get_unix_time_from_system())
	var checks: Array = []
	for check in BalanceConfig.tribulation_checks():
		var check_index := int(check.get("index", 0))
		var requirement := String(check.get("requirement", ""))
		if check_index == 0:
			requirement = "当前灵气 ≥ %s（治疗丹减半）" % NumberFormat.format(BalanceConfig.tribulation_qi_requirement(tribulation_target_realm))
		checks.append({
			"index": check_index,
			"name": String(check.get("name", "")),
			"desc": String(check.get("desc", "")),
			"requirement": requirement,
			"passed": check_index < tribulation_strikes_survived,
			"prepared": check_index < tribulation_prepared.size() and tribulation_prepared[check_index],
		})
	return {
		"active": tribulation_active,
		"target_realm": tribulation_target_realm,
		"target_realm_name": String(BalanceConfig.REALMS[tribulation_target_realm].get("name", "")) if tribulation_target_realm >= 0 and tribulation_target_realm < RealmConfig.realm_count() else "",
		"name": get_tribulation_name(),
		"total_strikes": tribulation_total_strikes,
		"strikes_survived": tribulation_strikes_survived,
		"seconds_to_next": seconds_to_next,
		"last_result": tribulation_last_result,
		"checks": checks,
		"healing_pills": healing_pills,
		"resistance_pills": resistance_pills,
		"enhancement_pills": enhancement_pills,
	}


func advance_tribulation() -> bool:
	if not tribulation_active:
		return false
	_resolve_tribulation_check(Time.get_unix_time_from_system())
	return true


# 渡劫丹改为“渡劫准备”：治疗丹让第一劫·灵气需求减半（每次渡劫限 1 枚）。
func use_healing_pill() -> bool:
	if not tribulation_active or healing_pills <= 0 or (tribulation_prepared.size() > 0 and tribulation_prepared[0]):
		return false
	healing_pills -= 1
	tribulation_prepared[0] = true
	emit_state_changed()
	return true


func use_resistance_pill() -> bool:
	if not tribulation_active or resistance_pills <= 0 or (tribulation_prepared.size() > 1 and tribulation_prepared[1]):
		return false
	resistance_pills -= 1
	tribulation_prepared[1] = true
	emit_state_changed()
	return true


func use_enhancement_pill() -> bool:
	if not tribulation_active or enhancement_pills <= 0 or (tribulation_prepared.size() > 2 and tribulation_prepared[2]):
		return false
	enhancement_pills -= 1
	tribulation_prepared[2] = true
	emit_state_changed()
	return true


func _update_tribulation(now: float) -> void:
	if not tribulation_active or now < tribulation_next_strike_at:
		return
	# 一帧只结算一道检查，避免从后台回来时瞬间跳过整段天劫。
	_resolve_tribulation_check(now)


func _resolve_tribulation_check(now: float) -> void:
	if not tribulation_active:
		return
	var check_index := tribulation_strikes_survived
	if check_index >= BalanceConfig.TRIBULATION_TOTAL_CHECKS:
		_complete_tribulation()
		return
	if _evaluate_tribulation_check(check_index):
		tribulation_strikes_survived += 1
		tribulation_last_result = "第%d劫通过" % (check_index + 1)
		if tribulation_strikes_survived >= BalanceConfig.TRIBULATION_TOTAL_CHECKS:
			_complete_tribulation()
			return
		tribulation_next_strike_at = now + BalanceConfig.TRIBULATION_CHECK_INTERVAL_SECONDS
		emit_state_changed()
		return
	# 检查失败：不损失修为，获得永久雷劫淬体（生产/修为 +5%，跨局保留）。
	tribulation_refine_bonus += BalanceConfig.TRIBULATION_REFINE_BONUS
	_fail_tribulation("未过第%d劫" % (check_index + 1))


# 三道检查：第一劫·灵气储备 / 第二劫·生产底蕴 / 第三劫·气运。
# 治疗丹减半灵气需求、抗性丹减半底蕴需求、强化丹直接通过气运劫。
func _evaluate_tribulation_check(check_index: int) -> bool:
	var prepared := check_index >= 0 and check_index < tribulation_prepared.size() and tribulation_prepared[check_index]
	match check_index:
		0:
			var qi_requirement := BalanceConfig.tribulation_qi_requirement(tribulation_target_realm)
			if prepared:
				qi_requirement *= BalanceConfig.TRIBULATION_HEAL_REQUIREMENT_MULT
			return qi >= qi_requirement
		1:
			var harvest_requirement := BalanceConfig.TRIBULATION_CHECK_HARVEST_REQUIREMENT
			if prepared:
				harvest_requirement = ceili(float(harvest_requirement) * BalanceConfig.TRIBULATION_RESISTANCE_REQUIREMENT_MULT)
			return run_harvest_count >= harvest_requirement
		2:
			if prepared:
				return true
			return run_random_event_count >= 1 or _has_luck_talent()
	return false


func _has_luck_talent() -> bool:
	return talent_bonus("crit_chance") > 0.0 or talent_bonus("rare_crit_chance") > 0.0 or talent_bonus("windfall_chance") > 0.0


func _complete_tribulation() -> void:
	var completed_realm := tribulation_target_realm
	tribulation_active = false
	tribulation_last_result = "渡劫成功"
	tribulation_target_realm = -1
	tribulation_next_strike_at = 0.0
	if completed_realm < 0 or completed_realm >= RealmConfig.realm_count():
		_fail_tribulation("目标境界无效")
		return
	realm_index = completed_realm
	# 突破成功：提高寿元上限并补满当前寿元。
	lifespan_max_years = BalanceConfig.LIFESPAN_YEARS_BY_REALM[mini(realm_index, BalanceConfig.LIFESPAN_YEARS_BY_REALM.size() - 1)]
	lifespan_years = lifespan_max_years
	lifespan_depleted = false
	# 突破本身给点，修为里程碑另行给点。
	promotion_count += 1
	var reward_index := mini(realm_index, BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM.size() - 1)
	_award_talent_points(int(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM[reward_index]))
	var rewards: Dictionary = RealmConfig.breakthrough_rewards(realm_index)
	_apply_breakthrough_rewards(rewards)
	tribulation_total_strikes = BalanceConfig.TRIBULATION_TOTAL_CHECKS
	tribulation_strikes_survived = 0
	tribulation_prepared = [false, false, false]
	realm_changed.emit()
	emit_state_changed()


func _fail_tribulation(reason: String) -> void:
	tribulation_active = false
	tribulation_last_result = "渡劫失败：%s（雷劫淬体 +%.0f%%）" % [reason, BalanceConfig.TRIBULATION_REFINE_BONUS * 100.0]
	tribulation_target_realm = -1
	tribulation_next_strike_at = 0.0
	tribulation_total_strikes = BalanceConfig.TRIBULATION_TOTAL_CHECKS
	tribulation_strikes_survived = 0
	tribulation_prepared = [false, false, false]
	emit_state_changed()


func _consume_breakthrough_materials(target_realm: int, mult := 1.0) -> void:
	for requirement in get_breakthrough_requirements(target_realm):
		var material_id := String(requirement.get("material_id", ""))
		var amount := maxi(0, int(requirement.get("amount", 0)))
		var needed := ceili(float(amount) * mult)
		breakthrough_materials[material_id] = maxi(0, get_breakthrough_material_count(material_id) - needed)


func has_breakthrough_materials_for_mode(target_realm: int, mode: String) -> bool:
	var mult := BalanceConfig.BREAKTHROUGH_STABLE_MATERIAL_MULT if mode != "forced" else 1.0
	for requirement in get_breakthrough_requirements(target_realm):
		var material_id := String(requirement.get("material_id", ""))
		var amount := maxi(0, int(requirement.get("amount", 0)))
		var needed := ceili(float(amount) * mult)
		if material_id == "" or get_breakthrough_material_count(material_id) < needed:
			return false
	return true


# 把突破奖励字典应用到自身。奖励键名与 unlock_* 变量名严格对齐。
# 突破奖励只“解锁”、不“回收”：rewards 全默认 false，只有 true 项才生效，
# 不能把早前境界已解锁的能力（灵雨诀 / 自动修炼）覆盖回 false。
func _apply_breakthrough_rewards(rewards: Dictionary) -> void:
	for key in rewards:
		var value: Variant = rewards[key]
		if key == "unlock_spirit_rain":
			spirit_rain_unlocked = spirit_rain_unlocked or bool(value)
		elif key.begins_with("unlock_"):
			# 其余 unlock_* 奖励键与同名变量一一对应。
			set(key, bool(get(key)) or bool(value))


# ───────────────────────── 倍率统一入口（契约[A]） ─────────────────────────

func talent_multiplier(effect_key: String) -> float:
	return TalentTree.multiplier(effect_key, talent_nodes)


# 概率类天赋效果（暴击率等）：相加语义，未购买时返回 0。
func talent_bonus(effect_key: String) -> float:
	return TalentTree.bonus(effect_key, talent_nodes)


# 生产类综合倍率（生长/产量/灵气/自动修炼灵气）。
# = 境界生产 × 天赋生产 × 灵田档位 × 事件 × 狂暴丹。
func get_production_mult(field_index: int) -> float:
	return SimulationSystem.live_production_multiplier(self, field_index)


## 由游戏内模拟器读取的统一报告入口。
## 报告只读当前状态并复制场景，不会修改实际经营进度。
func get_simulation_report(options: Dictionary = {}) -> Dictionary:
	return SimulationSystem.report(self, options)


## 由游戏内模拟器和 headless 验证共用的矩阵入口。
func get_simulation_matrix(kind: String, options: Dictionary = {}) -> Array:
	return SimulationSystem.matrix(self, kind, options)


## 按点击频率模拟从当前境界到目标境界的完整成长流程。
func get_breakthrough_simulation(options: Dictionary = {}) -> Dictionary:
	return SimulationSystem.simulate_breakthrough_flow(self, options)


func get_achievement_rows() -> Array[Dictionary]:
	return AchievementSystem.progress_rows(self)


# 修炼类综合倍率（灵田直接修为 / 自动修炼修为）。buff 不直接作用于 cultivation，
# 但会通过 production 影响收获数量；这里仍只汇总境界、天赋和事件修炼倍率。
func get_cultivation_mult() -> float:
	return SimulationSystem.live_cultivation_multiplier(self)


## 灵气库存对收获的加成。灵气不再只是法术燃料：库存越高，收获越强，且有基础软上限。
func get_qi_harvest_mult() -> float:
	return SimulationSystem.live_qi_harvest_multiplier(self)


func get_click_accel_seconds() -> float:
	return SimulationSystem.live_click_accel_seconds(self)


func get_lifespan_decay_per_second() -> float:
	return SimulationSystem.live_lifespan_decay_per_second(self)


# ───────────────────────── 季节 ─────────────────────────

func get_season_name() -> String:
	return String(BalanceConfig.SEASONS[season_index]["name"])


# ───────────────────────── 灵田 / 种植 / 收获 / 升档 ─────────────────────────

# 灵田 tier 乘数：凡1 / 灵10 / 宝100 / 仙1000。
func field_tier_mult(field_index: int) -> float:
	if field_index < 0 or field_index >= fields.size():
		return BalanceConfig.DEFAULT_MULTIPLIER
	var tier := clampi(int(fields[field_index].get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	return BalanceConfig.FIELD_TIER_MULTS[tier]


func get_crop_options() -> Array:
	var options := CropConfig.get_unlocked(realm_index)
	# 天降灵种事件：本世解锁高级灵植（紫芝），不受境界限制。
	if heavenly_seed_unlocked and not options.has(BalanceConfig.HEAVENLY_SEED_CROP):
		options.append(BalanceConfig.HEAVENLY_SEED_CROP)
	return options


# 种植：校验空田、作物已解锁，写入 crop_id 与按倍率缩短后的成熟时间；不改变该田固定虫害计时。
func plant_crop(field_index: int, crop_id: String) -> bool:
	if lifespan_depleted or tribulation_active:
		return false
	if field_index < 0 or field_index >= fields.size() or field_index >= unlocked_fields:
		return false
	if not get_crop_options().has(crop_id):
		return false
	var data: Dictionary = fields[field_index]
	if String(data.get("crop_id", "")) != "":
		return false
	var crop: Variant = CropConfig.get_crop(crop_id)
	if crop == null:
		return false
	var now := Time.get_unix_time_from_system()
	var growth_time := SimulationSystem.live_crop_growth_seconds(self, field_index, crop_id)
	# tier 保留，仅更新作物与时间。
	data["crop_id"] = crop_id
	data["planted_at"] = now
	data["ready_at"] = now + growth_time
	fields[field_index] = data
	emit_state_changed()
	return true


# 切换已在生长的灵植：放弃当前生长进度，立即按新作物重新计时；不改变固定虫害计时。
func switch_crop(field_index: int, crop_id: String) -> bool:
	if lifespan_depleted or tribulation_active:
		return false
	if field_index < 0 or field_index >= fields.size() or field_index >= unlocked_fields:
		return false
	if not get_crop_options().has(crop_id):
		return false
	var data: Dictionary = fields[field_index]
	var previous_crop_id := String(data.get("crop_id", ""))
	if previous_crop_id == "" or previous_crop_id == crop_id:
		return false
	var crop: Variant = CropConfig.get_crop(crop_id)
	if crop == null:
		return false
	var now := Time.get_unix_time_from_system()
	data["crop_id"] = crop_id
	data["planted_at"] = now
	data["ready_at"] = now + SimulationSystem.live_crop_growth_seconds(self, field_index, crop_id)
	fields[field_index] = data
	emit_state_changed()
	return true


# 点击加速：缩短当前作物的成熟倒计时，成熟后仍由自动收获统一结算。
func speed_up_crop(field_index: int) -> Dictionary:
	var empty := {"ok": false, "seconds": 0.0, "remaining": 0.0}
	if lifespan_depleted or tribulation_active or field_index < 0 or field_index >= fields.size():
		return empty
	var data: Dictionary = fields[field_index]
	if String(data.get("crop_id", "")) == "":
		return empty
	var now := Time.get_unix_time_from_system()
	var remaining := maxf(0.0, float(data.get("ready_at", 0.0)) - now)
	if remaining <= 0.0:
		return empty
	var reduced := minf(remaining, get_click_accel_seconds())
	data["ready_at"] = maxf(now, float(data.get("ready_at", 0.0)) - reduced)
	fields[field_index] = data
	emit_state_changed()
	return {"ok": true, "seconds": reduced, "remaining": maxf(0.0, remaining - reduced)}


# 收获结算：所有成熟作物都自动收获并立即补种；灵气库存提供额外加成。
# 结算在模型内同时完成补种，保证一次收获就是一个可保存的完整状态变更。
func harvest_crop(field_index: int) -> Dictionary:
	var empty := {"ok": false, "crop_id": "", "amount": 0, "cultivation": 0.0, "spirit_stones": 0.0}
	if lifespan_depleted or tribulation_active:
		return empty
	if field_index < 0 or field_index >= fields.size():
		return empty
	var data: Dictionary = fields[field_index]
	var crop_id := String(data.get("crop_id", ""))
	if crop_id == "":
		return empty
	if CropConfig.get_crop(crop_id) == null:
		return empty
	var pest_level := 0
	if field_index < insect_events.size():
		pest_level = int(insect_events[field_index].get("pest_level", 0))
	var tier := int(data.get("tier", 0))
	var simulated := SimulationSystem.live_field_result(self, field_index, crop_id, tier, pest_level)
	var amount := int(simulated.get("amount", 0))
	var cultivation_gain := float(simulated.get("cultivation_gain", 0.0))
	var spirit_stones_gain := float(simulated.get("spirit_stones_per_cycle", 0.0))
	# 幸运系：收获时 roll 暴击 / 稀有暴击 / 天降横财。概率由天赋 + 仙箱永久暴击组成（相加语义）。
	var luck_mult := 1.0
	var is_crit := false
	var is_rare := false
	var is_windfall := false
	var crit_chance := talent_bonus("crit_chance") + treasure_crit_bonus
	if crit_chance > 0.0 and randf() < crit_chance:
		is_crit = true
		crit_count += 1
		if talent_bonus("rare_crit_chance") > 0.0 and randf() < talent_bonus("rare_crit_chance"):
			is_rare = true
			luck_mult = BalanceConfig.LUCK_RARE_CRIT_MULT
			rare_crit_count += 1
		else:
			luck_mult = BalanceConfig.LUCK_CRIT_MULT
	cultivation_gain *= luck_mult
	spirit_stones_gain *= luck_mult
	if talent_bonus("windfall_chance") > 0.0 and randf() < talent_bonus("windfall_chance"):
		is_windfall = true
		windfall_count += 1
		# 横财按暴击后的本次灵石额外追加。
		spirit_stones_gain += spirit_stones_gain * BalanceConfig.LUCK_WINDFALL_RATIO
	# 宝箱 / 奇遇：每次收获独立 roll；天命转世天赋放大概率。
	var treasure := TreasureSystem.roll(_fate_mult())
	var treasure_found := false
	var treasure_name := ""
	if treasure.get("found", false):
		treasure_found = true
		treasure_name = String(treasure.get("name", ""))
		_apply_treasure_reward(treasure)
	# 灵田是当前循环的直接产出端：收获同时结算修为与灵石，不结算灵气。
	_add_cultivation(cultivation_gain)
	spirit_stones += spirit_stones_gain
	_record_crop_harvest(crop_id)
	_replant_after_harvest(field_index, crop_id, Time.get_unix_time_from_system())
	emit_state_changed()
	return {
		"ok": true,
		"crop_id": crop_id,
		"amount": amount,
		"cultivation": cultivation_gain,
		"spirit_stones": spirit_stones_gain,
		"qi_mult": float(simulated.get("qi_harvest_mult", 1.0)),
		"proficiency": get_crop_proficiency(crop_id),
		"crit": is_crit,
		"rare_crit": is_rare,
		"windfall": is_windfall,
		"luck_mult": luck_mult,
		"treasure_found": treasure_found,
		"treasure_name": treasure_name,
	}


# 天命转世天赋的奇遇倍率（无天命 = 1.0）。
func _fate_mult() -> float:
	var boon := BalanceConfig.reincarnation_boon(reincarnation_boon)
	return float(boon.get("fate_mult", 1.0))


# 应用宝箱奖励描述；GameState 是唯一入账方。
func _apply_treasure_reward(treasure: Dictionary) -> void:
	var reward: Dictionary = treasure.get("reward", {})
	var kind := String(reward.get("kind", ""))
	var amount := float(reward.get("amount", 0.0))
	match kind:
		"stones":
			spirit_stones += amount
		"qi":
			qi += amount
		"material":
			var material_id := String(reward.get("material_id", ""))
			if material_id != "" and BalanceConfig.BREAKTHROUGH_MATERIALS.has(material_id):
				breakthrough_materials[material_id] = get_breakthrough_material_count(material_id) + maxi(1, int(amount))
		"talent_points":
			_award_talent_points(int(amount))
		"permanent_production":
			treasure_production_bonus += amount
		"lifespan_max":
			lifespan_max_years += amount
			lifespan_years += amount
		"permanent_crit":
			treasure_crit_bonus += amount


func _replant_after_harvest(field_index: int, crop_id: String, planted_at: float) -> void:
	var crop: Variant = CropConfig.get_crop(crop_id)
	if crop == null:
		var empty_data: Dictionary = fields[field_index]
		empty_data["crop_id"] = ""
		empty_data["planted_at"] = 0.0
		empty_data["ready_at"] = 0.0
		fields[field_index] = empty_data
		return
	var data: Dictionary = fields[field_index]
	data["crop_id"] = crop_id
	data["planted_at"] = planted_at
	data["ready_at"] = planted_at + SimulationSystem.live_crop_growth_seconds(self, field_index, crop_id)
	fields[field_index] = data
	if field_index < insect_events.size():
		# 自动补种仍是同一条生产线：保留虫灾状态和计时，避免聚灵草每 5 秒
		# 重置一次预警，导致虫灾永远进不来。手动种植/切换作物也不改变固定袭击。
		var event: Dictionary = insect_events[field_index]
		if event.is_empty():
			event = {
				"active": false,
				"attacks": 0,
				"pest_level": 0,
				"next_attack_at": planted_at + BalanceConfig.INSECT_INITIAL_DELAY_SECONDS,
			}
		elif not event.has("next_attack_at"):
			event["next_attack_at"] = planted_at + BalanceConfig.INSECT_INITIAL_DELAY_SECONDS
		insect_events[field_index] = event

## 返回指定灵田槽位的购买费用与修行等级要求。
func get_field_slot_cost(field_index: int) -> Dictionary:
	if field_index < 0 or field_index >= BalanceConfig.FIELD_SLOT_COSTS.size():
		return {}
	return {"spirit_stones": SimulationSystem.slot_cost(self, realm_index, field_index)}


func can_buy_field_slot(field_index: int) -> bool:
	if lifespan_depleted or tribulation_active or field_index != unlocked_fields or field_index <= 0 or field_index >= fields.size():
		return false
	var cost := get_field_slot_cost(field_index)
	return spirit_stones >= float(cost.get("spirit_stones", 0.0))


func buy_field_slot(field_index: int) -> bool:
	if not can_buy_field_slot(field_index):
		return false
	var cost := get_field_slot_cost(field_index)
	spirit_stones -= float(cost.get("spirit_stones", 0.0))
	unlocked_fields += 1
	emit_state_changed()
	return true


func get_max_field_tier() -> int:
	return clampi(realm_index, 0, BalanceConfig.FIELD_TIER_UPGRADE_COSTS.size())


func get_field_upgrade_cost(field_index: int) -> Dictionary:
	if field_index < 0 or field_index >= fields.size():
		return {}
	var tier := int(fields[field_index].get("tier", 0))
	if tier < 0 or tier >= BalanceConfig.FIELD_TIER_UPGRADE_COSTS.size():
		return {}
	return BalanceConfig.FIELD_TIER_UPGRADE_COSTS[tier]


func can_purchase_field_tier(field_index: int) -> bool:
	if lifespan_depleted or tribulation_active or field_index < 0 or field_index >= fields.size() or field_index >= unlocked_fields:
		return false
	var tier := int(fields[field_index].get("tier", 0))
	if tier < 0 or tier >= BalanceConfig.FIELD_TIER_UPGRADE_COSTS.size() or tier >= get_max_field_tier():
		return false
	var cost := get_field_upgrade_cost(field_index)
	return realm_index >= int(cost.get("required_realm", tier + 1)) and spirit_stones >= float(cost.get("spirit_stones", 0.0))


# 灵田等级提升：修行等级只提供购买权限，实际升级全部消耗灵石。
func upgrade_field_tier(field_index: int) -> bool:
	if not can_purchase_field_tier(field_index):
		return false
	var data: Dictionary = fields[field_index]
	var tier := int(data.get("tier", 0))
	var cost := get_field_upgrade_cost(field_index)
	spirit_stones -= float(cost.get("spirit_stones", 0.0))
	data["tier"] = tier + 1
	fields[field_index] = data
	emit_state_changed()
	return true


# ───────────────────────── 天赋树 / 长期成长 ─────────────────────────

func is_talent_unlocked(node_id: String) -> bool:
	return TalentTree.is_unlocked(node_id, talent_nodes)


func can_unlock_talent(node_id: String) -> bool:
	return TalentTree.can_unlock(node_id, talent_nodes, talent_points)


func unlock_talent(node_id: String) -> bool:
	if not can_unlock_talent(node_id):
		return false
	var node := TalentTree.node_def(node_id)
	talent_points -= int(node.get("cost", 0))
	talent_nodes[node_id] = true
	emit_state_changed()
	return true


func _award_talent_points(amount: int) -> void:
	if amount <= 0:
		return
	talent_points += amount
	talent_points_earned += amount


func get_crop_proficiency(crop_id: String) -> Dictionary:
	return BalanceConfig.crop_proficiency_reward(crop_id, int(crop_proficiency.get(crop_id, 0)))


func _record_crop_harvest(crop_id: String) -> void:
	var previous_count := int(crop_proficiency.get(crop_id, 0))
	var current_count := previous_count + 1
	crop_proficiency[crop_id] = current_count
	total_harvest_count += 1
	run_harvest_count += 1
	var new_talent_points := BalanceConfig.crop_proficiency_talent_points(crop_id, previous_count, current_count)
	_award_talent_points(new_talent_points)


func _add_cultivation(amount: float) -> void:
	if amount <= 0.0:
		return
	cultivation += amount
	total_cultivation_earned += amount
	while talent_milestone_index < BalanceConfig.TALENT_MILESTONES.size() and total_cultivation_earned >= BalanceConfig.TALENT_MILESTONES[talent_milestone_index]:
		_award_talent_points(BalanceConfig.TALENT_MILESTONE_POINTS)
		talent_milestone_index += 1


# ───────────────────────── 法术 / 灵雨诀 ─────────────────────────

func is_spirit_rain_active(field_index: int) -> bool:
	return field_index >= 0 and field_index < spirit_rain_until.size() and spirit_rain_until[field_index] > Time.get_unix_time_from_system()


func cast_spirit_rain(
	field_index: int,
	duration := BalanceConfig.SPIRIT_RAIN_DURATION_SECONDS,
	cost := BalanceConfig.SPIRIT_RAIN_COST
	) -> bool:
	if lifespan_depleted or tribulation_active or not spirit_rain_unlocked:
		return false
	if field_index < 0 or field_index >= fields.size() or qi < cost:
		return false
	qi -= cost
	spirit_rain_until[field_index] = maxf(spirit_rain_until[field_index], Time.get_unix_time_from_system() + duration)
	emit_state_changed()
	return true


func cast_gengjin_sword(
	field_index: int,
	cost := BalanceConfig.GENGJIN_SWORD_COST,
	cooldown := BalanceConfig.GENGJIN_SWORD_COOLDOWN_SECONDS
	) -> bool:
	var now := Time.get_unix_time_from_system()
	if lifespan_depleted or tribulation_active or realm_index < BalanceConfig.ADVANCED_COMBAT_REALM_INDEX:
		return false
	if field_index < 0 or field_index >= insect_events.size() or qi < cost or now < sword_art_cooldown_until:
		return false
	if not bool(insect_events[field_index].get("active", false)):
		return false
	qi -= cost
	sword_art_cooldown_until = now + cooldown
	var corpses_gained := maxi(BalanceConfig.MIN_INSECT_CORPSES_PER_SWORD, int(insect_events[field_index].get("attacks", BalanceConfig.MIN_INSECT_CORPSES_PER_SWORD)))
	# 噬金虫王：剑诀击杀额外获得虫尸 ×10，并提前结束事件。
	if random_event == "insect_king" and is_random_event_active():
		corpses_gained += BalanceConfig.INSECT_KING_CORPSE_REWARD
		_clear_random_event()
	insect_corpses += corpses_gained
	insect_events[field_index] = {
		"active": false,
		"attacks": 0,
		"pest_level": 0,
		"next_attack_at": now + BalanceConfig.GENGJIN_SWORD_CLEAR_COOLDOWN_SECONDS,
	}
	emit_state_changed()
	return true


func upgrade_guardian_array(field_index: int, cost := BalanceConfig.GUARDIAN_UPGRADE_COST) -> bool:
	if lifespan_depleted or tribulation_active or realm_index < BalanceConfig.ADVANCED_COMBAT_REALM_INDEX:
		return false
	if field_index < 0 or field_index >= guardian_array_level.size() or spirit_stones < cost:
		return false
	spirit_stones -= cost
	guardian_array_level[field_index] += 1
	guardian_array_charges[field_index] = BalanceConfig.GUARDIAN_CHARGES_BASE_OFFSET + guardian_array_level[field_index]
	emit_state_changed()
	return true


# 生长乘数：季节 × 生长天赋 × 灵雨诀。境界与灵田档次只放大单次产出，
# 避免高境界叠加仙田后把长周期作物压成瞬间完成。
func get_growth_multiplier(field_index: int) -> float:
	return SimulationSystem.live_growth_multiplier(self, field_index)


# ───────────────────────── 主模拟循环 ─────────────────────────

func update_world(delta: float) -> void:
	if lifespan_depleted:
		return
	var now := Time.get_unix_time_from_system()
	# 寿元按运行时间流逝；归零后只进入提示状态，不再重置进度。
	if lifespan_years > 0.0:
		var before_lifespan := lifespan_years
		lifespan_years = maxf(0.0, lifespan_years - get_lifespan_decay_per_second() * delta)
		if before_lifespan > 0.0 and lifespan_years <= 0.0:
			lifespan_depleted = true
			decay_active = false
			if tribulation_active:
				_fail_tribulation("寿元耗尽")
			emit_state_changed()
			return
	# 天人五衰·继续修炼：每 60 秒 roll 一次天命奇遇。
	if decay_active and now >= fate_opportunity_at:
		fate_opportunity_at = now + BalanceConfig.FATE_OPPORTUNITY_INTERVAL_SECONDS
		roll_fate_opportunity()
	# 渡劫是暂停生产的独立阶段，只处理自动天劫；玩家可用按钮手动迎接下一道。
	if tribulation_active:
		_update_tribulation(now)
		return
	# 四季轮换（180 秒/季）。
	if now - season_started_at >= BalanceConfig.SEASON_DURATION_SECONDS:
		season_started_at = now
		season_index = (season_index + 1) % BalanceConfig.SEASONS.size()
		emit_state_changed()
	# 随机事件轮换。
	if random_event != "" and now >= random_event_until:
		_clear_random_event()
	elif random_event == "" and now >= random_event_cooldown_until:
		random_event = String(BalanceConfig.EVENT_EVENTS[randi() % BalanceConfig.EVENT_EVENTS.size()])
		random_event_until = now + float(BalanceConfig.EVENT_DURATIONS.get(random_event, BalanceConfig.DEFAULT_EVENT_DURATION_SECONDS))
		# 本世事件计数（第三劫·气运检查用）；天降灵种立即解锁紫芝。
		run_random_event_count += 1
		if random_event == "heavenly_seed":
			heavenly_seed_unlocked = true
		emit_state_changed()
	# 事件分量由当前事件驱动。
	if is_random_event_active() and random_event == "heavenly_seed":
		heavenly_seed_unlocked = true
	if is_random_event_active() and random_event == "auspicious":
		event_prod_mult = BalanceConfig.EVENT_PROD_BONUS
	else:
		event_prod_mult = BalanceConfig.DEFAULT_MULTIPLIER
	# 魔气侵染：生产 -50%，可用灵石净化提前结束。
	if is_random_event_active() and random_event == "demon_qi":
		event_prod_mult *= (1.0 - BalanceConfig.DEMON_QI_PRODUCTION_PENALTY)
	if is_random_event_active() and random_event == "dao_insight":
		event_cult_mult = BalanceConfig.EVENT_CULT_BONUS
	else:
		event_cult_mult = BalanceConfig.DEFAULT_MULTIPLIER

	# 噬金虫逻辑（保留；兵主诞辰期间攻击数 ×2、攻击间隔减半）。
	for i in range(insect_events.size()):
		if String(fields[i].get("crop_id", "")) == "":
			continue
		var event: Dictionary = insect_events[i]
		if not bool(event.get("active", false)) and now >= float(event.get("next_attack_at", 0.0)):
			event["active"] = true
			event["next_attack_at"] = now + BalanceConfig.INSECT_ATTACK_INTERVAL_SECONDS
			insect_events[i] = event
			emit_state_changed()
		elif bool(event.get("active", false)) and now >= float(event.get("next_attack_at", 0.0)):
			register_insect_attack(i)
			event = insect_events[i]
			event["next_attack_at"] = now + (BalanceConfig.INSECT_WARLORD_ATTACK_INTERVAL_SECONDS if random_event == "warlord_birthday" and is_random_event_active() else BalanceConfig.INSECT_ATTACK_INTERVAL_SECONDS)
			insect_events[i] = event

	# 自动修炼（筑基解锁）：灵气浓度 + 灵根天赋驱动。
	if unlock_auto_cultivation:
		var density := get_qi_density()
		var rates := automation.auto_rates(
			density,
			realm_index,
			event_prod_mult,
			event_cult_mult,
			RealmConfig.production_mult(realm_index),
			RealmConfig.cultivation_mult(realm_index),
			talent_multiplier("auto_cultivation_mult"),
			talent_multiplier("qi_gain_mult")
		)
		_add_cultivation(float(rates["cultivation_per_sec"]) * delta)
		qi += float(rates["qi_per_sec"]) * delta
		world_state_accumulator += delta
		if world_state_accumulator >= BalanceConfig.WORLD_STATE_EMIT_INTERVAL_SECONDS:
			world_state_accumulator = 0.0
			emit_state_changed()

	# 成熟后自动收获并立即补种；玩家点击生长中的作物只负责加速。
	_auto_harvest(now)


func _auto_harvest(now: float) -> void:
	for i in range(fields.size()):
		if i >= unlocked_fields:
			continue
		var data: Dictionary = fields[i]
		var crop_id := String(data.get("crop_id", ""))
		if crop_id == "":
			continue
		if now < float(data.get("ready_at", 0.0)):
			continue
		harvest_crop(i)


func register_insect_attack(field_index: int) -> void:
	var event: Dictionary = insect_events[field_index]
	var attack_count := BalanceConfig.INSECT_WARLORD_ATTACK_COUNT if random_event == "warlord_birthday" and is_random_event_active() else 1
	for _n in range(attack_count):
		event["attacks"] = int(event.get("attacks", 0)) + 1
		if guardian_array_charges[field_index] > 0:
			guardian_array_charges[field_index] -= 1
		else:
			event["pest_level"] = mini(BalanceConfig.MAX_PEST_LEVEL, int(event.get("pest_level", 0)) + 1)
	event["active"] = true
	insect_events[field_index] = event
	emit_state_changed()


func sell_insect_corpses() -> bool:
	if insect_corpses <= 0:
		return false
	spirit_stones += float(insect_corpses) * BalanceConfig.INSECT_CORPSE_SELL_PRICE
	insect_corpses = 0
	emit_state_changed()
	return true


# ───────────────────────── 商店 ─────────────────────────

# 返回商店商品列表，并把每个商品的 cost 替换为按购买次数计算的当前价格。
func get_shop_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for item in shop.get_items():
		var decorated := item.duplicate(true)
		var item_id := String(item.get("id", ""))
		decorated["cost"] = shop.get_cost(item_id, int(shop_purchase_counts.get(item_id, 0)))
		items.append(decorated)
	return items


func buy_shop_item(item_id: String) -> bool:
	var item := shop.get_item(item_id)
	if item.is_empty():
		return false
	if realm_index < int(item.get("required_realm", 0)):
		return false
	var purchases := int(shop_purchase_counts.get(item_id, 0))
	var cost := shop.get_cost(item_id, purchases)
	if cost <= 0.0 or spirit_stones < cost:
		return false
	var effect := String(item.get("effect", ""))
	var amount := float(item.get("amount", 0.0))
	if effect == "lifespan" and lifespan_years >= lifespan_max_years:
		return false
	# 大限期间生产暂停，生产 buff 购买无意义。
	if effect == "buff" and (lifespan_depleted or tribulation_active):
		return false
	spirit_stones -= cost
	match effect:
		"lifespan":
			lifespan_years = minf(lifespan_max_years, lifespan_years + amount)
			lifespan_depleted = lifespan_years <= 0.0
		"qi":
			qi += amount
		"tribulation_healing":
			healing_pills += 1
		"tribulation_resistance":
			resistance_pills += 1
		"tribulation_enhancement":
			enhancement_pills += 1
		"talent_points":
			_award_talent_points(int(amount))
		"buff":
			var now := Time.get_unix_time_from_system()
			# 连买刷新为较远结束时间，倍率取本次。
			active_buff_until = maxf(active_buff_until, now + float(item.get("duration", 0.0)))
			active_buff_mult = float(item.get("mult", 1.0))
		"breakthrough_material":
			var material_id := String(item.get("material_id", ""))
			if material_id == "" or not BalanceConfig.BREAKTHROUGH_MATERIALS.has(material_id):
				spirit_stones += cost
				return false
			breakthrough_materials[material_id] = get_breakthrough_material_count(material_id) + maxi(1, int(amount))
		_:
			spirit_stones += cost
			return false
	shop_purchase_counts[item_id] = purchases + 1
	emit_state_changed()
	return true


# ───────────────────────── 轮回 / 天人五衰 ─────────────────────────

## 转世奖励预览：保留未用天赋点 + 本世新跨修为里程碑 ×2 + 本世突破境界 ×1。
## 提前轮回（寿元 > 20%）奖励 ×80%；天人五衰（寿元 ≤ 20% 或大限）立即轮回 ×100%。
func get_reincarnation_reward_preview() -> Dictionary:
	var milestones := maxi(0, talent_milestone_index - run_start_milestone_index)
	var promotions := maxi(0, promotion_count - run_start_promotion_count)
	var base_points := milestones * BalanceConfig.REINCARNATION_MILESTONE_POINTS + promotions * BalanceConfig.REINCARNATION_BREAKTHROUGH_POINTS
	var early := not lifespan_depleted and not decay_active and lifespan_max_years > 0.0 \
		and lifespan_years > lifespan_max_years * BalanceConfig.DECAY_THRESHOLD_RATIO
	var mult := BalanceConfig.REINCARNATION_EARLY_PENALTY if early else 1.0
	var points := int(floor(float(base_points) * mult))
	return {
		"early": early,
		"decay_stage": is_decay_stage(),
		"milestones_crossed": milestones,
		"promotions": promotions,
		"base_points": base_points,
		"mult": mult,
		"points": points,
		"retained_points": talent_points,
		"total_points": talent_points + points,
	}


## 随时轮回：清空本世经营状态，保留长期成长，并按预览发放转世奖励。
## 渡劫期间与转世天赋未选定前不可轮回。
func reincarnate_now() -> bool:
	if tribulation_active or pending_reincarnation_boon:
		return false
	var preview := get_reincarnation_reward_preview()
	_perform_reincarnation(int(preview.get("points", 0)))
	return true


## 轮回核心：保存并恢复长期进度，结算本世奖励天赋点，等待三选一转世天赋。
func _perform_reincarnation(reward_points: int) -> void:
	var saved_nodes := talent_nodes.duplicate(true)
	var saved_points := talent_points
	var saved_earned_points := talent_points_earned
	var saved_total_cultivation := total_cultivation_earned
	var saved_milestone_index := talent_milestone_index
	var saved_crop_proficiency := crop_proficiency.duplicate(true)
	var saved_total_harvest_count := total_harvest_count
	var saved_promotion_count := promotion_count
	var saved_reincarnation_count := reincarnation_count + 1
	var saved_achievements := achievements.duplicate(true)
	var saved_achievement_points := achievement_points
	var saved_offline_claimed_talent_points := offline_claimed_talent_points
	var saved_offline_claimed_spirit_stone_units := offline_claimed_spirit_stone_units
	var saved_crit_count := crit_count
	var saved_rare_crit_count := rare_crit_count
	var saved_windfall_count := windfall_count
	var saved_treasure_production_bonus := treasure_production_bonus
	var saved_treasure_crit_bonus := treasure_crit_bonus
	var saved_fate_permanent_production := fate_permanent_production
	var saved_broken_dan_experience := broken_dan_experience
	var saved_tribulation_refine_bonus := tribulation_refine_bonus
	_reset_run_state()
	talent_nodes = saved_nodes
	talent_points = saved_points
	talent_points_earned = saved_earned_points
	total_cultivation_earned = saved_total_cultivation
	talent_milestone_index = saved_milestone_index
	crop_proficiency = saved_crop_proficiency
	total_harvest_count = saved_total_harvest_count
	promotion_count = saved_promotion_count
	reincarnation_count = saved_reincarnation_count
	achievements = saved_achievements
	achievement_points = saved_achievement_points
	offline_claimed_talent_points = saved_offline_claimed_talent_points
	offline_claimed_spirit_stone_units = saved_offline_claimed_spirit_stone_units
	crit_count = saved_crit_count
	rare_crit_count = saved_rare_crit_count
	windfall_count = saved_windfall_count
	treasure_production_bonus = saved_treasure_production_bonus
	treasure_crit_bonus = saved_treasure_crit_bonus
	fate_permanent_production = saved_fate_permanent_production
	broken_dan_experience = saved_broken_dan_experience
	tribulation_refine_bonus = saved_tribulation_refine_bonus
	_award_talent_points(reward_points)
	pending_reincarnation_boon = true
	reincarnation_boon = ""
	last_offline_report = {}
	_ensure_inventory_keys()
	emit_state_changed()


## 转世天赋三选一：轮回后本世生效、跨世不保留；选完前不再允许轮回。
func choose_reincarnation_boon(boon_id: String) -> bool:
	if not pending_reincarnation_boon:
		return false
	if BalanceConfig.reincarnation_boon(boon_id).is_empty():
		return false
	reincarnation_boon = boon_id
	pending_reincarnation_boon = false
	emit_state_changed()
	return true


func get_reincarnation_boon_options() -> Array[Dictionary]:
	return BalanceConfig.REINCARNATION_BOONS


# 天人五衰阶段：寿元低于阈值且未大限（此时弹出三选择）。
func is_decay_stage() -> bool:
	return not lifespan_depleted and lifespan_max_years > 0.0 \
		and lifespan_years / lifespan_max_years < BalanceConfig.DECAY_THRESHOLD_RATIO


# 三选择·继续修炼：生产 -50% 至寿元耗尽，期间每 60 秒 roll 一次天命奇遇。
func begin_decay_continuation() -> bool:
	if lifespan_depleted or decay_active or not is_decay_stage():
		return false
	decay_active = true
	fate_opportunity_at = Time.get_unix_time_from_system() + BalanceConfig.FATE_OPPORTUNITY_INTERVAL_SECONDS
	emit_state_changed()
	return true


# 三选择·渡劫续命：消耗 3 种渡劫丹各 1 + 当前境界寿元上限 20% 的灵石。
# 成功寿元 +50 年并解除衰败；失败寿元归零、强制轮回且奖励 ×80%。
func attempt_lifespan_tribulation() -> Dictionary:
	if lifespan_depleted or decay_active or not is_decay_stage():
		return {"ok": false, "reason": "当前不在天人五衰阶段"}
	if healing_pills < 1 or resistance_pills < 1 or enhancement_pills < 1:
		return {"ok": false, "reason": "需要治疗丹、抗性丹、强化丹各 1 枚"}
	var stone_cost := lifespan_max_years * BalanceConfig.LIFESPAN_TRIBULATION_STONE_RATIO
	if spirit_stones < stone_cost:
		return {"ok": false, "reason": "需要 %s 灵石" % NumberFormat.format(stone_cost)}
	spirit_stones -= stone_cost
	healing_pills -= 1
	resistance_pills -= 1
	enhancement_pills -= 1
	if randf() < BalanceConfig.LIFESPAN_TRIBULATION_SUCCESS_RATE:
		lifespan_years = minf(lifespan_max_years, lifespan_years + BalanceConfig.LIFESPAN_TRIBULATION_SUCCESS_YEARS)
		lifespan_depleted = lifespan_years <= 0.0
		tribulation_last_result = "渡劫续命成功：寿元 +%d 年，衰败解除" % int(BalanceConfig.LIFESPAN_TRIBULATION_SUCCESS_YEARS)
		emit_state_changed()
		return {"ok": true, "success": true, "reason": tribulation_last_result}
	# 失败：寿元归零、强制轮回且奖励 ×80%。
	lifespan_years = 0.0
	lifespan_depleted = true
	var milestones := maxi(0, talent_milestone_index - run_start_milestone_index)
	var promotions := maxi(0, promotion_count - run_start_promotion_count)
	var base_points := milestones * BalanceConfig.REINCARNATION_MILESTONE_POINTS + promotions * BalanceConfig.REINCARNATION_BREAKTHROUGH_POINTS
	var points := int(floor(float(base_points) * BalanceConfig.REINCARNATION_EARLY_PENALTY))
	_perform_reincarnation(points)
	return {"ok": true, "success": false, "reason": "渡劫续命失败：寿元耗尽，强制轮回（奖励 ×80%）"}


# 天命奇遇：继续修炼期间每 60 秒 roll 一次奇遇池（update_world 调用）。
func roll_fate_opportunity() -> Dictionary:
	if not decay_active:
		return {"found": false}
	var gift := _pick_weighted_fate_gift()
	var gift_id := String(gift.get("id", ""))
	match gift_id:
		"insight_scroll":
			_award_talent_points(int(gift.get("amount", 1)))
		"qi_jade":
			qi += float(gift.get("amount", 500.0))
		"permanent_production":
			fate_permanent_production += float(gift.get("amount", BalanceConfig.FATE_PERMANENT_PRODUCTION_BONUS))
		"lifespan_max":
			lifespan_max_years += float(gift.get("amount", 20.0))
			lifespan_years += float(gift.get("amount", 20.0))
	emit_state_changed()
	return {"found": true, "id": gift_id, "name": String(gift.get("name", "")), "desc": String(gift.get("desc", ""))}


func _pick_weighted_fate_gift() -> Dictionary:
	var total_weight := 0.0
	for gift in BalanceConfig.FATE_OPPORTUNITIES:
		total_weight += float(gift.get("weight", 1))
	var roll := randf() * total_weight
	var cumulative := 0.0
	for gift in BalanceConfig.FATE_OPPORTUNITIES:
		cumulative += float(gift.get("weight", 1))
		if roll < cumulative:
			return gift
	return BalanceConfig.FATE_OPPORTUNITIES[BalanceConfig.FATE_OPPORTUNITIES.size() - 1]


# ───────────────────────── 事件 / 季节查询 ─────────────────────────

func is_random_event_active() -> bool:
	return random_event != "" and random_event_until > Time.get_unix_time_from_system()


func get_random_event_display_name() -> String:
	if not is_random_event_active():
		return "无"
	match random_event:
		"auspicious":
			return "祥瑞降世"
		"dao_insight":
			return "天道感悟"
		"warlord_birthday":
			return "兵主诞辰"
		"ancient_cave":
			return "古修洞府"
		"heavenly_seed":
			return "天降灵种"
		"demon_qi":
			return "魔气侵染"
		"insect_king":
			return "噬金虫王"
	return "无"


## 古修洞府三选一：灵石 / 天赋点 / 随机宝箱。
func resolve_ancient_cave(choice: String) -> bool:
	if not (is_random_event_active() and random_event == "ancient_cave"):
		return false
	match choice:
		"stones":
			spirit_stones += BalanceConfig.ANCIENT_CAVE_STONES
		"talent":
			_award_talent_points(BalanceConfig.ANCIENT_CAVE_TALENT_POINTS)
		"treasure":
			var treasure := TreasureSystem.roll(_fate_mult())
			if treasure.get("found", false):
				_apply_treasure_reward(treasure)
			else:
				# 宝箱选择保底给灵石，避免三选一开空。
				spirit_stones += BalanceConfig.ANCIENT_CAVE_STONES
		_:
			return false
	_clear_random_event()
	emit_state_changed()
	return true


## 魔气侵染：花费当前灵石 10% 净化，提前结束事件。
func purify_demon_qi() -> bool:
	if not (is_random_event_active() and random_event == "demon_qi"):
		return false
	var cost := spirit_stones * BalanceConfig.DEMON_QI_PURIFY_COST_RATIO
	if spirit_stones < cost or cost <= 0.0:
		return false
	spirit_stones -= cost
	_clear_random_event()
	emit_state_changed()
	return true


# 事件提前结束或到期统一出口：清除事件并进入冷却。
func _clear_random_event() -> void:
	random_event = ""
	random_event_until = 0.0
	random_event_cooldown_until = Time.get_unix_time_from_system() + BalanceConfig.RANDOM_EVENT_COOLDOWN_SECONDS


# ───────────────────────── buff 查询 ─────────────────────────

func is_active_buff() -> bool:
	return active_buff_until > Time.get_unix_time_from_system()


func get_active_buff_remaining() -> float:
	return maxf(0.0, active_buff_until - Time.get_unix_time_from_system())


# ───────────────────────── 灵气浓度 / 自动修炼查询 ─────────────────────────

func get_qi_density() -> float:
	return AutomationSystem.compute_qi_density(fields, unlocked_fields)


# 自动修炼每秒产出（供 UI 展示）。未解锁返回 0，但仍返回当前浓度。
func get_auto_cultivation_per_sec() -> Dictionary:
	var density := get_qi_density()
	if lifespan_depleted or tribulation_active or not unlock_auto_cultivation:
		return {"cultivation": 0.0, "qi": 0.0, "density": density}
	var rates := automation.auto_rates(
		density,
		realm_index,
		event_prod_mult,
		event_cult_mult,
		RealmConfig.production_mult(realm_index),
		RealmConfig.cultivation_mult(realm_index),
		talent_multiplier("auto_cultivation_mult"),
		talent_multiplier("qi_gain_mult")
	)
	return {
		"cultivation": float(rates["cultivation_per_sec"]),
		"qi": float(rates["qi_per_sec"]),
		"density": density,
	}


# 离线结算预览：与离线时长无关，只根据长期计数计算尚未领取的差额。
func get_offline_settlement_preview(realm_override: int = -1) -> Dictionary:
	var total_talent := mini(
		BalanceConfig.OFFLINE_TALENT_POINT_CAP,
		mini(reincarnation_count, BalanceConfig.OFFLINE_REINCARNATION_TALENT_CAP)
		+ mini(floori(float(promotion_count) / BalanceConfig.OFFLINE_PROMOTION_DIVISOR), BalanceConfig.OFFLINE_PROMOTION_TALENT_CAP)
		+ mini(floori(float(total_harvest_count) / BalanceConfig.OFFLINE_HARVEST_DIVISOR), BalanceConfig.OFFLINE_HARVEST_TALENT_CAP)
	)
	var total_spirit_stone_units := (
		float(reincarnation_count) * BalanceConfig.OFFLINE_REINCARNATION_STONES
		+ float(promotion_count) * BalanceConfig.OFFLINE_PROMOTION_STONES
		+ float(total_harvest_count) * BalanceConfig.OFFLINE_HARVEST_STONES
	)
	var talent_reward := maxi(0, total_talent - offline_claimed_talent_points)
	var spirit_stone_units_reward := maxf(0.0, total_spirit_stone_units - offline_claimed_spirit_stone_units)
	var safe_realm := realm_index
	if realm_override >= 0:
		safe_realm = clampi(realm_override, 0, RealmConfig.realm_count() - 1)
	var production_mult := RealmConfig.production_mult(safe_realm)
	return {
		"active": not lifespan_depleted,
		"duration_independent": true,
		"talent_points": talent_reward,
		"spirit_stones": spirit_stone_units_reward * production_mult,
		"spirit_stone_units": spirit_stone_units_reward,
		"total_talent_points": total_talent,
		"total_spirit_stone_units": total_spirit_stone_units,
		"production_mult": production_mult,
		"reincarnation_count": reincarnation_count,
		"promotion_count": promotion_count,
		"total_harvest_count": total_harvest_count,
	}


# 由 SaveManager 在加载后调用；离线时长不参与本规则计算。
func apply_offline_report() -> void:
	var preview := get_offline_settlement_preview()
	var talent_reward := int(preview.get("talent_points", 0))
	var spirit_stones_reward := float(preview.get("spirit_stones", 0.0))
	if not lifespan_depleted:
		_award_talent_points(talent_reward)
		spirit_stones += spirit_stones_reward
		offline_claimed_talent_points = maxi(
			offline_claimed_talent_points,
		int(preview.get("total_talent_points", offline_claimed_talent_points))
		)
		offline_claimed_spirit_stone_units = maxf(
			offline_claimed_spirit_stone_units,
		float(preview.get("total_spirit_stone_units", offline_claimed_spirit_stone_units))
		)
	last_offline_report = {
		"cultivation": 0.0,
		"qi": 0.0,
		"talent_points": talent_reward if not lifespan_depleted else 0,
		"spirit_stones": spirit_stones_reward if not lifespan_depleted else 0.0,
		"pending_talent_points": talent_reward if lifespan_depleted else 0,
		"pending_spirit_stones": spirit_stones_reward if lifespan_depleted else 0.0,
		"credited_seconds": 0.0,
		"elapsed_seconds": 0.0,
		"duration_independent": true,
		"active": not lifespan_depleted,
		"lifespan_depleted": lifespan_depleted,
		"production_mult": float(preview.get("production_mult", 1.0)),
		"reincarnation_count": reincarnation_count,
		"promotion_count": promotion_count,
		"total_harvest_count": total_harvest_count,
	}
	emit_state_changed()
