## 商店面板。
## 这里提供灵石的长期消耗：续寿、补灵气、购买天赋点。
class_name ShopPanel
extends Control


var _root_vbox: VBoxContainer
var _items_box: VBoxContainer
var _feedback_label: Label
var _rows: Dictionary = {}
var _feedback_remaining := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(480.0, 380.0)
	_root_vbox = _build_root()
	_root_vbox.add_child(_make_label("【万宝商店】", 20, Color(1.0, 0.9, 0.5)))
	_root_vbox.add_child(_make_label("普通商品提供寿元、灵气和天赋点；突破材料只能在这里兑换，不能种植。", 14, Color(0.72, 0.82, 0.76)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(scroll)
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 8)
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_items_box)
	_build_rows()
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
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	return vbox


func _build_rows() -> void:
	for item in GameState.get_shop_items():
		var item_id := String(item.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := _make_label("", 14, Color(0.88, 0.9, 0.86))
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(100.0, 38.0)
		buy.pressed.connect(_on_buy.bind(item_id))
		row.add_child(buy)
		_items_box.add_child(row)
		_rows[item_id] = {"info": info, "buy": buy}


func _refresh() -> void:
	for item in GameState.get_shop_items():
		var item_id := String(item.get("id", ""))
		if not _rows.has(item_id):
			continue
		var row: Dictionary = _rows[item_id]
		var info: Label = row["info"]
		var buy: Button = row["buy"]
		var cost := float(item.get("cost", 0.0))
		var description := String(item.get("desc", ""))
		var effect := String(item.get("effect", ""))
		var required_realm := int(item.get("required_realm", 0))
		if effect == "breakthrough_material":
			var material_id := String(item.get("material_id", ""))
			description += "\n持有：%d" % GameState.get_breakthrough_material_count(material_id)
			if required_realm > 0:
				description += "　%s开放" % _realm_name(required_realm)
		elif effect == "tribulation_healing":
			description += "\n库存：%d" % GameState.healing_pills
		elif effect == "tribulation_resistance":
			description += "\n库存：%d" % GameState.resistance_pills
		elif effect == "tribulation_enhancement":
			description += "\n库存：%d" % GameState.enhancement_pills
		info.text = "%s  %s\n%s\n价格：%s 灵石" % [
			String(item.get("icon", "◇")),
			String(item.get("name", item_id)),
			description,
			NumberFormat.format(cost),
		]
		buy.text = "兑换" if effect == "breakthrough_material" else "购买"
		buy.disabled = (
			GameState.spirit_stones < cost
			or GameState.realm_index < required_realm
			or (item_id == "longevity_pill" and GameState.lifespan_years >= GameState.lifespan_max_years)
			or (effect == "buff" and (GameState.lifespan_depleted or GameState.tribulation_active))
		)


func _on_buy(item_id: String) -> void:
	var item := ShopSystem.new().get_item(item_id)
	if GameState.buy_shop_item(item_id):
		_set_feedback("购买%s成功。" % String(item.get("name", item_id)))
	else:
		_set_feedback("购买失败：灵石不足或当前资源已满。")


func _set_feedback(message: String) -> void:
	_feedback_label.text = message
	_feedback_remaining = 4.0


func _realm_name(realm_index: int) -> String:
	if realm_index < 0 or realm_index >= RealmConfig.realm_count():
		return "更高境界"
	return String(BalanceConfig.REALMS[realm_index].get("name", "更高境界"))


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	return label
