## 天赋树面板。
## 用节点、连线和分支选择展示长期成长，替代原来的三行固定升级按钮。
class_name TalentPanel
extends Control


const GRAPH_SIZE := Vector2(1150.0, 640.0)
const NODE_SIZE := Vector2(150.0, 72.0)
const NODE_POSITIONS: Dictionary = {
	"root": Vector2(385.0, 18.0),
	"farming_start": Vector2(55.0, 130.0),
	"farming_yield": Vector2(0.0, 275.0),
	"farming_speed": Vector2(165.0, 275.0),
	"farming_capstone": Vector2(80.0, 430.0),
	"farming_grand": Vector2(80.0, 555.0),
	"alchemy_start": Vector2(385.0, 130.0),
	"alchemy_power": Vector2(300.0, 275.0),
	"alchemy_quality": Vector2(465.0, 275.0),
	"alchemy_capstone": Vector2(382.0, 430.0),
	"alchemy_grand": Vector2(382.0, 555.0),
	"spirit_start": Vector2(715.0, 130.0),
	"spirit_qi": Vector2(630.0, 275.0),
	"spirit_lifespan": Vector2(795.0, 275.0),
	"spirit_capstone": Vector2(712.0, 430.0),
	"spirit_grand": Vector2(712.0, 555.0),
	"luck_start": Vector2(950.0, 130.0),
	"luck_wealth": Vector2(880.0, 275.0),
	"luck_crit": Vector2(1015.0, 275.0),
	"luck_capstone": Vector2(948.0, 430.0),
}

var _root_vbox: VBoxContainer
var _points_label: Label
var _hint_label: Label
var _feedback_label: Label
var _graph: Control
var _buttons: Dictionary = {}
var _feedback_remaining := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(760.0, 620.0)
	_root_vbox = _build_root()
	_root_vbox.add_child(_make_label("【天赋树】", 20, Color(1.0, 0.9, 0.5)))
	_points_label = _make_label("", 16, Color(0.9, 0.82, 0.45))
	_root_vbox.add_child(_points_label)
	_hint_label = _make_label("先点亮道心，再在每条分支的两个方向中选择路线；分支终点只需完成其中一个方向。", 14, Color(0.72, 0.82, 0.76))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_vbox.add_child(_hint_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(scroll)
	_graph = Control.new()
	_graph.custom_minimum_size = GRAPH_SIZE
	scroll.add_child(_graph)
	_build_links()
	_build_nodes()

	_feedback_label = _make_label("", 14, Color(0.95, 0.85, 0.6))
	_root_vbox.add_child(_feedback_label)
	if GameState.has_signal("state_changed"):
		GameState.state_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_feedback_remaining -= delta
	if _feedback_remaining <= 0.0:
		_feedback_label.text = ""


func _build_root() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	return vbox


func _build_links() -> void:
	for node_id in TalentTree.node_ids():
		var node := TalentTree.node_def(node_id)
		var targets: Array = []
		for required in node.get("requires", []):
			targets.append(String(required))
		for required_any in node.get("requires_any", []):
			targets.append(String(required_any))
		for parent_id in targets:
			if not NODE_POSITIONS.has(parent_id) or not NODE_POSITIONS.has(node_id):
				continue
			var line := Line2D.new()
			line.width = 3.0
			line.default_color = Color(0.45, 0.52, 0.58, 0.8)
			line.points = PackedVector2Array([
				NODE_POSITIONS[parent_id] + Vector2(NODE_SIZE.x * 0.5, NODE_SIZE.y),
				NODE_POSITIONS[node_id] + Vector2(NODE_SIZE.x * 0.5, 0.0),
			])
			line.z_index = -1
			_graph.add_child(line)


func _build_nodes() -> void:
	for node_id in TalentTree.node_ids():
		var node := TalentTree.node_def(node_id)
		var button := Button.new()
		button.position = NODE_POSITIONS[node_id]
		button.size = NODE_SIZE
		button.custom_minimum_size = NODE_SIZE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_node_pressed.bind(node_id))
		button.tooltip_text = String(node.get("desc", ""))
		_graph.add_child(button)
		_buttons[node_id] = button


func _refresh() -> void:
	_points_label.text = "可用天赋点：%d    累计获得：%d    已点亮节点：%d/%d" % [
		int(GameState.talent_points),
		int(GameState.talent_points_earned),
		GameState.talent_nodes.size(),
		TalentTree.node_ids().size(),
	]
	for node_id in _buttons.keys():
		var node := TalentTree.node_def(String(node_id))
		var button: Button = _buttons[node_id]
		var unlocked := GameState.is_talent_unlocked(String(node_id))
		var available := GameState.can_unlock_talent(String(node_id))
		var cost := int(node.get("cost", 0))
		var status := "已点亮" if unlocked else ("可点亮 · %d 点" % cost if available else "锁定 · %d 点" % cost)
		button.text = "%s %s\n%s\n%s" % [String(node.get("icon", "◇")), String(node.get("name", node_id)), status, String(node.get("desc", ""))]
		button.disabled = unlocked or not available
		if unlocked:
			button.modulate = Color(1.0, 0.85, 0.35)
		elif available:
			button.modulate = Color(0.75, 1.0, 0.8)
		else:
			button.modulate = Color(0.58, 0.62, 0.68)


func _on_node_pressed(node_id: String) -> void:
	if GameState.unlock_talent(node_id):
		_set_feedback("已点亮「%s」：%s" % [TalentTree.node_def(node_id).get("name", node_id), TalentTree.node_def(node_id).get("desc", "")])
	else:
		_set_feedback("该节点尚未满足前置条件或天赋点不足。")


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
