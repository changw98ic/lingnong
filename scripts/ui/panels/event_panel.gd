extends Control
class_name EventPanel

# 事件与反馈面板（契约：UI 面板 - 事件与反馈）。
# 职责：
#   - 显示当前季节（GameState.get_season_name）。
#   - 显示当前事件与剩余倒计时；祥瑞降世 / 天道感悟 / 兵主诞辰 时的爆发/警示提示。
#   - 目标灵田选择 + 灵雨诀 / 庚金剑诀 / 升级守护灵阵 / 出售虫尸 动作按钮（按解锁与境界显示）。
#   - 反馈区：操作反馈 + 离线结算摘要（GameState.last_offline_report）。
# 自包含：_ready 里用代码自建所有子节点并挂到 self；连 GameState.state_changed 刷新；
#   按钮直接调 GameState 方法；数字用 NumberFormat.format。不依赖 main.tscn 节点路径。

# 反馈文本自动清除的倒计时（秒）。
const FEEDBACK_DURATION := 4.0

# 当前选中的目标灵田索引（供法术/升级按钮使用）。
var selected_field := 0
# 反馈文本剩余展示时间，<=0 时清空 feedback_label。
var feedback_time := 0.0

# ─────────────── 子节点引用 ───────────────
var season_label: Label
var event_label: Label
var burst_label: Label
var buff_label: Label
var field_buttons: Array[Button] = []
var btn_spirit_rain: Button
var btn_gengjin_sword: Button
var btn_guardian: Button
var btn_sell_corpses: Button
# 交互事件：古修洞府三选一 + 魔气净化。
var cave_controls: GridContainer
var btn_cave_stones: Button
var btn_cave_talent: Button
var btn_cave_treasure: Button
var btn_purify_demon_qi: Button
var offline_label: Label
var feedback_label: Label


func _ready() -> void:
	# 让本面板可以被任意容器自由拉伸填充。
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_layout()
	GameState.state_changed.connect(_refresh)
	_show_offline_report_if_any()
	_refresh()


# ─────────────── 布局构建（一次性自建） ───────────────
func _build_layout() -> void:
	var box := VBoxContainer.new()
	box.name = "Content"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	box.add_child(_make_label("时节 · 事件 · 法术", 16, Color(1.0, 0.9, 0.6)))

	season_label = _make_label("", 14, Color(0.85, 0.85, 0.85))
	box.add_child(season_label)

	event_label = _make_label("", 14, Color(0.9, 0.9, 0.7))
	box.add_child(event_label)

	burst_label = _make_label("", 15, Color(1.0, 0.55, 0.3))
	box.add_child(burst_label)

	buff_label = _make_label("", 14, Color(0.95, 0.6, 0.6))
	box.add_child(buff_label)

	# 目标灵田选择行：3 个固定按钮，按解锁数量显隐。
	var field_row := HBoxContainer.new()
	field_row.add_theme_constant_override("separation", 4)
	field_row.add_child(_make_label("目标灵田：", 13, Color(0.8, 0.8, 0.8)))
	for i in range(BalanceConfig.FIELD_COUNT):
		var b := Button.new()
		b.text = "灵田%d" % (i + 1)
		b.custom_minimum_size = Vector2(72, 28)
		b.toggle_mode = true
		b.pressed.connect(_on_select_field.bind(i))
		field_row.add_child(b)
		field_buttons.append(b)
	box.add_child(field_row)

	# 法术/动作按钮网格。
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	btn_spirit_rain = _make_action_button("灵雨诀（%.0f 灵气）" % BalanceConfig.SPIRIT_RAIN_COST, _on_spirit_rain)
	btn_gengjin_sword = _make_action_button("庚金剑诀（%.0f 灵气）" % BalanceConfig.GENGJIN_SWORD_COST, _on_gengjin_sword)
	btn_guardian = _make_action_button("升级守护灵阵（%.0f 灵石）" % BalanceConfig.GUARDIAN_UPGRADE_COST, _on_upgrade_guardian)
	btn_sell_corpses = _make_action_button("出售虫尸", _on_sell_corpses)
	actions.add_child(btn_spirit_rain)
	actions.add_child(btn_gengjin_sword)
	actions.add_child(btn_guardian)
	actions.add_child(btn_sell_corpses)
	box.add_child(actions)

	# 古修洞府三选一（事件进行中显示）。
	cave_controls = GridContainer.new()
	cave_controls.columns = 3
	cave_controls.add_theme_constant_override("h_separation", 6)
	cave_controls.visible = false
	btn_cave_stones = _make_action_button("灵石 +%s" % NumberFormat.format(BalanceConfig.ANCIENT_CAVE_STONES), _on_cave_stones)
	btn_cave_talent = _make_action_button("天赋点 +%d" % int(BalanceConfig.ANCIENT_CAVE_TALENT_POINTS), _on_cave_talent)
	btn_cave_treasure = _make_action_button("随机宝箱", _on_cave_treasure)
	cave_controls.add_child(btn_cave_stones)
	cave_controls.add_child(btn_cave_talent)
	cave_controls.add_child(btn_cave_treasure)
	box.add_child(cave_controls)
	btn_purify_demon_qi = _make_action_button("净化魔气", _on_purify_demon_qi)
	btn_purify_demon_qi.visible = false
	box.add_child(btn_purify_demon_qi)

	# 反馈区：离线摘要（常驻）+ 操作反馈（瞬时）。
	var feedback_area := VBoxContainer.new()
	feedback_area.add_theme_constant_override("separation", 2)
	offline_label = _make_label("", 13, Color(0.7, 0.85, 1.0))
	feedback_label = _make_label("", 13, Color(0.95, 0.95, 0.7))
	feedback_area.add_child(offline_label)
	feedback_area.add_child(feedback_label)
	box.add_child(feedback_area)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_action_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	return b


# ─────────────── 每帧刷新（保证倒计时时时更新） ───────────────
func _process(delta: float) -> void:
	if feedback_time > 0.0:
		feedback_time -= delta
	_refresh()


# ─────────────── 全量刷新（state_changed 与 _process 共用） ───────────────
func _refresh() -> void:
	# 解锁变化后，保证 selected_field 落在已解锁范围内。
	if selected_field < 0 or selected_field >= GameState.unlocked_fields:
		selected_field = maxi(0, GameState.unlocked_fields - 1)

	var now := Time.get_unix_time_from_system()

	# 季节。
	season_label.text = "当前时节：%s" % GameState.get_season_name()

	# 事件名称与倒计时。
	if GameState.is_random_event_active():
		var remain := maxi(0, int(GameState.random_event_until - now))
		event_label.text = "当前事件：%s    剩余 %d 秒" % [GameState.get_random_event_display_name(), remain]
	else:
		var next_in := maxi(0, int(GameState.random_event_cooldown_until - now))
		event_label.text = "当前事件：无    下次约 %d 秒后" % next_in

	# 爆发/警示提示（仅事件进行中显示）。
	if GameState.is_random_event_active():
		burst_label.visible = true
		match GameState.random_event:
			"auspicious":
				burst_label.text = "★ 爆发：生产 ×10 进行中（生长/产量/灵气/自动灵气）★"
				burst_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
			"dao_insight":
				burst_label.text = "★ 爆发：修炼 ×20 进行中（灵田收获/自动修炼）★"
				burst_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
			"warlord_birthday":
				burst_label.text = "⚠ 噬金虫活跃：攻击 ×2、间隔减半 ⚠"
				burst_label.add_theme_color_override("font_color", Color(0.95, 0.5, 0.5))
			"ancient_cave":
				burst_label.text = "🏛 古修洞府：选择一份机缘（灵石 / 天赋点 / 随机宝箱）"
				burst_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
			"heavenly_seed":
				burst_label.text = "🌱 天降灵种：本世已解锁紫芝（高级灵植，元婴级）"
				burst_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			"demon_qi":
				burst_label.text = "☠ 魔气侵染：生产 -50%，可用灵石净化"
				burst_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.9))
			"insect_king":
				burst_label.text = "🐛 噬金虫王出现：用庚金剑诀击杀，额外获得虫尸 ×%d" % int(BalanceConfig.INSECT_KING_CORPSE_REWARD)
				burst_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
			_:
				burst_label.text = ""
		# 交互事件按钮显隐。
		cave_controls.visible = GameState.random_event == "ancient_cave"
		var demon_qi := GameState.random_event == "demon_qi"
		btn_purify_demon_qi.visible = demon_qi
		if demon_qi:
			var purify_cost := GameState.spirit_stones * BalanceConfig.DEMON_QI_PURIFY_COST_RATIO
			btn_purify_demon_qi.text = "净化魔气（花费当前灵石 %d%%，约 %s）" % [int(BalanceConfig.DEMON_QI_PURIFY_COST_RATIO * 100.0), NumberFormat.format(purify_cost)]
			btn_purify_demon_qi.disabled = GameState.spirit_stones <= 0.0
	else:
		burst_label.visible = false
		cave_controls.visible = false
		btn_purify_demon_qi.visible = false

	# 狂暴丹 buff 提示。
	if GameState.is_active_buff():
		buff_label.visible = true
		buff_label.text = "狂暴生效：生产 ×%.1f    剩余 %d 秒" % [GameState.active_buff_mult, int(GameState.get_active_buff_remaining())]
	else:
		buff_label.visible = false

	_refresh_field_buttons()
	_refresh_action_buttons()

	# 瞬时反馈到期清空。
	if feedback_time <= 0.0:
		feedback_label.text = ""


# 灵田选择按钮：仅显示已解锁地块，标注灵雨/虫害状态，高亮选中。
func _refresh_field_buttons() -> void:
	for i in range(field_buttons.size()):
		var b: Button = field_buttons[i]
		if i >= GameState.unlocked_fields:
			b.visible = false
			continue
		b.visible = true
		var tag := ""
		if GameState.is_spirit_rain_active(i):
			tag += "·雨"
		var has_crop := i < GameState.fields.size() and String(GameState.fields[i].get("crop_id", "")) != ""
		if has_crop and i < GameState.insect_events.size():
			var insect_event: Dictionary = GameState.insect_events[i]
			if bool(insect_event.get("active", false)):
				tag += "·虫"
			else:
				var insect_remaining := int(ceil(float(insect_event.get("next_attack_at", 0.0)) - Time.get_unix_time_from_system()))
				if insect_remaining > 0:
					tag += "·虫%d秒" % insect_remaining
				else:
					tag += "·虫即将"
		b.text = "灵田%d%s" % [i + 1, tag]
		b.button_pressed = (i == selected_field)


# 动作按钮：按解锁/境界显隐，按资源/状态启用。
func _refresh_action_buttons() -> void:
	# 灵雨诀：炼气起 spirit_rain_unlocked。
	var rain_unlocked := GameState.spirit_rain_unlocked
	btn_spirit_rain.visible = rain_unlocked
	if rain_unlocked:
		var rain_active := GameState.is_spirit_rain_active(selected_field)
		btn_spirit_rain.text = "灵雨诀生效中" if rain_active else "灵雨诀（%.0f 灵气）" % BalanceConfig.SPIRIT_RAIN_COST
		btn_spirit_rain.disabled = GameState.tribulation_active or rain_active or GameState.qi < BalanceConfig.SPIRIT_RAIN_COST

	# 庚金剑诀：筑基（realm_index >= 2）起。
	var sword_unlocked := GameState.realm_index >= BalanceConfig.ADVANCED_COMBAT_REALM_INDEX
	btn_gengjin_sword.visible = sword_unlocked
	if sword_unlocked:
		var has_insect := selected_field < GameState.insect_events.size() and bool(GameState.insect_events[selected_field].get("active", false))
		btn_gengjin_sword.text = "庚金剑诀（%.0f 灵气）" % BalanceConfig.GENGJIN_SWORD_COST
		btn_gengjin_sword.disabled = GameState.tribulation_active or (not has_insect) or GameState.qi < BalanceConfig.GENGJIN_SWORD_COST

	# 升级守护灵阵：筑基起。
	var guard_unlocked := GameState.realm_index >= BalanceConfig.ADVANCED_COMBAT_REALM_INDEX
	btn_guardian.visible = guard_unlocked
	if guard_unlocked:
		btn_guardian.text = "升级守护灵阵（%.0f 灵石）" % BalanceConfig.GUARDIAN_UPGRADE_COST
		btn_guardian.disabled = GameState.tribulation_active or GameState.spirit_stones < BalanceConfig.GUARDIAN_UPGRADE_COST

	# 出售虫尸：始终显示（8 灵石/个）。
	btn_sell_corpses.visible = true
	btn_sell_corpses.text = "出售虫尸（%d 个 · %.0f 灵石/个）" % [GameState.insect_corpses, BalanceConfig.INSECT_CORPSE_SELL_PRICE]
	btn_sell_corpses.disabled = GameState.insect_corpses <= 0
	if GameState.lifespan_depleted or GameState.tribulation_active:
		btn_spirit_rain.disabled = true
		btn_gengjin_sword.disabled = true
		btn_guardian.disabled = true


# ─────────────── 按钮处理（直接调 GameState 方法） ───────────────
func _on_select_field(i: int) -> void:
	if i >= 0 and i < GameState.unlocked_fields:
		selected_field = i


func _on_spirit_rain() -> void:
	if GameState.cast_spirit_rain(selected_field):
		_set_feedback("灵雨诀施放成功：该灵田生长速度 ×%.1f。" % BalanceConfig.SPIRIT_RAIN_GROWTH_MULT)
	else:
		_set_feedback("灵雨诀失败：需要 %.0f 灵气（且该田当前未在生效中）。" % BalanceConfig.SPIRIT_RAIN_COST)


func _on_gengjin_sword() -> void:
	if GameState.cast_gengjin_sword(selected_field):
		_set_feedback("庚金剑诀驱虫成功，已获得虫尸。")
	else:
		_set_feedback("庚金剑诀失败：需该田有活跃噬金虫、%.0f 灵气，且不在冷却。" % BalanceConfig.GENGJIN_SWORD_COST)


func _on_upgrade_guardian() -> void:
	if GameState.upgrade_guardian_array(selected_field):
		_set_feedback("守护灵阵升级成功：抵抗次数提升。")
	else:
		_set_feedback("升级失败：需要 %.0f 灵石。" % BalanceConfig.GUARDIAN_UPGRADE_COST)


func _on_sell_corpses() -> void:
	if GameState.sell_insect_corpses():
		_set_feedback("虫尸出售成功，灵石已到账。")
	else:
		_set_feedback("当前没有虫尸可出售。")


# ─────────────── 交互事件按钮处理 ───────────────
func _on_cave_stones() -> void:
	if GameState.resolve_ancient_cave("stones"):
		_set_feedback("古修洞府：获得 %s 灵石。" % NumberFormat.format(BalanceConfig.ANCIENT_CAVE_STONES))
	else:
		_set_feedback("古修洞府已关闭。")


func _on_cave_talent() -> void:
	if GameState.resolve_ancient_cave("talent"):
		_set_feedback("古修洞府：获得 %d 天赋点。" % int(BalanceConfig.ANCIENT_CAVE_TALENT_POINTS))
	else:
		_set_feedback("古修洞府已关闭。")


func _on_cave_treasure() -> void:
	if GameState.resolve_ancient_cave("treasure"):
		_set_feedback("古修洞府：开启随机宝箱。")
	else:
		_set_feedback("古修洞府已关闭。")


func _on_purify_demon_qi() -> void:
	if GameState.purify_demon_qi():
		_set_feedback("净化成功：魔气退散，生产恢复。")
	else:
		_set_feedback("净化失败：需要至少 1 灵石（花费当前灵石的 %d%%）。" % int(BalanceConfig.DEMON_QI_PURIFY_COST_RATIO * 100.0))


# ─────────────── 反馈 / 离线摘要 ───────────────
func _set_feedback(message: String) -> void:
	feedback_label.text = message
	feedback_time = FEEDBACK_DURATION


# 加载后显示按长期计数结算的离线差额。
func _show_offline_report_if_any() -> void:
	var report: Dictionary = GameState.last_offline_report
	var gained_talent := int(report.get("talent_points", 0))
	var gained_stones := float(report.get("spirit_stones", 0.0))
	var pending_talent := int(report.get("pending_talent_points", 0))
	var pending_stones := float(report.get("pending_spirit_stones", 0.0))
	if gained_talent <= 0 and gained_stones <= 0.0 and pending_talent <= 0 and pending_stones <= 0.0:
		offline_label.text = ""
		return
	if bool(report.get("active", false)):
		offline_label.text = "离线结算（与离线时长无关）：天赋点 +%d，灵石 +%s。" % [
			gained_talent,
			NumberFormat.format(gained_stones),
		]
	else:
		offline_label.text = "大限未续命：离线奖励待结算——天赋点 %d，灵石 %s。" % [
			pending_talent,
			NumberFormat.format(pending_stones),
		]
