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
var crop_inventory := {}
var realm_index := BalanceConfig.INITIAL_REALM_INDEX
var unlocked_fields := BalanceConfig.INITIAL_UNLOCKED_FIELDS
# 灵田结构（契约[C]）：每项 {crop_id, planted_at, ready_at, tier}。tier 0..3。
var fields: Array[Dictionary] = []

var insect_corpses := 0
# 寿元（年），按境界；归零后进入大限并暂停生产。商店可购买长生丹恢复。
var lifespan_max_years: float = BalanceConfig.LIFESPAN_YEARS_BY_REALM[BalanceConfig.INITIAL_REALM_INDEX]
var lifespan_years: float = BalanceConfig.LIFESPAN_YEARS_BY_REALM[BalanceConfig.INITIAL_REALM_INDEX]
var lifespan_depleted := false

# ───────────────────────── 天赋 / 长期进度 ─────────────────────────

var talent_points := 0
var talent_nodes: Dictionary = {"root": true}
var total_cultivation_earned := 0.0
var talent_milestone_index := 0
var achievements: Dictionary = {}
var achievement_points := 0

# 跨大限保留的长期统计。熟练度按“该作物实际收获次数”计数，
# 不因 start_new_run 清零；离线折算用下面三个计数器计算一次性差额。
var crop_proficiency: Dictionary = {}
var total_harvest_count := 0
var promotion_count := 0
var reincarnation_count := 0
var offline_claimed_talent_points := 0
var offline_claimed_spirit_stone_units := 0.0

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
var unlock_mind_flower := false
var unlock_sun_fruit := false
var unlock_heaven_lotus := false

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
	crop_inventory = {}
	realm_index = BalanceConfig.INITIAL_REALM_INDEX
	unlocked_fields = BalanceConfig.INITIAL_UNLOCKED_FIELDS
	# 灵雨、炼丹、配方、作物和自动化的初始解锁统一由 BalanceConfig 推导。
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


# 确保库存字典覆盖全部作物 id（缺则补 0），保持结构稳定。
func _ensure_inventory_keys() -> void:
	for crop_id in CropConfig.get_all():
		if not crop_inventory.has(crop_id):
			crop_inventory[crop_id] = 0
		if not crop_proficiency.has(crop_id):
			crop_proficiency[crop_id] = 0


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
	return not lifespan_depleted and realm_index + 1 < RealmConfig.realm_count() and cultivation >= get_next_realm_requirement()


# 突破：按 RealmConfig.breakthrough_rewards(new_realm_index) 应用奖励。
# production / cultivation 乘数不在这里设置——按当前境界实时查表。
func breakthrough() -> bool:
	if lifespan_depleted or not can_breakthrough():
		return false
	realm_index += 1
	# 突破延寿：提高寿元上限并补满当前寿元。
	lifespan_max_years = BalanceConfig.LIFESPAN_YEARS_BY_REALM[mini(realm_index, BalanceConfig.LIFESPAN_YEARS_BY_REALM.size() - 1)]
	lifespan_years = lifespan_max_years
	lifespan_depleted = false
	# 突破本身给点，修为里程碑另行给点。
	promotion_count += 1
	var reward_index := mini(realm_index, BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM.size() - 1)
	talent_points += int(BalanceConfig.TALENT_BREAKTHROUGH_POINTS_BY_REALM[reward_index])
	var rewards: Dictionary = RealmConfig.breakthrough_rewards(realm_index)
	_apply_breakthrough_rewards(rewards)
	realm_changed.emit()
	emit_state_changed()
	return true


# 把突破奖励字典应用到自身。奖励键名与 unlock_* 变量名严格对齐。
# 突破奖励只“解锁”、不“回收”：rewards 全默认 false，只有 true 项才生效，
# 不能把早前境界已解锁的能力（灵雨诀 / 各配方）覆盖回 false。
func _apply_breakthrough_rewards(rewards: Dictionary) -> void:
	for key in rewards:
		var value: Variant = rewards[key]
		if key == "unlock_spirit_rain":
			spirit_rain_unlocked = spirit_rain_unlocked or bool(value)
		elif key.begins_with("unlock_"):
			# 其余 unlock_* 奖励键与同名变量一一对应。
			set(key, bool(get(key)) or bool(value))


func get_breakthrough_rewards_for_current() -> Dictionary:
	return RealmConfig.breakthrough_rewards(realm_index)


# ───────────────────────── 倍率统一入口（契约[A]） ─────────────────────────

func talent_multiplier(effect_key: String) -> float:
	return TalentTree.multiplier(effect_key, talent_nodes)


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


func get_completed_achievement_count() -> int:
	return AchievementSystem.completed_count(self)


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


func get_season_multiplier(kind: String) -> float:
	return float(BalanceConfig.SEASONS[season_index].get(kind, BalanceConfig.DEFAULT_MULTIPLIER))


# ───────────────────────── 灵田 / 种植 / 收获 / 升档 ─────────────────────────

# 灵田 tier 乘数：凡1 / 灵10 / 宝100 / 仙1000。
func field_tier_mult(field_index: int) -> float:
	if field_index < 0 or field_index >= fields.size():
		return BalanceConfig.DEFAULT_MULTIPLIER
	var tier := clampi(int(fields[field_index].get("tier", 0)), 0, BalanceConfig.FIELD_TIER_MULTS.size() - 1)
	return BalanceConfig.FIELD_TIER_MULTS[tier]


func get_crop_options() -> Array:
	return CropConfig.get_unlocked(realm_index)


# 种植：校验空田、作物已解锁，写入 crop_id 与按倍率缩短后的成熟时间，重置该田虫害。
func plant_crop(field_index: int, crop_id: String) -> bool:
	if lifespan_depleted:
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
	if field_index < insect_events.size():
		insect_events[field_index] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": now + BalanceConfig.INSECT_INITIAL_DELAY_SECONDS}
	emit_state_changed()
	return true


# 点击加速：缩短当前作物的成熟倒计时，成熟后仍由自动收获统一结算。
func speed_up_crop(field_index: int) -> Dictionary:
	var empty := {"ok": false, "seconds": 0.0, "remaining": 0.0}
	if lifespan_depleted or field_index < 0 or field_index >= fields.size():
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
	if lifespan_depleted:
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
	}


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
		insect_events[field_index] = {
			"active": false,
			"attacks": 0,
			"pest_level": 0,
			"next_attack_at": planted_at + BalanceConfig.INSECT_INITIAL_DELAY_SECONDS,
		}

## 返回指定灵田槽位的购买费用与修行等级要求。
func get_field_slot_cost(field_index: int) -> Dictionary:
	if field_index < 0 or field_index >= BalanceConfig.FIELD_SLOT_COSTS.size():
		return {}
	return {"spirit_stones": SimulationSystem.slot_cost(self, realm_index, field_index)}


func can_buy_field_slot(field_index: int) -> bool:
	if lifespan_depleted or field_index != unlocked_fields or field_index <= 0 or field_index >= fields.size():
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
	if lifespan_depleted or field_index < 0 or field_index >= fields.size() or field_index >= unlocked_fields:
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


# 旧存档灵材迁移接口：当前主循环在收获时直接结算灵石，新收获不再写入灵材库存。
func sell_crop(crop_id: String, amount: int) -> bool:
	var crop: Variant = CropConfig.get_crop(crop_id)
	if crop == null or amount <= 0:
		return false
	if int(crop_inventory.get(crop_id, 0)) < amount:
		return false
	crop_inventory[crop_id] = int(crop_inventory.get(crop_id, 0)) - amount
	spirit_stones += float(crop["sell_price"]) * float(amount)
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


func add_talent_points(amount: int) -> void:
	if amount <= 0:
		return
	talent_points += amount
	emit_state_changed()


func get_crop_proficiency(crop_id: String) -> Dictionary:
	return BalanceConfig.crop_proficiency_reward(crop_id, int(crop_proficiency.get(crop_id, 0)))


func _record_crop_harvest(crop_id: String) -> void:
	var previous_count := int(crop_proficiency.get(crop_id, 0))
	var current_count := previous_count + 1
	crop_proficiency[crop_id] = current_count
	total_harvest_count += 1
	var new_talent_points := BalanceConfig.crop_proficiency_talent_points(crop_id, previous_count, current_count)
	if new_talent_points > 0:
		talent_points += new_talent_points


func _add_cultivation(amount: float) -> void:
	if amount <= 0.0:
		return
	cultivation += amount
	total_cultivation_earned += amount
	while talent_milestone_index < BalanceConfig.TALENT_MILESTONES.size() and total_cultivation_earned >= BalanceConfig.TALENT_MILESTONES[talent_milestone_index]:
		talent_points += BalanceConfig.TALENT_MILESTONE_POINTS
		talent_milestone_index += 1


# ───────────────────────── 法术 / 灵雨诀 ─────────────────────────

func is_spirit_rain_active(field_index: int) -> bool:
	return field_index >= 0 and field_index < spirit_rain_until.size() and spirit_rain_until[field_index] > Time.get_unix_time_from_system()


func cast_spirit_rain(
	field_index: int,
	duration := BalanceConfig.SPIRIT_RAIN_DURATION_SECONDS,
	cost := BalanceConfig.SPIRIT_RAIN_COST
	) -> bool:
	if lifespan_depleted or not spirit_rain_unlocked:
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
	if lifespan_depleted or realm_index < BalanceConfig.ADVANCED_COMBAT_REALM_INDEX:
		return false
	if field_index < 0 or field_index >= insect_events.size() or qi < cost or now < sword_art_cooldown_until:
		return false
	if not bool(insect_events[field_index].get("active", false)):
		return false
	qi -= cost
	sword_art_cooldown_until = now + cooldown
	insect_corpses += maxi(BalanceConfig.MIN_INSECT_CORPSES_PER_SWORD, int(insect_events[field_index].get("attacks", BalanceConfig.MIN_INSECT_CORPSES_PER_SWORD)))
	insect_events[field_index] = {
		"active": false,
		"attacks": 0,
		"pest_level": 0,
		"next_attack_at": now + BalanceConfig.GENGJIN_SWORD_CLEAR_COOLDOWN_SECONDS,
	}
	emit_state_changed()
	return true


func upgrade_guardian_array(field_index: int, cost := BalanceConfig.GUARDIAN_UPGRADE_COST) -> bool:
	if lifespan_depleted or realm_index < BalanceConfig.ADVANCED_COMBAT_REALM_INDEX:
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
			emit_state_changed()
			return
	# 四季轮换（180 秒/季）。
	if now - season_started_at >= BalanceConfig.SEASON_DURATION_SECONDS:
		season_started_at = now
		season_index = (season_index + 1) % BalanceConfig.SEASONS.size()
		emit_state_changed()
	# 随机事件三选一轮换。
	if random_event != "" and now >= random_event_until:
		random_event = ""
		random_event_cooldown_until = now + BalanceConfig.RANDOM_EVENT_COOLDOWN_SECONDS
		emit_state_changed()
	elif random_event == "" and now >= random_event_cooldown_until:
		random_event = String(BalanceConfig.EVENT_EVENTS[randi() % BalanceConfig.EVENT_EVENTS.size()])
		random_event_until = now + float(BalanceConfig.EVENT_DURATIONS.get(random_event, BalanceConfig.DEFAULT_EVENT_DURATION_SECONDS))
		emit_state_changed()
	# 事件分量由当前事件驱动。
	if is_random_event_active() and random_event == "auspicious":
		event_prod_mult = BalanceConfig.EVENT_PROD_BONUS
	else:
		event_prod_mult = BalanceConfig.DEFAULT_MULTIPLIER
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
	var purchases := int(shop_purchase_counts.get(item_id, 0))
	var cost := shop.get_cost(item_id, purchases)
	if cost <= 0.0 or spirit_stones < cost:
		return false
	var effect := String(item.get("effect", ""))
	var amount := float(item.get("amount", 0.0))
	if effect == "lifespan" and lifespan_years >= lifespan_max_years:
		return false
	# 大限期间生产暂停，生产 buff 购买无意义。
	if effect == "buff" and lifespan_depleted:
		return false
	spirit_stones -= cost
	match effect:
		"lifespan":
			lifespan_years = minf(lifespan_max_years, lifespan_years + amount)
			lifespan_depleted = lifespan_years <= 0.0
		"qi":
			qi += amount
		"talent_points":
			talent_points += int(amount)
		"buff":
			var now := Time.get_unix_time_from_system()
			# 连买刷新为较远结束时间，倍率取本次。
			active_buff_until = maxf(active_buff_until, now + float(item.get("duration", 0.0)))
			active_buff_mult = float(item.get("mult", 1.0))
		_:
			spirit_stones += cost
			return false
	shop_purchase_counts[item_id] = purchases + 1
	emit_state_changed()
	return true


# ───────────────────────── 寿元 ─────────────────────────

func restore_lifespan(amount: float) -> bool:
	if amount <= 0.0:
		return false
	var before := lifespan_years
	lifespan_years = minf(lifespan_max_years, lifespan_years + amount)
	lifespan_depleted = lifespan_years <= 0.0
	if lifespan_years <= before:
		return false
	emit_state_changed()
	return true


## 大限结算后的手动开局：清空本轮经营状态，但保留天赋树、未用天赋点和修为里程碑。
## 不自动触发，也不称为转世；玩家可以先去商店续命，确认结束后再开启新局。
func start_new_run() -> bool:
	if not lifespan_depleted:
		return false
	var saved_nodes := talent_nodes.duplicate(true)
	var saved_points := talent_points
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
	_reset_run_state()
	talent_nodes = saved_nodes
	talent_points = saved_points
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
	last_offline_report = {}
	_ensure_inventory_keys()
	emit_state_changed()
	return true


func increase_lifespan_max(amount: float) -> bool:
	if amount <= 0.0:
		return false
	lifespan_max_years += amount
	lifespan_years += amount
	lifespan_depleted = false
	emit_state_changed()
	return true


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
	return "无"


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
	if lifespan_depleted or not unlock_auto_cultivation:
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
		talent_points += talent_reward
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
