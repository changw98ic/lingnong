## 灵农修仙 v3 主控制器（组合层）。
##
## 职责（契约：main.gd 变薄，只做组合 + 循环 + 爽感）：
##   1. _ready：加载存档 → 构建根布局 → 实例化 9 个自包含面板（HUD + 8 个主面板）；
##   2. _process：每帧驱动世界（update_world）+ 30 秒自动存档；
##   3. 爽感：监听 realm_changed 弹居中"突破成功"提示淡出；监听 state_changed 在资源
##      离散增长时（收获修为/灵石、商店和法术）弹出 +N 浮动数字上浮淡出。
##
## 不再保留 v2 的内联按钮/标签逻辑——玩法 UI 全部交由各面板自管理。
extends Control


## 自动存档周期（秒）。
const _SAVE_INTERVAL := 30.0
## 浮动数字上浮时长（秒）。
const _FLOAT_LIFETIME := 0.9
## 浮动数字上浮距离（像素）。
const _FLOAT_RISE := 56.0
## 浮动数字 x 抖动范围（像素，正负）。
const _FLOAT_JITTER := 90.0
## 同屏浮动数字上限（超过则丢弃，避免刷屏）。
const _FLOAT_MAX_CONCURRENT := 12
## 触发浮动数字的最小资源增量（过滤浮点噪声）。
const _FLOAT_MIN_DELTA := 0.5
## 突破提示停留时长（秒）。
const _BREAKTHROUGH_LIFETIME := 2.0


## 内容主容器（标题 + HUD + 主行）。
var _content_vbox: VBoxContainer

## 浮动数字层（置顶，不拦截鼠标）。
var _float_layer: Control
## 突破动画层（置顶，不拦截鼠标）。
var _breakthrough_layer: Control

## 上一次记录的核心资源值，用于在 state_changed 时计算离散增量。
var _prev_cultivation := 0.0
var _prev_spirit_stones := 0.0
var _prev_qi := 0.0

## 自动存档累计器。
var _save_accumulator := 0.0


func _ready() -> void:
	# 先加载存档：面板在 _ready 时即读取 GameState，必须先就位。
	SaveManager.load_game()
	# 在面板实例化前快照资源值，建立浮动数字的基线（避免加载即误触发）。
	_snapshot_resource_values()

	# 内容层：标题 + HUD + 标签式主面板。
	_content_vbox = _build_layout()

	# 两个置顶特效层（mouse_filter=IGNORE，不挡按钮点击）。
	_float_layer = _make_full_rect_layer("FloatLayer")
	add_child(_float_layer)
	_breakthrough_layer = _make_full_rect_layer("BreakthroughLayer")
	add_child(_breakthrough_layer)

	# 实例化并挂载 HUD 与 8 个自包含主面板。
	_instantiate_panels(_content_vbox)

	# 爽感接线：境界突破 → 居中提示；状态变更 → 资源增量浮动数字。
	GameState.realm_changed.connect(_on_realm_changed)
	GameState.state_changed.connect(_on_state_changed_for_floats)
	# 即时存档：任何模型变更（收获 / 出售 / 服丹 / 突破 / 天赋 / 事件切换）立即落盘，
	# 强退最多丢一帧；30 秒定时器保留作兜底。
	GameState.state_changed.connect(_on_state_changed_for_save)


func _process(delta: float) -> void:
	# 每帧驱动世界（季节 / 事件 / 噬金虫 / 自动修炼 / 自动收获）。
	GameState.update_world(delta)

	# 30 秒自动存档。
	_save_accumulator += delta
	if _save_accumulator >= _SAVE_INTERVAL:
		_save_accumulator = 0.0
		SaveManager.save_game()


# ─────────────────────────── 布局构建 ───────────────────────────

## 创建一个铺满根 Control、不拦截鼠标的特效层。
func _make_full_rect_layer(name: String) -> Control:
	var layer := Control.new()
	layer.name = name
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer


## 根布局：MarginContainer（留白 + 全幅，挂到 self）→ VBoxContainer（标题 + 内容），返回 VBox。
func _build_layout() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "灵农修仙 · 灵田问道"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.34))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(title)

	return vbox


## 实例化面板：HUD 常驻顶部；下方 TabContainer 一次只显示一个主面板（不再全挤一屏）。
func _instantiate_panels(root: VBoxContainer) -> void:
	# 顶部 HUD 横铺（常驻：境界/资源/倍率/事件，无论在哪个标签都可见）。
	root.add_child(HUDPanel.new())

	# 标签栏：种植 / 修炼·突破 / 天赋树 / 成就 / 商店 / 法术·事件 / 数值模拟。
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.current_tab = 0
	root.add_child(tabs)

	_add_tab(tabs, FieldPanel.new(), "种植")
	_add_tab(tabs, ProgressionPanel.new(), "修炼·突破")
	_add_tab(tabs, TalentPanel.new(), "天赋树")
	_add_tab(tabs, AchievementPanel.new(), "成就")
	_add_tab(tabs, ShopPanel.new(), "商店")
	_add_tab(tabs, EventPanel.new(), "法术·事件")
	_add_tab(tabs, SimulationPanel.new(), "数值模拟")


## 把面板作为标签页加入 TabContainer：填满标签区，标题用 title。
func _add_tab(tabs: TabContainer, panel: Control, title: String) -> void:
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.name = title
	tabs.add_child(panel)
	tabs.set_tab_title(panel.get_index(), title)


## 把面板包进 PanelContainer 做视觉边框。expand_h=true 时横向扩张占位。
## add=true 时把边框挂到 parent；否则返回边框由调用方自行挂载。
func _wrap_in_frame(panel: Control, expand_h: bool, parent: Control, add: bool = true) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand_h else Control.SIZE_SHRINK_CENTER
	frame.add_child(panel)
	if add:
		parent.add_child(frame)
	return frame


# ─────────────────────────── 爽感：突破动画 ───────────────────────────

## 境界突破：弹一个居中"突破成功！{境界} 生产×N 修炼×N"提示，上浮淡出 2 秒。
## realm_changed 在 realm_index 已递增后触发，故此处读到的即新境界。
func _on_realm_changed() -> void:
	var realm_name := String(GameState.get_realm_name())
	var prod := _fmt_mult(float(GameState.get_production_mult(0)))
	var cult := _fmt_mult(float(GameState.get_cultivation_mult()))
	var text := "突破成功！%s\n生产 ×%s    修炼 ×%s" % [realm_name, prod, cult]
	_spawn_breakthrough(text)


## 构造居中突破提示并用 Tween 上浮 + 淡入淡出。
func _spawn_breakthrough(text: String) -> void:
	# CenterContainer 保证多行 Label 在任意尺寸下都居中，避免锚点计算偏差。
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breakthrough_layer.add_child(center)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate.a = 0.0
	center.add_child(label)

	# 并行：淡入 + 全程上浮；延迟淡出；最后清理。
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.tween_property(label, "position", Vector2(0.0, -30.0), _BREAKTHROUGH_LIFETIME).as_relative().set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(_BREAKTHROUGH_LIFETIME - 0.6)
	tween.chain().tween_callback(center.queue_free)


## 状态变更即存：玩家动作与离散事件入账后立即写入存档。
func _on_state_changed_for_save() -> void:
	SaveManager.save_game()


# ─────────────────────────── 爽感：浮动数字 ───────────────────────────

## 状态变更：比较核心资源前后差值，正向离散增量弹出 +N 浮动数字。
## update_world 的自动修炼不触发 state_changed，故此处捕获的几乎都是玩家动作
## （收获 / 出售 / 服丹）与离散计时事件带来的资源入账。
func _on_state_changed_for_floats() -> void:
	if _float_layer.get_child_count() >= _FLOAT_MAX_CONCURRENT:
		_snapshot_resource_values()
		return

	var c := float(GameState.cultivation)
	var s := float(GameState.spirit_stones)
	var q := float(GameState.qi)
	var dc := c - _prev_cultivation
	var ds := s - _prev_spirit_stones
	var dq := q - _prev_qi
	# 先快照再弹数字，避免多次入账被合并遗漏。
	_snapshot_resource_values()

	if dc > _FLOAT_MIN_DELTA:
		_spawn_float("+%s 修为" % NumberFormat.format(dc), Color(1.0, 0.85, 0.4))
	if ds > _FLOAT_MIN_DELTA:
		_spawn_float("+%s 灵石" % NumberFormat.format(ds), Color(1.0, 0.95, 0.6))
	if dq > _FLOAT_MIN_DELTA:
		_spawn_float("+%s 灵气" % NumberFormat.format(dq), Color(0.7, 0.9, 1.0))


## 在浮动层上部居中区域生成一个 +N Label，上浮 + 淡出后自动销毁。
func _spawn_float(text: String, color: Color) -> void:
	var w := _float_layer.size.x
	var h := _float_layer.size.y
	# 窗口尚未布局时兜底为一个合理位置。
	if w <= 1.0:
		w = 1280.0
	if h <= 1.0:
		h = 720.0
	var start_x := w * 0.5 + randf_range(-_FLOAT_JITTER, _FLOAT_JITTER)
	var start_y := h * 0.18

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	label.position = Vector2(start_x, start_y)
	_float_layer.add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	# 上浮 + 轻微随机横向漂移。
	tween.tween_property(label, "position", Vector2(randf_range(-20.0, 20.0), -_FLOAT_RISE), _FLOAT_LIFETIME).as_relative().set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, _FLOAT_LIFETIME)
	tween.chain().tween_callback(label.queue_free)


# ─────────────────────────── 工具 ───────────────────────────

## 记录当前核心资源值，作为下一次增量比较的基线。
func _snapshot_resource_values() -> void:
	_prev_cultivation = float(GameState.cultivation)
	_prev_spirit_stones = float(GameState.spirit_stones)
	_prev_qi = float(GameState.qi)


## 倍率展示：<10 保留 1 位小数；>=10 取整。与各面板口径一致。
func _fmt_mult(value: float) -> String:
	if is_nan(value):
		return "1.0"
	if value < 10.0:
		return "%.1f" % value
	return "%.0f" % value
