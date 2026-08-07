extends Control

const CROP := {"id": "gathering_grass", "name": "聚灵草", "growth": 5.0, "qi": 3.0}
const PILL_ID := "qi_gathering_pill"
const FOUNDATION_PILL := "foundation_pill"
const GOLDEN_PILL := "golden_pill"
const FRENZY_PILL := "frenzy_pill"

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
@onready var shop_box: VBoxContainer = $Content/MainRow/ShopPanel/ShopBox
@onready var actions: GridContainer = $Content/Actions
@onready var breakthrough_button: Button = $Content/Actions/Breakthrough
@onready var save_button: Button = $Content/Actions/Save
@onready var feedback: Label = $Content/Feedback

var field_buttons: Array[Button] = []
var selected_field := 0
var save_accumulator := 0.0
var feedback_time := 0.0

# 炼丹相关动态按钮与灵气浓度信息（按境界解锁显示）。
var brew_foundation_button: Button
var consume_foundation_button: Button
var brew_golden_button: Button
var consume_golden_button: Button
var brew_frenzy_button: Button
var consume_frenzy_button: Button
var spirit_vein_label: Label

func _ready() -> void:
	SaveManager.load_game()
	sell_button.pressed.connect(_sell_one)
	sell_all_button.pressed.connect(_sell_all)
	buy_button.pressed.connect(_buy_one)
	buy_all_button.pressed.connect(_buy_all)
	consume_button.pressed.connect(_consume_one)
	breakthrough_button.pressed.connect(_on_breakthrough_pressed)
	save_button.pressed.connect(_on_save_pressed)
	# 法术与系统动作按钮（含 v2 新增的升级灵田 / 灵脉化田）。
	for label in ["灵雨诀", "庚金剑诀", "升级守护灵阵", "升级灵田", "灵脉化田", "出售虫尸", "木灵根", "聚气效率", "农道悟性", "长生印记", "转世"]:
		_add_action_button(label)
	_build_shop_extras()
	_build_fields()
	GameState.state_changed.connect(_refresh)
	_show_offline_report_if_any()
	if feedback_time <= 0.0:
		_set_feedback("先点击空闲灵田，种下第一株聚灵草。")
	_refresh()

func _add_action_button(label: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(125, 32)
	button.pressed.connect(_on_action.bind(label))
	actions.add_child(button)

# 动态构建炼丹按钮（含狂暴丹）与灵气浓度信息标签，附加到商店面板底部。
func _build_shop_extras() -> void:
	brew_foundation_button = _add_shop_button("炼制筑基丹（10 草 → +1000 修为）", _brew_foundation)
	consume_foundation_button = _add_shop_button("服用筑基丹（+1000 修为 × 境界）", _consume_foundation)
	brew_golden_button = _add_shop_button("炼制金元丹（100 草 → +30000 修为）", _brew_golden)
	consume_golden_button = _add_shop_button("服用金元丹（+30000 修为 × 境界）", _consume_golden)
	brew_frenzy_button = _add_shop_button("炼制狂暴丹（30 草 → 60 秒生产 ×3）", _brew_frenzy)
	consume_frenzy_button = _add_shop_button("服用狂暴丹（60 秒生产 ×3）", _consume_frenzy)
	spirit_vein_label = Label.new()
	spirit_vein_label.add_theme_font_size_override("font_size", 14)
	spirit_vein_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.78, 1))
	shop_box.add_child(spirit_vein_label)

func _add_shop_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 30)
	button.pressed.connect(handler)
	shop_box.add_child(button)
	return button

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
		button.custom_minimum_size = Vector2(210, 140)
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
	# 事件爆发窗：祥瑞降世期间显著标注 ×5 生产。
	var event_tag := "  ★ 祥瑞降世·生产 ×5 ★" if (GameState.is_random_event_active() and GameState.random_event == "auspicious") else ""
	var buff_tag := ""
	if GameState.is_active_buff():
		buff_tag = "  [狂暴 ×%.1f %ds]" % [GameState.active_buff_mult, int(GameState.get_active_buff_remaining())]
	# 自动修炼信息（筑基起显示浓度与每秒产出）。
	var auto := GameState.get_auto_cultivation_per_sec()
	var auto_tag := ""
	if GameState.auto_cultivation_unlocked:
		auto_tag = "\n灵气浓度：%.0f    自动修炼：每秒 +%s 修为 +%s 灵气" % [float(auto["density"]), NumberFormat.format(float(auto["cultivation"])), NumberFormat.format(float(auto["qi"]))]
	stats.text = "灵石  %s    灵气  %s    修为  %s / %s    境界  %s\n时节：%s    事件：%s    虫尸：%d    知识点：%d    寿元：%.1f天%s%s%s" % [NumberFormat.format(GameState.spirit_stones), NumberFormat.format(GameState.qi), NumberFormat.format(current), NumberFormat.format(requirement), GameState.get_realm_name(), GameState.get_season_name(), GameState.get_random_event_display_name(), GameState.insect_corpses, GameState.knowledge_points, GameState.lifespan_days, event_tag, buff_tag, auto_tag]
	guidance.text = _get_guidance()

func _refresh_shop() -> void:
	var crop_count := int(GameState.crop_inventory.get(CROP.id, 0))
	var qi_pill_count := int(GameState.pills.get(PILL_ID, 0))
	var foundation_count := int(GameState.pills.get(FOUNDATION_PILL, 0))
	var golden_count := int(GameState.pills.get(GOLDEN_PILL, 0))
	var frenzy_count := int(GameState.pills.get(FRENZY_PILL, 0))
	inventory_label.text = "灵草库存：%d 株\n出售单价：5 灵石" % crop_count
	pill_info.text = "聚气丹：%d 枚（5 灵石/枚，服用 +50 修为 × 境界）\n筑基丹：%d 枚（+1000 修为 × 境界）\n金元丹：%d 枚（+30000 修为 × 境界）\n狂暴丹：%d 枚（60 秒生产 ×3）" % [qi_pill_count, foundation_count, golden_count, frenzy_count]
	sell_button.disabled = crop_count < 1
	sell_all_button.disabled = crop_count < 1
	buy_button.disabled = GameState.spirit_stones < 5.0
	buy_all_button.disabled = GameState.spirit_stones < 5.0
	consume_button.disabled = qi_pill_count < 1

	# 炼丹按钮按境界显示与启用。
	brew_foundation_button.visible = GameState.foundation_pill_unlocked
	consume_foundation_button.visible = GameState.foundation_pill_unlocked
	brew_foundation_button.disabled = not GameState.can_brew_pill(FOUNDATION_PILL)
	consume_foundation_button.disabled = foundation_count < 1
	brew_golden_button.visible = GameState.golden_pill_unlocked
	consume_golden_button.visible = GameState.golden_pill_unlocked
	brew_golden_button.disabled = not GameState.can_brew_pill(GOLDEN_PILL)
	consume_golden_button.disabled = golden_count < 1
	# 狂暴丹与筑基丹同阶解锁（unlock_realm=2）。
	brew_frenzy_button.visible = GameState.foundation_pill_unlocked
	consume_frenzy_button.visible = GameState.foundation_pill_unlocked
	brew_frenzy_button.disabled = not GameState.can_brew_pill(FRENZY_PILL)
	consume_frenzy_button.disabled = frenzy_count < 1 or GameState.is_active_buff()

	# 灵气浓度与自动修炼（筑基起显示）。
	if GameState.auto_cultivation_unlocked:
		var per_sec: Dictionary = GameState.get_auto_cultivation_per_sec()
		spirit_vein_label.text = "灵气浓度：%.0f    自动修炼：每秒 +%s 修为 +%s 灵气" % [float(per_sec["density"]), NumberFormat.format(float(per_sec["cultivation"])), NumberFormat.format(float(per_sec["qi"]))]
		spirit_vein_label.visible = true
	else:
		spirit_vein_label.visible = false

func _refresh_fields() -> void:
	var now := Time.get_unix_time_from_system()
	for i in range(field_buttons.size()):
		var button: Button = field_buttons[i]
		var data: Dictionary = GameState.fields[i]
		var event: Dictionary = GameState.insect_events[i]
		if i >= GameState.unlocked_fields:
			button.text = "灵田 %d\n尚未解锁\n突破境界后开放" % (i + 1)
			button.disabled = true
			continue
		button.disabled = false
		# 田自身属性：等级 / 品质 / 灵脉化标记。
		var level := int(data.get("level", 1))
		var quality := float(data.get("quality", 1.0))
		var field_tag := "Lv.%d · 品质×%.1f%s" % [level, quality, " · 灵脉" if bool(data.get("spirit_vein", false)) else ""]
		var pest := "\n噬金虫：阵法 %d / 虫害 %d" % [GameState.guardian_array_charges[i], event.get("pest_level", 0)] if event.get("active", false) else ""
		var rain := "\n灵雨诀生效中" if GameState.is_spirit_rain_active(i) else ""
		if String(data.get("crop_id", "")) == "":
			button.text = "灵田 %d\n%s\n空闲\n点击种植聚灵草" % [i + 1, field_tag]
		elif now >= float(data.get("ready_at", 0.0)):
			button.text = "灵田 %d\n%s\n聚灵草成熟！\n点击收获%s" % [i + 1, field_tag, pest]
		else:
			button.text = "灵田 %d\n%s\n生长中 %d 秒%s%s" % [i + 1, field_tag, maxi(0, int(float(data["ready_at"]) - now)), pest, rain]
		button.modulate = Color(1.0, 0.82, 0.35) if i == selected_field else Color.WHITE

func _on_field_pressed(index: int) -> void:
	selected_field = index
	var data: Dictionary = GameState.fields[index]
	var now := Time.get_unix_time_from_system()
	if String(data.get("crop_id", "")) == "":
		GameState.insect_events[index] = {"active": false, "attacks": 0, "pest_level": 0, "next_attack_at": now + 180.0}
		# 种植：保留田的 level/quality/spirit_vein，只更新作物与时间。
		data["crop_id"] = CROP.id
		data["planted_at"] = now
		data["ready_at"] = now + CROP.growth / GameState.get_growth_multiplier(index)
		GameState.fields[index] = data
		_set_feedback("种植成功：聚灵草将在约 5 秒后成熟。")
	elif now >= float(data.get("ready_at", 0.0)):
		var result: Dictionary = GameState.harvest_crop(index)
		if bool(result.get("ok", false)):
			# 收获后清空作物，保留田升级与灵脉属性。
			data["crop_id"] = ""
			data["planted_at"] = 0.0
			data["ready_at"] = 0.0
			GameState.fields[index] = data
			_set_feedback("收获成功：聚灵草 ×%d，灵气 +%s。现在去右侧商店出售。" % [int(result["amount"]), NumberFormat.format(float(result["qi"]))])
		else:
			_set_feedback("这块灵田没有可收获的作物。")
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
		_set_feedback("出售成功：聚灵草 ×%d，灵石 +%s。" % [amount, NumberFormat.format(amount * 5.0)])
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
		_set_feedback("服用成功：聚气丹转化为修为（随境界倍增）。继续经营，达到目标后尝试突破。")
	else:
		_set_feedback("没有聚气丹可服用，请先出售灵草并购买丹药。")
	_after_action()

func _brew_foundation() -> void:
	if GameState.brew_pill(FOUNDATION_PILL):
		_set_feedback("炼制成功：筑基丹 ×1。")
	else:
		_set_feedback("炼制失败：需要 10 株聚灵草。")
	_after_action()

func _consume_foundation() -> void:
	if GameState.consume_pill(FOUNDATION_PILL, 1):
		_set_feedback("服用筑基丹：修为大增（× 境界修炼倍率）。")
	else:
		_set_feedback("没有筑基丹可服用。")
	_after_action()

func _brew_golden() -> void:
	if GameState.brew_pill(GOLDEN_PILL):
		_set_feedback("炼制成功：金元丹 ×1。")
	else:
		_set_feedback("炼制失败：需要 100 株聚灵草。")
	_after_action()

func _consume_golden() -> void:
	if GameState.consume_pill(GOLDEN_PILL, 1):
		_set_feedback("服用金元丹：修为暴涨（× 境界修炼倍率）。")
	else:
		_set_feedback("没有金元丹可服用。")
	_after_action()

func _brew_frenzy() -> void:
	if GameState.brew_pill(FRENZY_PILL):
		_set_feedback("炼制成功：狂暴丹 ×1。服用后 60 秒内生产 ×3。")
	else:
		_set_feedback("炼制失败：需要 30 株聚灵草。")
	_after_action()

func _consume_frenzy() -> void:
	if GameState.consume_pill(FRENZY_PILL, 1):
		_set_feedback("服用狂暴丹：60 秒内生长/产量/灵气 ×3。")
	else:
		_set_feedback("没有狂暴丹可服用，或狂暴效果已在生效中。")
	_after_action()

func _on_action(label: String) -> void:
	var success := false
	if label == "灵雨诀":
		if not GameState.spirit_rain_unlocked:
			_set_feedback("灵雨诀需突破到炼气后解锁。")
			_after_action()
			return
		success = GameState.cast_spirit_rain(selected_field)
		_set_feedback("灵雨诀施放成功：当前灵田生长速度提高 8 倍。" if success else "灵气不足，需要 10 灵气。先收获灵草。")
	elif label == "庚金剑诀":
		if GameState.realm_index < 2:
			_set_feedback("庚金剑诀需突破到筑基后解锁。")
			_after_action()
			return
		success = GameState.cast_gengjin_sword(selected_field)
		_set_feedback("庚金剑诀成功驱虫，并获得虫尸。" if success else "当前没有可驱逐的噬金虫，或灵气不足/法术冷却中。")
	elif label == "升级守护灵阵":
		if GameState.realm_index < 2:
			_set_feedback("守护灵阵需突破到筑基后解锁。")
			_after_action()
			return
		success = GameState.upgrade_guardian_array(selected_field)
		_set_feedback("守护灵阵升级成功：抵抗次数提高。" if success else "升级需要 100 灵石。")
	elif label == "升级灵田":
		# 灵田升级：消耗 50*level 灵石，提升产量乘数。
		success = GameState.upgrade_field(selected_field)
		if success:
			var lv := int(GameState.fields[selected_field].get("level", 1))
			_set_feedback("灵田升级至 Lv.%d，产量进一步提升。下次消耗 %d 灵石。" % [lv, 50 * lv])
		else:
			var cur_lv := int(GameState.fields[selected_field].get("level", 1)) if selected_field < GameState.fields.size() else 1
			_set_feedback("升级失败：需要灵田升级解锁，且持有 %d 灵石。" % (50 * cur_lv))
	elif label == "灵脉化田":
		# 灵脉化田：消耗 500 灵石，品质 ×3 且贡献 +10 灵气浓度。
		success = GameState.spirit_veinify_field(selected_field)
		_set_feedback("灵脉化田成功：品质 ×3，灵气浓度 +10。" if success else "灵脉化田失败：需金丹解锁、500 灵石，且该田尚未灵脉化。")
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
		_set_feedback("转世完成：知识点与永久专精已保留，第二世更快。" if success else "当前无法转世。")
	if success and feedback.text == "":
		_set_feedback("操作成功。")
	_after_action()

func _on_breakthrough_pressed() -> void:
	if GameState.breakthrough():
		_set_feedback(_describe_breakthrough())
		SaveManager.save_game()
		_refresh()
	else:
		_set_feedback("修为还不够：先通过商店购买并服用聚气丹。")

# 根据本次突破奖励生成解锁/增益摘要。
func _describe_breakthrough() -> String:
	var rewards: Dictionary = GameState.get_breakthrough_rewards_for_current()
	var parts := PackedStringArray()
	if int(rewards.get("field_delta", 0)) > 0:
		parts.append("新灵田")
	if bool(rewards.get("unlock_spirit_rain", false)):
		parts.append("灵雨诀")
	if bool(rewards.get("auto_harvest", false)):
		parts.append("自动收获")
	if bool(rewards.get("unlock_alchemy", false)):
		parts.append("炼丹炉")
	if bool(rewards.get("unlock_foundation_pill", false)):
		parts.append("筑基丹/狂暴丹配方")
	if bool(rewards.get("unlock_field_upgrade", false)):
		parts.append("灵田升级")
	if bool(rewards.get("unlock_auto_cultivation", false)):
		parts.append("自动修炼（灵气浓度）")
	if bool(rewards.get("unlock_golden_pill", false)):
		parts.append("金元丹配方")
	if bool(rewards.get("unlock_spirit_veinify", false)):
		parts.append("灵脉化田")
	if parts.is_empty():
		return "突破成功：境界提升。"
	return "突破成功！本次解锁/增益：" + ", ".join(parts)

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
	return "继续循环：收获 → 出售 → 买丹药 → 服用 → 修为突破。境界越高，生产与修炼倍率越强。"

func _set_feedback(message: String) -> void:
	feedback.text = message
	feedback_time = 4.0

# 加载后若有离线自动修炼收益，弹出一次性摘要（筑基起生效）。
func _show_offline_report_if_any() -> void:
	var report: Dictionary = GameState.last_offline_report
	if not bool(report.get("active", false)):
		return
	var gained_c := float(report.get("cultivation", 0.0))
	var gained_q := float(report.get("qi", 0.0))
	if gained_c <= 0.0 and gained_q <= 0.0:
		return
	var hours := float(report.get("credited_seconds", 0.0)) / 3600.0
	var capped := bool(report.get("capped", false))
	_set_feedback("离线结算（%.1f 小时%s）：灵气浓度 %.0f，修为 +%s，灵气 +%s。" % [hours, "，已达 8 小时上限" if capped else "", float(report.get("qi_density", 0.0)), NumberFormat.format(gained_c), NumberFormat.format(gained_q)])
