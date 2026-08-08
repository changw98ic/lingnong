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
	_root_vbox.add_child(_make_label("修为达到门槛后手动突破。每次突破获得天赋点，修为里程碑也会持续发放天赋点。", 14, Color(0.72, 0.82, 0.76)))

	_realm_info_label = _make_label("", 16, Color(0.92, 0.95, 0.9))
	_realm_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_realm_info_label)

	_breakthrough_preview_label = _make_label("", 14, Color(0.78, 0.88, 0.78))
	_breakthrough_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_breakthrough_preview_label)

	_breakthrough_button = _make_button("尝试突破", _on_breakthrough_pressed)
	_root_vbox.add_child(_breakthrough_button)
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
	_realm_info_label.text = "当前境界：%s\n当前修为：%s" % [realm_name, NumberFormat.format(current)]

	if lifespan_depleted:
		_breakthrough_preview_label.text = "大限已至：自动种植、收获、炼丹和自动修炼已暂停。可先去商店续命；也可以保留天赋树和未用天赋点，开始新局。"
		_breakthrough_button.visible = false
		_new_run_button.visible = true
	elif is_finite(next_requirement):
		var next_name := _next_realm_name(realm_index)
		var pct := current / next_requirement * 100.0 if next_requirement > 0.0 else 0.0
		_realm_info_label.text += "\n下一境界：%s　需要 %s（%.1f%%）" % [next_name, NumberFormat.format(next_requirement), pct]
		_breakthrough_preview_label.text = "突破后解锁：" + _describe_rewards(realm_index + 1)
		_breakthrough_button.disabled = not GameState.can_breakthrough()
		_breakthrough_button.text = "突破 → %s" % next_name if GameState.can_breakthrough() else "继续积累修为"
		_breakthrough_button.visible = true
		_new_run_button.visible = false
	else:
		_breakthrough_preview_label.text = "已达当前原型最高境界。后续成长集中在灵田、自动化和天赋树。"
		_breakthrough_button.disabled = true
		_breakthrough_button.text = "已达最高境界"
		_breakthrough_button.visible = true
		_new_run_button.visible = false

	_talent_info_label.text = "当前天赋点：%d\n打开【天赋树】面板，在分支节点之间选择路线。已完成修为里程碑：%d/%d。" % [
		int(GameState.talent_points),
		int(GameState.talent_milestone_index),
		BalanceConfig.TALENT_MILESTONES.size(),
	]


func _on_breakthrough_pressed() -> void:
	if GameState.breakthrough():
		_set_feedback("突破成功：境界倍率提升，获得新的天赋点。")
	else:
		_set_feedback("修为还没有达到下一境界门槛。")


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
	if bool(rewards.get("unlock_mind_flower", false)):
		parts.append("凝神花")
	if bool(rewards.get("unlock_sun_fruit", false)):
		parts.append("赤阳果")
	if bool(rewards.get("unlock_heaven_lotus", false)):
		parts.append("天道莲")
	return ", ".join(parts) if not parts.is_empty() else "无新增解锁项"


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
