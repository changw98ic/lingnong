## HUDPanel
## 顶部信息总览面板（v3 新增，契约 [UI 面板 / HUD]）。
##
## 职责：纯展示当前游戏核心状态，不承载交互按钮。所有数据来自 GameState 公共 API。
## 自包含：_ready 里用代码自建 Label/Container，不依赖 main.tscn 的任何节点路径，
##         由 main.gd 实例化并挂载即可。数字一律走 NumberFormat.format。
##
## 布局分三行：
##   第一行：境界名 · 修为/门槛进度（含百分比）· 当前总倍率（生产/修炼）· 天赋点
##   第二行：灵石 / 灵气及收获加成 / 天赋点 / 寿元 / 虫尸（核心资源）
##   第三行：时节 · 当前随机事件标签 · 狂暴 buff 倒计时 · 自动修炼每秒产出
##
## 刷新策略：
##   - 主刷新接 GameState.state_changed（任意模型变更即同步）
##   - 另在 _process 里以约 10 Hz 做轻量补刷，保证 buff 倒计时、自动修炼数值平滑跳动，
##     即使本帧没有 state_changed 信号也能保持视觉同步。
class_name HUDPanel
extends Control


## 补刷节流间隔（秒）。倒计时/每秒产出这类时间敏感数字按此频率刷新。
const _TICK_INTERVAL := 0.1

## 内部布局根：VBoxContainer，三行 HBoxContainer 挂在其下。
var _root_vbox: VBoxContainer

# 第一行节点
var _realm_label: Label
var _progress_label: Label
var _mult_label: Label
var _talent_header_label: Label

# 第二行节点
var _stones_label: Label
var _qi_label: Label
var _talent_label: Label
var _corpses_label: Label
var _lifespan_label: Label

# 第三行节点
var _season_label: Label
var _event_label: Label
var _buff_label: Label
var _auto_label: Label

## 补刷累计器。
var _tick_accumulator := 0.0


func _ready() -> void:
	# 让面板默认占满父级宽度、高度随内容自适应。
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 96)

	_root_vbox = _build_layout_root()
	_build_row1(_root_vbox)
	_build_row2(_root_vbox)
	_build_row3(_root_vbox)

	# 模型变更 → 立即全量刷新；另由 _process 做时间敏感补刷。
	if GameState.has_signal("state_changed"):
		GameState.state_changed.connect(_refresh_full)
	_refresh_full()


func _process(delta: float) -> void:
	_tick_accumulator += delta
	if _tick_accumulator >= _TICK_INTERVAL:
		_tick_accumulator = 0.0
		_refresh_tick()


# ─────────────────────────── 布局构建 ───────────────────────────

## 构建内部布局根：self → MarginContainer（留白 + 全幅）→ VBoxContainer（行容器）。
## 返回 VBoxContainer，三行 HBoxContainer 随后逐行加入其中。
func _build_layout_root() -> VBoxContainer:
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


## 第一行：境界 / 修为进度 / 总倍率 / 天赋点。
func _build_row1(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	_realm_label = _make_label("境界：—", 20, Color(1.0, 0.92, 0.55))
	row.add_child(_realm_label)
	row.add_child(_make_separator())

	_progress_label = _make_label("修为 0 / 0", 16, Color.WHITE)
	row.add_child(_progress_label)
	row.add_child(_make_separator())

	_mult_label = _make_label("生产×1.0  修炼×1.0", 16, Color(0.78, 0.95, 1.0))
	row.add_child(_mult_label)
	row.add_child(_make_separator())

	_talent_header_label = _make_label("天赋点 0", 14, Color(0.8, 0.85, 1.0))
	_talent_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talent_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_talent_header_label)


## 第二行：核心资源。
func _build_row2(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)

	_stones_label = _make_label("灵石 0", 16, Color(1.0, 0.95, 0.6))
	row.add_child(_stones_label)

	_qi_label = _make_label("灵气 0", 16, Color(0.7, 0.9, 1.0))
	row.add_child(_qi_label)

	_talent_label = _make_label("天赋点 0", 16, Color(0.95, 0.75, 1.0))
	row.add_child(_talent_label)

	_lifespan_label = _make_label("寿元 60年", 16, Color(0.95, 0.8, 0.7))
	row.add_child(_lifespan_label)

	_corpses_label = _make_label("虫尸 0", 14, Color(0.75, 0.75, 0.75))
	_corpses_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_corpses_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_corpses_label)


## 第三行：时节 / 事件 / buff / 自动修炼。
func _build_row3(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	_season_label = _make_label("时节：春", 14, Color(0.8, 0.85, 0.7))
	row.add_child(_season_label)
	row.add_child(_make_separator())

	_event_label = _make_label("", 14, Color(1.0, 0.82, 0.4))
	_event_label.visible = false
	row.add_child(_event_label)

	_buff_label = _make_label("", 14, Color(1.0, 0.55, 0.55))
	_buff_label.visible = false
	row.add_child(_buff_label)

	_auto_label = _make_label("", 14, Color(0.75, 0.95, 0.8))
	_auto_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_auto_label)


## 创建一个带字号、颜色与黑色描边的 Label（描边保证在背景上可读）。
func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	return label


## 行内分隔符（纯文本竖线，避免引入额外控件）。
func _make_separator() -> Label:
	var sep := Label.new()
	sep.text = "|"
	sep.add_theme_font_size_override("font_size", 14)
	sep.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	sep.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	sep.add_theme_constant_override("outline_size", 3)
	return sep


# ─────────────────────────── 刷新逻辑 ───────────────────────────

## 全量刷新（state_changed 触发）：三行全部重绘。
func _refresh_full() -> void:
	_refresh_row1()
	_refresh_row2()
	_refresh_row3()


## 时间敏感补刷（_process 触发）：只更新会随时间变动的部分，
## 避免每帧重写资源数字造成无谓的字符串分配。
func _refresh_tick() -> void:
	_refresh_row1()
	_refresh_row2()
	_refresh_row3()


## 第一行：境界 / 修为进度 / 总倍率 / 天赋点。
func _refresh_row1() -> void:
	_realm_label.text = "境界：%s" % _str(GameState.get_realm_name(), "—")

	var current := _float_or(GameState.cultivation, 0.0)
	var requirement := _float_or(GameState.get_next_realm_requirement(), 0.0)
	if requirement > 0.0:
		var pct: float = current / requirement * 100.0
		_progress_label.text = "修为 %s / %s（%.1f%%）" % [
			NumberFormat.format(current),
			NumberFormat.format(requirement),
			pct,
		]
	else:
		# 已达最高境界：只显示当前修为。
		_progress_label.text = "修为 %s（已圆满）" % NumberFormat.format(current)

	# 总倍率：取 0 号灵田的生产倍率作为代表（凡/灵/宝/仙随田档不同），
	# 修炼倍率与具体灵田无关。
	var prod_mult := _safe_call_float("get_production_mult", [0], 1.0)
	var cult_mult := _safe_call_float("get_cultivation_mult", [], 1.0)
	_mult_label.text = "生产×%s  修炼×%s" % [
		_fmt_mult(prod_mult),
		_fmt_mult(cult_mult),
	]

	_talent_header_label.text = "天赋点 %d" % _int_or(GameState.talent_points, 0)


## 第二行：核心资源。
func _refresh_row2() -> void:
	_stones_label.text = "灵石 %s" % NumberFormat.format(_float_or(GameState.spirit_stones, 0.0))
	_qi_label.text = "灵气 %s（收获×%s）" % [
		NumberFormat.format(_float_or(GameState.qi, 0.0)),
		_fmt_mult(_float_or(GameState.get_qi_harvest_mult(), 1.0)),
	]
	_talent_label.text = "天赋点 %d" % _int_or(GameState.talent_points, 0)
	var ly: float = maxf(0.0, _float_or(GameState.lifespan_years, 0.0))
	var max_life: float = maxf(0.0, _float_or(GameState.lifespan_max_years, 0.0))
	_lifespan_label.text = "寿元 %d/%d年" % [int(ly), int(max_life)]
	if bool(GameState.lifespan_depleted):
		_lifespan_label.text += "（大限，去商店续命）"
		_lifespan_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.32))
	else:
		_lifespan_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.32) if ly < 30.0 else Color(0.95, 0.8, 0.7))
	_corpses_label.text = "虫尸 %d" % _int_or(GameState.insect_corpses, 0)


## 第三行：时节 / 事件 / buff / 自动修炼（随时间跳动）。
func _refresh_row3() -> void:
	_season_label.text = "时节：%s" % _str(GameState.get_season_name(), "—")
	_refresh_event_tag()
	_refresh_buff_tag()
	_refresh_auto_tag()


## 随机事件标签：祥瑞降世(生产×10) / 天道感悟(修炼×20) / 兵主诞辰(虫攻×2)。
func _refresh_event_tag() -> void:
	var active: bool = bool(_safe_call("is_random_event_active", [], false))
	if not active:
		_event_label.visible = false
		_event_label.text = ""
		return
	var ev_id := _str(GameState.random_event, "")
	var display := _str(GameState.get_random_event_display_name(), "事件生效中")
	var tag := ""
	match ev_id:
		"auspicious":
			# 祥瑞降世：生产类倍率爆发（契约 [I]：×10）。
			tag = "★ %s 生产×%.0f" % [display, _float_or(GameState.event_prod_mult, BalanceConfig.EVENT_PROD_BONUS)]
		"dao_insight":
			# 天道感悟：修炼类倍率爆发（契约 [I]：×20）。
			tag = "%s 修炼×%.0f" % [display, _float_or(GameState.event_cult_mult, BalanceConfig.EVENT_CULT_BONUS)]
		"warlord_birthday":
			# 兵主诞辰：噬金虫攻击倍增（契约 [I]：×2）。
			tag = "☠ %s 虫攻×2" % display
		_:
			# 兜底：未知事件，仅显示名字与当前倍率分量。
			tag = "● %s（生产×%.1f 修炼×%.1f）" % [
				display,
				_float_or(GameState.event_prod_mult, BalanceConfig.DEFAULT_MULTIPLIER),
				_float_or(GameState.event_cult_mult, BalanceConfig.DEFAULT_MULTIPLIER),
			]
	_event_label.text = tag
	_event_label.visible = true


## 狂暴 buff 倒计时：仅 is_active_buff() 为真时显示。
func _refresh_buff_tag() -> void:
	var active: bool = bool(_safe_call("is_active_buff", [], false))
	if not active:
		_buff_label.visible = false
		_buff_label.text = ""
		return
	var mult := _float_or(GameState.active_buff_mult, 1.0)
	var remaining := _safe_call_float("get_active_buff_remaining", [], 0.0)
	_buff_label.text = "[狂暴 ×%s  %ds]" % [_fmt_mult(mult), maxi(0, int(remaining))]
	_buff_label.visible = true


## 自动修炼每秒产出：浓度/修为/灵气任一大于 0 时显示。
func _refresh_auto_tag() -> void:
	if GameState.lifespan_depleted:
		_auto_label.text = "大限：自动修炼与生产已暂停"
		_auto_label.visible = true
		return
	var auto: Dictionary = _safe_call_dict("get_auto_cultivation_per_sec", [], {})
	var density := _float_or(auto.get("density", 0.0), 0.0)
	var cult_per := _float_or(auto.get("cultivation", 0.0), 0.0)
	var qi_per := _float_or(auto.get("qi", 0.0), 0.0)
	if density <= 0.0 and cult_per <= 0.0 and qi_per <= 0.0:
		_auto_label.visible = false
		_auto_label.text = ""
		return
	_auto_label.text = "浓度 %.0f → 自动修炼 修为+%s/s  灵气+%s/s" % [
		density,
		NumberFormat.format(cult_per),
		NumberFormat.format(qi_per),
	]
	_auto_label.visible = true


# ─────────────────────────── 工具方法 ───────────────────────────

## 倍率统一展示：<10 保留 1 位小数；>=10 取整。避免长尾浮点。
func _fmt_mult(value: float) -> String:
	if is_nan(value):
		return "1.0"
	if value < 10.0:
		return "%.1f" % value
	return "%.0f" % value


## 取字符串，nil/空兜底。
func _str(value: Variant, fallback: String) -> String:
	if value == null:
		return fallback
	var s := str(value)
	return s if s != "" else fallback


## 取 float，类型不符/nil 兜底。
func _float_or(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	return float(value)


## 取 int，类型不符/nil 兜底。
func _int_or(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	return int(value)


## 安全调用方法取 float；集成期 GameState 尚未实现该方法时返回 fallback。
func _safe_call_float(method: String, args: Array, fallback: float) -> float:
	var v: Variant = _safe_call(method, args, fallback)
	return _float_or(v, fallback)


## 安全调用方法取 Dictionary。
func _safe_call_dict(method: String, args: Array, fallback: Dictionary) -> Dictionary:
	var v: Variant = _safe_call(method, args, fallback)
	if v is Dictionary:
		return v
	return fallback


## 统一的安全调用入口：方法不存在或返回 null 时返回 fallback。
## 仅用于刷新路径，避免集成期 GameState API 缺失导致整面板白屏。
func _safe_call(method: String, args: Array, fallback: Variant) -> Variant:
	if not GameState.has_method(method):
		return fallback
	var callable := Callable(GameState, method)
	var r: Variant = callable.callv(args) if not args.is_empty() else callable.call()
	return r if r != null else fallback
