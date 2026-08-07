extends Node

signal state_changed
signal realm_changed

const REALMS := [
    {"name": "凡人", "required_cultivation": 0.0},
    {"name": "炼气", "required_cultivation": 50.0},
    {"name": "筑基", "required_cultivation": 500.0},
    {"name": "金丹", "required_cultivation": 5000.0},
]

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

const CROPS := {
    "gathering_grass": {"name": "聚灵草", "sell_price": 5.0},
}

const PILLS := {
    "qi_gathering_pill": {"name": "聚气丹", "price": 5.0, "cultivation": 50.0},
}

var spirit_stones := 0.0
var qi := 0.0
var cultivation := 0.0
var crop_inventory := {"gathering_grass": 0}
var pills := {"qi_gathering_pill": 0}
var realm_index := 0
var field_level := 1
var unlocked_fields := 1
var fields: Array[Dictionary] = []

var practitioner_upgrades := {"wood_spirit": 0, "qi_gathering": 0, "farmer_insight": 0, "longevity": 0}
var knowledge_points := 0
var reincarnation_count := 0
var lifespan_days := 100.0
var max_lifespan_days := 100.0

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

func _ready() -> void:
    initialize_new_game()

func initialize_new_game() -> void:
    spirit_stones = 0.0
    qi = 0.0
    cultivation = 0.0
    crop_inventory = {"gathering_grass": 0}
    pills = {"qi_gathering_pill": 0}
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
    return REALMS[realm_index]["name"]

func get_next_realm_requirement() -> float:
    if realm_index + 1 >= REALMS.size():
        return INF
    return REALMS[realm_index + 1]["required_cultivation"]

func can_breakthrough() -> bool:
    return realm_index + 1 < REALMS.size() and cultivation >= get_next_realm_requirement()

func breakthrough() -> bool:
    if not can_breakthrough():
        return false
    realm_index += 1
    if realm_index == 1:
        unlocked_fields = 2
    elif realm_index == 2:
        unlocked_fields = 3
    elif realm_index == 3:
        field_level += 2
    realm_changed.emit()
    emit_state_changed()
    return true

func get_season_name() -> String:
    return SEASONS[season_index]["name"]

func get_season_multiplier(kind: String) -> float:
    return float(SEASONS[season_index].get(kind, 1.0))

func get_growth_multiplier(field_index: int) -> float:
    var multiplier := get_season_multiplier("growth")
    multiplier *= 1.0 + practitioner_upgrades["wood_spirit"] * 0.05
    if is_spirit_rain_active(field_index):
        multiplier *= 1.5
    return multiplier

func is_spirit_rain_active(field_index: int) -> bool:
    return field_index >= 0 and field_index < spirit_rain_until.size() and spirit_rain_until[field_index] > Time.get_unix_time_from_system()

func cast_spirit_rain(field_index: int, duration := 60.0, cost := 10.0) -> bool:
    if field_index < 0 or field_index >= fields.size() or qi < cost:
        return false
    qi -= cost
    spirit_rain_until[field_index] = maxf(spirit_rain_until[field_index], Time.get_unix_time_from_system() + duration)
    emit_state_changed()
    return true

func cast_gengjin_sword(field_index: int, cost := 20.0, cooldown := 120.0) -> bool:
    var now := Time.get_unix_time_from_system()
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
    qi += qi_amount * get_season_multiplier("qi") * (1.0 + practitioner_upgrades["qi_gathering"] * 0.08)
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

func consume_pill(pill_id: String, amount: int = 1) -> bool:
    if not PILLS.has(pill_id) or amount <= 0 or int(pills.get(pill_id, 0)) < amount:
        return false
    var event_multiplier := 2.0 if is_random_event_active() and random_event == "auspicious" else 1.0
    var cultivation_multiplier: float = (1.0 + practitioner_upgrades["farmer_insight"] * 0.10) * event_multiplier
    pills[pill_id] = int(pills.get(pill_id, 0)) - amount
    cultivation += float(PILLS[pill_id]["cultivation"]) * amount * cultivation_multiplier
    emit_state_changed()
    return true

func add_rewards(stones: float, qi_amount: float, cultivation_amount: float, yield_multiplier := 1.0) -> void:
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

func reincarnate() -> bool:
    knowledge_points += get_knowledge_for_reincarnation()
    reincarnation_count += 1
    spirit_stones = 100.0
    qi = 0.0
    cultivation = 0.0
    realm_index = 0
    field_level = 1
    unlocked_fields = 1
    initialize_new_game()
    emit_state_changed()
    return true

func is_random_event_active() -> bool:
    return random_event != "" and random_event_until > Time.get_unix_time_from_system()

func get_random_event_display_name() -> String:
    if not is_random_event_active():
        return "无"
    return "祥瑞降世" if random_event == "auspicious" else "兵主诞辰"
