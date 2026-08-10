## 境界突破面板。
## 天赋树已经独立到 TalentPanel；这里展示境界门槛、突破模式、渡劫检查、轮回与天人五衰。
class_name ProgressionPanel
extends Control


const _REFRESH_INTERVAL := 0.25

var _root_vbox: VBoxContainer
var _realm_info_label: Label
var _breakthrough_preview_label: Label
var _breakthrough_buttons: Array[Button] = []
var _tribulation_status_label: Label
var _tribulation_button: Button
var _tribulation_controls: GridContainer
var _healing_button: Button
var _resistance_button: Button
var _enhancement_button: Button
var _reincarnation_button: Button
var _reincarnation_preview_label: Label
var _decay_controls: GridContainer
var _reincarnate_immediately_button: Button
var _decay_continue_button: Button
var _lifespan_tribulation_button: Button
var _boon_controls: GridContainer
var _boon_buttons: Array[Button] = []
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
	_root_vbox.add_child(_make_label("修为达标并备齐突破材料后，选择稳定/强行突破；三道生产体系检查全部通过才晋级。", 14, Color(0.72, 0.82, 0.76)))

	_realm_info_label = _make_label("", 16, Color(0.92, 0.95, 0.9))
	_realm_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_realm_info_label)

	_breakthrough_preview_label = _make_label("", 14, Color(0.78, 0.88, 0.78))
	_breakthrough_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_breakthrough_preview_label)

	var breakthrough_row := HBoxContainer.new()
	breakthrough_row.add_theme_constant_override("separation", 6)
	_breakthrough_buttons.append(_make_button("稳定突破（材料×1.5，95%）", _on_breakthrough_stable))
	_breakthrough_buttons.append(_make_button("强行突破（材料×1，50%）", _on_breakthrough_forced))
	for button in _breakthrough_buttons:
		breakthrough_row.add_child(button)
	_root_vbox.add_child(breakthrough_row)

	_tribulation_status_label = _make_label("", 14, Color(1.0, 0.72, 0.42))
	_tribulation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tribulation_status_label.visible = false
	_root_vbox.add_child(_tribulation_status_label)
	_tribulation_button = _make_button("迎接下一道检查", _on_tribulation_strike)
	_tribulation_button.visible = false
	_root_vbox.add_child(_tribulation_button)
	_tribulation_controls = GridContainer.new()
	_tribulation_controls.columns = 3
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

	_reincarnation_preview_label = _make_label("", 14, Color(0.8, 0.9, 1.0))
	_reincarnation_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reincarnation_preview_label.visible = false
	_root_vbox.add_child(_reincarnation_preview_label)
	_reincarnation_button = _make_button("随时轮回", _on_reincarnate_now)
	_reincarnation_button.visible = false
	_root_vbox.add_child(_reincarnation_button)
	# 天人五衰三选择。
	_decay_controls = GridContainer.new()
	_decay_controls.columns = 3
	_decay_controls.add_theme_constant_override("h_separation", 6)
	_decay_controls.add_theme_constant_override("v_separation", 6)
	_decay_controls.visible = false
	_reincarnate_immediately_button = _make_button("立即轮回（×100%）", _on_reincarnate_now)
	_decay_continue_button = _make_button("继续修炼（生产-50%）", _on_decay_continue)
	_lifespan_tribulation_button = _make_button("渡劫续命（70%）", _on_lifespan_tribulation)
	_decay_controls.add_child(_reincarnate_immediately_button)
	_decay_controls.add_child(_decay_continue_button)
	_decay_controls.add_child(_lifespan_tribulation_button)
	_root_vbox.add_child(_decay_controls)
	# 转世天赋三选一。
	_boon_controls = GridContainer.new()
	_boon_controls.columns = 3
	_boon_controls.add_theme_constant_override("h_separation", 6)
	_boon_controls.add_theme_constant_override("v_separation", 6)
	_boon_controls.visible = false
	for boon in GameState.get_reincarnation_boon_options():
		var boon_id := String(boon.get("id", ""))
		var button := _make_button(String(boon.get("name", boon_id)), _on_choose_boon.bind(boon_id))
		button.tooltip_text = String(boon.get("desc", ""))
		_boon_controls.add_child(button)
		_boon_buttons.append(button)
	_root_vbox.add_child(_boon_controls)
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
	var decay_stage := bool(GameState.is_decay_stage())
	var decay_running := bool(GameState.decay_active)
	var pending_boon := bool(GameState.pending_reincarnation_boon)
	_realm_info_label.text = "当前境界：%s\n当前修为：%s　寿元：%s / %s 年" % [
		realm_name,
		NumberFormat.format(current),
		NumberFormat.format(GameState.lifespan_years),
		NumberFormat.format(GameState.lifespan_max_years),
	]
	if decay_running:
		_realm_info_label.text += "\n天人五衰·继续修炼中：生产 -50%，每 60 秒天命奇遇。"
	elif decay_stage:
		_realm_info_label.text += "\n⚠ 天人五衰将至（寿元不足 20%）：立即轮回、继续修炼或渡劫续命。"
	if GameState.reincarnation_boon != "":
		var boon := BalanceConfig.reincarnation_boon(GameState.reincarnation_boon)
		_realm_info_label.text += "\n本世转世天赋：%s（%s）" % [String(boon.get("name", "")), String(boon.get("desc", ""))]

	if tribulation_active:
		var status: Dictionary = GameState.get_tribulation_status()
		_realm_info_label.text += "\n正在挑战：%s（完成后进入%s）" % [String(status.get("name", "天劫")), String(status.get("target_realm_name", "下一境界"))]
		_breakthrough_preview_label.text = "天劫期间暂停种植、收获、事件和自动修炼。检查失败不损失修为，获得永久雷劫淬体（生产/修为 +5%）。"
		_hide_reincarnation_ui()
		_refresh_tribulation(status)
	elif pending_boon:
		_breakthrough_preview_label.text = "转世成功！选择一个本世生效的转世天赋（跨世不保留）。"
		_hide_breakthrough_ui()
		_hide_tribulation_controls()
		_hide_decay_controls()
		_show_boon_controls()
	elif lifespan_depleted:
		_breakthrough_preview_label.text = "大限已至：生产暂停。可先去商店续命，或立即轮回（保留天赋树、未用天赋点和长期成长）。"
		_hide_breakthrough_ui()
		_hide_tribulation_controls()
		_hide_boon_controls()
		_refresh_reincarnation_ui(true)
	elif decay_stage:
		_breakthrough_preview_label.text = "天人五衰：寿元不足 20%。立即轮回拿满奖励，继续修炼接受生产衰减，或渡劫续命搏 70% 成功率。"
		_hide_breakthrough_ui()
		_hide_tribulation_controls()
		_hide_boon_controls()
		_refresh_decay_controls()
		_refresh_reincarnation_ui(false)
	elif is_finite(next_requirement):
		var next_name := _next_realm_name(realm_index)
		var pct := current / next_requirement * 100.0 if next_requirement > 0.0 else 0.0
		_realm_info_label.text += "\n下一境界：%s　需要 %s（%.1f%%）" % [next_name, NumberFormat.format(next_requirement), pct]
		_breakthrough_preview_label.text = "突破后解锁：%s\n%s" % [_describe_rewards(realm_index + 1), _describe_requirements(realm_index + 1)]
		_refresh_breakthrough_buttons()
		_hide_tribulation_controls()
		_hide_decay_controls()
		_hide_boon_controls()
		_refresh_reincarnation_ui(false)
	else:
		_breakthrough_preview_label.text = "已达当前原型最高境界。后续成长集中在灵田、自动化和天赋树。"
		for button in _breakthrough_buttons:
			button.disabled = true
			button.visible = true
		button_text_for_max()
		_hide_tribulation_controls()
		_hide_decay_controls()
		_hide_boon_controls()
		_refresh_reincarnation_ui(false)

	if not tribulation_active and GameState.tribulation_last_result != "":
		_breakthrough_preview_label.text += "\n" + String(GameState.tribulation_last_result)

	_talent_info_label.text = "可用天赋点：%d（累计获得 %d）\n打开【天赋树】面板，在分支节点之间选择路线。已完成修为里程碑：%d/%d。\n碎丹经验：+%.0f%%（封顶 +%.0f%%）　雷劫淬体：生产/修为 +%.0f%%" % [
		int(GameState.talent_points),
		int(GameState.talent_points_earned),
		int(GameState.talent_milestone_index),
		BalanceConfig.TALENT_MILESTONES.size(),
		GameState.broken_dan_experience * 100.0,
		BalanceConfig.BROKEN_DAN_SUCCESS_CAP * 100.0,
		GameState.tribulation_refine_bonus * 100.0,
	]


func button_text_for_max() -> void:
	for button in _breakthrough_buttons:
		button.text = "已达最高境界"


func _refresh_breakthrough_buttons() -> void:
	var can_break := GameState.can_breakthrough()
	var stable_info: Dictionary = GameState.get_breakthrough_mode_info("stable")
	var forced_info: Dictionary = GameState.get_breakthrough_mode_info("forced")
	_breakthrough_buttons[0].text = "稳定突破（材料×1.5，成功率 %.0f%%）" % (float(stable_info.get("success_rate", 0.0)) * 100.0)
	_breakthrough_buttons[1].text = "强行突破（材料×1，成功率 %.0f%%）" % (float(forced_info.get("success_rate", 0.0)) * 100.0)
	_breakthrough_buttons[0].disabled = not can_break
	_breakthrough_buttons[1].disabled = not can_break
	for button in _breakthrough_buttons:
		button.visible = true


func _refresh_reincarnation_ui(depleted: bool) -> void:
	var preview: Dictionary = GameState.get_reincarnation_reward_preview()
	_reincarnation_preview_label.visible = true
	var mult_text := "×%.0f%%" % (float(preview.get("mult", 1.0)) * 100.0)
	_reincarnation_preview_label.text = "轮回奖励：保留未用天赋点 %d + 本世里程碑 %d×2 + 本世突破 %d×1 = %d 点（%s）\n总天赋点：%d" % [
		int(preview.get("retained_points", 0)),
		int(preview.get("milestones_crossed", 0)),
		int(preview.get("promotions", 0)),
		int(preview.get("points", 0)),
		mult_text,
		int(preview.get("total_points", 0)),
	]
	if bool(preview.get("early", false)):
		_reincarnation_preview_label.text += "\n提前轮回：奖励 ×80%。"
	elif not depleted:
		_reincarnation_preview_label.text += "\n已进入天人五衰，轮回奖励 ×100%。"
	if depleted:
		_reincarnation_button.visible = true
		_reincarnation_button.text = "立即轮回（天人五衰 ×100%）"
	else:
		_reincarnation_button.visible = not bool(GameState.tribulation_active) and not bool(GameState.pending_reincarnation_boon)
		_reincarnation_button.text = "随时轮回（提前 ×80%）"


func _refresh_decay_controls() -> void:
	_decay_controls.visible = true
	var stone_cost := GameState.lifespan_max_years * BalanceConfig.LIFESPAN_TRIBULATION_STONE_RATIO
	var pills_ready := GameState.healing_pills >= 1 and GameState.resistance_pills >= 1 and GameState.enhancement_pills >= 1
	_reincarnate_immediately_button.disabled = false
	_decay_continue_button.disabled = bool(GameState.decay_active)
	_lifespan_tribulation_button.disabled = not pills_ready or GameState.spirit_stones < stone_cost
	_lifespan_tribulation_button.text = "渡劫续命（3丹+%s灵石，70%）" % NumberFormat.format(stone_cost)


func _hide_breakthrough_ui() -> void:
	for button in _breakthrough_buttons:
		button.visible = false


func _hide_reincarnation_ui() -> void:
	_reincarnation_button.visible = false
	_reincarnation_preview_label.visible = false
	_hide_decay_controls()
	_hide_boon_controls()


func _hide_decay_controls() -> void:
	_decay_controls.visible = false


func _show_boon_controls() -> void:
	_boon_controls.visible = true
	_reincarnation_button.visible = false
	_reincarnation_preview_label.visible = false


func _hide_boon_controls() -> void:
	_boon_controls.visible = false


func _refresh_tribulation(status: Dictionary) -> void:
	_tribulation_status_label.visible = true
	_tribulation_button.visible = true
	_tribulation_controls.visible = true
	var seconds_to_next := float(status.get("seconds_to_next", 0.0))
	var check_lines := PackedStringArray()
	for check in status.get("checks", []):
		var mark := "✓" if bool(check.get("passed", false)) else "·"
		var prepared_mark := "【已准备】" if bool(check.get("prepared", false)) else ""
		check_lines.append("%s %s（%s）%s" % [mark, String(check.get("name", "")), String(check.get("requirement", "")), prepared_mark])
	_tribulation_status_label.text = "天劫：%s　进度 %d/%d　下一道自动结算 %.1f 秒\n%s\n库存：治疗丹 %d　抗性丹 %d　强化丹 %d" % [
		String(status.get("name", "天劫")),
		int(status.get("strikes_survived", 0)),
		int(status.get("total_strikes", 0)),
		seconds_to_next,
		"\n".join(check_lines),
		int(status.get("healing_pills", 0)),
		int(status.get("resistance_pills", 0)),
		int(status.get("enhancement_pills", 0)),
	]
	_tribulation_button.text = "迎接下一道检查（立即结算）"
	_tribulation_button.disabled = false
	var prepared: Array = [false, false, false]
	if status.has("checks"):
		for check in status.get("checks", []):
			var check_index := int(check.get("index", 0))
			if check_index >= 0 and check_index < prepared.size():
				prepared[check_index] = bool(check.get("prepared", false))
	_healing_button.text = "治疗丹（灵气劫减半）×%d" % int(status.get("healing_pills", 0))
	_resistance_button.text = "抗性丹（底蕴劫减半）×%d" % int(status.get("resistance_pills", 0))
	_enhancement_button.text = "强化丹（气运劫直通）×%d" % int(status.get("enhancement_pills", 0))
	_healing_button.disabled = int(status.get("healing_pills", 0)) <= 0 or prepared[0]
	_resistance_button.disabled = int(status.get("resistance_pills", 0)) <= 0 or prepared[1]
	_enhancement_button.disabled = int(status.get("enhancement_pills", 0)) <= 0 or prepared[2]


func _hide_tribulation_controls() -> void:
	_tribulation_status_label.visible = false
	_tribulation_button.visible = false
	_tribulation_controls.visible = false


func _on_breakthrough_stable() -> void:
	_attempt_breakthrough("stable")


func _on_breakthrough_forced() -> void:
	_attempt_breakthrough("forced")


func _attempt_breakthrough(mode: String) -> void:
	var result: Dictionary = GameState.breakthrough(mode)
	if not bool(result.get("ok", false)):
		_set_feedback("突破失败：%s。" % String(result.get("reason", GameState.get_breakthrough_block_reason())))
	elif not bool(result.get("success", false)):
		_set_feedback("碎丹：材料已消耗，碎丹经验 +%.0f%%。" % (BalanceConfig.BROKEN_DAN_SUCCESS_BONUS * 100.0))
	else:
		_set_feedback("突破材料已消耗，开始%s：目标%s。" % [GameState.get_tribulation_name(), _next_realm_name(GameState.realm_index)])


func _on_tribulation_strike() -> void:
	if GameState.advance_tribulation():
		if GameState.tribulation_active:
			_set_feedback("当前检查已结算，剩余 %d 道。" % (GameState.tribulation_total_strikes - GameState.tribulation_strikes_survived))
		elif GameState.tribulation_last_result.begins_with("渡劫成功"):
			_set_feedback("渡劫成功：已进入%s，获得突破奖励。" % GameState.get_realm_name())
		else:
			_set_feedback(GameState.tribulation_last_result)


func _on_healing_pill() -> void:
	_set_feedback("治疗丹使用%s。" % ("成功：第一劫·灵气需求减半" if GameState.use_healing_pill() else "失败：库存不足或已准备"))


func _on_resistance_pill() -> void:
	_set_feedback("抗性丹使用%s。" % ("成功：第二劫·底蕴需求减半" if GameState.use_resistance_pill() else "失败：库存不足或已准备"))


func _on_enhancement_pill() -> void:
	_set_feedback("强化丹使用%s。" % ("成功：第三劫·气运直接通过" if GameState.use_enhancement_pill() else "失败：库存不足或已准备"))


func _on_reincarnate_now() -> void:
	if GameState.reincarnate_now():
		_set_feedback("轮回成功：长期成长保留，请在下方选择本世转世天赋。")
	else:
		_set_feedback("当前无法轮回（渡劫中或尚未选择转世天赋）。")


func _on_decay_continue() -> void:
	if GameState.begin_decay_continuation():
		_set_feedback("继续修炼：生产 -50% 至寿元耗尽，期间每 60 秒 roll 一次天命奇遇。")
	else:
		_set_feedback("当前不在天人五衰阶段。")


func _on_lifespan_tribulation() -> void:
	var result: Dictionary = GameState.attempt_lifespan_tribulation()
	if not bool(result.get("ok", false)):
		_set_feedback("渡劫续命失败：%s。" % String(result.get("reason", "")))
	elif bool(result.get("success", false)):
		_set_feedback("渡劫续命成功：寿元 +%d 年，衰败解除。" % int(BalanceConfig.LIFESPAN_TRIBULATION_SUCCESS_YEARS))
	else:
		_set_feedback("渡劫续命失败：寿元耗尽，已强制轮回（奖励 ×80%）。")


func _on_choose_boon(boon_id: String) -> void:
	if GameState.choose_reincarnation_boon(boon_id):
		var boon := BalanceConfig.reincarnation_boon(boon_id)
		_set_feedback("本世转世天赋已生效：%s" % String(boon.get("name", boon_id)))
	else:
		_set_feedback("当前不需要选择转世天赋。")


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
