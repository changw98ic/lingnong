extends Control

const CROP := {"id": "gathering_grass", "name": "聚灵草", "growth": 5.0, "qi": 3.0}
const PILL_ID := "qi_gathering_pill"

@onready var guidance: Label = $Content/Guidance
@onready var stats: Label = $Content/Stats
@onready var progress: ProgressBar = $Content/Progress
@onready var fields_grid: GridContainer = $Content/MainRow/FieldsPanel/FieldsBox/Fields
@onready var inventory_label: Label = $Content/MainRow/ShopPanel/ShopBox/Inventory
@onready var pill_info: Label = $Content/MainRow/ShopPanel/ShopBox/PillInfo
@onready var sell_button: Button = $Content/MainRow/ShopPanel/ShopBox/Sell
@onready var sell_all_button: Button = $Content/MainRow/ShopPanel/ShopBox/SellAll
@onready var buy_button: Button = $Content/MainRow/ShopPanel/ShopBox/Buy
@onready var buy_all_button: Button = $Content/MainRow/ShopPanel/ShopBox/BuyAll
@onready var consume_button: Button = $Content/MainRow/ShopPanel/ShopBox/Consume
@onready var actions: GridContainer = $Content/Actions
@onready var breakthrough_button: Button = $Content/Actions/Breakthrough
@onready var save_button: Button = $Content/Actions/Save
@onready var feedback: Label = $Content/Feedback

var field_buttons: Array[Button] = []
var selected_field := 0
var save_accumulator := 0.0
var feedback_time := 0.0

func _ready() -> void:
    SaveManager.load_game()
    sell_button.pressed.connect(_sell_one)
    sell_all_button.pressed.connect(_sell_all)
    buy_button.pressed.connect(_buy_one)
    buy_all_button.pressed.connect(_buy_all)
    consume_button.pressed.connect(_consume_one)
    breakthrough_button.pressed.connect(_on_breakthrough_pressed)
    save_button.pressed.connect(_on_save_pressed)
    for label in ["灵雨诀", "庚金剑诀", "升级守护灵阵", "出售虫尸", "木灵根", "聚气效率", "农道悟性", "长生印记", "转世"]:
        _add_action_button(label)
    _build_fields()
    GameState.state_changed.connect(_refresh)
    _set_feedback("先点击空闲灵田，种下第一株聚灵草。")
    _refresh()

func _add_action_button(label: String) -> void:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size = Vector2(125, 32)
    button.pressed.connect(_on_action.bind(label))
    actions.add_child(button)

func _process(delta: float) -> void:
    save_accumulator += delta
    if save_accumulator >= 30.0:
        save_accumulator = 0.0
        SaveManager.save_game()
    GameState.update_world(delta)
    _refresh_fields()
    _refresh_stats()
    if feedback_time > 0.0:
        feedback_time -= delta
        if feedback_time <= 0.0:
            feedback.text = ""

func _build_fields() -> void:
    for child in fields_grid.get_children():
        child.queue_free()
    field_buttons.clear()
    for i in range(GameState.fields.size()):
        var button := Button.new()
        button.custom_minimum_size = Vector2(210, 125)
        button.pressed.connect(_on_field_pressed.bind(i))
        fields_grid.add_child(button)
        field_buttons.append(button)

func _refresh() -> void:
    _refresh_stats()
    _refresh_shop()
    _refresh_fields()
    breakthrough_button.disabled = not GameState.can_breakthrough()

func _refresh_stats() -> void:
    var requirement := GameState.get_next_realm_requirement()
    var current := GameState.cultivation
    if is_finite(requirement):
        progress.max_value = maxf(1.0, requirement)
        progress.value = minf(current, requirement)
    else:
        progress.max_value = 1.0
        progress.value = 1.0
    stats.text = "灵石  %s    灵气  %s    修为  %s / %s    境界  %s\n时节：%s    事件：%s    虫尸：%d    知识点：%d    寿元：%.1f天" % [_compact(GameState.spirit_stones), _compact(GameState.qi), _compact(current), "∞" if not is_finite(requirement) else _compact(requirement), GameState.get_realm_name(), GameState.get_season_name(), GameState.get_random_event_display_name(), GameState.insect_corpses, GameState.knowledge_points, GameState.lifespan_days]
    guidance.text = _get_guidance()

func _refresh_shop() -> void:
    var crop_count := int(GameState.crop_inventory.get(CROP.id, 0))
    var pill_count := int(GameState.pills.get(PILL_ID, 0))
    inventory_label.text = "灵草库存：%d 株\n出售单价：5 灵石" % crop_count
    pill_info.text = "聚气丹：%d 枚\n购买：5 灵石 / 枚\n服用：+50 修为" % pill_count
    sell_button.disabled = crop_count < 1
    sell_all_button.disabled = crop_count < 1
    buy_button.disabled = GameState.spirit_stones < 5.0
    buy_all_button.disabled = GameState.spirit_stones < 5.0
    consume_button.disabled = pill_count < 1

func _refresh_fields() -> void:
    var now := Time.get_unix_time_from_system()
    for i in range(field_buttons.size()):
        var button := field_buttons[i]
        var data: Dictionary = GameState.fields[i]
        var event: Dictionary = GameState.insect_events[i]
        if i >= GameState.unlocked_fields:
            button.text = "灵田 %d\n尚未解锁\n突破境界后开放" % (i + 1)
            button.disabled = true
            continue
        button.disabled = false
        var pest := "\n噬金虫：阵法 %d / 虫害 %d" % [GameState.guardian_array_charges[i], event.get("pest_level", 0)] if event.get("active", false) else ""
        var rain := "\n灵雨诀生效中" if GameState.is_spirit_rain_active(i) else ""
        if String(data.get("crop_id", "")) == "":
            button.text = "灵田 %d\n空闲\n点击种植聚灵草" % (i + 1)
        elif now >= float(data.get("ready_at", 0.0)):
            button.text = "灵田 %d\n聚灵草成熟！\n点击收获%s" % [i + 1, pest]
        else:
            button.text = "灵田 %d\n生长中 %d 秒%s%s" % [i + 1, maxi(0, int(float(data["ready_at"]) - now)), pest, rain]
        button.modulate = Color(1.0, 0.82, 0.35) if i == selected_field else Color.WHITE

func _on_field_pressed(index: int) -> void:
    selected_field = index
    var data: Dictionary = GameState.fields[index]
    var now := Time.get_unix_time_from_system()
    if String(data.get("crop_id", "")) == "":
        GameState.insect_events[index] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": now + 180.0}
        GameState.fields[index] = {"crop_id": CROP.id, "planted_at": now, "ready_at": now + CROP.growth / GameState.get_growth_multiplier(index)}
        _set_feedback("种植成功：聚灵草将在约 5 秒后成熟。")
    elif now >= float(data.get("ready_at", 0.0)):
        var pest_level := int(GameState.insect_events[index].get("pest_level", 0))
        var yield_amount := maxi(1, int(floor(maxf(0.0, 1.0 - pest_level * 0.25))))
        GameState.harvest_crop(index, CROP.id, yield_amount, CROP.qi)
        GameState.fields[index] = {"crop_id": "", "planted_at": 0.0, "ready_at": 0.0}
        _set_feedback("收获成功：聚灵草 ×%d，灵气 +%.0f。现在去右侧商店出售。" % [yield_amount, CROP.qi])
    else:
        _set_feedback("这块灵田还在生长，剩余约 %d 秒。" % maxi(0, int(float(data["ready_at"]) - now)))
    SaveManager.save_game()
    _refresh()

func _sell_one() -> void:
    if GameState.sell_crop(CROP.id, 1):
        _set_feedback("出售成功：灵石 +5。可以购买聚气丹了。")
    else:
        _set_feedback("没有可出售的聚灵草。")
    _after_action()

func _sell_all() -> void:
    var amount := int(GameState.crop_inventory.get(CROP.id, 0))
    if amount > 0 and GameState.sell_crop(CROP.id, amount):
        _set_feedback("出售成功：聚灵草 ×%d，灵石 +%d。" % [amount, amount * 5])
    else:
        _set_feedback("没有可出售的聚灵草。")
    _after_action()

func _buy_one() -> void:
    if GameState.buy_pill(PILL_ID, 1):
        _set_feedback("购买成功：聚气丹 ×1。服用它即可获得修为。")
    else:
        _set_feedback("灵石不足，需要 5 灵石。先收获并出售聚灵草。")
    _after_action()

func _buy_all() -> void:
    var amount := int(floor(GameState.spirit_stones / 5.0))
    if amount > 0 and GameState.buy_pill(PILL_ID, amount):
        _set_feedback("购买成功：聚气丹 ×%d。" % amount)
    else:
        _set_feedback("灵石不足，无法购买聚气丹。")
    _after_action()

func _consume_one() -> void:
    if GameState.consume_pill(PILL_ID, 1):
        _set_feedback("服用成功：修为 +10。继续经营，达到目标后尝试突破。")
    else:
        _set_feedback("没有聚气丹可服用，请先出售灵草并购买丹药。")
    _after_action()

func _on_action(label: String) -> void:
    var success := false
    if label == "灵雨诀":
        success = GameState.cast_spirit_rain(selected_field)
        _set_feedback("灵雨诀施放成功：当前灵田生长速度提高。" if success else "灵气不足，需要 10 灵气。先收获灵草。")
    elif label == "庚金剑诀":
        success = GameState.cast_gengjin_sword(selected_field)
        _set_feedback("庚金剑诀成功驱虫，并获得虫尸。" if success else "当前没有可驱逐的噬金虫，或灵气不足/法术冷却中。")
    elif label == "升级守护灵阵":
        success = GameState.upgrade_guardian_array(selected_field)
        _set_feedback("守护灵阵升级成功：抵抗次数提高。" if success else "升级需要 100 灵石。")
    elif label == "出售虫尸":
        success = GameState.sell_insect_corpses()
        _set_feedback("虫尸出售成功：获得灵石。" if success else "当前没有虫尸。")
    elif label == "木灵根":
        success = GameState.buy_practitioner_upgrade("wood_spirit")
    elif label == "聚气效率":
        success = GameState.buy_practitioner_upgrade("qi_gathering")
    elif label == "农道悟性":
        success = GameState.buy_practitioner_upgrade("farmer_insight")
    elif label == "长生印记":
        success = GameState.buy_practitioner_upgrade("longevity")
    elif label == "转世":
        success = GameState.reincarnate()
        _set_feedback("转世完成：知识点和永久专精已保留。" if success else "当前无法转世。")
    if success and feedback.text == "":
        _set_feedback("操作成功。")
    _after_action()

func _on_breakthrough_pressed() -> void:
    if GameState.breakthrough():
        _set_feedback("突破成功：境界提升，新的灵田或系统已解锁！")
        SaveManager.save_game()
        _refresh()
    else:
        _set_feedback("修为还不够：先通过商店购买并服用聚气丹。")

func _on_save_pressed() -> void:
    SaveManager.save_game()
    _set_feedback("存档成功。")

func _after_action() -> void:
    SaveManager.save_game()
    _refresh()

func _get_guidance() -> String:
    var crop_count := int(GameState.crop_inventory.get(CROP.id, 0))
    var pill_count := int(GameState.pills.get(PILL_ID, 0))
    if GameState.realm_index == 0 and GameState.cultivation <= 0.0:
        if crop_count <= 0 and GameState.spirit_stones <= 0.0:
            return "当前目标 1/4：点击左侧空闲灵田，种植聚灵草。"
        if crop_count > 0:
            return "当前目标 2/4：灵草已入库，点击右侧“出售 1 株”获得灵石。"
        if GameState.spirit_stones >= 5.0 and pill_count <= 0:
            return "当前目标 3/4：点击右侧“购买 1 枚聚气丹”。"
        if pill_count > 0:
            return "当前目标 4/4：点击右侧“服用 1 枚聚气丹”，把经营收益转成修为。"
    if GameState.can_breakthrough():
        return "阶段目标：修为已达标，点击“尝试突破”解锁新的成长空间。"
    return "继续循环：收获 → 出售 → 买丹药 → 服用 → 修为突破。"

func _set_feedback(message: String) -> void:
    feedback.text = message
    feedback_time = 4.0

func _compact(value: float) -> String:
    return str(snapped(value, 0.1))
