extends Node

signal state_changed
signal realm_changed

# 境界表来自 RealmConfig（scripts/systems/realm_config.gd），索引与 realm_index 对齐：
# 0 凡人 / 1 炼气 / 2 筑基 / 3 金丹。直接引用 RealmConfig.REALMS 保证数值单一来源。
# 子系统 AlchemySystem / AutomationSystem 通过 class_name 全局可用，无需 preload。

const SEASONS := [
	{"name": "春·万物萌发", "growth": 1.25, "yield": 1.0, "qi": 1.0},
	{"name": "夏·灵气鼎盛", "growth": 1.0, "yield": 1.0, "qi": 1.25},
	{"name": "秋·五谷丰登", "growth": 1.0, "yield": 1.25, "qi": 1.0},
	{"name": "冬·蛰伏养息", "growth": 1.0, "yield": 1.0, "qi": 1.0},
]

const PRACTITIONER_UPGRADES := {
	"wood_spirit": {"name": "木灵根", "cost": 20, "effect": "生长速度 +5%"},
	"qi_gathering": {"name": "聚气效率", "cost": 20, "effect": "灵气产出 +8%"},
	"farmer_insight": {"name": "农道悟性", "cost": 20, "effect": "丹药修为 +10%"},
	"longevity": {"name": "长生印记", "cost": 30, "effect": "本世寿元 +10天"},
}

# 作物表：sell_price 用于出售；growth / qi 用于种植与自动收获结算。
const CROPS := {
	"gathering_grass": {"name": "聚灵草", "sell_price": 5.0, "growth": 5.0, "qi": 3.0},
}

# 聚气丹走“花灵石购买”的旧手工业流程；筑基丹 / 金元丹由 AlchemySystem 炼制。
const PILLS := {
	"qi_gathering_pill": {"name": "聚气丹", "price": 5.0, "cultivation": 50.0},
}

const GRASS_ID := "gathering_grass"
const AUTO_BREW_INTERVAL := 5.0

var spirit_stones := 0.0
var qi := 0.0
var cultivation := 0.0
var crop_inventory := {"gathering_grass": 0}
var pills := {"qi_gathering_pill": 0, "foundation_pill": 0, "golden_pill": 0}
var realm_index := 0
var field_level := 1
var unlocked_fields := 1
var fields: Array[Dictionary] = []

var practitioner_upgrades := {"wood_spirit": 0, "qi_gathering": 0, "farmer_insight": 0, "longevity": 0}
var knowledge_points := 0
var reincarnation_count := 0
# 转世全局产出倍率，跨世保留：1 + 0.5 * reincarnation_count。
var reincarnation_mult := 1.0
# 金丹突破累乘的全局产出倍率（本世有效，转世重置）。
var global_prod_mult := 1.0
# 炼气突破带来的灵气产出倍率（本世有效，转世重置）。
var qi_gen_mult := 1.0
var lifespan_days := 100.0
var max_lifespan_days := 100.0

# 解锁标志位（由突破奖励驱动）。
var spirit_rain_unlocked := false
var auto_harvest_enabled := false
var alchemy_unlocked := false
var foundation_pill_unlocked := false
var golden_pill_unlocked := false
var spirit_vein_unlocked := false

# 子系统实例。
var alchemy := AlchemySystem.new()
var automation := AutomationSystem.new()

var spirit_rain_until: Array[float] = []
var guardian_array_level: Array[int] = []
var guardian_array_charges: Array[int] = []
var insect_events: Array[Dictionary] = []
var insect_corpses := 0
var season_index := 0
var season_started_at := 0.0
var random_event := ""
var random_event_until := 0.0
var random_event_cooldown_until := 0.0
var sword_art_cooldown_until := 0.0
var next_auto_brew_at := 0.0

# 离线结算摘要，由 SaveManager 加载后写入，供 UI 读取。
var last_offline_report: Dictionary = {}


func _ready() -> void:
	initialize_new_game()


func initialize_new_game() -> void:
	spirit_stones = 0.0
	qi = 0.0
	cultivation = 0.0
	crop_inventory = {"gathering_grass": 0}
	pills = {"qi_gathering_pill": 0, "foundation_pill": 0, "golden_pill": 0}
	fields.clear()
	spirit_rain_until.clear()
	guardian_array_level.clear()
	guardian_array_charges.clear()
	insect_events.clear()
	season_index = 0
	season_started_at = Time.get_unix_time_from_system()
	random_event = ""
	random_event_until = 0.0
	random_event_cooldown_until = Time.get_unix_time_from_system() + 180.0
	insect_corpses = 0
	next_auto_brew_at = 0.0
	lifespan_days = maxf(1.0, max_lifespan_days + practitioner_upgrades["longevity"] * 10.0)
	for i in range(3):
		fields.append({"crop_id": "", "planted_at": 0.0, "ready_at": 0.0})
		spirit_rain_until.append(0.0)
		guardian_array_level.append(1)
		guardian_array_charges.append(3)
		insect_events.append({
			"active": false,
			"attacks": 0,
			"pest_level": 0,
			"next_attack_at": Time.get_unix_time_from_system() + 180.0,
		})
	emit_state_changed()


func emit_state_changed() -> void:
	state_changed.emit()


func get_realm_name() -> String:
	return String(RealmConfig.REALMS[realm_index]["name"])


func get_next_realm_requirement() -> float:
	if realm_index + 1 >= RealmConfig.realm_count():
		return INF
	return float(RealmConfig.REALMS[realm_index + 1]["required_cultivation"])


func can_breakthrough() -> bool:
	return realm_index + 1 < RealmConfig.realm_count() and cultivation >= get_next_realm_requirement()


# 突破：按 RealmConfig.breakthrough_rewards(new_realm_index) 应用奖励。
func breakthrough() -> bool:
	if not can_breakthrough():
		return false
	realm_index += 1
	var rewards: Dictionary = RealmConfig.breakthrough_rewards(realm_index)
	var field_delta := int(rewards.get("field_delta", 0))
	if field_delta > 0:
		unlocked_fields = mini(3, unlocked_fields + field_delta)
	if bool(rewards.get("unlock_spirit_rain", false)):
		spirit_rain_unlocked = true
	if bool(rewards.get("auto_harvest", false)):
		auto_harvest_enabled = true
	if bool(rewards.get("unlock_alchemy", false)):
		alchemy_unlocked = true
	if bool(rewards.get("unlock_foundation_pill", false)):
		foundation_pill_unlocked = true
	if bool(rewards.get("unlock_golden_pill", false)):
		golden_pill_unlocked = true
	if bool(rewards.get("unlock_spirit_vein", false)):
		spirit_vein_unlocked = true
		automation.activate_spirit_vein()
	var qi_mult := float(rewards.get("qi_gen_mult", 1.0))
	if qi_mult != 1.0:
		qi_gen_mult *= qi_mult
	var global_delta := float(rewards.get("global_mult_delta", 1.0))
	if global_delta != 1.0:
		global_prod_mult *= global_delta
	realm_changed.emit()
	emit_state_changed()
	return true


# 返回当前境界那次突破的奖励描述，供 UI 展示。
func get_breakthrough_rewards_for_current() -> Dictionary:
	return RealmConfig.breakthrough_rewards(realm_index)


func get_season_name() -> String:
	return String(SEASONS[season_index]["name"])


func get_season_multiplier(kind: String) -> float:
	return float(SEASONS[season_index].get(kind, 1.0))


# 生长乘数 = 季节 × 木灵根 × 灵雨诀(×8) × reincarnation_mult × global_prod_mult。
func get_growth_multiplier(field_index: int) -> float:
	var multiplier := get_season_multiplier("growth")
	multiplier *= 1.0 + practitioner_upgrades["wood_spirit"] * 0.05
	if is_spirit_rain_active(field_index):
		multiplier *= RealmConfig.SPIRIT_RAIN_GROWTH_MULT
	multiplier *= reincarnation_mult * global_prod_mult
	return multiplier


func is_spirit_rain_active(field_index: int) -> bool:
	return field_index >= 0 and field_index < spirit_rain_until.size() and spirit_rain_until[field_index] > Time.get_unix_time_from_system()


func cast_spirit_rain(field_index: int, duration := 60.0, cost := 10.0) -> bool:
	if not spirit_rain_unlocked:
		return false
	if field_index < 0 or field_index >= fields.size() or qi < cost:
		return false
	qi -= cost
	spirit_rain_until[field_index] = maxf(spirit_rain_until[field_index], Time.get_unix_time_from_system() + duration)
	emit_state_changed()
	return true


func cast_gengjin_sword(field_index: int, cost := 20.0, cooldown := 120.0) -> bool:
	var now := Time.get_unix_time_from_system()
	if realm_index < 2:
		return false
	if field_index < 0 or field_index >= insect_events.size() or qi < cost or now < sword_art_cooldown_until:
		return false
	if not bool(insect_events[field_index].get("active", false)):
		return false
	qi -= cost
	sword_art_cooldown_until = now + cooldown
	insect_corpses += maxi(1, int(insect_events[field_index].get("attacks", 1)))
	insect_events[field_index] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": now + 300.0}
	emit_state_changed()
	return true


func upgrade_guardian_array(field_index: int, cost := 100.0) -> bool:
	if realm_index < 2:
		return false
	if field_index < 0 or field_index >= guardian_array_level.size() or spirit_stones < cost:
		return false
	spirit_stones -= cost
	guardian_array_level[field_index] += 1
	guardian_array_charges[field_index] = 2 + guardian_array_level[field_index]
	emit_state_changed()
	return true


func harvest_crop(field_index: int, crop_id: String, amount: int, qi_amount: float) -> bool:
	if field_index < 0 or field_index >= fields.size() or amount <= 0:
		return false
	crop_inventory[crop_id] = int(crop_inventory.get(crop_id, 0)) + amount
	var qi_gain := qi_amount
	qi_gain *= get_season_multiplier("qi")
	qi_gain *= 1.0 + practitioner_upgrades["qi_gathering"] * 0.08
	qi_gain *= qi_gen_mult
	qi_gain *= reincarnation_mult * global_prod_mult
	qi += qi_gain
	emit_state_changed()
	return true


func sell_crop(crop_id: String, amount: int) -> bool:
	if not CROPS.has(crop_id) or amount <= 0 or int(crop_inventory.get(crop_id, 0)) < amount:
		return false
	var event_multiplier := 2.0 if is_random_event_active() and random_event == "auspicious" else 1.0
	var final_multiplier := get_season_multiplier("yield") * event_multiplier
	crop_inventory[crop_id] = int(crop_inventory.get(crop_id, 0)) - amount
	spirit_stones += float(CROPS[crop_id]["sell_price"]) * amount * final_multiplier
	emit_state_changed()
	return true


func buy_pill(pill_id: String, amount: int = 1) -> bool:
	if not PILLS.has(pill_id) or amount <= 0:
		return false
	var total_cost := float(PILLS[pill_id]["price"]) * amount
	if spirit_stones < total_cost:
		return false
	spirit_stones -= total_cost
	pills[pill_id] = int(pills.get(pill_id, 0)) + amount
	emit_state_changed()
	return true


# 通用丹药服用：聚气丹 / 筑基丹 / 金元丹均可服用，修为基础值来自 PILLS 或炼丹配方。
func consume_pill(pill_id: String, amount: int = 1) -> bool:
	if amount <= 0 or int(pills.get(pill_id, 0)) < amount:
		return false
	var cultivation_per := _get_pill_cultivation(pill_id)
	if cultivation_per < 0.0:
		return false
	var event_multiplier := 2.0 if is_random_event_active() and random_event == "auspicious" else 1.0
	var cultivation_multiplier: float = (1.0 + practitioner_upgrades["farmer_insight"] * 0.10) * event_multiplier
	pills[pill_id] = int(pills.get(pill_id, 0)) - amount
	cultivation += cultivation_per * amount * cultivation_multiplier
	emit_state_changed()
	return true


func _get_pill_cultivation(pill_id: String) -> float:
	if PILLS.has(pill_id):
		return float(PILLS[pill_id]["cultivation"])
	for recipe in alchemy.get_recipes():
		if String(recipe.get("id", "")) == pill_id:
			return float(recipe.get("cultivation", 0.0))
	return -1.0


# 用灵草炼制筑基丹 / 金元丹（配方见 AlchemySystem.RECIPES）。扣草与加丹由本方法应用。
func brew_pill(recipe_id: String) -> bool:
	var grass_count := int(crop_inventory.get(GRASS_ID, 0))
	var result: Dictionary = alchemy.brew(recipe_id, grass_count, realm_index)
	if not bool(result.get("ok", false)):
		return false
	var cost := int(result.get("grass_cost", 0))
	crop_inventory[GRASS_ID] = grass_count - cost
	var pill_id := String(result.get("pill_id", ""))
	pills[pill_id] = int(pills.get(pill_id, 0)) + 1
	emit_state_changed()
	return true


func can_brew_pill(recipe_id: String) -> bool:
	return alchemy.can_brew(recipe_id, int(crop_inventory.get(GRASS_ID, 0)), realm_index)


func get_recipe_name(recipe_id: String) -> String:
	for recipe in alchemy.get_recipes():
		if String(recipe.get("id", "")) == recipe_id:
			return String(recipe.get("name", recipe_id))
	return recipe_id


func get_recipe_grass_cost(recipe_id: String) -> int:
	for recipe in alchemy.get_recipes():
		if String(recipe.get("id", "")) == recipe_id:
			return int(recipe.get("grass_cost", 0))
	return 0


func add_rewards(stones: float, qi_amount: float, cultivation_amount: float, yield_multiplier := 1.0) -> void:
	# 遗留实现（旧收获流程），新系统不应再调用。
	var event_multiplier := 2.0 if is_random_event_active() and random_event == "auspicious" else 1.0
	var final_multiplier := yield_multiplier * get_season_multiplier("yield") * event_multiplier
	spirit_stones += stones * final_multiplier
	qi += qi_amount * get_season_multiplier("qi") * (1.0 + practitioner_upgrades["qi_gathering"] * 0.08) * event_multiplier
	cultivation += cultivation_amount * (1.0 + practitioner_upgrades["farmer_insight"] * 0.10) * event_multiplier
	emit_state_changed()


func update_world(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	# 原型中 1 个真实小时对应 1 个游戏日，避免按帧消耗寿元。
	lifespan_days = maxf(0.0, lifespan_days - delta / 3600.0)
	if now - season_started_at >= 180.0:
		season_started_at = now
		season_index = (season_index + 1) % SEASONS.size()
		emit_state_changed()
	if random_event != "" and now >= random_event_until:
		random_event = ""
		random_event_cooldown_until = now + 180.0
		emit_state_changed()
	elif random_event == "" and now >= random_event_cooldown_until:
		random_event = "auspicious" if randi() % 2 == 0 else "warlord_birthday"
		random_event_until = now + 60.0
		emit_state_changed()
	for i in range(insect_events.size()):
		if String(fields[i].get("crop_id", "")) == "":
			continue
		var event: Dictionary = insect_events[i]
		if not bool(event.get("active", false)) and now >= float(event.get("next_attack_at", 0.0)):
			event["active"] = true
			event["next_attack_at"] = now + 60.0
			insect_events[i] = event
			emit_state_changed()
		elif bool(event.get("active", false)) and now >= float(event.get("next_attack_at", 0.0)):
			register_insect_attack(i)
			event = insect_events[i]
			event["next_attack_at"] = now + (30.0 if random_event == "warlord_birthday" and is_random_event_active() else 60.0)
			insect_events[i] = event

	# 灵脉被动产出（金丹解锁）：tick 用 reincarnation_mult，结果再乘 global_prod_mult。
	if automation.is_spirit_vein_active():
		var gain: Dictionary = automation.tick(delta, reincarnation_mult)
		cultivation += float(gain.get("cultivation", 0.0)) * global_prod_mult
		qi += float(gain.get("qi", 0.0)) * global_prod_mult

	# 自动收获（炼气解锁）：成熟地块自动收获并立即补种同种作物，循环不中断。
	if auto_harvest_enabled:
		_auto_harvest(now)

	# 自动炼丹（金丹解锁）：每 AUTO_BREW_INTERVAL 秒尝试炼一枚筑基丹。
	if spirit_vein_unlocked and now >= next_auto_brew_at:
		if alchemy.can_brew("foundation_pill", int(crop_inventory.get(GRASS_ID, 0)), realm_index):
			brew_pill("foundation_pill")
		next_auto_brew_at = now + AUTO_BREW_INTERVAL


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
		var crop: Dictionary = CROPS.get(crop_id, {})
		var pest_level := int(insect_events[i].get("pest_level", 0))
		var yield_amount := maxi(1, int(floor(maxf(0.0, 1.0 - pest_level * 0.25))))
		var qi_amount := float(crop.get("qi", 0.0))
		harvest_crop(i, crop_id, yield_amount, qi_amount)
		# 自动补种：收完立刻种回同一种作物，并重置该田虫害，保证生产循环不中断。
		# 行为与手动种植一致（手动种植也会在落种时把该田虫害事件重置为 180 秒后再来）。
		insect_events[i] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": now + 180.0}
		var growth_time := float(crop.get("growth", 5.0)) / get_growth_multiplier(i)
		fields[i] = {"crop_id": crop_id, "planted_at": now, "ready_at": now + growth_time}


func register_insect_attack(field_index: int) -> void:
	var event: Dictionary = insect_events[field_index]
	var attack_count := 2 if random_event == "warlord_birthday" and is_random_event_active() else 1
	for _n in range(attack_count):
		event["attacks"] = int(event.get("attacks", 0)) + 1
		if guardian_array_charges[field_index] > 0:
			guardian_array_charges[field_index] -= 1
		else:
			event["pest_level"] = mini(3, int(event.get("pest_level", 0)) + 1)
	event["active"] = true
	insect_events[field_index] = event
	emit_state_changed()


func sell_insect_corpses() -> bool:
	if insect_corpses <= 0:
		return false
	spirit_stones += insect_corpses * 8.0
	insect_corpses = 0
	emit_state_changed()
	return true


func can_buy_practitioner_upgrade(upgrade_id: String) -> bool:
	if not PRACTITIONER_UPGRADES.has(upgrade_id):
		return false
	var definition: Dictionary = PRACTITIONER_UPGRADES[upgrade_id]
	var current_level: int = practitioner_upgrades.get(upgrade_id, 0)
	var cost := int(ceil(float(definition["cost"]) * (1.0 + current_level * 0.5)))
	return knowledge_points >= cost


func buy_practitioner_upgrade(upgrade_id: String) -> bool:
	if not can_buy_practitioner_upgrade(upgrade_id):
		return false
	var definition: Dictionary = PRACTITIONER_UPGRADES[upgrade_id]
	var current_level: int = practitioner_upgrades.get(upgrade_id, 0)
	var cost := int(ceil(float(definition["cost"]) * (1.0 + current_level * 0.5)))
	knowledge_points -= cost
	practitioner_upgrades[upgrade_id] = current_level + 1
	emit_state_changed()
	return true


func get_knowledge_for_reincarnation() -> int:
	return int((realm_index + 1) * 10 + cultivation / 100.0 + insect_corpses + (5 if lifespan_days > 0.0 else 0.0))


# 转世：保留知识点 / 专精 / 转世次数与倍率；重置本世资源、境界、灵田与解锁标志。
func reincarnate() -> bool:
	knowledge_points += get_knowledge_for_reincarnation()
	reincarnation_count += 1
	reincarnation_mult = 1.0 + 0.5 * float(reincarnation_count)
	global_prod_mult = 1.0
	qi_gen_mult = 1.0
	spirit_rain_unlocked = false
	auto_harvest_enabled = false
	alchemy_unlocked = false
	foundation_pill_unlocked = false
	golden_pill_unlocked = false
	spirit_vein_unlocked = false
	realm_index = 0
	field_level = 1
	unlocked_fields = 1
	# 新建灵脉实例，使 spirit_vein_active 归 false。
	automation = AutomationSystem.new()
	initialize_new_game()
	# initialize_new_game 会把灵石清零，转世给一点启动资金。
	spirit_stones = 100.0
	emit_state_changed()
	return true


func is_random_event_active() -> bool:
	return random_event != "" and random_event_until > Time.get_unix_time_from_system()


func get_random_event_display_name() -> String:
	if not is_random_event_active():
		return "无"
	return "祥瑞降世" if random_event == "auspicious" else "兵主诞辰"


# 灵脉每秒产出（基础 × 转世倍率 × 全局倍率），未激活返回 0，供 UI 展示。
func get_spirit_vein_per_sec() -> Dictionary:
	if not automation.is_spirit_vein_active():
		return {"cultivation": 0.0, "qi": 0.0}
	var mult := reincarnation_mult * global_prod_mult
	return {
		"cultivation": AutomationSystem.BASE_CULTIVATION_PER_SEC * mult,
		"qi": AutomationSystem.BASE_QI_PER_SEC * mult,
	}


# 由 SaveManager 在加载后调用：结算离线灵脉产出并累加进 cultivation/qi，
# 同时把摘要写入 last_offline_report 供 UI 展示。
func apply_offline_report(saved_at: float) -> void:
	var now := Time.get_unix_time_from_system()
	var elapsed := maxf(0.0, now - saved_at)
	var report: Dictionary = automation.compute_offline(elapsed, reincarnation_mult)
	var offline_cultivation := float(report.get("cultivation", 0.0)) * global_prod_mult
	var offline_qi := float(report.get("qi", 0.0)) * global_prod_mult
	cultivation += offline_cultivation
	qi += offline_qi
	last_offline_report = {
		"cultivation": offline_cultivation,
		"qi": offline_qi,
		"capped": bool(report.get("capped", false)),
		"credited_seconds": float(report.get("credited_seconds", 0.0)),
		"elapsed_seconds": elapsed,
		"cap_seconds": AutomationSystem.OFFLINE_CAP_SECONDS,
		"active": automation.is_spirit_vein_active(),
	}
	emit_state_changed()
