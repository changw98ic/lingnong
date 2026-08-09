## 游戏内数值模拟面板。
##
## 面板不维护第二份数值表：所有结果通过 GameState.get_simulation_report /
## get_simulation_matrix 读取真实境界、作物、灵田、天赋、季节、事件和自动化数据。
## 当前状态变化后会自动刷新；全量矩阵需要点击刷新，避免后台每帧重复计算大矩阵。
class_name SimulationPanel
extends Control


const MODES: Array[Dictionary] = [
	{"id": "live", "name": "实时状态"},
	{"id": "realm", "name": "境界 × 灵田"},
	{"id": "crop", "name": "作物矩阵"},
	{"id": "season", "name": "四季矩阵"},
	{"id": "talent", "name": "天赋矩阵"},
	{"id": "proficiency", "name": "熟练度矩阵"},
	{"id": "event", "name": "事件矩阵"},
	{"id": "progression", "name": "境界总表"},
	{"id": "breakthrough", "name": "突破流程"},
	{"id": "full", "name": "全量核心矩阵"},
]


var _root_vbox: VBoxContainer
var _source_label: Label
var _mode_option: OptionButton
var _realm_option: OptionButton
var _crop_option: OptionButton
var _season_option: OptionButton
var _talent_option: OptionButton
var _event_option: OptionButton
var _field_count: SpinBox
var _tier: SpinBox
var _clicks_per_second: SpinBox
var _click_scope: OptionButton
var _qi: SpinBox
var _pest_level: SpinBox
var _rain_check: CheckBox
var _auto_check: CheckBox
var _material_gate_check: CheckBox
var _tribulation_gate_check: CheckBox
var _maximize_check: CheckBox
var _auto_refresh_check: CheckBox
var _result_view: RichTextLabel
var _feedback: Label
var _refresh_button: Button
var _export_button: Button
var _refreshing := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(900.0, 560.0)
	_root_vbox = _build_root()
	_build_header()
	_build_controls()
	_build_result_view()
	_build_footer()
	if GameState.has_signal("state_changed"):
		GameState.state_changed.connect(_on_game_state_changed)
	_refresh_controls_from_state()
	_refresh_result()


func _build_root() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 7)
	margin.add_child(vbox)
	return vbox


func _build_header() -> void:
	_root_vbox.add_child(_make_label("【数值模拟】", 20, Color(1.0, 0.9, 0.5)))
	_root_vbox.add_child(_make_label(
		"直接读取 GameState：境界、天赋、作物、灵田档位、槽位价格、四季、事件、灵气、自动修炼和离线结算。灵田收获直接结算修为与灵石，不结算灵气。模拟只读，不会改变当前存档。",
		13,
		Color(0.72, 0.82, 0.76)
	))
	_source_label = _make_label("", 13, Color(0.65, 0.85, 0.95))
	_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_source_label)


func _build_controls() -> void:
	var controls := GridContainer.new()
	controls.columns = 4
	controls.add_theme_constant_override("h_separation", 10)
	controls.add_theme_constant_override("v_separation", 5)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(controls)

	_mode_option = _make_option()
	for mode in MODES:
		_mode_option.add_item(String(mode.get("name", "")))
	_mode_option.item_selected.connect(_on_mode_selected)
	controls.add_child(_control_cell("视图", _mode_option))

	_realm_option = _make_option()
	_realm_option.add_item("跟随当前")
	for realm in BalanceConfig.REALMS:
		_realm_option.add_item(String(realm.get("name", "")))
	_realm_option.item_selected.connect(_on_control_changed)
	controls.add_child(_control_cell("境界", _realm_option))

	_crop_option = _make_option()
	for crop_id_variant in CropConfig.get_all():
		var crop_id := String(crop_id_variant)
		var crop: Variant = CropConfig.get_crop(crop_id)
		_crop_option.add_item(String(crop.get("name", crop_id)) if crop != null else crop_id)
		_crop_option.set_item_metadata(_crop_option.item_count - 1, crop_id)
	_crop_option.item_selected.connect(_on_control_changed)
	controls.add_child(_control_cell("作物", _crop_option))

	_season_option = _make_option()
	_season_option.add_item("跟随当前")
	for season in BalanceConfig.SEASONS:
		_season_option.add_item(String(season.get("name", "")))
	_season_option.item_selected.connect(_on_control_changed)
	controls.add_child(_control_cell("时节", _season_option))

	_talent_option = _make_option()
	for profile in SimulationSystem.talent_profiles(GameState):
		_talent_option.add_item(String(profile.get("name", "")))
		_talent_option.set_item_metadata(_talent_option.item_count - 1, String(profile.get("id", "")))
	_talent_option.item_selected.connect(_on_control_changed)
	controls.add_child(_control_cell("天赋", _talent_option))

	_event_option = _make_option()
	for event in SimulationSystem.event_profiles(GameState):
		_event_option.add_item(String(event.get("name", "")))
		_event_option.set_item_metadata(_event_option.item_count - 1, String(event.get("id", "")))
	_event_option.item_selected.connect(_on_control_changed)
	controls.add_child(_control_cell("事件", _event_option))

	_field_count = _make_spin(1.0, float(GameState.fields.size()), 1.0)
	_field_count.value_changed.connect(_on_control_changed_value)
	controls.add_child(_control_cell("田数", _field_count))

	_tier = _make_spin(0.0, float(BalanceConfig.FIELD_TIER_MULTS.size() - 1), 1.0)
	_tier.value_changed.connect(_on_control_changed_value)
	controls.add_child(_control_cell("档位", _tier))

	_clicks_per_second = _make_spin(0.0, 20.0, 0.5)
	_clicks_per_second.value = BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND
	_clicks_per_second.suffix = " 次/秒"
	_clicks_per_second.value_changed.connect(_on_control_changed_value)
	controls.add_child(_control_cell("点击频率", _clicks_per_second))

	_click_scope = _make_option()
	_click_scope.add_item("全局共用（玩家总点击）")
	_click_scope.set_item_metadata(0, "global")
	_click_scope.add_item("每块灵田独立")
	_click_scope.set_item_metadata(1, "per_field")
	_click_scope.select(0)
	_click_scope.item_selected.connect(_on_control_changed)
	controls.add_child(_control_cell("点击分配", _click_scope))

	_qi = _make_spin(0.0, 1000000000.0, 100.0)
	_qi.allow_greater = true
	_qi.suffix = " 灵气"
	_qi.value_changed.connect(_on_control_changed_value)
	controls.add_child(_control_cell("灵气", _qi))

	_pest_level = _make_spin(0.0, 3.0, 1.0)
	_pest_level.suffix = " 级"
	_pest_level.value_changed.connect(_on_control_changed_value)
	controls.add_child(_control_cell("虫害", _pest_level))

	_rain_check = CheckBox.new()
	_rain_check.text = "灵雨诀"
	_rain_check.toggled.connect(_on_toggle_changed)
	controls.add_child(_control_cell("生长", _rain_check))

	_auto_check = CheckBox.new()
	_auto_check.text = "自动修炼"
	_auto_check.toggled.connect(_on_toggle_changed)
	controls.add_child(_control_cell("自动化", _auto_check))

	_material_gate_check = CheckBox.new()
	_material_gate_check.text = "按当前库存校验"
	_material_gate_check.button_pressed = true
	_material_gate_check.toggled.connect(_on_toggle_changed)
	controls.add_child(_control_cell("突破材料", _material_gate_check))

	_tribulation_gate_check = CheckBox.new()
	_tribulation_gate_check.text = "按渡劫丹库存校验"
	_tribulation_gate_check.button_pressed = true
	_tribulation_gate_check.toggled.connect(_on_toggle_changed)
	controls.add_child(_control_cell("天劫丹药", _tribulation_gate_check))

	_maximize_check = CheckBox.new()
	_maximize_check.text = "自动加点并最大化购买"
	_maximize_check.button_pressed = true
	_maximize_check.toggled.connect(_on_toggle_changed)
	controls.add_child(_control_cell("突破流程策略", _maximize_check))

	var hint := _make_label("实时状态会使用当前每块田的作物、档位、虫害和灵雨；其它视图使用上方参数重算。突破流程按点击频率推进种植、收获直接修为、突破和天劫；默认把点击频率视为玩家总点击，也可切换为每块灵田独立点击。开启最大化后，获得天赋点会立即按修为收益解锁节点，灵石会自动保证寿元、突破材料和渡劫丹药，再购买有实际收益的聚气玉。", 12, Color(0.62, 0.72, 0.68))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(hint)


func _build_result_view() -> void:
	_result_view = RichTextLabel.new()
	_result_view.bbcode_enabled = false
	_result_view.fit_content = false
	_result_view.scroll_active = true
	_result_view.scroll_following = false
	_result_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_view.custom_minimum_size = Vector2(0.0, 320.0)
	_result_view.add_theme_font_size_override("normal_font_size", 13)
	_root_vbox.add_child(_result_view)


func _build_footer() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_refresh_button = Button.new()
	_refresh_button.text = "刷新模拟"
	_refresh_button.custom_minimum_size = Vector2(110.0, 32.0)
	_refresh_button.pressed.connect(_refresh_result)
	row.add_child(_refresh_button)

	_export_button = Button.new()
	_export_button.text = "导出 JSON"
	_export_button.custom_minimum_size = Vector2(110.0, 32.0)
	_export_button.pressed.connect(_export_report)
	row.add_child(_export_button)

	_auto_refresh_check = CheckBox.new()
	_auto_refresh_check.text = "跟随游戏状态自动刷新"
	_auto_refresh_check.button_pressed = true
	row.add_child(_auto_refresh_check)

	_feedback = _make_label("", 13, Color(0.95, 0.85, 0.6))
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_feedback)
	_root_vbox.add_child(row)


func _control_cell(caption: String, control: Control) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(190.0, 0.0)
	cell.add_theme_constant_override("separation", 2)
	var label := _make_label(caption, 12, Color(0.67, 0.75, 0.72))
	cell.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(control)
	return cell


func _make_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(180.0, 28.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return option


func _make_spin(minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.custom_minimum_size = Vector2(180.0, 28.0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _refresh_controls_from_state() -> void:
	if _refreshing:
		return
	_refreshing = true
	_field_count.value = clampi(int(GameState.unlocked_fields), 1, GameState.fields.size())
	_qi.value = maxf(0.0, float(GameState.qi))
	_auto_check.button_pressed = bool(GameState.unlock_auto_cultivation)
	var current_crop := ""
	for data in GameState.fields:
		if String(data.get("crop_id", "")) != "":
			current_crop = String(data.get("crop_id", ""))
			break
	if current_crop != "":
		_select_metadata(_crop_option, current_crop)
	_select_metadata(_talent_option, "current")
	var event_id := "normal"
	if GameState.is_random_event_active():
		event_id = String(GameState.random_event)
	_select_metadata(_event_option, event_id)
	_season_option.select(clampi(int(GameState.season_index) + 1, 0, _season_option.item_count - 1))
	_refreshing = false


func _on_game_state_changed() -> void:
	_refresh_controls_from_state()
	if _auto_refresh_check != null and _auto_refresh_check.button_pressed and _mode_id() != "full":
		_refresh_result()


func _on_mode_selected(_index: int) -> void:
	_refresh_result()


func _on_control_changed(_index: int) -> void:
	if not _refreshing:
		_refresh_result()


func _on_control_changed_value(_value: float) -> void:
	if not _refreshing:
		_refresh_result()


func _on_toggle_changed(_pressed: bool) -> void:
	if not _refreshing:
		_refresh_result()


func _refresh_result() -> void:
	if _result_view == null:
		return
	_refresh_button.disabled = true
	var mode := _mode_id()
	var options := _options()
	_source_label.text = "数据源：GameState 实时状态　|　模式：%s　|　当前境界：%s　|　当前天赋节点：%d" % [
		_mode_name(mode),
		GameState.get_realm_name(),
		GameState.talent_nodes.size(),
	]
	if mode == "live":
		var report := GameState.get_simulation_report(options)
		_result_view.text = _format_report(report)
	else:
		var rows := GameState.get_simulation_matrix(mode, options)
		_result_view.text = _format_matrix(mode, rows)
	_refresh_button.disabled = false


func _mode_id() -> String:
	if _mode_option == null or _mode_option.selected < 0 or _mode_option.selected >= MODES.size():
		return "live"
	return String(MODES[_mode_option.selected].get("id", "live"))


func _options() -> Dictionary:
	var realm_index := _realm_option.selected - 1
	var season_index := _season_option.selected - 1
	var crop_id := String(_crop_option.get_item_metadata(_crop_option.selected))
	var profile_id := String(_talent_option.get_item_metadata(_talent_option.selected))
	var profile := _profile_by_id(profile_id)
	var click_scope := String(_click_scope.get_item_metadata(_click_scope.selected))
	var event_id := String(_event_option.get_item_metadata(_event_option.selected))
	var event := _event_by_id(event_id)
	var options := {
		"mode": _mode_id(),
		"realm_index": realm_index if realm_index >= 0 else int(GameState.realm_index),
		"season_index": season_index if season_index >= 0 else int(GameState.season_index),
		"crop_id": crop_id,
		"profile_id": profile_id,
		"talent_nodes": profile.get("nodes", GameState.talent_nodes),
		"tier": int(_tier.value),
		"field_count": int(_field_count.value),
		"clicks_per_second": float(_clicks_per_second.value),
		"click_scope": click_scope,
		"qi": float(_qi.value),
		"event_id": event_id,
		"event_prod_mult": float(event.get("prod", 1.0)),
		"event_cult_mult": float(event.get("cult", 1.0)),
		"pest_level": int(_pest_level.value) if event_id == "normal" else int(event.get("pest_level", _pest_level.value)),
		"spirit_rain_active": _rain_check.button_pressed,
		"auto_cultivation_enabled": _auto_check.button_pressed,
		"enforce_breakthrough_materials": _material_gate_check.button_pressed,
		"enforce_tribulation_supplies": _tribulation_gate_check.button_pressed,
		"maximize_progression": _maximize_check.button_pressed,
		"auto_buy_shop_resources": _maximize_check.button_pressed,
	}
	return options


func _format_report(report: Dictionary) -> String:
	var scenario: Dictionary = report.get("scenario", {})
	var representative: Dictionary = report.get("representative", {})
	var multiplier: Dictionary = report.get("multipliers", {})
	var auto: Dictionary = report.get("auto_rates", {})
	var click: Dictionary = report.get("click", {})
	var offline: Dictionary = report.get("offline_settlement", {})
	var tribulation: Dictionary = report.get("tribulation", {})
	var lines := PackedStringArray()
	lines.append("=== 实时场景报告 ===")
	lines.append("境界：%s    时节：%s    作物基准：%s    天赋：%s" % [
		String(scenario.get("realm_name", "")),
		String(scenario.get("season_name", "")),
		String(representative.get("crop_name", "")),
		_talent_name()
	])
	lines.append("灵气：%s    虫害：%d级    灵雨：%s    事件生产×%s / 修炼×%s" % [
		_fmt(float(scenario.get("qi", 0.0))),
		int(scenario.get("pest_level", 0)),
		"是" if bool(scenario.get("spirit_rain_active", false)) else "否",
		_fmt_mult(float(scenario.get("event_prod_mult", 1.0))),
		_fmt_mult(float(scenario.get("event_cult_mult", 1.0))),
	])
	lines.append("倍率拆解：境界生产×%s  天赋生产×%s  生长天赋×%s  灵田×%s  灵气收获×%s  狂暴×%s" % [
		_fmt_mult(float(multiplier.get("realm_production", 1.0))),
		_fmt_mult(float(multiplier.get("talent_production", 1.0))),
		_fmt_mult(float(multiplier.get("talent_growth", 1.0))),
		_fmt_mult(float(multiplier.get("field_tier", 1.0))),
		_fmt_mult(float(multiplier.get("qi_harvest", 1.0))),
		_fmt_mult(float(multiplier.get("buff", 1.0))),
	])
	lines.append("")
	lines.append("灵田产线")
	for field in report.get("fields", []):
		if not bool(field.get("active", false)):
			lines.append("  灵田%d：空闲" % (int(field.get("field_index", 0)) + 1))
			continue
		lines.append("  灵田%d：%s / %s，熟练 %d次·第%d档，单轮 %s 株，周期 %s，修为 %s/s，灵石 %s/s，灵气 0/s" % [
			int(field.get("field_index", 0)) + 1,
			String(field.get("crop_name", "")),
			_tier_name(int(field.get("tier", 0))),
			int(field.get("proficiency_count", 0)),
			int(field.get("proficiency_stage", 0)),
			_fmt(float(field.get("amount", 0.0))),
			_fmt_seconds(float(field.get("growth_seconds", 0.0))),
			_fmt(float(field.get("cultivation_per_sec", 0.0))),
			_fmt(float(field.get("spirit_stones_per_sec", 0.0))),
		])
	lines.append("熟练度奖励：当前作物产量+%d，基础成熟-%s，累计天赋点贡献 %d；跨大限保留。" % [
		int(representative.get("proficiency_yield_bonus", 0)),
		_fmt_seconds(float(representative.get("proficiency_growth_reduction", 0.0))),
		int(representative.get("proficiency_talent_points", 0)),
	])
	lines.append("灵田总生产：修为 %s/s，灵石 %s/s，灵气 0/s，灵气浓度 %s，单轮 %s 株" % [
		_fmt(float(report.get("total_cultivation_per_sec", 0.0))),
		_fmt(float(report.get("total_spirit_stones_per_sec", 0.0))),
		_fmt(float(report.get("qi_density", 0.0))),
		_fmt(float(report.get("total_harvest_per_cycle", 0.0))),
	])
	lines.append("")
	lines.append("槽位回本（新增一条同配置产线）")
	for row in report.get("slot_rows", []):
		lines.append("  第%d块：成本 %s，边际 %s/s，回本 %s" % [
			int(row.get("field_index", 0)) + 1,
			_fmt(float(row.get("cost", 0.0))),
			_fmt(float(row.get("marginal_rate", 0.0))),
			_fmt_seconds(float(row.get("payback_seconds", INF))),
		])
	lines.append("灵田升档回本（按当前代表作物）")
	for row in report.get("upgrade_rows", []):
		var status := "已开放" if bool(row.get("available", false)) else ("需要%s" % _realm_name(int(row.get("required_realm", 0))))
		lines.append("  %s→%s：成本 %s，产能差 %s/s，回本 %s，%s" % [
			_tier_name(int(row.get("from_tier", 0))),
			_tier_name(int(row.get("to_tier", 0))),
			_fmt(float(row.get("cost", 0.0))),
			_fmt(float(row.get("delta_rate", 0.0))),
			_fmt_seconds(float(row.get("payback_seconds", INF))),
			status,
		])
	lines.append("")
	lines.append("主动操作：每秒点击 %s 次；单次点击减 %s 秒；完成一轮约需 %d 次点击，实际周期 %s；点一次后剩 %s" % [
		_fmt(float(click.get("clicks_per_second", BalanceConfig.DEFAULT_PLAYER_CLICKS_PER_SECOND))),
		_fmt(float(click.get("click_accel_seconds", 0.0))),
		int(click.get("clicks_to_finish", 0)),
		_fmt_seconds(float(click.get("click_cycle_seconds", click.get("growth_seconds", 0.0)))),
		_fmt_seconds(float(click.get("after_one_click_seconds", 0.0))),
	])
	lines.append("自动修炼（在线）：修为 %s/s，灵气 %s/s" % [
		_fmt(float(auto.get("cultivation_per_sec", 0.0))),
		_fmt(float(auto.get("qi_per_sec", 0.0))),
	])
	if bool(tribulation.get("active", false)):
		lines.append("天劫：%s，进度 %d/%d，劫体 %s/%s，抗性剩余 %d 道；生产已暂停。" % [
			String(tribulation.get("name", "天劫")),
			int(tribulation.get("strikes_survived", 0)),
			int(tribulation.get("total_strikes", 0)),
			_fmt(float(tribulation.get("health", 0.0))),
			_fmt(float(tribulation.get("health_max", 0.0))),
			int(tribulation.get("resistance_charges", 0)),
		])
	var offline_status := "生效" if bool(offline.get("active", false)) else "大限中，暂不结算"
	lines.append("离线折算（与离线时长无关）：天赋点 +%d，灵石 +%s；%s。离线不增加修为和灵气。" % [
		int(offline.get("talent_points", 0)),
		_fmt(float(offline.get("spirit_stones", 0.0))),
		offline_status,
	])
	return "\n".join(lines)


func _format_matrix(kind: String, rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append("=== %s：%d 条 ===" % [_mode_name(kind), rows.size()])
	if kind == "full":
		return _format_full_matrix(rows)
	if kind == "progression":
		return _format_progression_matrix(rows)
	if kind == "proficiency":
		return _format_proficiency_matrix(rows)
	if kind == "breakthrough":
		return _format_breakthrough_matrix(rows)
	for row in rows:
		var report: Dictionary = row.get("report", {})
		var prefix := _matrix_prefix(kind, row)
		lines.append("%s | 灵石 %s/s | 灵气 %s/s | 修为 %s/s | 浓度 %s" % [
			prefix,
			_fmt(float(row.get("stones_per_sec", 0.0))),
			_fmt(float(row.get("qi_per_sec", 0.0))),
			_fmt(float(row.get("cultivation_per_sec", 0.0))),
			_fmt(float(row.get("density", 0.0))),
		])
		if kind == "realm":
			var slots: Array = report.get("slot_rows", [])
			if not slots.is_empty():
				lines.append("    槽位回本：第2块 %s；第3块 %s" % [
					_fmt_seconds(float(slots[0].get("payback_seconds", INF))),
					_fmt_seconds(float(slots[1].get("payback_seconds", INF))) if slots.size() > 1 else "—",
				])
		if kind == "talent":
			var mult: Dictionary = report.get("multipliers", {})
			lines.append("    天赋倍率：产出×%s，生长×%s，自动修炼×%s" % [
				_fmt_mult(float(mult.get("talent_production", 1.0))),
				_fmt_mult(float(mult.get("talent_growth", 1.0))),
				_fmt_mult(float(mult.get("talent_auto_cultivation", 1.0))),
			])
	return "\n".join(lines)


func _format_breakthrough_matrix(rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append("=== 突破流程：%d 条 ===" % rows.size())
	lines.append("灵田收获直接结算修为与灵石，不产生灵气；点击频率按上方的点击分配计算；自动修炼按境界解锁后计入；阶段耗时包含天劫。")
	for row in rows:
		var flow: Dictionary = row.get("flow", {})
		var status := "已完成"
		if not bool(flow.get("completed", false)):
			if bool(flow.get("estimated_completed", false)):
				status = "时间估算可达（未按全部真实门槛确认）"
			else:
				status = "未完成：%s" % String(flow.get("blocked_reason", "未知原因"))
		lines.append("配置：%s / %d块 / %s / %s；总耗时 %s；总点击 %s；%s" % [
			String(row.get("profile_name", "当前天赋")),
			int(row.get("field_count", flow.get("field_count", 0))),
			_tier_name(int(row.get("tier", flow.get("tier", 0)))),
			_fmt(float(row.get("clicks_per_second", flow.get("clicks_per_second", 0.0)))),
			_fmt_seconds(float(row.get("total_seconds", flow.get("total_seconds", 0.0)))),
			_fmt(float(flow.get("total_clicks", 0.0))),
			status,
		])
		var material_status := "已备齐"
		if not bool(flow.get("breakthrough_materials_ready", true)):
			material_status = "缺材料，预计商店兑换 %s 灵石" % _fmt(float(flow.get("breakthrough_material_shop_cost", 0.0)))
		lines.append("突破材料：%s；本次模拟%s" % [material_status, "按库存校验" if bool(flow.get("enforce_breakthrough_materials", false)) else "时间估算，未校验材料"])
		lines.append("渡劫丹药：%s；本次模拟%s" % [
			"已备齐" if bool(flow.get("tribulation_supplies_ready", true)) else "当前库存不足",
			"按库存校验" if bool(flow.get("enforce_tribulation_supplies", false)) else "时间估算，未校验丹药",
		])
		if bool(flow.get("maximize_progression", false)):
			lines.append("最大化策略：天赋点实时解锁；灵石自动购买寿元、材料和渡劫丹；只有超过资源预留的灵石才购买能产生实际收益的聚气玉。")
		lines.append("点击模型：%s；季节：%s；%s" % [
			String(flow.get("click_mode", "每块灵田独立点击")),
			String(flow.get("season_name", "")),
			String(flow.get("cultivation_mode", "灵田收获直接结算修为")),
		])
		for stage in flow.get("stages", []):
			var stage_materials := "已备齐" if bool(stage.get("materials_ready", true)) else "缺材料，需 %s 灵石" % _fmt(float(stage.get("material_shop_cost", 0.0)))
			var stage_tribulation := "不计天劫"
			if bool(flow.get("include_tribulation", true)):
				if not stage.has("tribulation_total_strikes"):
					stage_tribulation = "未开始"
				elif bool(stage.get("tribulation_success", false)):
					stage_tribulation = "%s %d道，%s" % [
						String(stage.get("tribulation_name", "天劫")),
						int(stage.get("tribulation_total_strikes", stage.get("tribulation_strikes", 0))),
						"丹药足够" if bool(flow.get("enforce_tribulation_supplies", false)) else "时间估算，未校验丹药",
					]
				else:
					stage_tribulation = "%s，%s" % [
						String(stage.get("tribulation_name", "天劫")),
						"丹药不足，建议至少治疗丹 %d 枚" % int(stage.get("tribulation_recommended_healing_pills", 0)) if bool(flow.get("enforce_tribulation_supplies", false)) else "时间估算，当前库存不足",
					]
			lines.append("  %s→%s：耗时 %s（修炼 %s + %s）；种植 %s（单轮修为 %s、灵石 %s）；收获 %d 轮；点击 %d；自动修为 %s；阶段后修为 %s；材料 %s" % [
				String(stage.get("from_realm_name", "")),
				String(stage.get("to_realm_name", "")),
				_fmt_seconds(float(stage.get("duration_seconds", stage.get("seconds", 0.0)))),
				_fmt_seconds(float(stage.get("seconds", 0.0)) - float(stage.get("tribulation_seconds", 0.0))),
				stage_tribulation,
				String(stage.get("crop_name", "")),
				_fmt(float(stage.get("cultivation_per_cycle", 0.0))),
				_fmt(float(stage.get("spirit_stones_per_cycle", 0.0))),
				int(stage.get("harvest_cycles", 0)),
				int(stage.get("clicks", 0)),
				_fmt(float(stage.get("auto_cultivation", 0.0))),
				_fmt(float(stage.get("cultivation_after", 0.0))),
				stage_materials,
			])
			if bool(flow.get("maximize_progression", false)):
				lines.append("    自动加点 %d 个；购买：聚气玉 %d、突破材料 %d、长生丹 %d；阶段寿元 %s→%s 年；可用天赋点 %d（累计获得 %d）。" % [
					(stage.get("talent_unlocks", []) as Array).size(),
					int(stage.get("qi_purchases", 0)),
					int(stage.get("material_purchases", 0)),
					int(stage.get("lifespan_purchases", 0)),
					_fmt(float(stage.get("lifespan_before_years", 0.0))),
					_fmt(float(stage.get("lifespan_after_years", 0.0))),
					int(stage.get("talent_points_after_tribulation", 0)),
					int(stage.get("talent_points_earned_after_tribulation", 0)),
				])
		lines.append("最终状态：%s 修为；%s 灵石；%s 灵气；累计收获 %s；自动修为 %s。" % [
			_fmt(float(flow.get("final_cultivation", 0.0))),
			_fmt(float(flow.get("final_spirit_stones", 0.0))),
			_fmt(float(flow.get("final_qi", 0.0))),
			_fmt(float(flow.get("harvest_cycles", 0.0))),
			_fmt(float(flow.get("auto_cultivation", 0.0))),
		])
		if bool(flow.get("maximize_progression", false)):
			lines.append("最终天赋：可用 %d 点 / 累计获得 %d 点 / 已花费 %d 点；自动购买总支出 %s 灵石。" % [
				int(flow.get("talent_points", 0)),
				int(flow.get("talent_points_earned", 0)),
				int(flow.get("talent_points_spent", 0)),
				_fmt(float(flow.get("spirit_stones_spent", 0.0))),
			])
	return "\n".join(lines)


func _format_proficiency_matrix(rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append("=== 熟练度矩阵：%d 条 ===" % rows.size())
	lines.append("每种灵植分别累计收获；产量/成熟时间取当前最高档位，跨过门槛的天赋点逐档累计并跨大限保留。")
	for row in rows:
		var report: Dictionary = row.get("report", {})
		lines.append("%s / 第%d档 / %d次：产量+%d，基础成熟-%s，累计天赋点 %d；修为 %s/s，灵石 %s/s" % [
			String(row.get("crop_name", "")),
			int(row.get("stage", 0)),
			int(row.get("harvest_count", 0)),
			int(row.get("yield_bonus", 0)),
			_fmt_seconds(float(row.get("growth_reduction", 0.0))),
			int(row.get("talent_points", 0)),
			_fmt(float(report.get("total_cultivation_per_sec", 0.0))),
			_fmt(float(report.get("total_spirit_stones_per_sec", 0.0))),
		])
	return "\n".join(lines)


func _format_progression_matrix(rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append("=== 境界总表：%d 条 ===" % rows.size())
	for row in rows:
		var report: Dictionary = row.get("report", {})
		var auto: Dictionary = report.get("auto_rates", {})
		lines.append("%s | 门槛修为 %s | 生产×%s | 修炼×%s | 寿元 %s年/%s | 突破天赋 +%d | 3田自动修为 %s/s、灵气 %s/s | 解锁：%s" % [
			String(row.get("realm_name", "")),
			_fmt(float(row.get("required_cultivation", 0.0))),
			_fmt_mult(float(row.get("production_mult", 1.0))),
			_fmt_mult(float(row.get("cultivation_mult", 1.0))),
			_fmt(float(row.get("lifespan_max_years", 0.0))),
			_fmt_seconds(float(row.get("lifespan_duration_seconds", 0.0))),
			int(row.get("breakthrough_talent_points", 0)),
			_fmt(float(auto.get("cultivation_per_sec", 0.0))),
			_fmt(float(auto.get("qi_per_sec", 0.0))),
			String(row.get("unlocks", "—")),
		])
	return "\n".join(lines)


func _format_full_matrix(rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append("核心全量矩阵：境界 × 已解锁作物 × 四季 × 天赋路线 × 田数 × 可用档位")
	lines.append("事件、灵气、灵雨、虫害仍可用上方参数单独切换；这里不把短期爆发混进基础成长。")
	var min_row: Dictionary = {}
	var max_row: Dictionary = {}
	var min_rate := INF
	var max_rate := -INF
	for row in rows:
		var rate := float(row.get("stones_per_sec", 0.0))
		if rate < min_rate:
			min_rate = rate
			min_row = row
		if rate > max_rate:
			max_rate = rate
			max_row = row
		lines.append("%s | %s | %s | %s | %d块/%s | 灵石 %s/s | 灵气 %s/s | 修为 %s/s" % [
			String(row.get("realm_name", "")),
			String(row.get("crop_name", "")),
			String(row.get("season_name", "")),
			String(row.get("profile_name", "")),
			int(row.get("field_count", 0)),
			_tier_name(int(row.get("tier", 0))),
			_fmt(rate),
			_fmt(float(row.get("qi_per_sec", 0.0))),
			_fmt(float(row.get("cultivation_per_sec", 0.0))),
		])
	lines.append("")
	if not min_row.is_empty():
		lines.append("最低基础产出：%s / %s / %s / %s，灵石 %s/s" % [
			String(min_row.get("realm_name", "")), String(min_row.get("crop_name", "")),
			String(min_row.get("season_name", "")), String(min_row.get("profile_name", "")), _fmt(min_rate),
		])
	if not max_row.is_empty():
		lines.append("最高基础产出：%s / %s / %s / %s，灵石 %s/s" % [
			String(max_row.get("realm_name", "")), String(max_row.get("crop_name", "")),
			String(max_row.get("season_name", "")), String(max_row.get("profile_name", "")), _fmt(max_rate),
		])
	return "\n".join(lines)


func _matrix_prefix(kind: String, row: Dictionary) -> String:
	match kind:
		"realm":
			return "%s / %d块 / %s / %s" % [String(row.get("realm_name", "")), int(row.get("field_count", 0)), String(row.get("crop_name", "")), _tier_name(int(row.get("tier", 0)))]
		"crop":
			return "%s / %s / %d块 / %s" % [String(row.get("realm_name", "")), String(row.get("crop_name", "")), int(row.get("field_count", 0)), _tier_name(int(row.get("tier", 0)))]
		"season":
			return "%s / %s / %s / %d块" % [String(row.get("season_name", "")), String(row.get("crop_name", "")), _tier_name(int(row.get("tier", 0))), int(row.get("field_count", 0))]
		"talent":
			return "%s / %s / %d块 / %s" % [String(row.get("profile_name", "")), String(row.get("crop_name", "")), int(row.get("field_count", 0)), _tier_name(int(row.get("tier", 0)))]
		"event":
			return "%s / %s / %d块 / %s" % [String(row.get("event_name", "")), String(row.get("crop_name", "")), int(row.get("field_count", 0)), _tier_name(int(row.get("tier", 0)))]
		"progression":
			return String(row.get("realm_name", "境界"))
	return "场景"


func _profile_by_id(profile_id: String) -> Dictionary:
	for profile in SimulationSystem.talent_profiles(GameState):
		if String(profile.get("id", "")) == profile_id:
			return profile
	return SimulationSystem.talent_profiles(GameState)[0]


func _event_by_id(event_id: String) -> Dictionary:
	for event in SimulationSystem.event_profiles(GameState):
		if String(event.get("id", "")) == event_id:
			return event
	return SimulationSystem.event_profiles(GameState)[0]


func _select_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _talent_name() -> String:
	if _talent_option == null:
		return "当前天赋"
	return _talent_option.get_item_text(_talent_option.selected)


func _tier_name(tier: int) -> String:
	if tier < 0 or tier >= BalanceConfig.FIELD_TIER_NAMES.size():
		return "未知档位"
	return BalanceConfig.FIELD_TIER_NAMES[tier]


func _realm_name(realm_index: int) -> String:
	if realm_index < 0 or realm_index >= RealmConfig.realm_count():
		return "最高境界"
	return String(BalanceConfig.REALMS[realm_index].get("name", ""))


func _mode_name(mode_id: String) -> String:
	for mode in MODES:
		if String(mode.get("id", "")) == mode_id:
			return String(mode.get("name", mode_id))
	return mode_id


func _fmt(value: float) -> String:
	if not is_finite(value):
		return "—"
	return NumberFormat.format(value)


func _fmt_mult(value: float) -> String:
	if not is_finite(value):
		return "—"
	if value < 10.0:
		return "%.2f" % value
	return NumberFormat.format(value)


func _fmt_seconds(seconds: float) -> String:
	if not is_finite(seconds):
		return "—"
	if seconds < 60.0:
		return "%.1f秒" % seconds
	if seconds < 3600.0:
		return "%.1f分钟" % (seconds / 60.0)
	return "%.1f小时" % (seconds / 3600.0)


func _export_report() -> void:
	var payload: Dictionary
	var mode := _mode_id()
	if mode == "live":
		payload = {"kind": mode, "report": GameState.get_simulation_report(_options())}
	else:
		payload = {"kind": mode, "rows": GameState.get_simulation_matrix(mode, _options())}
	var file := FileAccess.open("user://simulation_report.json", FileAccess.WRITE)
	if file == null:
		_feedback.text = "导出失败。"
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	_feedback.text = "已导出到 user://simulation_report.json"


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	return label
