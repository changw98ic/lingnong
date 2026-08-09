## 境界突破面板。
## 天赋树已经独立到 TalentPanel；这里只展示境界门槛、解锁内容和天赋点来源。
class_name ProgressionPanel
extends Control


const _REFRESH_INTERVAL := 0.25

var _root_vbox: VBoxContainer
var _realm_info_label: Label
var _breakthrough_preview_label: Label
var _breakthrough_button: Button
var _new_run_button: Button
var _tribulation_status_label: Label
var _tribulation_button: Button
var _tribulation_controls: GridContainer
var _healing_button: Button
var _resistance_button: Button
var _enhancement_button: Button
var _talent_info_label: Label
var _feedback_label: Label
var _feedback_remaining := 0.0
var _refresh_accumulator := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(420.0, 360.0)
	_root_vbox = _build_root_vbox()
	_build_sections()
	if GameState.has_signal("state_changed"):
		GameState.state_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_feedback_remaining -= delta
	if _feedback_remaining <= 0.0:
		_feedback_label.text = ""
	_refresh_accumulator += delta
	if _refresh_accumulator >= _REFRESH_INTERVAL:
		_refresh_accumulator = 0.0
		_refresh()


func _build_root_vbox() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	return vbox


func _build_sections() -> void:
	_root_vbox.add_child(_make_label("【修炼与突破】", 20, Color(1.0, 0.9, 0.5)))
	_root_vbox.add_child(_make_label("修为达到门槛并备齐突破材料后才能开始天劫。材料和渡劫丹药都只能去商店兑换。", 14, Color(0.72, 0.82, 0.76)))

	_realm_info_label = _make_label("", 16, Color(0.92, 0.95, 0.9))
	_realm_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_realm_info_label)

	_breakthrough_preview_label = _make_label("", 14, Color(0.78, 0.88, 0.78))
	_breakthrough_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_breakthrough_preview_label)

	_breakthrough_button = _make_button("尝试突破", _on_breakthrough_pressed)
	_root_vbox.add_child(_breakthrough_button)
	_tribulation_status_label = _make_label("", 14, Color(1.0, 0.72, 0.42))
	_tribulation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tribulation_status_label.visible = false
	_root_vbox.add_child(_tribulation_status_label)
	_tribulation_button = _make_button("迎接下一道天劫", _on_tribulation_strike)
	_tribulation_button.visible = false
	_root_vbox.add_child(_tribulation_button)
	_tribulation_controls = GridContainer.new()
	_tribulation_controls.columns = 2
	_tribulation_controls.add_theme_constant_override("h_separation", 6)
	_tribulation_controls.add_theme_constant_override("v_separation", 6)
	_tribulation_controls.visible = false
	_healing_button = _make_button("治疗丹", _on_healing_pill)
	_resistance_button = _make_button("抗性丹", _on_resistance_pill)
	_enhancement_button = _make_button("强化丹", _on_enhancement_pill)
	_tribulation_controls.add_child(_healing_button)
	_tribulation_controls.add_child(_resistance_button)
	_tribulation_controls.add_child(_enhancement_button)
	_root_vbox.add_child(_tribulation_controls)
	_new_run_button = _make_button("大限结算：保留天赋并开始新局", _on_new_run_pressed)
	_new_run_button.visible = false
	_root_vbox.add_child(_new_run_button)
	_root_vbox.add_child(HSeparator.new())

	_talent_info_label = _make_label("", 15, Color(0.9, 0.86, 0.65))
	_talent_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_talent_info_label)

	_feedback_label = _make_label("", 14, Color(0.95, 0.85, 0.6))
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_feedback_label)


func _refresh() -> void:
	var realm_index := int(GameState.realm_index)
	var current := float(GameState.cultivation)
	var next_requirement := float(GameState.get_next_realm_requirement())
	var realm_name := GameState.get_realm_name()
	var lifespan_depleted := bool(GameState.lifespan_depleted)
	var tribulation_active := bool(GameState.tribulation_active)
	_realm_info_label.text = "当前境界：%s\n当前修为：%s" % [realm_name, NumberFormat.format(current)]

	if tribulation_active:
		var status: Dictionary = GameState.get_tribulation_status()
		_realm_info_label.text += "\n正在挑战：%s（完成后进入%s）" % [String(status.get("name", "天劫")), String(status.get("target_realm_name", "下一境界"))]
		_breakthrough_preview_label.text = "天劫期间暂停种植、收获、事件和自动修炼。可以手动迎接下一道，也可以等待自动结算。"
		_breakthrough_button.visible = false
		_new_run_button.visible = false
		_refresh_tribulation(status)
	elif lifespan_depleted:
		_breakthrough_preview_label.text = "大限已至：自动种植、收获和自动修炼已暂停。可先去商店续命；也可以保留天赋树和未用天赋点，开始新局。"
		_breakthrough_button.visible = false
		_new_run_button.visible = true
		_hide_tribulation_controls()
	elif is_finite(next_requirement):
		var next_name := _next_realm_name(realm_index)
		var pct := current / next_requirement * 100.0 if next_requirement > 0.0 else 0.0
		_realm_info_label.text += "\n下一境界：%s　需要 %s（%.1f%%）" % [next_name, NumberFormat.format(next_requirement), pct]
		_breakthrough_preview_label.text = "突破后解锁：%s\n%s" % [_describe_rewards(realm_index + 1), _describe_requirements(realm_index + 1)]
		_breakthrough_button.disabled = not GameState.can_breakthrough()
		if GameState.can_breakthrough():
			_breakthrough_button.text = "突破 → %s" % next_name
		elif current < next_requirement:
			_breakthrough_button.text = "继续积累修为"
		else:
			_breakthrough_button.text = "去商店兑换突破材料"
		_breakthrough_button.visible = true
		_new_run_button.visible = false
		_hide_tribulation_controls()
	else:
		_breakthrough_preview_label.text = "已达当前原型最高境界。后续成长集中在灵田、自动化和天赋树。"
		_breakthrough_button.disabled = true
		_breakthrough_button.text = "已达最高境界"
		_breakthrough_button.visible = true
		_new_run_button.visible = false
		_hide_tribulation_controls()

	if not tribulation_active and GameState.tribulation_last_result != "":
		_breakthrough_preview_label.text += "\n" + String(GameState.tribulation_last_result)

	_talent_info_label.text = "可用天赋点：%d（累计获得 %d）\n打开【天赋树】面板，在分支节点之间选择路线。已完成修为里程碑：%d/%d。" % [
		int(GameState.talent_points),
		int(GameState.talent_points_earned),
		int(GameState.talent_milestone_index),
		BalanceConfig.TALENT_MILESTONES.size(),
	]


func _on_breakthrough_pressed() -> void:
	if GameState.breakthrough():
		var status: Dictionary = GameState.get_tribulation_status()
		_set_feedback("突破材料已消耗，开始%s：目标%s。" % [String(status.get("name", "天劫")), String(status.get("target_realm_name", "下一境界"))])
	else:
		_set_feedback("突破失败：%s。" % GameState.get_breakthrough_block_reason())


func _on_tribulation_strike() -> void:
	if GameState.advance_tribulation():
		if GameState.tribulation_active:
			_set_feedback("天劫已结算一道，剩余 %d 道。" % (GameState.tribulation_total_strikes - GameState.tribulation_strikes_survived))
		elif GameState.tribulation_last_result.begins_with("渡劫成功"):
			_set_feedback("渡劫成功：已进入%s，获得突破奖励。" % GameState.get_realm_name())
		else:
			_set_feedback(GameState.tribulation_last_result)


func _on_healing_pill() -> void:
	_set_feedback("治疗丹使用%s。" % ("成功" if GameState.use_healing_pill() else "失败：劫体已满或库存不足"))


func _on_resistance_pill() -> void:
	_set_feedback("抗性丹使用%s。" % ("成功，接下来伤害减半" if GameState.use_resistance_pill() else "失败：库存不足或不在渡劫中"))


func _on_enhancement_pill() -> void:
	_set_feedback("强化丹使用%s。" % ("成功，劫体上限提升" if GameState.use_enhancement_pill() else "失败：库存不足或本次已使用"))


func _refresh_tribulation(status: Dictionary) -> void:
	_tribulation_status_label.visible = true
	_tribulation_button.visible = true
	_tribulation_controls.visible = true
	var seconds_to_next := float(status.get("seconds_to_next", 0.0))
	_tribulation_status_label.text = "天劫：%s　进度 %d/%d\n劫体 %s/%s　最近伤害 %s　下一道自动结算 %.1f 秒\n抗性剩余 %d 道　强化%s\n库存：治疗丹 %d　抗性丹 %d　强化丹 %d" % [
		String(status.get("name", "天劫")),
		int(status.get("strikes_survived", 0)),
		int(status.get("total_strikes", 0)),
		NumberFormat.format(float(status.get("health", 0.0))),
		NumberFormat.format(float(status.get("health_max", 0.0))),
		NumberFormat.format(float(status.get("last_damage", 0.0))),
		seconds_to_next,
		int(status.get("resistance_charges", 0)),
		"已生效" if bool(status.get("enhancement_active", false)) else "未使用",
		int(status.get("healing_pills", 0)),
		int(status.get("resistance_pills", 0)),
		int(status.get("enhancement_pills", 0)),
	]
	_tribulation_button.text = "迎接下一道天劫（立即结算）"
	_tribulation_button.disabled = false
	_healing_button.text = "治疗丹（+%.0f）×%d" % [BalanceConfig.TRIBULATION_HEAL_AMOUNT, int(status.get("healing_pills", 0))]
	_resistance_button.text = "抗性丹（%.0f道）×%d" % [float(BalanceConfig.TRIBULATION_RESISTANCE_CHARGES), int(status.get("resistance_pills", 0))]
	_enhancement_button.text = "强化丹（劫体+%.0f）×%d" % [BalanceConfig.TRIBULATION_ENHANCEMENT_HEALTH_BONUS, int(status.get("enhancement_pills", 0))]
	_healing_button.disabled = int(status.get("healing_pills", 0)) <= 0 or float(status.get("health", 0.0)) >= float(status.get("health_max", 0.0))
	_resistance_button.disabled = int(status.get("resistance_pills", 0)) <= 0
	_enhancement_button.disabled = int(status.get("enhancement_pills", 0)) <= 0 or bool(status.get("enhancement_active", false))


func _hide_tribulation_controls() -> void:
	_tribulation_status_label.visible = false
	_tribulation_button.visible = false
	_tribulation_controls.visible = false


func _on_new_run_pressed() -> void:
	if GameState.start_new_run():
		_set_feedback("新局开始：天赋树、未用天赋点和修为里程碑已保留。")
	else:
		_set_feedback("当前还没有到达大限。")


func _next_realm_name(realm_index: int) -> String:
	var idx := realm_index + 1
	if idx < 0 or idx >= RealmConfig.realm_count():
		return "—"
	return String(BalanceConfig.REALMS[idx]["name"])


func _describe_rewards(realm_index: int) -> String:
	var rewards := RealmConfig.breakthrough_rewards(realm_index)
	var parts := PackedStringArray()
	match realm_index:
		1:
			parts.append("开放灵田升至灵田")
		2:
			parts.append("开放灵田升至宝田")
		3:
			parts.append("开放灵田升至仙田")
	if bool(rewards.get("unlock_spirit_rain", false)):
		parts.append("灵雨诀")
	if bool(rewards.get("unlock_auto_cultivation", false)):
		parts.append("自动修炼")
	for crop_id_variant in CropConfig.get_all():
		var crop_id := String(crop_id_variant)
		var crop: Variant = CropConfig.get_crop(crop_id)
		if crop is Dictionary and int(crop.get("unlock_realm", -1)) == realm_index:
			parts.append("开放%s" % String(crop.get("name", crop_id)))
	return ", ".join(parts) if not parts.is_empty() else "无新增解锁项"


func _describe_requirements(target_realm: int) -> String:
	var requirements := GameState.get_breakthrough_requirements(target_realm)
	if requirements.is_empty():
		return "突破材料：无"
	var parts := PackedStringArray()
	for requirement in requirements:
		var material_id := String(requirement.get("material_id", ""))
		var required_amount := int(requirement.get("amount", 0))
		var material: Variant = BalanceConfig.BREAKTHROUGH_MATERIALS.get(material_id, {})
		var material_name := material_id if not material is Dictionary else String(material.get("name", material_id))
		parts.append("%s %d/%d" % [material_name, GameState.get_breakthrough_material_count(material_id), required_amount])
	return "突破材料：" + "、".join(parts)


func _set_feedback(message: String) -> void:
	_feedback_label.text = message
	_feedback_remaining = 4.0


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180.0, 36.0)
	button.pressed.connect(handler)
	return button
