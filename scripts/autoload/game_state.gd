extends Node

signal state_changed
signal realm_changed

# 境界表来自 RealmConfig（scripts/systems/realm_config.gd），索引与 realm_index 对齐：
# 0 凡人 / 1 炼气 / 2 筑基 / 3 金丹。境界同时是 Gate（突破门槛）与 Modifier
#（production 作用于生长/产量/灵气/自动修炼灵气；cultivation 作用于丹药修为/自动修炼修为）。
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

# 聚气丹走“花灵石购买”的旧手工业流程；筑基丹 / 金元丹 / 狂暴丹由 AlchemySystem 炼制。
const PILLS := {
	"qi_gathering_pill": {"name": "聚气丹", "price": 5.0, "cultivation": 50.0},
}

const GRASS_ID := "gathering_grass"
const AUTO_BREW_INTERVAL := 5.0
# 田升级与灵脉化的灵石消耗。
const FIELD_UPGRADE_BASE_COST := 50.0
const SPIRIT_VEINIFY_COST := 500.0
# 事件爆发窗：祥瑞降世期间全局生产倍率。
const AUSPICIOUS_PRODUCTION_MULT := 5.0
const RANDOM_EVENT_DURATION := 60.0

var spirit_stones := 0.0
var qi := 0.0
var cultivation := 0.0
var crop_inventory := {"gathering_grass": 0}
# 丹药库存：聚气丹（灵石购买）+ 筑基/金元/狂暴丹（炼丹炉产出）。
var pills := {"qi_gathering_pill": 0, "foundation_pill": 0, "golden_pill": 0, "frenzy_pill": 0}
var realm_index := 0
var unlocked_fields := 1
# 灵田结构（契约[2]）：每田自带 level/quality/spirit_vein，决定 field_yield_mult 与灵气浓度。
var fields: Array[Dictionary] = []

var practitioner_upgrades := {"wood_spirit": 0, "qi_gathering": 0, "farmer_insight": 0, "longevity": 0}
var knowledge_points := 0
var reincarnation_count := 0
# 转世全局产出倍率，跨世保留：1 + 0.5 * reincarnation_count。
var reincarnation_mult := 1.0
var lifespan_days := 100.0
var max_lifespan_days := 100.0

# v2 新增：事件爆发窗全局生产倍率（祥瑞降世期间 =5.0，其余 =1.0）。
var event_production_mult := 1.0
# v2 新增：狂暴丹 active_buff。active_buff_until > now 时 active_buff_mult 生效。
var active_buff_until := 0.0
var active_buff_mult := 1.0

# 解锁标志位（由突破奖励 RealmConfig.breakthrough_rewards 驱动）。
var spirit_rain_unlocked := false
var auto_harvest_enabled := false
var alchemy_unlocked := false
var foundation_pill_unlocked := false
var golden_pill_unlocked := false
# v2 新增解锁：灵田升级（筑基）、自动修炼（筑基）、灵脉化田（金丹）。
var field_upgrade_unlocked := false
var auto_cultivation_unlocked := false
var spirit_veinify_unlocked := false

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
	pills = {"qi_gathering_pill": 0, "foundation_pill": 0, "golden_pill": 0, "frenzy_pill": 0}
	fields.clear()
	spirit_rain_until.clear()
	guardian_array_level.clear()
	guardian_array_charges.clear()
	insect_events.clear()
	season_index = 0
	season_started_at = Time.get_unix_time_from_system()
	random_event = ""
	random_event_until = 0.0
	event_production_mult = 1.0
	active_buff_until = 0.0
	active_buff_mult = 1.0
	random_event_cooldown_until = Time.get_unix_time_from_system() + 180.0
	insect_corpses = 0
	next_auto_brew_at = 0.0
	lifespan_days = maxf(1.0, max_lifespan_days + practitioner_upgrades["longevity"] * 10.0)
	for i in range(3):
		# 每田初始化为新结构：空作物、level=1、quality=1.0、非灵脉。
		fields.append({
			"crop_id": "",
			"planted_at": 0.0,
			"ready_at": 0.0,
			"level": 1,
			"quality": 1.0,
			"spirit_vein": false,
		})
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
# production / cultivation 乘数不在这里设置——它们按当前境界实时查表。
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
	if bool(rewards.get("unlock_field_upgrade", false)):
		field_upgrade_unlocked = true
	if bool(rewards.get("unlock_auto_cultivation", false)):
		auto_cultivation_unlocked = true
	if bool(rewards.get("unlock_golden_pill", false)):
		golden_pill_unlocked = true
	if bool(rewards.get("unlock_spirit_veinify", false)):
		spirit_veinify_unlocked = true
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


# 田自身产量乘数 = quality * (1 + (level-1)*0.2)（契约[2]）。
func field_yield_mult(field_index: int) -> float:
	if field_index < 0 or field_index >= fields.size():
		return 1.0
	var data: Dictionary = fields[field_index]
	var level := int(data.get("level", 1))
	var quality := float(data.get("quality", 1.0))
	return quality * (1.0 + float(level - 1) * 0.2)


# 狂暴丹 active_buff 是否生效中。
func is_active_buff() -> bool:
	return active_buff_until > Time.get_unix_time_from_system()


# 当前 active_buff 剩余秒数（<=0 表示未生效）。
func get_active_buff_remaining() -> float:
	return maxf(0.0, active_buff_until - Time.get_unix_time_from_system())


# 生长乘数（契约[3]）= 季节 × 木灵根 × 灵雨诀(×8) × production_mult × reincarnation_mult
#                         × event_production_mult × (active_buff?active_buff_mult:1)。
func get_growth_multiplier(field_index: int) -> float:
	var multiplier := get_season_multiplier("growth")
	multiplier *= 1.0 + practitioner_upgrades["wood_spirit"] * 0.05
	if is_spirit_rain_active(field_index):
		multiplier *= RealmConfig.SPIRIT_RAIN_GROWTH_MULT
	multiplier *= RealmConfig.production_mult(realm_index)
	multiplier *= reincarnation_mult
	multiplier *= event_production_mult
	if is_active_buff():
		multiplier *= active_buff_mult
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


# 灵田升级（筑基解锁）：消耗 50*level 灵石，level += 1，提升 field_yield_mult。
func upgrade_field(field_index: int) -> bool:
	if not field_upgrade_unlocked:
		return false
	if field_index < 0 or field_index >= fields.size():
		return false
	var data: Dictionary = fields[field_index]
	var level := int(data.get("level", 1))
	var cost := FIELD_UPGRADE_BASE_COST * float(level)
	if spirit_stones < cost:
		return false
	spirit_stones -= cost
	data["level"] = level + 1
	fields[field_index] = data
	emit_state_changed()
	return true


# 灵脉化田（金丹解锁）：消耗 500 灵石，quality *= 3，spirit_vein=true（贡献 +10 灵气浓度）。
func spirit_veinify_field(field_index: int) -> bool:
	if not spirit_veinify_unlocked:
		return false
	if field_index < 0 or field_index >= fields.size():
		return false
	var data: Dictionary = fields[field_index]
	if bool(data.get("spirit_vein", false)):
		return false
	if spirit_stones < SPIRIT_VEINIFY_COST:
		return false
	spirit_stones -= SPIRIT_VEINIFY_COST
	data["quality"] = float(data.get("quality", 1.0)) * 3.0
	data["spirit_vein"] = true
	fields[field_index] = data
	emit_state_changed()
	return true


# 收获结算（契约[3]）。产量与灵气均在此方法内统一计算，外部仅需传入田索引。
# 返回 {"ok": bool, "crop_id": String, "amount": int, "qi": float} 供 UI 反馈。
func harvest_crop(field_index: int) -> Dictionary:
	var empty := {"ok": false, "crop_id": "", "amount": 0, "qi": 0.0}
	if field_index < 0 or field_index >= fields.size():
		return empty
	var data: Dictionary = fields[field_index]
	var crop_id := String(data.get("crop_id", ""))
	if crop_id == "" or not CROPS.has(crop_id):
		return empty
	var crop: Dictionary = CROPS[crop_id]
	# 产量 = 1 * field_yield_mult * season.yield * event_production_mult * buff * pest_factor。
	var pest_level := int(insect_events[field_index].get("pest_level", 0))
	var pest_factor := maxf(0.0, 1.0 - float(pest_level) * 0.25)
	var buff_mult := active_buff_mult if is_active_buff() else 1.0
	var yield_amount := maxi(1, int(floor(
		field_yield_mult(field_index)
		* get_season_multiplier("yield")
		* event_production_mult
		* buff_mult
		* pest_factor
	)))
	crop_inventory[crop_id] = int(crop_inventory.get(crop_id, 0)) + yield_amount
	# 灵气 = crop.qi * production_mult * reincarnation_mult * event_production_mult * season.qi * (1+qi_gathering*0.08)。
	var qi_gain := float(crop.get("qi", 0.0))
	qi_gain *= RealmConfig.production_mult(realm_index)
	qi_gain *= reincarnation_mult
	qi_gain *= event_production_mult
	qi_gain *= get_season_multiplier("qi")
	qi_gain *= 1.0 + practitioner_upgrades["qi_gathering"] * 0.08
	qi += qi_gain
	emit_state_changed()
	return {"ok": true, "crop_id": crop_id, "amount": yield_amount, "qi": qi_gain}


# 出售灵材（契约[6]）：去掉旧的 auspicious ×2 散落逻辑，event 加成已在收获时计入产量。
func sell_crop(crop_id: String, amount: int) -> bool:
	if not CROPS.has(crop_id) or amount <= 0 or int(crop_inventory.get(crop_id, 0)) < amount:
		return false
	crop_inventory[crop_id] = int(crop_inventory.get(crop_id, 0)) - amount
	spirit_stones += float(CROPS[crop_id]["sell_price"]) * amount
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


# 通用丹药服用（契约[4]）：
#   - 狂暴丹(frenzy_pill)：不加修为，改为设置 active_buff_until/active_buff_mult。
#   - 其余（聚气/筑基/金元）：修为 = base * cultivation_mult * (1 + farmer_insight*0.10)。
func consume_pill(pill_id: String, amount: int = 1) -> bool:
	if amount <= 0 or int(pills.get(pill_id, 0)) < amount:
		return false
	# buff 类丹药：设置 active_buff，不加工区修为。
	if alchemy.is_buff_recipe(pill_id):
		var buff: Dictionary = alchemy.get_buff(pill_id)
		var mult := float(buff.get("mult", 1.0))
		var duration := float(buff.get("duration", 0.0))
		pills[pill_id] = int(pills.get(pill_id, 0)) - amount
		var now := Time.get_unix_time_from_system()
		# 多次服用刷新为较远结束时间，倍率取本次。
		active_buff_until = maxf(active_buff_until, now + duration * float(amount))
		active_buff_mult = mult
		emit_state_changed()
		return true
	var base := _get_pill_cultivation(pill_id)
	if base < 0.0:
		return false
	pills[pill_id] = int(pills.get(pill_id, 0)) - amount
	var cultivation_multiplier: float = RealmConfig.cultivation_mult(realm_index) * (1.0 + float(practitioner_upgrades["farmer_insight"]) * 0.10)
	cultivation += base * float(amount) * cultivation_multiplier
	emit_state_changed()
	return true


# 丹药修为基础值：聚气丹走 PILLS；筑基/金元走 AlchemySystem 配方的 output_cultivation。
func _get_pill_cultivation(pill_id: String) -> float:
	if PILLS.has(pill_id):
		return float(PILLS[pill_id]["cultivation"])
	var recipe: Dictionary = alchemy.get_recipe(pill_id)
	if not recipe.is_empty():
		return float(recipe.get("output_cultivation", 0.0))
	return -1.0


# 用灵草炼制筑基/金元/狂暴丹（配方见 AlchemySystem.RECIPES）。扣草与加丹由本方法应用。
# 新签名：brew/can_brew 第 2 个参数是 crop_inventory:Dictionary。
func brew_pill(recipe_id: String) -> bool:
	var result: Dictionary = alchemy.brew(recipe_id, crop_inventory, realm_index)
	if not bool(result.get("ok", false)):
		return false
	var inputs: Dictionary = result.get("inputs", {})
	for crop_id in inputs:
		crop_inventory[crop_id] = int(crop_inventory.get(crop_id, 0)) - int(inputs[crop_id])
	var pill_id := String(result.get("pill_id", ""))
	pills[pill_id] = int(pills.get(pill_id, 0)) + 1
	emit_state_changed()
	return true


func can_brew_pill(recipe_id: String) -> bool:
	return alchemy.can_brew(recipe_id, crop_inventory, realm_index)


func get_recipe_name(recipe_id: String) -> String:
	var recipe: Dictionary = alchemy.get_recipe(recipe_id)
	if not recipe.is_empty():
		return String(recipe.get("name", recipe_id))
	return recipe_id


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
		random_event_until = now + RANDOM_EVENT_DURATION
		emit_state_changed()
	# 事件爆发窗（契约[6]）：祥瑞降世期间生产 ×5，其余（含兵主诞辰）归 1.0。
	event_production_mult = AUSPICIOUS_PRODUCTION_MULT if (is_random_event_active() and random_event == "auspicious") else 1.0

	# 噬金虫逻辑（保留，兵主诞辰期间攻击数 ×2、攻击间隔减半）。
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

	# 自动修炼（筑基解锁，契约[5]）：灵气浓度驱动，每帧累加修为/灵气。
	if auto_cultivation_unlocked:
		var density := AutomationSystem.compute_qi_density(fields, unlocked_fields)
		var rates := automation.auto_rates(
			density,
			realm_index,
			reincarnation_mult,
			event_production_mult,
			RealmConfig.production_mult(realm_index),
			RealmConfig.cultivation_mult(realm_index)
		)
		cultivation += float(rates["cultivation_per_sec"]) * delta
		qi += float(rates["qi_per_sec"]) * delta

	# 自动收获（炼气解锁）：成熟地块自动收获并立即补种同种作物，循环不中断。
	if auto_harvest_enabled:
		_auto_harvest(now)

	# 自动炼丹（金丹解锁）：每 AUTO_BREW_INTERVAL 秒尝试炼一枚筑基丹。
	if spirit_veinify_unlocked and now >= next_auto_brew_at:
		if alchemy.can_brew("foundation_pill", crop_inventory, realm_index):
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
		harvest_crop(i)
		# 自动补种：收完立刻种回同一种作物，并重置该田虫害，保证生产循环不中断。
		# 保留田的 level/quality/spirit_vein，只重置作物与时间。
		insect_events[i] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": now + 180.0}
		var crop: Dictionary = CROPS.get(crop_id, {})
		var growth_time := float(crop.get("growth", 5.0)) / get_growth_multiplier(i)
		data["crop_id"] = crop_id
		data["planted_at"] = now
		data["ready_at"] = now + growth_time
		fields[i] = data


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


# 转世（契约[7]）：保留知识点/专精/转世次数与倍率；重置本世资源、境界、灵田与解锁标志。
func reincarnate() -> bool:
	knowledge_points += get_knowledge_for_reincarnation()
	reincarnation_count += 1
	reincarnation_mult = 1.0 + 0.5 * float(reincarnation_count)
	# 重置本世解锁标志。
	spirit_rain_unlocked = false
	auto_harvest_enabled = false
	alchemy_unlocked = false
	foundation_pill_unlocked = false
	field_upgrade_unlocked = false
	auto_cultivation_unlocked = false
	golden_pill_unlocked = false
	spirit_veinify_unlocked = false
	# 重置 buff 与事件倍率。
	active_buff_until = 0.0
	active_buff_mult = 1.0
	event_production_mult = 1.0
	realm_index = 0
	unlocked_fields = 1
	# initialize_new_game 会把每田重置为 level=1/quality=1.0/spirit_vein=false/作物空。
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


# 灵气浓度（契约[5]）：种植中普通田 +1，灵脉化田 +10。
func get_qi_density() -> float:
	return AutomationSystem.compute_qi_density(fields, unlocked_fields)


# 自动修炼每秒产出（供 UI 展示）。未解锁返回 0，但仍返回当前浓度。
func get_auto_cultivation_per_sec() -> Dictionary:
	var density := get_qi_density()
	if not auto_cultivation_unlocked:
		return {"cultivation": 0.0, "qi": 0.0, "density": density}
	var rates := automation.auto_rates(
		density,
		realm_index,
		reincarnation_mult,
		event_production_mult,
		RealmConfig.production_mult(realm_index),
		RealmConfig.cultivation_mult(realm_index)
	)
	return {
		"cultivation": float(rates["cultivation_per_sec"]),
		"qi": float(rates["qi_per_sec"]),
		"density": density,
	}


# 由 SaveManager 在加载后调用：用新 compute_offline 签名结算离线自动修炼（筑基起生效）。
func apply_offline_report(saved_at: float) -> void:
	var now := Time.get_unix_time_from_system()
	var elapsed := maxf(0.0, now - saved_at)
	var density := get_qi_density()
	# 加载时 event_production_mult 尚未运行 update_world，按 1.0 结算离线。
	var report: Dictionary = automation.compute_offline(
		density,
		realm_index,
		reincarnation_mult,
		event_production_mult,
		RealmConfig.production_mult(realm_index),
		RealmConfig.cultivation_mult(realm_index),
		elapsed
	)
	var offline_cultivation := float(report.get("cultivation", 0.0))
	var offline_qi := float(report.get("qi", 0.0))
	cultivation += offline_cultivation
	qi += offline_qi
	last_offline_report = {
		"cultivation": offline_cultivation,
		"qi": offline_qi,
		"capped": bool(report.get("capped", false)),
		"credited_seconds": float(report.get("credited_seconds", 0.0)),
		"elapsed_seconds": elapsed,
		"cap_seconds": AutomationSystem.OFFLINE_CAP_SECONDS,
		# 筑基起自动修炼才生效，用于 UI 判断是否展示离线摘要。
		"active": auto_cultivation_unlocked,
		"qi_density": density,
	}
	emit_state_changed()
