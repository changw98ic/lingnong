## 成就面板。
##
## 目标定义和进度读取 AchievementSystem；面板不维护第二份统计，也不发放主经济资源。
class_name AchievementPanel
extends Control


var _root_vbox: VBoxContainer
var _summary_label: Label
var _rows_vbox: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(760.0, 560.0)
	_root_vbox = _build_root()
	_root_vbox.add_child(_make_label("【成就】", 20, Color(1.0, 0.9, 0.5)))
	_summary_label = _make_label("", 16, Color(0.9, 0.82, 0.45))
	_root_vbox.add_child(_summary_label)
	var hint := _make_label(
		"成就记录灵田、修行、境界、熟练度和轮回目标。成就点只记录完成度，不改变修为、灵石或天赋点倍率。",
		13,
		Color(0.72, 0.82, 0.76)
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(scroll)
	_rows_vbox = VBoxContainer.new()
	_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_vbox.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows_vbox)

	if GameState.has_signal("state_changed"):
		GameState.state_changed.connect(_refresh)
	_refresh()


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


func _refresh() -> void:
	if not is_instance_valid(_summary_label) or not is_instance_valid(_rows_vbox):
		return
	var rows: Array[Dictionary] = AchievementSystem.progress_rows(GameState)
	var completed := AchievementSystem.completed_count(GameState)
	_summary_label.text = "已完成 %d/%d    成就点 %d" % [completed, rows.size(), int(GameState.achievement_points)]
	while _rows_vbox.get_child_count() > 0:
		_rows_vbox.get_child(0).free()
	for row in rows:
		var completed_row := bool(row.get("completed", false))
		var current := float(row.get("current", 0.0))
		var target := float(row.get("target", 1.0))
		var status := "✓ 已完成" if completed_row else "○ 进行中"
		var label := _make_label(
			"%s  [%s] %s    %s / %s    +%d 成就点\n%s" % [
				status,
				String(row.get("category", "其他")),
				String(row.get("name", "")),
				NumberFormat.format(current),
				NumberFormat.format(target),
				int(row.get("points", 0)),
				String(row.get("desc", "")),
			],
			15,
			Color(1.0, 0.84, 0.38) if completed_row else Color(0.64, 0.70, 0.74)
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(0.0, 48.0)
		_rows_vbox.add_child(label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	return label
