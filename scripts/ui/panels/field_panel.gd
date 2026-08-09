## 灵田面板。
##
## 灵田槽位和灵田等级都用灵石购买：修行境界只负责开放购买权限。
## 作物成熟后自动收获并补种；玩家点击生长中的灵田可以减少成熟倒计时。
class_name FieldPanel
extends Control


const _TICK_INTERVAL := 0.1
const _FEEDBACK_LINGER := 4.0
var _root_vbox: VBoxContainer
var _speed_label: Label
var _grid: GridContainer
var _feedback: Label
var _cards: Array[Dictionary] = []
var _unlocked_crop_set: Dictionary = {}
var _switching_fields: Dictionary = {}
var _tick_accumulator := 0.0
var _feedback_time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(720, 340)
	_root_vbox = _build_root_vbox()
	_build_header(_root_vbox)
	_speed_label = _make_label("", 14, Color(0.75, 0.9, 0.82))
	_root_vbox.add_child(_speed_label)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_root_vbox.add_child(_grid)
	_feedback = _make_label("", 14, Color(0.95, 0.92, 0.6))
	_root_vbox.add_child(_feedback)
	_build_field_cards()
	if GameState.has_signal("state_changed"):
		GameState.state_changed.connect(_refresh_full)
	_refresh_full()


func _process(delta: float) -> void:
	if _feedback_time > 0.0:
		_feedback_time -= delta
		if _feedback_time <= 0.0:
			_feedback.text = ""
	_tick_accumulator += delta
	if _tick_accumulator >= _TICK_INTERVAL:
		_tick_accumulator = 0.0
		_refresh_body_texts()


func _build_root_vbox() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	return vbox


func _build_header(parent: Node) -> void:
	parent.add_child(_make_label("【灵田】", 20, Color(1.0, 0.9, 0.5)))
	parent.add_child(_make_label("空闲田点击种植；生长中点击田块加速；需要换作物时点击【切换作物】。切换会重置当前生长进度，成熟后按新作物自动补种。", 13, Color(0.7, 0.8, 0.7)))


func _build_field_cards() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	for i in range(GameState.fields.size()):
		_cards.append(_make_card(i))


func _make_card(field_index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(228, 190)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	var body := Button.new()
	body.custom_minimum_size = Vector2(0, 100)
	body.alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.add_theme_font_size_override("font_size", 13)
	body.text = "灵田 %d" % (field_index + 1)
	body.pressed.connect(_on_body_pressed.bind(field_index))
	vbox.add_child(body)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	vbox.add_child(actions)

	var switch_crop := Button.new()
	switch_crop.custom_minimum_size = Vector2(0, 28)
	switch_crop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switch_crop.add_theme_font_size_override("font_size", 12)
	switch_crop.visible = false
	switch_crop.pressed.connect(_on_switch_pressed.bind(field_index))
	actions.add_child(switch_crop)

	var crops: Dictionary = {}
	for crop_id in CropConfig.get_all():
		var crop: Variant = CropConfig.get_crop(String(crop_id))
		var disp_name := String(crop_id) if crop == null else String(crop.get("name", crop_id))
		var btn := Button.new()
		btn.text = "种 " + disp_name
		btn.custom_minimum_size = Vector2(0, 26)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		btn.visible = false
		btn.pressed.connect(_on_crop_button.bind(field_index, String(crop_id)))
		actions.add_child(btn)
		crops[String(crop_id)] = btn

	var buy_slot := Button.new()
	buy_slot.custom_minimum_size = Vector2(0, 28)
	buy_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_slot.add_theme_font_size_override("font_size", 12)
	buy_slot.visible = false
	buy_slot.pressed.connect(_on_buy_slot.bind(field_index))
	actions.add_child(buy_slot)

	var upgrade := Button.new()
	upgrade.custom_minimum_size = Vector2(0, 28)
	upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade.add_theme_font_size_override("font_size", 12)
	upgrade.visible = false
	upgrade.pressed.connect(_on_upgrade.bind(field_index))
	actions.add_child(upgrade)

	return {"panel": panel, "body": body, "switch_crop": switch_crop, "crops": crops, "buy_slot": buy_slot, "upgrade": upgrade}


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _refresh_full() -> void:
	if GameState.lifespan_depleted:
		_speed_label.text = "大限已至：生产暂停，去商店续命或在修炼·突破面板开始新局。"
	elif GameState.tribulation_active:
		_speed_label.text = "渡劫中：生产暂停，完成天劫后恢复灵田操作。"
	else:
		_speed_label.text = "点击加速：每次减少成熟倒计时 %s 秒；农道天赋可以提高点击效果。" % NumberFormat.format(GameState.get_click_accel_seconds())
	if _cards.size() != GameState.fields.size():
		_build_field_cards()
	_unlocked_crop_set = {}
	for crop_id in GameState.get_crop_options():
		_unlocked_crop_set[String(crop_id)] = true
	for i in range(_cards.size()):
		_refresh_card(i)


func _refresh_card(field_index: int) -> void:
	var card: Dictionary = _cards[field_index]
	var body: Button = card["body"]
	var locked := field_index >= GameState.unlocked_fields
	body.text = _body_text(field_index)
	body.disabled = locked or GameState.lifespan_depleted or GameState.tribulation_active
	card["panel"].modulate = Color(0.55, 0.55, 0.55, 1.0) if locked else Color.WHITE

	var data: Dictionary = GameState.fields[field_index]
	var crop_id := String(data.get("crop_id", ""))
	var idle := not locked and not GameState.lifespan_depleted and not GameState.tribulation_active and crop_id == ""
	var active := not locked and not GameState.lifespan_depleted and not GameState.tribulation_active and crop_id != ""
	var switching := bool(_switching_fields.get(field_index, false))
	if not active:
		_switching_fields.erase(field_index)
		switching = false
	var switch_crop: Button = card["switch_crop"]
	switch_crop.visible = active
	switch_crop.text = "取消切换" if switching else "切换作物"
	switch_crop.disabled = not active
	var crops: Dictionary = card["crops"]
	for available_crop_id in crops:
		var btn: Button = crops[available_crop_id]
		btn.visible = (idle or switching) and _unlocked_crop_set.has(available_crop_id) and (idle or available_crop_id != crop_id)

	_refresh_slot_button(field_index, card["buy_slot"])
	_refresh_upgrade_button(field_index, card["upgrade"])


func _refresh_slot_button(field_index: int, buy_slot: Button) -> void:
	if field_index < GameState.unlocked_fields or field_index >= GameState.fields.size() or field_index <= 0:
		buy_slot.visible = false
		return
	buy_slot.visible = field_index == GameState.unlocked_fields
	if not buy_slot.visible:
		return
	var cost := GameState.get_field_slot_cost(field_index)
	var cost_text := NumberFormat.format(float(cost.get("spirit_stones", 0.0))) + " 灵石"
	if GameState.lifespan_depleted:
		buy_slot.text = "大限后可购买灵田"
		buy_slot.disabled = true
	elif GameState.tribulation_active:
		buy_slot.text = "渡劫中暂不可购买"
		buy_slot.disabled = true
	else:
		buy_slot.text = "购买灵田%d（%s）" % [field_index + 1, cost_text]
		buy_slot.disabled = not GameState.can_buy_field_slot(field_index)


func _refresh_upgrade_button(field_index: int, upgrade: Button) -> void:
	if field_index >= GameState.unlocked_fields:
		upgrade.visible = false
		return
	var data: Dictionary = GameState.fields[field_index]
	var tier := int(data.get("tier", 0))
	if tier < 0 or tier >= BalanceConfig.FIELD_TIER_UPGRADE_COSTS.size():
		upgrade.visible = false
		return
	upgrade.visible = true
	var cost := GameState.get_field_upgrade_cost(field_index)
	var required_realm := int(cost.get("required_realm", tier + 1))
	var next_tier := clampi(tier + 1, 0, BalanceConfig.FIELD_TIER_NAMES.size() - 1)
	if GameState.lifespan_depleted:
		upgrade.text = "大限后可升至%s" % BalanceConfig.FIELD_TIER_NAMES[next_tier]
		upgrade.disabled = true
	elif GameState.tribulation_active:
		upgrade.text = "渡劫中暂不可升档"
		upgrade.disabled = true
	elif GameState.get_max_field_tier() <= tier:
		upgrade.text = "升至%s（%s后开放）" % [BalanceConfig.FIELD_TIER_NAMES[next_tier], _realm_name(required_realm)]
		upgrade.disabled = true
	else:
		upgrade.text = "升至%s（%s）" % [BalanceConfig.FIELD_TIER_NAMES[next_tier], _cost_text(cost)]
		upgrade.disabled = not GameState.can_purchase_field_tier(field_index)


func _refresh_body_texts() -> void:
	for i in range(_cards.size()):
		_cards[i]["body"].text = _body_text(i)


func _body_text(field_index: int) -> String:
	var data: Dictionary = GameState.fields[field_index]
	var tier := clampi(int(data.get("tier", 0)), 0, BalanceConfig.FIELD_TIER_NAMES.size() - 1)
	var header := "灵田 %d · %s · 产量 ×%s" % [field_index + 1, BalanceConfig.FIELD_TIER_NAMES[tier], NumberFormat.format(GameState.field_tier_mult(field_index))]
	if field_index >= GameState.unlocked_fields:
		return header + "\n未购买\n等待购买"
	if GameState.lifespan_depleted:
		return header + "\n大限已至\n去商店续命或开始新局"
	if GameState.tribulation_active:
		return header + "\n渡劫中\n生产暂停"
	return header + "\n" + _status_text(field_index)


func _status_text(field_index: int) -> String:
	var data: Dictionary = GameState.fields[field_index]
	var crop_id := String(data.get("crop_id", ""))
	if crop_id == "":
		if _unlocked_crop_set.size() <= 1:
			return "空闲，点击种植"
		return "空闲，选择下方作物种植"
	var crop: Variant = CropConfig.get_crop(crop_id)
	var crop_name := crop_id if crop == null else String(crop.get("name", crop_id))
	var now := Time.get_unix_time_from_system()
	var ready_at := float(data.get("ready_at", 0.0))
	var lines := PackedStringArray()
	if now >= ready_at:
		lines.append("%s 已成熟，自动收获中" % crop_name)
	else:
		lines.append("%s 生长中 · 剩 %d 秒 · 点击加速" % [crop_name, maxi(0, int(ready_at - now))])
	if field_index < GameState.insect_events.size():
		var event: Dictionary = GameState.insect_events[field_index]
		if bool(event.get("active", false)):
			var charges := 0
			if field_index < GameState.guardian_array_charges.size():
				charges = int(GameState.guardian_array_charges[field_index])
			lines.append("噬金虫：阵法 %d / 虫害 %d" % [charges, int(event.get("pest_level", 0))])
		else:
			var insect_remaining := int(ceil(float(event.get("next_attack_at", 0.0)) - now))
			if insect_remaining > 0:
				lines.append("噬金虫侦测：%d 秒后出现" % insect_remaining)
			else:
				lines.append("噬金虫侦测：即将出现")
	if GameState.is_spirit_rain_active(field_index):
		lines.append("灵雨诀生效中")
	return "\n".join(lines)


func _on_body_pressed(field_index: int) -> void:
	if GameState.tribulation_active:
		_set_feedback("渡劫中：灵田操作暂停，完成天劫后恢复。")
		return
	if GameState.lifespan_depleted:
		_set_feedback("大限已至：请去商店续命，或在修炼·突破面板开始新局。")
		return
	if field_index >= GameState.unlocked_fields:
		_set_feedback("这块灵田尚未购买。")
		return
	var data: Dictionary = GameState.fields[field_index]
	var crop_id := String(data.get("crop_id", ""))
	if crop_id == "":
		if _unlocked_crop_set.size() == 1:
			_on_plant(field_index, String(GameState.get_crop_options()[0]))
		else:
			_set_feedback("选择下方作物种植。")
		return
	var now := Time.get_unix_time_from_system()
	if now >= float(data.get("ready_at", 0.0)):
		_set_feedback("作物已成熟，自动收获会立即补种。")
		return
	var result: Dictionary = GameState.speed_up_crop(field_index)
	if bool(result.get("ok", false)):
		_set_feedback("点击加速 %s 秒，剩余 %s 秒。" % [NumberFormat.format(float(result.get("seconds", 0.0))), NumberFormat.format(float(result.get("remaining", 0.0)))])
	else:
		_set_feedback("当前作物已经成熟或无法加速。")


func _on_plant(field_index: int, crop_id: String) -> void:
	if GameState.plant_crop(field_index, crop_id):
		_switching_fields.erase(field_index)
		var crop: Variant = CropConfig.get_crop(crop_id)
		var disp_name := crop_id if crop == null else String(crop.get("name", crop_id))
		_set_feedback("种下 %s。" % disp_name)
	else:
		_set_feedback("种植失败：灵田尚未购买或当前已到大限。")
	_refresh_full()


func _on_crop_button(field_index: int, crop_id: String) -> void:
	if field_index < 0 or field_index >= GameState.fields.size():
		return
	var current_crop_id := String(GameState.fields[field_index].get("crop_id", ""))
	if current_crop_id == "":
		_on_plant(field_index, crop_id)
	else:
		_on_switch_crop(field_index, crop_id)


func _on_switch_pressed(field_index: int) -> void:
	if field_index < 0 or field_index >= GameState.fields.size():
		return
	var current_crop_id := String(GameState.fields[field_index].get("crop_id", ""))
	if current_crop_id == "":
		_set_feedback("当前灵田为空，请直接选择作物种植。")
		return
	_switching_fields[field_index] = not bool(_switching_fields.get(field_index, false))
	if bool(_switching_fields.get(field_index, false)):
		_set_feedback("请选择新作物；切换会放弃当前生长进度并立即重新计时。")
	else:
		_set_feedback("已取消切换。")
	_refresh_full()


func _on_switch_crop(field_index: int, crop_id: String) -> void:
	if GameState.switch_crop(field_index, crop_id):
		_switching_fields.erase(field_index)
		var crop: Variant = CropConfig.get_crop(crop_id)
		var disp_name := crop_id if crop == null else String(crop.get("name", crop_id))
		_set_feedback("已切换为 %s，当前生长进度已重置。" % disp_name)
	else:
		_set_feedback("切换失败：作物未解锁或当前灵田状态不允许切换。")
	_refresh_full()


func _on_buy_slot(field_index: int) -> void:
	if GameState.buy_field_slot(field_index):
		_set_feedback("灵田%d购买成功。" % (field_index + 1))
	else:
		_set_feedback("购买失败：需要足够灵石，且当前不能处于大限。")
	_refresh_full()


func _on_upgrade(field_index: int) -> void:
	if GameState.upgrade_field_tier(field_index):
		_set_feedback("灵田升档成功，产量倍率提升。")
	else:
		_set_feedback("升档失败：需要已购买该灵田、达到对应境界并有足够灵石。")
	_refresh_full()


func _cost_text(cost: Dictionary) -> String:
	return NumberFormat.format(float(cost.get("spirit_stones", 0.0))) + " 灵石"


func _realm_name(realm_index: int) -> String:
	if realm_index < 0 or realm_index >= RealmConfig.realm_count():
		return "更高境界"
	return String(BalanceConfig.REALMS[realm_index].get("name", "更高境界"))


func _set_feedback(text: String) -> void:
	_feedback.text = text
	_feedback_time = _FEEDBACK_LINGER
