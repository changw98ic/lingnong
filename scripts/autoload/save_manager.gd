extends Node

const SAVE_PATH := "user://lingnong_save.json"
const SAVE_VERSION := 5

func save_game() -> bool:
    var data := {
        "version": SAVE_VERSION,
        "spirit_stones": GameState.spirit_stones,
        "qi": GameState.qi,
        "cultivation": GameState.cultivation,
        "crop_inventory": GameState.crop_inventory,
        "pills": GameState.pills,
        "realm_index": GameState.realm_index,
        "field_level": GameState.field_level,
        "unlocked_fields": GameState.unlocked_fields,
        "fields": GameState.fields,
        "spirit_rain_until": GameState.spirit_rain_until,
        "guardian_array_level": GameState.guardian_array_level,
        "guardian_array_charges": GameState.guardian_array_charges,
        "insect_events": GameState.insect_events,
        "insect_corpses": GameState.insect_corpses,
        "season_index": GameState.season_index,
        "season_started_at": GameState.season_started_at,
        "random_event": GameState.random_event,
        "random_event_until": GameState.random_event_until,
        "random_event_cooldown_until": GameState.random_event_cooldown_until,
        "sword_art_cooldown_until": GameState.sword_art_cooldown_until,
        "practitioner_upgrades": GameState.practitioner_upgrades,
        "knowledge_points": GameState.knowledge_points,
        "reincarnation_count": GameState.reincarnation_count,
        "lifespan_days": GameState.lifespan_days,
        "saved_at": Time.get_unix_time_from_system(),
    }
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_error("无法写入存档")
        return false
    file.store_string(JSON.stringify(data))
    return true

func load_game() -> bool:
    if not FileAccess.file_exists(SAVE_PATH):
        return false
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return false
    var data = JSON.parse_string(file.get_as_text())
    if not data is Dictionary:
        return false

    GameState.spirit_stones = float(data.get("spirit_stones", 0.0))
    GameState.qi = float(data.get("qi", 0.0))
    GameState.cultivation = float(data.get("cultivation", 0.0))
    GameState.crop_inventory = data.get("crop_inventory", {"gathering_grass": 0})
    GameState.pills = data.get("pills", {"qi_gathering_pill": 0})
    GameState.realm_index = int(data.get("realm_index", 0))
    GameState.field_level = int(data.get("field_level", 1))
    GameState.unlocked_fields = int(data.get("unlocked_fields", 1))
    var saved_fields = data.get("fields", [])
    if saved_fields is Array:
        GameState.fields.clear()
        for field in saved_fields:
            if field is Dictionary:
                GameState.fields.append(field)
    var saved_rain = data.get("spirit_rain_until", [])
    if saved_rain is Array:
        GameState.spirit_rain_until.clear()
        for value in saved_rain:
            GameState.spirit_rain_until.append(float(value))
    var saved_guardian_levels = data.get("guardian_array_level", [])
    if saved_guardian_levels is Array:
        GameState.guardian_array_level.clear()
        for value in saved_guardian_levels:
            GameState.guardian_array_level.append(int(value))
    var saved_guardian_charges = data.get("guardian_array_charges", [])
    if saved_guardian_charges is Array:
        GameState.guardian_array_charges.clear()
        for value in saved_guardian_charges:
            GameState.guardian_array_charges.append(int(value))
    var saved_insect_events = data.get("insect_events", [])
    if saved_insect_events is Array:
        GameState.insect_events.clear()
        for event in saved_insect_events:
            if event is Dictionary:
                GameState.insect_events.append(event)
    GameState.insect_corpses = int(data.get("insect_corpses", 0))
    GameState.season_index = int(data.get("season_index", 0))
    GameState.season_started_at = float(data.get("season_started_at", Time.get_unix_time_from_system()))
    GameState.random_event = String(data.get("random_event", ""))
    GameState.random_event_until = float(data.get("random_event_until", 0.0))
    GameState.random_event_cooldown_until = float(data.get("random_event_cooldown_until", Time.get_unix_time_from_system() + 180.0))
    GameState.sword_art_cooldown_until = float(data.get("sword_art_cooldown_until", 0.0))
    GameState.practitioner_upgrades = data.get("practitioner_upgrades", GameState.practitioner_upgrades)
    GameState.knowledge_points = int(data.get("knowledge_points", 0))
    GameState.reincarnation_count = int(data.get("reincarnation_count", 0))
    GameState.lifespan_days = float(data.get("lifespan_days", GameState.max_lifespan_days))
    GameState.emit_state_changed()
    return true
