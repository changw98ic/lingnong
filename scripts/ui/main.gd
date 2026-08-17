extends Control

const NumberFmt = preload("res://scripts/core/numbers/number_format_service.gd")
const EnvironmentLayer = preload("res://scripts/ui/environment_art_layer.gd")
const Art = preload("res://scripts/art/art_catalog.gd")

const BG := Color("0b1513")
const SURFACE := Color(0.071, 0.129, 0.114, 0.70)
const SURFACE_RAISED := Color(0.090, 0.161, 0.137, 0.82)
const SURFACE_DEEP := Color(0.055, 0.102, 0.090, 0.58)
const BORDER := Color("29463b")
const BORDER_SOFT := Color("1e352e")
const TEXT := Color("eef5ee")
const MUTED := Color("96aaa0")
const GOLD := Color("e9bd5c")
const GREEN := Color("67d39b")
const BLUE := Color("75b9ff")
const RED := Color("ed8b86")
const PURPLE := Color("c8a7ff")
const MIN_FONT_SIZE := 24
const BUTTON_ICON_SCALE := 2.0

const PAGE_INFO := {
	"overview": {"title": "洞府", "subtitle": "看清当前收益、路线状态，以及下一步最值得做的事。"},
	"production": {"title": "灵田", "subtitle": "调配灵植阵势，蕴养灵田与聚灵阵。"},
	"route": {"title": "境界", "subtitle": "在道途上择定下一境，叩问破关并迎击雷劫。"},
	"tribulation": {"title": "雷劫", "subtitle": "劫云已至时，在渡劫法坛完成这一境的考验。"},
	"materials": {"title": "宝物", "subtitle": "开启百宝阁，清点宝箱、灵材与天道印记。"},
	"automation": {"title": "阵法", "subtitle": "点亮阵纹，让灵田、破境、雷劫与轮回自行运转。"},
	"reset": {"title": "轮回 / 飞升", "subtitle": "走上轮回台，在转世与登天之间作出抉择。"},
	"receipts": {"title": "日志", "subtitle": "翻开玉册，回看突破、雷劫、轮回与飞升。"},
}

const DRAWER_PAGES := ["production", "route", "tribulation", "materials", "automation", "reset", "receipts"]
const PAGE_ANIMATIONS := {
	"production": "animation.mind_flower_breathe",
	"tribulation": "animation.tribulation",
	"materials": "animation.chest_rare_open",
	"automation": "animation.gathering_array_cycle",
	"reset": "animation.reincarnation",
	"receipts": "animation.disciple_inspecting",
}

const BLUEPRINT_ORDER := [
	"auto_purchase_max",
	"auto_tribulation",
	"roi_purchase",
	"material_reserve",
	"auto_breakthrough",
	"auto_reincarnation",
	"offline_cross_run",
]

const BLUEPRINT_NAMES := {
	"auto_purchase_max": "自动购买最大",
	"auto_tribulation": "自动结算雷劫",
	"roi_purchase": "收益率购买",
	"material_reserve": "材料保底预留",
	"auto_breakthrough": "自动突破",
	"auto_reincarnation": "自动轮回",
	"offline_cross_run": "离线跨世模拟",
}

const BLUEPRINT_DESCRIPTIONS := {
	"auto_purchase_max": "把当前预算按优先级投入灵田、灵土和聚灵阵。",
	"auto_tribulation": "气血达到安全线后自动锁定并结算雷劫。",
	"roi_purchase": "优先购买对当前生产收益最划算的升级。",
	"material_reserve": "按硬保底需要预留下一轮突破材料。",
	"auto_breakthrough": "材料和修为达标后自动尝试突破批次。",
	"auto_reincarnation": "满足轮回规则后自动开启下一世。",
	"offline_cross_run": "离线结算时允许模拟跨越世代边界。",
}

const BLUEPRINT_UNLOCKS := {
	"auto_purchase_max": "普通练气",
	"auto_tribulation": "锻体练气士",
	"roi_purchase": "丹道筑基",
	"material_reserve": "丹道筑基",
	"auto_breakthrough": "一纹金丹",
	"auto_reincarnation": "三纹金丹",
	"offline_cross_run": "三纹金丹",
}

const TIER_NAMES := {"common": "普通", "elite": "精良", "rare": "稀有"}
const MAJOR_NAMES := {"qi": "练气", "foundation": "筑基", "golden": "金丹"}

const NAV_ART := {
	"overview": "res://assets/art/static/navigation_icon/navigation-icon-overview.png",
	"production": "res://assets/art/static/navigation_icon/navigation-icon-production.png",
	"route": "res://assets/art/static/navigation_icon/navigation-icon-paths.png",
	"tribulation": "res://assets/art/static/navigation_icon/navigation-icon-tribulation.png",
	"materials": "res://assets/art/static/navigation_icon/navigation-icon-materials.png",
	"receipts": "res://assets/art/static/navigation_icon/navigation-icon-receipts.png",
	"automation": "res://assets/art/static/navigation_icon/navigation-icon-automation.png",
	"reset": "res://assets/art/static/navigation_icon/navigation-icon-reincarnation.png",
}

const CROP_ART := {
	"gathering_grass": "res://assets/art/static/crop/crop-gathering-grass.png",
	"nourishing_ginseng": "res://assets/art/static/crop/crop-nourishing-ginseng.png",
	"mind_flower": "res://assets/art/static/crop/crop-mind-flower.png",
	"sun_fruit": "res://assets/art/static/crop/crop-sun-fruit.png",
	"five_element_ear": "res://assets/art/static/crop/crop-five-element-ear.png",
	"heaven_lotus": "res://assets/art/static/crop/crop-heaven-lotus.png",
	"purple_mushroom": "res://assets/art/static/crop/crop-purple-mushroom.png",
}

const CROP_ANIMATIONS := {
	"gathering_grass": "animation.gathering_grass_sway",
	"nourishing_ginseng": "animation.nourishing_ginseng_breathe",
	"mind_flower": "animation.mind_flower_breathe",
	"sun_fruit": "animation.sun_fruit_breathe",
	"five_element_ear": "animation.five_element_ear_sway",
	"heaven_lotus": "animation.heaven_lotus_breathe",
	"purple_mushroom": "animation.purple_mushroom_breathe",
}

const MAGENTA_MATTE_ANIMATIONS := {
	"animation.clouds_drift": true,
	"animation.waterfall_flow": true,
	"animation.stream_flow": true,
	"animation.waterwheel_turn": true,
	"animation.bamboo_leaves_sway": true,
	"animation.gathering_array_cycle": true,
	"animation.spirit_crystal_breathe": true,
	"animation.gathering_grass_sway": true,
	"animation.nourishing_ginseng_breathe": true,
	"animation.sun_fruit_breathe": true,
	"animation.five_element_ear_sway": true,
	"animation.heaven_lotus_breathe": true,
	"animation.disciple_watering": true,
	"animation.disciple_meditating": true,
	"animation.disciple_inspecting": true,
	"animation.disciple_casting": true,
	"animation.spirit_beast_idle": true,
	"animation.butterfly_flight": true,
	"animation.chest_common_open": true,
	"animation.chest_elite_open": true,
}

const RED_MATTE_ANIMATIONS := {
	"animation.mind_flower_breathe": true,
	"animation.purple_mushroom_breathe": true,
	"animation.chest_rare_open": true,
}

const REALM_ART := {
	"qi": "res://assets/art/static/realm/realm-qi-refining.png",
	"foundation": "res://assets/art/static/realm/realm-foundation.png",
	"golden": "res://assets/art/static/realm/realm-golden-core.png",
}

const TIER_ART := {
	"common": "res://assets/art/static/chest/chest-common.png",
	"elite": "res://assets/art/static/chest/chest-elite.png",
	"rare": "res://assets/art/static/chest/chest-rare.png",
}

var _page_box: VBoxContainer
var _page_scroll: ScrollContainer
var _page_drawer: PanelContainer
var _game_header: Control
var _bottom_navigation: Control
var _drawer_title: Label
var _drawer_subtitle: Label
var _drawer_animation: AnimatedSprite2D
var _drawer_static_crest: TextureRect
var _drawer_animation_slot: Control
var _drawer_nav_buttons: Dictionary = {}
var _nav_box: VBoxContainer
var _page_title: Label
var _page_subtitle: Label
var _header_summary: Label
var _status_pill: Label
var _sidebar_target: Label
var _notice_label: Label
var _notice_toast: PanelContainer
var _nav_buttons: Dictionary = {}
var _hud_values: Dictionary = {}
var _normalized_icon_cache: Dictionary = {}
var _world_outline_materials: Dictionary = {}
var _crop_transition_from := ""
var _crop_transition_to := ""
var _crop_transition_pending := false
var _current_page := "overview"
var _page_dirty := true
var _last_render_revision := -1
var _refresh_accumulator := 0.0
var _page_refresh_accumulator := 0.0
var _save_accumulator := 0.0
var _simulation_tick := false
var _preserve_page_scroll := false


func _ready() -> void:
	SaveManager.load_game()
	_build_ui()
	GameState.state_changed.connect(_on_state_changed)
	_refresh()


func _process(delta: float) -> void:
	_page_refresh_accumulator += delta
	_simulation_tick = true
	GameState.update_world(delta)
	_simulation_tick = false
	_refresh_accumulator += delta
	_save_accumulator += delta
	if _refresh_accumulator >= 0.25:
		_refresh_accumulator = 0.0
		_refresh()
	if _save_accumulator >= 10.0:
		_save_accumulator = 0.0
		SaveManager.save_game()


func _on_state_changed() -> void:
	if not _simulation_tick:
		_page_dirty = true


func _build_ui() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = MIN_FONT_SIZE
	theme = ui_theme

	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = _asset("res://assets/art/static/environment/environment-cultivation-valley-base.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var environment_art := EnvironmentLayer.new()
	environment_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(environment_art)

	_game_header = _build_game_header()
	add_child(_game_header)
	add_child(_build_side_navigation())

	_page_drawer = PanelContainer.new()
	_page_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_drawer.z_index = 50
	_page_drawer.visible = false
	var drawer_background := StyleBoxFlat.new()
	drawer_background.bg_color = Color(0.004, 0.018, 0.014, 0.84)
	_page_drawer.add_theme_stylebox_override("panel", drawer_background)
	add_child(_page_drawer)

	var game_frame := PanelContainer.new()
	game_frame.name = "GameFrame"
	game_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_page_drawer.add_child(game_frame)
	var frame_art := TextureRect.new()
	frame_art.name = "GameFrameArtwork"
	frame_art.texture = _normalized_icon("res://assets/art/static/ui/ui-context-panel.png")
	frame_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_art.stretch_mode = TextureRect.STRETCH_SCALE
	frame_art.modulate = Color(1.0, 1.0, 1.0, 0.42)
	frame_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_art.visible = false
	game_frame.add_child(frame_art)

	var frame_inset := MarginContainer.new()
	frame_inset.add_theme_constant_override("margin_left", 24)
	frame_inset.add_theme_constant_override("margin_right", 24)
	frame_inset.add_theme_constant_override("margin_top", 18)
	frame_inset.add_theme_constant_override("margin_bottom", 18)
	game_frame.add_child(frame_inset)
	var inner_panel := PanelContainer.new()
	inner_panel.name = "GameInnerPanel"
	inner_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	frame_inset.add_child(inner_panel)
	var drawer_margin := MarginContainer.new()
	drawer_margin.add_theme_constant_override("margin_left", 10)
	drawer_margin.add_theme_constant_override("margin_right", 10)
	drawer_margin.add_theme_constant_override("margin_top", 8)
	drawer_margin.add_theme_constant_override("margin_bottom", 8)
	inner_panel.add_child(drawer_margin)
	var drawer_body := VBoxContainer.new()
	drawer_body.add_theme_constant_override("separation", 18)
	drawer_margin.add_child(drawer_body)
	var command_bar := PanelContainer.new()
	command_bar.name = "DrawerCommandBar"
	command_bar.add_theme_stylebox_override("panel", _drawer_command_bar_style())
	drawer_body.add_child(command_bar)
	var command_margin := MarginContainer.new()
	command_margin.add_theme_constant_override("margin_left", 18)
	command_margin.add_theme_constant_override("margin_right", 18)
	command_margin.add_theme_constant_override("margin_top", 8)
	command_margin.add_theme_constant_override("margin_bottom", 8)
	command_bar.add_child(command_margin)
	var drawer_header := HBoxContainer.new()
	drawer_header.custom_minimum_size.y = 124
	drawer_header.add_theme_constant_override("separation", 18)
	command_margin.add_child(drawer_header)
	drawer_header.add_child(_build_drawer_animation_crest())
	var drawer_identity := VBoxContainer.new()
	drawer_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_identity.alignment = BoxContainer.ALIGNMENT_CENTER
	drawer_identity.add_theme_constant_override("separation", 4)
	_drawer_title = _label("", 34, Color("fff1bb"))
	_drawer_subtitle = _label("", MIN_FONT_SIZE, MUTED)
	_apply_text_outline(_drawer_title, 4)
	drawer_identity.add_child(_drawer_title)
	drawer_identity.add_child(_drawer_subtitle)
	drawer_header.add_child(drawer_identity)

	var drawer_tabs := HBoxContainer.new()
	drawer_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	drawer_tabs.add_theme_constant_override("separation", 8)
	_drawer_nav_buttons.clear()
	for page_id in DRAWER_PAGES:
		var tab := _drawer_tab_button(String(page_id))
		_drawer_nav_buttons[page_id] = tab
		drawer_tabs.add_child(tab)
	drawer_header.add_child(drawer_tabs)

	var close_button := _page_button("返回洞府", _close_page_drawer, GOLD, String(NAV_ART["overview"]))
	close_button.custom_minimum_size = Vector2(190, 72)
	drawer_header.add_child(close_button)
	_add_game_divider(drawer_body)

	_page_scroll = ScrollContainer.new()
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer_body.add_child(_page_scroll)
	_page_box = VBoxContainer.new()
	_page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_box.custom_minimum_size = Vector2(0, 0)
	_page_box.add_theme_constant_override("separation", 14)
	_page_scroll.add_child(_page_box)

	_bottom_navigation = _build_bottom_nav()
	add_child(_bottom_navigation)


func _build_drawer_animation_crest() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(124, 124)
	_drawer_animation_slot = slot
	var frame := TextureRect.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.texture = _normalized_icon("res://assets/art/static/ui/ui-round-icon-button-frame.png")
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(frame)
	_drawer_animation = AnimatedSprite2D.new()
	_drawer_animation.name = "AnimatedPageCrest"
	_drawer_animation.position = Vector2(62, 58)
	_drawer_animation.z_index = 1
	slot.add_child(_drawer_animation)
	_drawer_static_crest = TextureRect.new()
	_drawer_static_crest.name = "StaticPageCrest"
	_drawer_static_crest.position = Vector2(16, 12)
	_drawer_static_crest.size = Vector2(92, 92)
	_drawer_static_crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drawer_static_crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drawer_static_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_static_crest.visible = false
	_drawer_static_crest.z_index = 1
	slot.add_child(_drawer_static_crest)
	return slot


func _drawer_tab_button(page_id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(68, 68)
	button.toggle_mode = true
	button.icon = _normalized_icon(String(NAV_ART.get(page_id, "")))
	button.add_theme_constant_override("icon_max_width", 52)
	button.expand_icon = true
	button.tooltip_text = String(PAGE_INFO.get(page_id, {}).get("title", page_id))
	button.set_meta("drawer_page_id", page_id)
	button.add_theme_stylebox_override("normal", _drawer_tab_style(false))
	button.add_theme_stylebox_override("hover", _drawer_tab_style(true))
	button.add_theme_stylebox_override("pressed", _drawer_tab_style(true))
	button.pressed.connect(_drawer_tab_selected.bind(page_id))
	return button


func _drawer_tab_selected(page_id: String) -> void:
	if _current_page == page_id:
		return
	_current_page = page_id
	_page_dirty = true
	_preserve_page_scroll = false
	_set_drawer_visuals(page_id)
	_update_nav()
	if is_instance_valid(_page_box):
		_render_page(GameState.get_summary())


func _set_drawer_visuals(page_id: String) -> void:
	var info: Dictionary = PAGE_INFO.get(page_id, PAGE_INFO["overview"])
	if is_instance_valid(_drawer_title):
		_drawer_title.text = String(info["title"])
	if is_instance_valid(_drawer_subtitle):
		_drawer_subtitle.text = String(info["subtitle"])
	if not is_instance_valid(_drawer_animation):
		return
	if page_id == "route":
		var definition := BalanceConfig.node(GameState.run.active_target_id)
		var major := String(definition.get("major", "qi"))
		_drawer_animation.stop()
		_drawer_animation.visible = false
		if is_instance_valid(_drawer_static_crest):
			_drawer_static_crest.texture = _normalized_icon(String(REALM_ART.get(major, REALM_ART["qi"])))
			_drawer_static_crest.visible = true
		return
	_drawer_animation.visible = true
	if is_instance_valid(_drawer_static_crest):
		_drawer_static_crest.visible = false
	var animation_id := String(PAGE_ANIMATIONS.get(page_id, "animation.disciple_meditating"))
	var frames := Art.sprite_frames(animation_id)
	var animation_entry := Art.animation_entry(animation_id)
	if String(animation_entry.get("blend_mode", "mix")) == "additive":
		var additive_material := CanvasItemMaterial.new()
		additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_drawer_animation.material = additive_material
	else:
		_drawer_animation.material = null
	_drawer_animation.sprite_frames = frames
	_drawer_animation.animation = &"default"
	_drawer_animation.frame = 0
	_drawer_animation.speed_scale = 1.05
	if frames != null and frames.get_frame_count(&"default") > 0:
		var texture := frames.get_frame_texture(&"default", 0)
		if texture != null:
			var frame_size := texture.get_size()
			var fit := minf(92.0 / maxf(1.0, frame_size.x), 92.0 / maxf(1.0, frame_size.y))
			_drawer_animation.scale = Vector2.ONE * fit
	_drawer_animation.play()


func _add_game_divider(parent: VBoxContainer) -> void:
	var divider := HBoxContainer.new()
	divider.add_theme_constant_override("separation", 12)
	parent.add_child(divider)
	var left := HSeparator.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_stylebox_override("separator", _divider_style())
	divider.add_child(left)
	var emblem := TextureRect.new()
	emblem.custom_minimum_size = Vector2(42, 28)
	emblem.texture = _normalized_icon("res://assets/art/static/brand/brand-lingnong-emblem.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.modulate = Color(1.0, 0.88, 0.54, 0.90)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_child(emblem)
	var right := HSeparator.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("separator", _divider_style())
	divider.add_child(right)


func _build_game_header() -> Control:
	var header := Control.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.z_index = 20

	var profile := PanelContainer.new()
	profile.position = Vector2(20, 16)
	profile.size = Vector2(430, 132)
	profile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	header.add_child(profile)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	profile.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	margin.add_child(row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(100, 100)
	portrait.texture = _normalized_icon("res://assets/art/static/portrait/portrait-main-cultivator.png")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 2)
	_page_title = _scene_label("灵溪小筑", 30, Color("fff0bc"))
	identity.add_child(_page_title)
	_page_subtitle = _scene_label("", MIN_FONT_SIZE, Color("f1e5bd"))
	_page_subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	identity.add_child(_page_subtitle)
	_header_summary = _scene_label("", MIN_FONT_SIZE, Color("e1d5ad"))
	_header_summary.autowrap_mode = TextServer.AUTOWRAP_OFF
	_header_summary.visible = false
	identity.add_child(_header_summary)
	_status_pill = _scene_label("● 运行中", MIN_FONT_SIZE, Color("f1c968"))
	identity.add_child(_status_pill)
	row.add_child(identity)

	var hud := HBoxContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud.offset_left = -900.0
	hud.offset_right = -78.0
	hud.offset_top = 14.0
	hud.offset_bottom = 98.0
	hud.alignment = BoxContainer.ALIGNMENT_END
	hud.add_theme_constant_override("separation", 10)
	_hud_values.clear()
	hud.add_child(_hud_chip("cultivation", "修为", "res://assets/art/static/resource_icon/resource-icon-cultivation.png", GOLD))
	hud.add_child(_hud_chip("stones", "灵石", "res://assets/art/static/resource_icon/resource-icon-spirit-stone.png", GREEN))
	hud.add_child(_hud_chip("body", "体魄", "res://assets/art/static/resource_icon/resource-icon-physique.png", BLUE))
	hud.add_child(_hud_chip("spirit", "神识", "res://assets/art/static/resource_icon/resource-icon-consciousness.png", PURPLE))
	header.add_child(hud)

	var save_button := Button.new()
	save_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	save_button.offset_left = -74.0
	save_button.offset_right = -10.0
	save_button.offset_top = 14.0
	save_button.offset_bottom = 78.0
	save_button.icon = _normalized_icon("res://assets/art/static/action_icon/action-icon-save.png")
	save_button.add_theme_constant_override("icon_max_width", 56)
	save_button.expand_icon = true
	save_button.add_theme_stylebox_override("normal", _round_nav_style(false, 4))
	save_button.add_theme_stylebox_override("hover", _round_nav_style(true, 4))
	save_button.add_theme_stylebox_override("pressed", _round_nav_style(true, 4))
	save_button.pressed.connect(_save_now)
	save_button.tooltip_text = "保存进度"
	header.add_child(save_button)
	return header


func _build_bottom_nav() -> PanelContainer:
	var dock := PanelContainer.new()
	dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dock.offset_left = -340.0
	dock.offset_right = 340.0
	dock.offset_top = -154.0
	dock.offset_bottom = -4.0
	dock.z_index = 20
	dock.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin := MarginContainer.new()
	dock.add_child(margin)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	var items := [
		["overview", "洞府"],
		["production", "灵田"],
		["route", "境界"],
		["materials", "宝物"],
		["automation", "阵法"],
	]
	for item in items:
		var page_id := String(item[0])
		row.add_child(_scene_nav_item(page_id, String(item[1]), String(NAV_ART.get(page_id, "")), 72.0, true))
	return dock


func _hud_chip(key: String, title: String, icon_path: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(190, 80)
	chip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	chip.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.texture = _normalized_icon(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 1)
	var title_label := _scene_label(title, MIN_FONT_SIZE, Color("f2e5ba"))
	_apply_text_outline(title_label, 5)
	labels.add_child(title_label)
	var value := _scene_label("—", 28, accent.lerp(Color.WHITE, 0.22))
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	_apply_text_outline(value, 6)
	labels.add_child(value)
	row.add_child(labels)
	_hud_values[key] = {"value": value}
	return chip


func _build_side_navigation() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 20

	var left := VBoxContainer.new()
	left.position = Vector2(22, 178)
	left.add_theme_constant_override("separation", -10)
	left.add_child(_scene_nav_item("receipts", "日志", String(NAV_ART["receipts"]), 64.0))
	left.add_child(_scene_nav_item("tribulation", "雷劫", String(NAV_ART["tribulation"]), 64.0))
	layer.add_child(left)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -110.0
	right.offset_right = -18.0
	right.offset_top = 178.0
	right.offset_bottom = 390.0
	right.add_theme_constant_override("separation", 14)
	right.add_child(_scene_nav_item("reset", "轮回", String(NAV_ART["reset"]), 64.0))
	layer.add_child(right)
	return layer


func _scene_nav_item(
	page_id: String,
	title: String,
	icon_path: String,
	button_size: float,
	outlined_icon: bool = false
) -> VBoxContainer:
	var icon_size := int(round((button_size - 20.0) * BUTTON_ICON_SCALE))
	var hit_size := maxf(button_size, float(icon_size))
	var item := VBoxContainer.new()
	item.custom_minimum_size = Vector2(maxf(92.0, hit_size), hit_size + 40.0)
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", 2)
	var button := Button.new()
	button.custom_minimum_size = Vector2(hit_size, hit_size)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon_texture := _normalized_icon(icon_path)
	if outlined_icon:
		_add_outlined_button_icon(button, icon_texture)
	else:
		button.icon = icon_texture
		button.add_theme_constant_override("icon_max_width", icon_size)
		button.expand_icon = true
	button.toggle_mode = true
	button.set_meta("page_id", page_id)
	button.set_meta("scene_nav", true)
	button.tooltip_text = String(PAGE_INFO.get(page_id, {}).get("title", title))
	button.pressed.connect(_select_page.bind(page_id))
	button.add_theme_stylebox_override("normal", _round_nav_style(false, 0))
	button.add_theme_stylebox_override("hover", _round_nav_style(true, 0))
	button.add_theme_stylebox_override("pressed", _round_nav_style(true, 0))
	_nav_buttons[page_id] = button
	item.add_child(button)
	var label := _label(title, MIN_FONT_SIZE, Color("f8edc6"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.12, 0.08, 0.90))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	item.add_child(label)
	return item


func _add_outlined_button_icon(button: Button, texture: Texture2D) -> void:
	var layer := Control.new()
	layer.name = "IconOutlineLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.clip_contents = false
	button.add_child(layer)

	var outline_offsets := [
		Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5),
		Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4),
	]
	for offset in outline_offsets:
		var outline := _button_icon_rect(texture)
		outline.offset_left += offset.x
		outline.offset_right += offset.x
		outline.offset_top += offset.y
		outline.offset_bottom += offset.y
		outline.modulate = Color(0.018, 0.055, 0.043, 0.98)
		layer.add_child(outline)

	var face := _button_icon_rect(texture)
	face.name = "IconFace"
	layer.add_child(face)


func _button_icon_rect(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _build_sidebar() -> PanelContainer:
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(248, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_stylebox_override("panel", _panel_style(SURFACE, BORDER, 14))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	sidebar.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)

	var brand_panel := PanelContainer.new()
	brand_panel.custom_minimum_size = Vector2(0, 78)
	brand_panel.add_theme_stylebox_override("panel", _panel_style(Color("dce7dc"), Color("b8d0bd"), 10))
	var brand_margin := MarginContainer.new()
	brand_margin.add_theme_constant_override("margin_left", 8)
	brand_margin.add_theme_constant_override("margin_right", 8)
	brand_margin.add_theme_constant_override("margin_top", 7)
	brand_margin.add_theme_constant_override("margin_bottom", 7)
	brand_panel.add_child(brand_margin)
	var brand_logo := TextureRect.new()
	brand_logo.custom_minimum_size = Vector2(0, 62)
	brand_logo.texture = _asset("res://assets/art/static/brand/brand-lingnong-emblem.png")
	brand_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_margin.add_child(brand_logo)
	body.add_child(brand_panel)
	var version := _label("增量化 v1.2 · 夜行灵田", 12, MUTED)
	body.add_child(version)
	_add_separator(body)

	_nav_box = VBoxContainer.new()
	_nav_box.add_theme_constant_override("separation", 5)
	body.add_child(_nav_box)

	_add_nav_group("运行", [
		["overview", "总览", "收益与下一步"],
		["production", "生产", "作物与升级"],
		["route", "路线", "境界与突破"],
		["tribulation", "雷劫", "气血与结算"],
	])
	_add_nav_group("资源", [
		["materials", "宝箱与材料", "库存与信用"],
		["receipts", "日志", "完整修行记录"],
	])
	_add_nav_group("系统", [
		["automation", "自动化", "逐项开关"],
		["reset", "轮回 / 飞升", "阶段切换"],
	])

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)

	var target_card := PanelContainer.new()
	target_card.add_theme_stylebox_override("panel", _panel_style(SURFACE_DEEP, BORDER_SOFT, 10))
	body.add_child(target_card)
	var target_margin := MarginContainer.new()
	target_margin.add_theme_constant_override("margin_left", 12)
	target_margin.add_theme_constant_override("margin_right", 12)
	target_margin.add_theme_constant_override("margin_top", 11)
	target_margin.add_theme_constant_override("margin_bottom", 11)
	target_card.add_child(target_margin)
	var target_body := VBoxContainer.new()
	target_body.add_theme_constant_override("separation", 4)
	target_margin.add_child(target_body)
	target_body.add_child(_label("当前目标", 12, MUTED))
	_sidebar_target = _label("载入中", 15, TEXT)
	_sidebar_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_body.add_child(_sidebar_target)

	var quick_save := _page_button("保存当前进度", _save_now, GREEN, "res://assets/art/static/action_icon/action-icon-save.png")
	quick_save.custom_minimum_size.y = 38
	body.add_child(quick_save)
	var hint := _label("数据每 10 秒自动保存\n关键操作会立即写入存档", 11, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	return sidebar


func _add_nav_group(title: String, items: Array) -> void:
	var group_title := _label(title, 11, MUTED)
	group_title.uppercase = true
	_nav_box.add_child(group_title)
	for item in items:
		var page_id := String(item[0])
		var button := _page_button("%s   ·  %s" % [String(item[1]), String(item[2])], _select_page.bind(page_id), TEXT)
		button.icon = _normalized_icon(String(NAV_ART.get(page_id, "")))
		button.add_theme_constant_override("icon_max_width", int(22 * BUTTON_ICON_SCALE))
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 64)
		button.set_meta("page_id", page_id)
		_nav_buttons[page_id] = button
		_nav_box.add_child(button)


func _refresh() -> void:
	if not is_instance_valid(_page_box):
		return
	var summary := GameState.get_summary()
	var info: Dictionary = PAGE_INFO.get(_current_page, PAGE_INFO["overview"])
	_page_title.text = "灵溪小筑"
	_page_subtitle.text = "%s  ·  第 %d 世" % [GameState.get_realm_name(), int(summary["generation"])]
	if is_instance_valid(_drawer_title):
		_drawer_title.text = String(info["title"])
	if is_instance_valid(_drawer_subtitle):
		_drawer_subtitle.text = String(info["subtitle"])
	_header_summary.text = "修为 %s/s  ·  灵石 %s/s" % [
		NumberFmt.magnitude(summary["cultivation_per_second"]),
		NumberFmt.magnitude(summary["stone_per_second"]),
	]
	_set_hud("cultivation", NumberFmt.magnitude(summary["cultivation"]), "+%s / 秒" % NumberFmt.magnitude(summary["cultivation_per_second"]))
	_set_hud("stones", NumberFmt.magnitude(summary["spirit_stones"]), "+%s / 秒" % NumberFmt.magnitude(summary["stone_per_second"]))
	_set_hud("body", NumberFmt.magnitude(summary["body_power"]), "本世气血基础")
	_set_hud("spirit", NumberFmt.magnitude(summary["spirit_power"]), "本世神识功率")
	var status := String(summary["status"])
	_status_pill.text = "● %s" % _status_text(status)
	_status_pill.add_theme_color_override("font_color", GREEN if status == "RUNNING" else GOLD)
	if is_instance_valid(_sidebar_target):
		_sidebar_target.text = _target_name(summary["target"])
	_update_nav()
	if is_instance_valid(_page_drawer) and _page_drawer.visible and (_page_dirty or _page_refresh_accumulator >= 1.0 or _last_render_revision < 0):
		_page_refresh_accumulator = 0.0
		_render_page(summary)
	_page_dirty = false


func _set_hud(key: String, value: String, detail: String) -> void:
	var entry: Dictionary = _hud_values.get(key, {})
	var value_label := entry.get("value") as Label
	var detail_label := entry.get("detail") as Label
	if value_label != null:
		value_label.text = value
	if detail_label != null:
		detail_label.text = detail


func _update_nav() -> void:
	for page_id in _nav_buttons:
		var button: Button = _nav_buttons[page_id]
		if not is_instance_valid(button):
			continue
		var drawer_open := is_instance_valid(_page_drawer) and _page_drawer.visible
		var active := (String(page_id) == "overview" and not drawer_open) or (drawer_open and String(page_id) == _current_page)
		button.button_pressed = active
		if button.has_meta("scene_nav"):
			button.modulate = Color(1.0, 0.84, 0.48) if active else Color.WHITE
			button.add_theme_stylebox_override("normal", _round_nav_style(false))
			button.add_theme_stylebox_override("hover", _round_nav_style(true))
			button.add_theme_stylebox_override("pressed", _round_nav_style(true))
			continue
		button.add_theme_stylebox_override("normal", _button_style(SURFACE_RAISED if active else SURFACE, GOLD if active else BORDER_SOFT))
		button.add_theme_stylebox_override("hover", _button_style(SURFACE_RAISED, GOLD if active else BORDER))
		button.add_theme_stylebox_override("pressed", _button_style(SURFACE_RAISED, GOLD))
	for page_id in _drawer_nav_buttons:
		var drawer_button: Button = _drawer_nav_buttons[page_id]
		if not is_instance_valid(drawer_button):
			continue
		var drawer_active := is_instance_valid(_page_drawer) and _page_drawer.visible and String(page_id) == _current_page
		drawer_button.button_pressed = drawer_active
		drawer_button.modulate = Color(1.0, 0.86, 0.50) if drawer_active else Color.WHITE
		drawer_button.add_theme_stylebox_override("normal", _drawer_tab_style(drawer_active))


func _render_page(summary: Dictionary) -> void:
	var previous_scroll := 0
	if _preserve_page_scroll and is_instance_valid(_page_scroll):
		previous_scroll = _page_scroll.scroll_vertical
	_clear_container(_page_box)
	match _current_page:
		"overview":
			_render_overview(summary)
		"production":
			_render_production(summary)
		"route":
			_render_route(summary)
		"tribulation":
			_render_tribulation(summary)
		"materials":
			_render_materials(summary)
		"automation":
			_render_automation(summary)
		"reset":
			_render_reset(summary)
		"receipts":
			_render_receipts(summary)
		_:
			_render_overview(summary)
	_last_render_revision = int(summary["revision"])
	if is_instance_valid(_page_scroll):
		_page_scroll.scroll_vertical = previous_scroll if _preserve_page_scroll else 0
	_preserve_page_scroll = true


func _render_overview(summary: Dictionary) -> void:
	var target: Dictionary = summary["target"]
	var target_id := String(target.get("id", ""))
	var target_definition: Dictionary = BalanceConfig.node(target_id) if not target_id.is_empty() else {}
	var target_major := String(target_definition.get("major", "qi"))
	var target_name := String(target.get("name", "暂无目标")) if not target_id.is_empty() else "暂无新境界"

	var stage := PanelContainer.new()
	stage.custom_minimum_size = Vector2(0, 270)
	stage.add_theme_stylebox_override("panel", _panel_style(Color(0.027, 0.075, 0.064, 0.70), Color(0.47, 0.67, 0.50, 0.48), 18))
	var stage_margin := MarginContainer.new()
	stage_margin.add_theme_constant_override("margin_left", 14)
	stage_margin.add_theme_constant_override("margin_right", 14)
	stage_margin.add_theme_constant_override("margin_top", 12)
	stage_margin.add_theme_constant_override("margin_bottom", 12)
	stage.add_child(stage_margin)
	var stage_body := VBoxContainer.new()
	stage_body.add_theme_constant_override("separation", 8)
	stage_margin.add_child(stage_body)
	var stage_header := HBoxContainer.new()
	stage_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage_title := _label("灵田夜话", 18, TEXT)
	stage_title.custom_minimum_size.x = 92
	stage_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	stage_header.add_child(stage_title)
	var stage_hint := _label("修行正在自动增长 · 下一步：%s" % _next_action_text(summary), 12, MUTED)
	stage_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	stage_header.add_child(stage_hint)
	stage_body.add_child(stage_header)

	var world_row := HBoxContainer.new()
	world_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_row.add_theme_constant_override("separation", 10)
	stage_body.add_child(world_row)

	var field_panel := PanelContainer.new()
	field_panel.custom_minimum_size = Vector2(318, 0)
	field_panel.add_theme_stylebox_override("panel", _panel_style(SURFACE_DEEP, BORDER_SOFT, 14))
	var field_margin := MarginContainer.new()
	field_margin.add_theme_constant_override("margin_left", 10)
	field_margin.add_theme_constant_override("margin_right", 10)
	field_margin.add_theme_constant_override("margin_top", 8)
	field_margin.add_theme_constant_override("margin_bottom", 8)
	field_panel.add_child(field_margin)
	var field_body := VBoxContainer.new()
	field_body.add_theme_constant_override("separation", 5)
	field_margin.add_child(field_body)
	field_body.add_child(_label("灵田阵列", 14, TEXT))
	field_body.add_child(_label("灵田 %d 级 · 灵土 %d 阶 · 聚灵阵 %d 级" % [int(GameState.farm.field_level), int(GameState.farm.soil_tier), int(GameState.farm.array_level)], 11, MUTED))
	var crop_grid := GridContainer.new()
	crop_grid.columns = 3
	crop_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	crop_grid.add_theme_constant_override("h_separation", 6)
	crop_grid.add_theme_constant_override("v_separation", 5)
	field_body.add_child(crop_grid)
	var available := GameState.get_available_crops()
	for index in range(mini(available.size(), 6)):
		crop_grid.add_child(_crop_plot(available[index]))
	if available.is_empty():
		field_body.add_child(_label("灵田还未苏醒。", 12, MUTED))
	world_row.add_child(field_panel)

	var shrine := PanelContainer.new()
	shrine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shrine.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.12, 0.095, 0.45), Color(0.65, 0.54, 0.28, 0.46), 14))
	var shrine_margin := MarginContainer.new()
	shrine_margin.add_theme_constant_override("margin_left", 12)
	shrine_margin.add_theme_constant_override("margin_right", 12)
	shrine_margin.add_theme_constant_override("margin_top", 8)
	shrine_margin.add_theme_constant_override("margin_bottom", 8)
	shrine.add_child(shrine_margin)
	var shrine_body := VBoxContainer.new()
	shrine_body.alignment = BoxContainer.ALIGNMENT_CENTER
	shrine_body.add_theme_constant_override("separation", 3)
	shrine_margin.add_child(shrine_body)
	var realm_icon := TextureRect.new()
	realm_icon.custom_minimum_size = Vector2(122, 122)
	realm_icon.texture = _asset(String(REALM_ART.get(target_major, REALM_ART["qi"])))
	realm_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	realm_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	realm_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shrine_body.add_child(realm_icon)
	shrine_body.add_child(_label(GameState.get_realm_name(), 17, GOLD))
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 8)
	progress.show_percentage = false
	progress.max_value = 1.0
	var progress_value := 0.18
	if not target_id.is_empty() and target.has("requirement"):
		progress_value = clampf(float(summary["cultivation"].log10()) / maxf(1.0, float(target["requirement"].log10())), 0.0, 1.0)
	progress.value = progress_value
	progress.add_theme_stylebox_override("background", _button_style(Color(0.02, 0.05, 0.04, 0.8), BORDER_SOFT))
	progress.add_theme_stylebox_override("fill", _button_style(Color(0.66, 0.48, 0.18, 0.9), GOLD))
	shrine_body.add_child(progress)
	shrine_body.add_child(_label("本世修为 %s" % NumberFmt.magnitude(summary["cultivation"]), 11, MUTED))
	world_row.add_child(shrine)

	var quest := PanelContainer.new()
	quest.custom_minimum_size = Vector2(272, 0)
	quest.add_theme_stylebox_override("panel", _panel_style(SURFACE_DEEP, BORDER_SOFT, 14))
	var quest_margin := MarginContainer.new()
	quest_margin.add_theme_constant_override("margin_left", 11)
	quest_margin.add_theme_constant_override("margin_right", 11)
	quest_margin.add_theme_constant_override("margin_top", 8)
	quest_margin.add_theme_constant_override("margin_bottom", 8)
	quest.add_child(quest_margin)
	var quest_body := VBoxContainer.new()
	quest_body.add_theme_constant_override("separation", 5)
	quest_margin.add_child(quest_body)
	quest_body.add_child(_label("修行手札", 14, TEXT))
	quest_body.add_child(_label(target_name, 19, GOLD))
	quest_body.add_child(_label("修为 ETA %s\n材料 ETA %s\n突破成功率 %.1f%%" % [
		NumberFmt.seconds(float(summary["target_eta_seconds"])),
		NumberFmt.seconds(float(summary["material_eta_seconds"])),
		float(target.get("probability", 0.0)) * 100.0,
	], 12, MUTED))
	var quest_actions := _button_row()
	quest_body.add_child(quest_actions)
	quest_actions.add_child(_page_button("境界", _select_page.bind("route"), BLUE))
	var breakthrough_button := _page_button("突破", _do_breakthrough, GREEN)
	breakthrough_button.disabled = target_id.is_empty()
	quest_actions.add_child(breakthrough_button)
	if not GameState.run.pending_tribulation.is_empty():
		quest_actions.add_child(_page_button("渡劫", _do_tribulation, GOLD))
	world_row.add_child(quest)

	_page_box.add_child(stage)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 10)
	_page_box.add_child(quick_row)
	quick_row.add_child(_game_quick_card("灵田", "res://assets/art/static/farm_icon/farm-icon-field.png", "%s\n效率 %.1f%%" % [_plan_text(summary["plan"]), float(summary["efficiency"]) * 100.0], "去灵田", _select_page.bind("production"), BLUE))
	quick_row.add_child(_game_quick_card("宝物", "res://assets/art/static/chest/chest-common.png", "普通箱 %s\n道蕴 %s" % [NumberFmt.counter(GameState.lineage.treasure.chests.get("common", BigCounter.zero())), NumberFmt.magnitude(GameState.lineage.total_dao)], "看宝物", _select_page.bind("materials"), PURPLE))
	var reset_preview: Dictionary = summary["reset"]
	quick_row.add_child(_game_quick_card("轮回", "res://assets/art/static/navigation_icon/navigation-icon-reincarnation.png", "预计道蕴 +%s\n第 %d 世" % [NumberFmt.magnitude(reset_preview.get("dao_gain", BigCounter.zero())), int(summary["generation"])], "看轮回", _select_page.bind("reset"), RED))


func _crop_plot(crop: Dictionary) -> PanelContainer:
	var plot := PanelContainer.new()
	plot.custom_minimum_size = Vector2(92, 92)
	plot.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.16, 0.11, 0.50), BORDER_SOFT, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	plot.add_child(margin)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 0)
	margin.add_child(body)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(54, 54)
	icon.texture = _asset(String(CROP_ART.get(String(crop.get("id", "")), "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon)
	var name_label := _label(String(crop.get("name", "灵植")), 10, TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.add_child(name_label)
	return plot


func _game_quick_card(title: String, icon_path: String, detail: String, action_text: String, action: Callable, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 112)
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.10, 0.075, 0.70), BORDER_SOFT, 14))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	margin.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	body.add_child(header)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.texture = _normalized_icon(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)
	header.add_child(_label(title, 15, accent))
	var detail_label := _label(detail, 11, MUTED)
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail_label)
	body.add_child(_page_button(action_text, action, accent))
	return card


func _begin_world_scene(accent: Color, bottom_height: float = 126.0) -> Dictionary:
	var root := Control.new()
	root.name = "WorldSceneRoot"
	root.custom_minimum_size = Vector2(0, 720)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_box.add_child(root)

	var backdrop := TextureRect.new()
	backdrop.name = "WorldBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = _asset("res://assets/art/static/environment/environment-cultivation-valley-base.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	backdrop.modulate = Color(0.55, 0.68, 0.58, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	var veil := ColorRect.new()
	veil.name = "WorldVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.003, 0.022, 0.017, 0.34)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)

	var world := Control.new()
	world.name = "WorldObjects"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(world)

	var bottom_panel: PanelContainer = null
	var bottom_row: HBoxContainer = null
	if bottom_height > 0.0:
		bottom_panel = PanelContainer.new()
		bottom_panel.name = "WorldActionDock"
		bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bottom_panel.offset_left = 52
		bottom_panel.offset_right = -52
		bottom_panel.offset_top = -bottom_height
		bottom_panel.offset_bottom = -18
		bottom_panel.add_theme_stylebox_override("panel", _world_bottom_style(accent))
		root.add_child(bottom_panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_right", 18)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		bottom_panel.add_child(margin)
		bottom_row = HBoxContainer.new()
		bottom_row.name = "WorldActionRow"
		bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
		bottom_row.add_theme_constant_override("separation", 10)
		margin.add_child(bottom_row)

	return {
		"root": root,
		"world": world,
		"bottom_panel": bottom_panel,
		"bottom_row": bottom_row,
	}


func _anchor_world_control(control: Control, anchor: Vector2, object_size: Vector2) -> void:
	control.set_anchor(SIDE_LEFT, anchor.x)
	control.set_anchor(SIDE_RIGHT, anchor.x)
	control.set_anchor(SIDE_TOP, anchor.y)
	control.set_anchor(SIDE_BOTTOM, anchor.y)
	control.offset_left = -object_size.x * 0.5
	control.offset_right = object_size.x * 0.5
	control.offset_top = -object_size.y * 0.5
	control.offset_bottom = object_size.y * 0.5


func _world_caption(
	world: Control,
	text: String,
	anchor: Vector2,
	font_size: int,
	color: Color,
	width: float = 620.0,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
) -> Label:
	var label := _scene_label(text, font_size, color)
	label.name = "WorldCaption"
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_world_control(label, anchor, Vector2(width, 52))
	world.add_child(label)
	return label


func _add_world_object(
	world: Control,
	node_name: String,
	title: String,
	icon_path: String,
	anchor: Vector2,
	action: Callable,
	active: bool,
	enabled: bool,
	detail: String = "",
	accent: Color = GOLD,
	icon_size: float = 116.0
) -> Button:
	var slot := VBoxContainer.new()
	slot.name = node_name
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_theme_constant_override("separation", 2)
	_anchor_world_control(slot, anchor, Vector2(maxf(150.0, icon_size + 28.0), icon_size + 76.0))
	world.add_child(slot)

	var button := Button.new()
	button.name = "ObjectButton"
	button.custom_minimum_size = Vector2(icon_size, icon_size)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.icon = _normalized_icon(icon_path)
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	button.add_theme_constant_override("icon_max_width", int(icon_size * 0.78))
	button.add_theme_stylebox_override("normal", _world_object_style(active, accent))
	button.add_theme_stylebox_override("hover", _world_object_style(true, accent))
	button.add_theme_stylebox_override("pressed", _world_object_style(true, accent))
	button.add_theme_stylebox_override("disabled", _world_object_style(false, MUTED))
	button.disabled = not enabled
	button.tooltip_text = title if detail.is_empty() else "%s\n%s" % [title, detail]
	button.pressed.connect(action)
	slot.add_child(button)

	var title_label := _scene_label(title, MIN_FONT_SIZE, Color("fff1b5") if active else TEXT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.clip_text = true
	slot.add_child(title_label)
	if not detail.is_empty():
		var detail_label := _scene_label(detail, MIN_FONT_SIZE, GREEN if active else MUTED)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail_label.clip_text = true
		slot.add_child(detail_label)

	if active:
		var pulse := button.create_tween().set_loops()
		pulse.tween_property(button, "modulate", Color(1.12, 1.12, 1.12, 1.0), 0.65).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(button, "modulate", Color.WHITE, 0.65).set_trans(Tween.TRANS_SINE)
	return button


func _add_world_animation(
	world: Control,
	node_name: String,
	animation_id: String,
	anchor: Vector2,
	object_size: Vector2,
	title: String = "",
	detail: String = "",
	action: Callable = Callable()
) -> AnimatedSprite2D:
	var holder := Control.new()
	holder.name = node_name
	_anchor_world_control(holder, anchor, object_size)
	holder.pivot_offset = object_size * 0.5
	world.add_child(holder)

	var sprite := Art.create_animated_sprite(animation_id)
	sprite.name = "AnimatedWorldAsset"
	sprite.position = Vector2(object_size.x * 0.5, object_size.y * 0.5)
	sprite.speed_scale = 0.84
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_fit_world_sprite(sprite, object_size * 0.82)
	if sprite.sprite_frames != null:
		var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
		if frame_count > 0:
			sprite.frame = int(Time.get_ticks_msec() / 135) % frame_count
	var animation_entry := Art.animation_entry(animation_id)
	if String(animation_entry.get("blend_mode", "mix")) == "mix" and sprite.sprite_frames != null:
		var shadow := AnimatedSprite2D.new()
		shadow.name = "FidelityShadow"
		shadow.sprite_frames = sprite.sprite_frames
		shadow.animation = sprite.animation
		shadow.frame = sprite.frame
		shadow.speed_scale = sprite.speed_scale
		shadow.position = sprite.position + Vector2(0, 12)
		shadow.scale = sprite.scale * 1.035
		shadow.modulate = Color(0.01, 0.025, 0.018, 0.42)
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		shadow.play()
		holder.add_child(shadow)
		sprite.material = _high_fidelity_outline_material(animation_id)
	holder.add_child(sprite)

	if action.is_valid():
		var hit := Button.new()
		hit.name = "ObjectButton"
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.flat = true
		hit.tooltip_text = title if detail.is_empty() else "%s\n%s" % [title, detail]
		hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("hover", _world_object_style(true, GOLD))
		hit.add_theme_stylebox_override("pressed", _world_object_style(true, GOLD))
		hit.pressed.connect(action)
		holder.add_child(hit)

	if not title.is_empty():
		var label := _scene_label(title, 27, Color("fff1b5"))
		label.position = Vector2(-40, object_size.y - 8)
		label.size = Vector2(object_size.x + 80, 38)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		holder.add_child(label)
	if not detail.is_empty():
		var detail_label := _scene_label(detail, MIN_FONT_SIZE, MUTED)
		detail_label.position = Vector2(-40, object_size.y + 28)
		detail_label.size = Vector2(object_size.x + 80, 34)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		holder.add_child(detail_label)
	return sprite


func _add_locked_crop(
	world: Control,
	node_name: String,
	title: String,
	icon_path: String,
	anchor: Vector2,
	requirement: String,
	action: Callable
) -> Button:
	var holder := Control.new()
	holder.name = node_name
	_anchor_world_control(holder, anchor, Vector2(220, 206))
	holder.pivot_offset = Vector2(110, 103)
	holder.set_meta("locked_crop", node_name.trim_prefix("UnlockCrop_"))
	world.add_child(holder)

	var crop_shadow := TextureRect.new()
	crop_shadow.name = "CropShadow"
	crop_shadow.position = Vector2(55, 8)
	crop_shadow.size = Vector2(110, 110)
	crop_shadow.texture = _normalized_icon(icon_path)
	crop_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crop_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crop_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	crop_shadow.modulate = Color(0.0, 0.015, 0.008, 0.48)
	crop_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(crop_shadow)

	var crop_icon := TextureRect.new()
	crop_icon.name = "LockedCropArt"
	crop_icon.position = Vector2(55, 0)
	crop_icon.size = Vector2(110, 110)
	crop_icon.texture = _normalized_icon(icon_path)
	crop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crop_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	crop_icon.modulate = Color(0.62, 0.70, 0.65, 0.66)
	crop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(crop_icon)

	var lock_badge := TextureRect.new()
	lock_badge.name = "LockBadge"
	lock_badge.position = Vector2(137, 63)
	lock_badge.size = Vector2(52, 52)
	lock_badge.texture = _normalized_icon("res://assets/art/static/action_icon/action-icon-locked.png")
	lock_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	lock_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lock_badge)

	var crop_label := _scene_label(title, MIN_FONT_SIZE, Color("e8e3c9"))
	crop_label.position = Vector2(0, 104)
	crop_label.size = Vector2(220, 34)
	crop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crop_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	crop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(crop_label)

	var requirement_label := _scene_label("需 · %s" % requirement, MIN_FONT_SIZE, MUTED)
	requirement_label.position = Vector2(-18, 132)
	requirement_label.size = Vector2(256, 32)
	requirement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	requirement_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	requirement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(requirement_label)

	var unlock := Button.new()
	unlock.name = "ObjectButton"
	unlock.text = "解锁"
	unlock.position = Vector2(44, 164)
	unlock.size = Vector2(132, 42)
	unlock.icon = _normalized_icon("res://assets/art/static/action_icon/action-icon-locked.png")
	unlock.expand_icon = true
	unlock.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	unlock.add_theme_constant_override("icon_max_width", 30)
	unlock.add_theme_font_size_override("font_size", MIN_FONT_SIZE)
	unlock.add_theme_color_override("font_color", Color("fff3bd"))
	unlock.add_theme_color_override("font_hover_color", Color.WHITE)
	unlock.add_theme_stylebox_override("normal", _world_unlock_button_style(false))
	unlock.add_theme_stylebox_override("hover", _world_unlock_button_style(true))
	unlock.add_theme_stylebox_override("pressed", _world_unlock_button_style(true))
	unlock.tooltip_text = "%s\n完成 %s 后解锁" % [title, requirement]
	unlock.pressed.connect(action)
	unlock.set_meta("locked_crop", holder.get_meta("locked_crop"))
	holder.add_child(unlock)
	return unlock


func _fit_world_sprite(sprite: AnimatedSprite2D, max_size: Vector2) -> void:
	if sprite.sprite_frames == null:
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var scale_factor := minf(max_size.x / source_size.x, max_size.y / source_size.y)
	sprite.scale = Vector2.ONE * scale_factor


func _high_fidelity_outline_material(animation_id: String) -> ShaderMaterial:
	var matte_mode := 1 if MAGENTA_MATTE_ANIMATIONS.has(animation_id) else (2 if RED_MATTE_ANIMATIONS.has(animation_id) else 0)
	if _world_outline_materials.has(matte_mode):
		var cached := _world_outline_materials[matte_mode] as ShaderMaterial
		if is_instance_valid(cached):
			return cached
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.68, 0.88, 0.58, 0.52);
uniform float outline_width : hint_range(0.5, 3.0) = 1.25;
uniform int matte_mode = 0;

float keyed_alpha(vec4 pixel) {
	float alpha = pixel.a;
	if (matte_mode == 1) {
		float magenta_dominance = min(pixel.r, pixel.b) - pixel.g;
		float magenta_balance = 1.0 - abs(pixel.r - pixel.b);
		float key = smoothstep(0.10, 0.28, magenta_dominance)
			* smoothstep(0.22, 0.50, min(pixel.r, pixel.b))
			* smoothstep(0.50, 0.85, magenta_balance);
		alpha *= 1.0 - key;
	} else if (matte_mode == 2) {
		float red_dominance = pixel.r - max(pixel.g, pixel.b);
		float key = smoothstep(0.48, 0.72, red_dominance)
			* smoothstep(0.74, 0.96, pixel.r);
		alpha *= 1.0 - key;
	}
	return alpha;
}

void fragment() {
	vec4 tint = COLOR;
	vec4 base = texture(TEXTURE, UV);
	base.a = keyed_alpha(base);
	vec2 step_size = TEXTURE_PIXEL_SIZE * outline_width;
	float nearby = 0.0;
	nearby = max(nearby, keyed_alpha(texture(TEXTURE, UV + vec2(step_size.x, 0.0))));
	nearby = max(nearby, keyed_alpha(texture(TEXTURE, UV - vec2(step_size.x, 0.0))));
	nearby = max(nearby, keyed_alpha(texture(TEXTURE, UV + vec2(0.0, step_size.y))));
	nearby = max(nearby, keyed_alpha(texture(TEXTURE, UV - vec2(0.0, step_size.y))));
	nearby = max(nearby, keyed_alpha(texture(TEXTURE, UV + step_size)));
	nearby = max(nearby, keyed_alpha(texture(TEXTURE, UV - step_size)));
	float edge = max(nearby - base.a, 0.0);
	float clean_weight = smoothstep(0.16, 0.46, base.a);
	vec3 clean_rgb = mix(outline_color.rgb, base.rgb, clean_weight);
	vec4 outlined = vec4(outline_color.rgb, edge * outline_color.a);
	vec4 combined = vec4(clean_rgb, max(base.a, outlined.a));
	COLOR = combined * tint;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("matte_mode", matte_mode)
	_world_outline_materials[matte_mode] = material
	return material


func _play_crop_switch_transition(sprite: AnimatedSprite2D, mode: String) -> void:
	if not is_instance_valid(sprite) or not is_instance_valid(sprite.get_parent()):
		return
	var holder := sprite.get_parent() as Control
	holder.set_meta("crop_transition", mode)
	if mode == "grow":
		holder.scale = Vector2(0.28, 0.28)
		holder.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var grow := holder.create_tween()
		grow.set_parallel(true)
		grow.tween_property(holder, "scale", Vector2(1.10, 1.10), 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		grow.tween_property(holder, "modulate", Color.WHITE, 0.28).set_trans(Tween.TRANS_SINE)
		grow.chain().tween_property(holder, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
	elif mode == "retire":
		var retire := holder.create_tween()
		retire.tween_property(holder, "modulate", Color(0.58, 0.67, 0.61, 0.34), 0.22).set_trans(Tween.TRANS_SINE)
		retire.parallel().tween_property(holder, "scale", Vector2(0.78, 0.78), 0.22).set_trans(Tween.TRANS_SINE)
		retire.tween_property(holder, "modulate", Color(0.64, 0.72, 0.67, 0.62), 0.30).set_trans(Tween.TRANS_SINE)
		retire.parallel().tween_property(holder, "scale", Vector2(0.90, 0.90), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _add_world_path(world: Control, anchors: Array, accent: Color) -> void:
	var path := Line2D.new()
	path.name = "RealmPath"
	path.width = 7.0
	path.default_color = Color(accent.r, accent.g, accent.b, 0.62)
	path.joint_mode = Line2D.LINE_JOINT_ROUND
	path.begin_cap_mode = Line2D.LINE_CAP_ROUND
	path.end_cap_mode = Line2D.LINE_CAP_ROUND
	path.z_index = 0
	world.add_child(path)
	var refresh_points := func() -> void:
		var points := PackedVector2Array()
		for item in anchors:
			var anchor: Vector2 = item
			points.append(Vector2(world.size.x * anchor.x, world.size.y * anchor.y))
		path.points = points
	world.resized.connect(refresh_points)
	refresh_points.call()


func _world_toolbar_button(
	text: String,
	icon_path: String,
	action: Callable,
	accent: Color,
	disabled: bool = false,
	minimum_width: float = 160.0
) -> Button:
	var button := _page_button(text, action, accent, icon_path)
	button.custom_minimum_size = Vector2(minimum_width, 76)
	button.disabled = disabled
	return button


func _toolbar_icon_slot(
	parent: HBoxContainer,
	title: String,
	icon_path: String,
	count: String,
	accent: Color = GOLD
) -> void:
	var slot := VBoxContainer.new()
	slot.custom_minimum_size = Vector2(94, 0)
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(slot)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(62, 62)
	icon.texture = _normalized_icon(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	icon.tooltip_text = title
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.add_child(icon)
	var count_label := _scene_label(count, MIN_FONT_SIZE, accent)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	slot.add_child(count_label)


func _render_production(summary: Dictionary) -> void:
	_add_page_heading("灵田", "")
	var view := _begin_world_scene(GREEN, 124)
	var world := view["world"] as Control
	var bottom := view["bottom_row"] as HBoxContainer
	var available := GameState.get_available_crops()
	var plan: Dictionary = summary["plan"]
	var dominant := _dominant_crop(plan, available)
	var positions := [
		Vector2(0.38, 0.41), Vector2(0.64, 0.41), Vector2(0.31, 0.62), Vector2(0.50, 0.62),
		Vector2(0.69, 0.62), Vector2(0.18, 0.58), Vector2(0.82, 0.58),
	]
	var available_by_id := {}
	for crop in available:
		available_by_id[String(crop.get("id", ""))] = crop
	var transition_pending := _crop_transition_pending
	var crop_ids := BalanceConfig.CROPS.keys()
	for index in range(crop_ids.size()):
		var crop_id := String(crop_ids[index])
		var definition: Dictionary = BalanceConfig.CROPS[crop_id]
		if available_by_id.has(crop_id):
			var crop: Dictionary = available_by_id[crop_id]
			var ratio := float(plan.get(crop_id, 0.0))
			var sprite := _add_world_animation(
				world,
				"Crop_%s" % crop_id,
				String(CROP_ANIMATIONS.get(crop_id, "animation.gathering_grass_sway")),
				positions[index],
				Vector2(180, 180),
				String(crop.get("name", "灵植")),
				"主植" if crop_id == dominant else "%.0f%%" % (ratio * 100.0),
				_select_single_crop.bind(crop_id)
			)
			var crop_holder := sprite.get_parent() as Control
			if crop_id != dominant:
				crop_holder.modulate = Color(0.64, 0.72, 0.67, 0.62)
				crop_holder.scale = Vector2(0.90, 0.90)
			if transition_pending and crop_id == _crop_transition_to:
				_play_crop_switch_transition(sprite, "grow")
			elif transition_pending and crop_id == _crop_transition_from:
				_play_crop_switch_transition(sprite, "retire")
		else:
			var requirement := _crop_unlock_requirement(definition)
			var unlock_button := _add_locked_crop(
				world,
				"UnlockCrop_%s" % crop_id,
				String(definition.get("name", crop_id)),
				String(CROP_ART.get(crop_id, "res://assets/art/static/action_icon/action-icon-locked.png")),
				positions[index],
				requirement,
				_request_crop_unlock.bind(crop_id)
			)
			unlock_button.set_meta("locked_crop", crop_id)
			unlock_button.get_parent().set_meta("locked_crop", crop_id)
	if transition_pending:
		_crop_transition_pending = false
	_world_caption(
		world,
		"灵田 %d级  ·  灵土 %d阶  ·  聚灵阵 %d级" % [int(GameState.farm.field_level), int(GameState.farm.soil_tier), int(GameState.farm.array_level)],
		Vector2(0.50, 0.08),
		28,
		Color("fff1b5")
	)
	bottom.add_child(_world_toolbar_button("修为阵势", "res://assets/art/static/resource_icon/resource-icon-cultivation.png", _set_preset.bind("cultivation", "修为"), GOLD))
	bottom.add_child(_world_toolbar_button("灵石阵势", "res://assets/art/static/resource_icon/resource-icon-spirit-stone.png", _set_preset.bind("stones", "灵石"), GREEN))
	bottom.add_child(_world_toolbar_button("均衡阵势", "res://assets/art/static/farm_icon/farm-icon-gathering-array.png", _set_preset.bind("balanced", "均衡"), BLUE))
	bottom.add_child(_world_toolbar_button("稀有宝箱", "res://assets/art/static/chest/chest-rare.png", _set_preset.bind("rare", "稀有箱"), PURPLE))
	bottom.add_child(_world_toolbar_button("蕴养灵田", "res://assets/art/static/farm_icon/farm-icon-field.png", _buy_upgrade.bind("field_level", "灵田"), GREEN))
	bottom.add_child(_world_toolbar_button("蕴养灵土", "res://assets/art/static/farm_icon/farm-icon-soil.png", _buy_upgrade.bind("soil_tier", "灵土"), GREEN))
	bottom.add_child(_world_toolbar_button("蕴养聚灵阵", "res://assets/art/static/farm_icon/farm-icon-gathering-array.png", _buy_upgrade.bind("array_level", "聚灵阵"), GREEN))


func _dominant_crop(plan: Dictionary, available: Array) -> String:
	var best_id := ""
	var best_ratio := -1.0
	for crop in available:
		var crop_id := String(crop.get("id", ""))
		var ratio := float(plan.get(crop_id, 0.0))
		if ratio > best_ratio:
			best_ratio = ratio
			best_id = crop_id
	return best_id


func _crop_unlock_requirement(definition: Dictionary) -> String:
	var node_id := String(definition.get("unlock_node", ""))
	if node_id.is_empty():
		return "初始灵田"
	return String(BalanceConfig.node(node_id).get("name", node_id))


func _request_crop_unlock(crop_id: String) -> void:
	var definition := BalanceConfig.crop(crop_id)
	if definition.is_empty():
		return
	var unlock_node := String(definition.get("unlock_node", ""))
	var crop_name := String(definition.get("name", crop_id))
	if unlock_node.is_empty() or GameState.lineage.historical_realm_unlocks.has(unlock_node):
		_select_single_crop(crop_id)
		return
	var realm_name := String(BalanceConfig.node(unlock_node).get("name", unlock_node))
	if GameState.run.completed_nodes.has(unlock_node):
		_notify("%s 已在本世证得；完成轮回后解锁 %s。" % [realm_name, crop_name])
		_select_page("reset")
		return
	var result := GameState.choose_target(unlock_node)
	if bool(result.get("ok", false)):
		_notify("已把 %s 设为当前道途；证得并轮回后解锁 %s。" % [realm_name, crop_name])
	else:
		_notify("先沿境界路线前往 %s，证得并轮回后解锁 %s。" % [realm_name, crop_name])
	_select_page("route")


func _render_route(summary: Dictionary) -> void:
	_add_page_heading("境界", "")
	var view := _begin_world_scene(GOLD, 124)
	var world := view["world"] as Control
	var bottom := view["bottom_row"] as HBoxContainer
	var node_rows := GameState.get_node_rows()
	var positions := [
		Vector2(0.07, 0.57), Vector2(0.15, 0.33), Vector2(0.24, 0.57), Vector2(0.33, 0.32),
		Vector2(0.42, 0.57), Vector2(0.51, 0.32), Vector2(0.60, 0.57), Vector2(0.69, 0.32),
		Vector2(0.78, 0.57), Vector2(0.87, 0.32), Vector2(0.94, 0.57),
	]
	_add_world_path(world, positions.slice(0, node_rows.size()), GOLD)
	for index in range(node_rows.size()):
		var row: Dictionary = node_rows[index]
		var node_id := String(row.get("id", ""))
		var active := node_id == GameState.run.active_target_id
		var legal := bool(row.get("legal", false))
		var completed := bool(row.get("completed", false)) or bool(row.get("inherited", false))
		var state := "心愿" if active else ("已证" if completed else ("可选" if legal else "未悟"))
		var detail := "%s · %.0f%%" % [state, float(row.get("probability", 0.0)) * 100.0]
		_add_world_object(
			world,
			"RealmNode_%s" % node_id,
			String(row.get("name", node_id)),
			String(REALM_ART.get(String(row.get("major", "qi")), REALM_ART["qi"])),
			positions[index],
			_choose_target.bind(node_id),
			active,
			legal and not active,
			detail,
			GOLD,
			108.0
		)

	var target: Dictionary = summary["target"]
	var target_id := String(target.get("id", ""))
	var target_name := String(target.get("name", "道途已尽")) if not target_id.is_empty() else "道途已尽"
	var target_state := "%.1f%%" % (float(target.get("probability", 0.0)) * 100.0) if not target_id.is_empty() else ""
	var target_label := _scene_label("当前心愿 · %s  %s" % [target_name, target_state], 28, Color("fff1b5"))
	target_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	bottom.add_child(target_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	bottom.add_child(_world_toolbar_button("叩问一次", "res://assets/art/static/action_icon/action-icon-breakthrough.png", _do_breakthrough_once, GREEN, target_id.is_empty(), 210))
	bottom.add_child(_world_toolbar_button("连续叩关", "res://assets/art/static/action_icon/action-icon-breakthrough.png", _do_breakthrough, GOLD, target_id.is_empty(), 210))
	bottom.add_child(_world_toolbar_button("迎击雷劫", String(NAV_ART["tribulation"]), _do_tribulation, BLUE, GameState.run.pending_tribulation.is_empty(), 210))


func _render_tribulation(summary: Dictionary) -> void:
	_add_page_heading("雷劫", "")
	var view := _begin_world_scene(BLUE, 124)
	var world := view["world"] as Control
	var bottom := view["bottom_row"] as HBoxContainer
	var pending: Dictionary = GameState.run.pending_tribulation
	_add_world_animation(
		world,
		"TribulationCloud",
		"animation.tribulation",
		Vector2(0.50, 0.40),
		Vector2(570, 500)
	)
	if pending.is_empty():
		_world_caption(world, "劫云未聚", Vector2(0.50, 0.72), 34, MUTED)
		bottom.add_child(_world_toolbar_button("前往境界", String(NAV_ART["route"]), _select_page.bind("route"), GOLD, false, 250))
		bottom.add_child(_world_toolbar_button("调整阵法", String(NAV_ART["automation"]), _select_page.bind("automation"), GREEN, false, 250))
		return
	var damage := BigCounter.from_string(String(pending.get("total_damage", "0")))
	_world_caption(
		world,
		"雷击 %d 道  ·  气血 %s  ·  劫伤 %s" % [
			int(pending.get("strike_count", pending.get("strikes", 0))),
			NumberFmt.counter(GameState.run.current_hp),
			NumberFmt.counter(damage),
		],
		Vector2(0.50, 0.72),
		30,
		Color("fff1b5"),
		1100
	)
	bottom.add_child(_world_toolbar_button("迎击雷劫", String(NAV_ART["tribulation"]), _do_tribulation, GOLD, false, 330))
	bottom.add_child(_world_toolbar_button("调整阵法", String(NAV_ART["automation"]), _select_page.bind("automation"), GREEN, false, 230))
	bottom.add_child(_world_toolbar_button("返回境界", String(NAV_ART["route"]), _select_page.bind("route"), BLUE, false, 230))


func _material_art_path(material_id: String) -> String:
	var path := "res://assets/art/static/material/material-%s.png" % material_id.replace("_", "-")
	return path if ResourceLoader.exists(path) else "res://assets/art/static/action_icon/action-icon-locked.png"


func _render_materials(summary: Dictionary) -> void:
	_add_page_heading("宝物", "")
	var view := _begin_world_scene(PURPLE, 164)
	var world := view["world"] as Control
	var bottom := view["bottom_row"] as HBoxContainer
	var treasure := GameState.get_treasure_summary()
	var chests: Dictionary = treasure["chests"]
	var chest_data := [
		["common", "animation.chest_common_open", Vector2(0.25, 0.40), "普通宝箱", GREEN],
		["elite", "animation.chest_elite_open", Vector2(0.50, 0.36), "精良宝箱", BLUE],
		["rare", "animation.chest_rare_open", Vector2(0.75, 0.40), "稀有宝箱", PURPLE],
	]
	for item in chest_data:
		var tier := String(item[0])
		_add_world_animation(
			world,
			"Chest_%s" % tier,
			String(item[1]),
			item[2],
			Vector2(300, 270),
			String(item[3]),
			NumberFmt.counter(chests.get(tier, BigCounter.zero()))
		)
	_world_caption(world, "天道印记 · %s" % NumberFmt.counter(treasure["dao_mark_count"]), Vector2(0.50, 0.68), 30, GOLD)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inventory_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(inventory_scroll)
	var inventory_row := HBoxContainer.new()
	inventory_row.add_theme_constant_override("separation", 10)
	inventory_scroll.add_child(inventory_row)
	for material_id in BalanceConfig.MATERIALS:
		var definition: Dictionary = BalanceConfig.MATERIALS[material_id]
		if bool(definition.get("dormant", false)):
			continue
		var id := String(material_id)
		_toolbar_icon_slot(
			inventory_row,
			String(definition.get("name", id)),
			_material_art_path(id),
			NumberFmt.counter(GameState.lineage.materials.amount(id)),
			PURPLE if String(definition.get("tier", "common")) == "rare" else TEXT
		)


func _render_automation(summary: Dictionary) -> void:
	_add_page_heading("阵法", "")
	var view := _begin_world_scene(GREEN, 124)
	var world := view["world"] as Control
	var bottom := view["bottom_row"] as HBoxContainer
	var automation := GameState.get_automation_summary()
	var enabled: Array = automation["enabled"]
	var unlocked: Array = automation["unlocked"]
	_add_world_animation(
		world,
		"GatheringArray",
		"animation.gathering_array_cycle",
		Vector2(0.50, 0.55),
		Vector2(350, 330)
	)
	var rune_positions := [
		Vector2(0.50, 0.16), Vector2(0.70, 0.27), Vector2(0.79, 0.52),
		Vector2(0.66, 0.70), Vector2(0.34, 0.70), Vector2(0.21, 0.52), Vector2(0.30, 0.27),
	]
	for index in range(BLUEPRINT_ORDER.size()):
		var blueprint_id := String(BLUEPRINT_ORDER[index])
		var is_unlocked := unlocked.has(blueprint_id)
		var is_enabled := enabled.has(blueprint_id)
		_add_world_object(
			world,
			"Rune_%s" % blueprint_id,
			String(BLUEPRINT_NAMES.get(blueprint_id, blueprint_id)),
			"res://assets/art/static/action_icon/action-icon-auto.png" if is_unlocked else "res://assets/art/static/action_icon/action-icon-locked.png",
			rune_positions[index],
			_toggle_blueprint.bind(blueprint_id, not is_enabled),
			is_enabled,
			is_unlocked,
			"运转" if is_enabled else ("沉寂" if is_unlocked else "未悟"),
			GREEN,
			88.0
		)
	bottom.add_child(_world_toolbar_button("全部点亮", String(NAV_ART["automation"]), _toggle_global_automation.bind(true), GREEN, false, 180))
	bottom.add_child(_world_toolbar_button("全部封闭", "res://assets/art/static/action_icon/action-icon-locked.png", _toggle_global_automation.bind(false), RED, false, 180))
	for ratio in [0.5, 0.75, 1.0]:
		bottom.add_child(_world_toolbar_button("阵力 %.0f%%" % (ratio * 100.0), "res://assets/art/static/farm_icon/farm-icon-gathering-array.png", _set_budget.bind(ratio), BLUE if is_equal_approx(float(automation["purchase_budget_ratio"]), ratio) else MUTED, false, 170))
	for mode in [["safe", "安全渡劫"], ["exact", "精确渡劫"], ["manual", "手动渡劫"]]:
		bottom.add_child(_world_toolbar_button(String(mode[1]), String(NAV_ART["tribulation"]), _set_tribulation_mode.bind(String(mode[0])), GOLD if String(automation["tribulation_mode"]) == String(mode[0]) else MUTED, false, 190))


func _render_reset(summary: Dictionary) -> void:
	_add_page_heading("轮回 / 飞升", "")
	var view := _begin_world_scene(PURPLE, 0)
	var world := view["world"] as Control
	var reset_preview := GameState.get_reset_preview()
	var ascension := GameState.get_ascension_preview()
	var can_reset := bool(reset_preview.get("can_reset", false))
	var can_ascend := bool(ascension.get("ready", false))
	_add_world_animation(
		world,
		"ReincarnationPortal",
		"animation.reincarnation",
		Vector2(0.50, 0.43),
		Vector2(520, 470)
	)
	_add_world_object(
		world,
		"ReincarnationChoice",
		"转世轮回",
		"res://assets/art/static/navigation_icon/navigation-icon-reincarnation.png",
		Vector2(0.22, 0.47),
		_confirm_reincarnation,
		can_reset,
		can_reset,
		"道蕴 +%s" % NumberFmt.magnitude(reset_preview["dao_gain"]),
		RED,
		170.0
	)
	_add_world_object(
		world,
		"AscensionChoice",
		"登天飞升",
		"res://assets/art/static/resource_icon/resource-icon-dao-essence.png",
		Vector2(0.78, 0.47),
		_confirm_ascend,
		can_ascend,
		can_ascend,
		"法则 +%s" % NumberFmt.counter(ascension["law_gain"]),
		PURPLE,
		170.0
	)
	_world_caption(world, "点击命轮作出选择", Vector2(0.50, 0.79), 30, Color("fff1b5"))


func _render_receipts(summary: Dictionary) -> void:
	_add_page_heading("日志", "")
	var view := _begin_world_scene(BLUE, 124)
	var world := view["world"] as Control
	var bottom := view["bottom_row"] as HBoxContainer
	var receipt_list := GameState.get_receipts(100)
	var sprite := _add_world_animation(
		world,
		"InspectingDisciple",
		"animation.disciple_inspecting",
		Vector2(0.82, 0.46),
		Vector2(330, 390)
	)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.82)

	var journal := PanelContainer.new()
	journal.name = "CultivationJournal"
	journal.set_anchor(SIDE_LEFT, 0.06)
	journal.set_anchor(SIDE_RIGHT, 0.72)
	journal.set_anchor(SIDE_TOP, 0.07)
	journal.set_anchor(SIDE_BOTTOM, 0.76)
	journal.add_theme_stylebox_override("panel", _journal_style())
	world.add_child(journal)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	journal.add_child(margin)
	var receipt_scroll := ScrollContainer.new()
	receipt_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	receipt_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(receipt_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	receipt_scroll.add_child(list)
	if receipt_list.is_empty():
		var empty := _label("玉册尚空", 30, MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	else:
		for index in range(receipt_list.size() - 1, -1, -1):
			var item: Dictionary = receipt_list[index]
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 12)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(46, 46)
			icon.texture = _normalized_icon(_receipt_icon_path(String(item.get("kind", ""))))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			line.add_child(icon)
			var number := int(item.get("receipt_id", 0))
			var text := _label("#%d  %s" % [number, _receipt_line(item)], MIN_FONT_SIZE, TEXT)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(text)
			list.add_child(line)
			list.add_child(HSeparator.new())
	var count_label := _scene_label("玉册 %d 条" % receipt_list.size(), 28, GOLD)
	count_label.custom_minimum_size = Vector2(190, 60)
	count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(count_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	bottom.add_child(_world_toolbar_button("铭刻此刻", "res://assets/art/static/action_icon/action-icon-save.png", _save_now, GREEN, false, 280))


func _add_page_heading(title: String, subtitle: String) -> void:
	if not _notice_label == null and not _notice_label.text.is_empty():
		if is_instance_valid(_notice_toast):
			_notice_toast.queue_free()
		var notice_panel := PanelContainer.new()
		notice_panel.name = "GameNoticeToast"
		notice_panel.z_index = 120
		notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		notice_panel.set_anchor(SIDE_LEFT, 0.0)
		notice_panel.set_anchor(SIDE_RIGHT, 1.0)
		notice_panel.set_anchor(SIDE_TOP, 0.0)
		notice_panel.set_anchor(SIDE_BOTTOM, 0.0)
		notice_panel.offset_left = 34
		notice_panel.offset_right = -34
		notice_panel.offset_top = 206
		notice_panel.offset_bottom = 260
		notice_panel.add_theme_stylebox_override("panel", _game_notice_style())
		var notice := _label("◆ %s" % _notice_label.text, MIN_FONT_SIZE, GOLD)
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice_panel.add_child(notice)
		add_child(notice_panel)
		_notice_toast = notice_panel
		_notice_label.text = ""
		var toast_lifetime := notice_panel.create_tween()
		toast_lifetime.tween_interval(2.2)
		toast_lifetime.tween_property(notice_panel, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE)
		toast_lifetime.tween_callback(notice_panel.queue_free)


func _button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	return row


func _add_separator(parent: Node) -> void:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	parent.add_child(separator)


func _page_button(text: String, action: Callable, accent: Color = BLUE, icon_path: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 56
	if not icon_path.is_empty():
		button.icon = _normalized_icon(icon_path)
		button.add_theme_constant_override("icon_max_width", int(28 * BUTTON_ICON_SCALE))
		button.expand_icon = true
		button.custom_minimum_size.y = 72
	button.add_theme_font_size_override("font_size", MIN_FONT_SIZE)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _button_style(SURFACE_RAISED, BORDER_SOFT))
	button.add_theme_stylebox_override("hover", _button_style(SURFACE_RAISED, accent))
	button.add_theme_stylebox_override("pressed", _button_style(SURFACE_DEEP, accent))
	button.add_theme_stylebox_override("disabled", _button_style(SURFACE_DEEP, BORDER_SOFT))
	button.pressed.connect(action)
	return button


func _asset(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var texture := load(path)
	return texture as Texture2D


func _normalized_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _normalized_icon_cache.has(path):
		return _normalized_icon_cache[path] as Texture2D
	var source := _asset(path)
	if source == null:
		return null
	var normalized: Texture2D = source
	var image := source.get_image()
	if image != null:
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var atlas := AtlasTexture.new()
			atlas.atlas = source
			atlas.region = Rect2(used.position, used.size)
			normalized = atlas
	_normalized_icon_cache[path] = normalized
	return normalized


func _label(text: String, font_size: int = 14, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(MIN_FONT_SIZE, font_size))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _scene_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.08, 0.05, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 3)
	return label


func _apply_text_outline(label: Label, outline_size: int) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.050, 0.040, 0.98))
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("shadow_outline_size", 4)


func _drawer_command_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.036, 0.028, 0.97)
	style.border_color = Color(0.82, 0.66, 0.30, 0.68)
	style.border_width_bottom = 2
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _world_bottom_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.028, 0.021, 0.90)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.62)
	style.border_width_top = 2
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.56)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	return style


func _world_object_style(active: bool, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.050, 0.038, 0.38)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.95 if active else 0.34)
	style.set_border_width_all(3 if active else 1)
	style.set_corner_radius_all(999)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.42) if active else Color(0.0, 0.0, 0.0, 0.38)
	style.shadow_size = 13 if active else 5
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _world_unlock_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.24, 0.16, 0.96) if hovered else Color(0.035, 0.13, 0.09, 0.92)
	style.border_color = Color("f4d16f") if hovered else Color(0.69, 0.58, 0.28, 0.90)
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	style.shadow_size = 7 if hovered else 4
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _journal_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.095, 0.045, 0.88)
	style.border_color = Color(0.88, 0.71, 0.34, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 10
	return style


func _game_notice_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.12, 0.035, 0.88)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _drawer_tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.18, 0.055, 0.82) if active else Color(0.03, 0.10, 0.075, 0.76)
	style.border_color = GOLD if active else Color(0.55, 0.48, 0.26, 0.62)
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	style.shadow_size = 5
	return style


func _divider_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.68, 0.30, 0.72)
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


func _round_nav_style(active: bool, content_margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.95, 0.76, 0.10) if active else Color.TRANSPARENT
	style.border_color = Color.TRANSPARENT
	style.set_corner_radius_all(999)
	style.content_margin_left = content_margin
	style.content_margin_right = content_margin
	style.content_margin_top = content_margin
	style.content_margin_bottom = content_margin
	return style


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _select_page(page_id: String) -> void:
	if page_id == "overview":
		_close_page_drawer()
		return
	if is_instance_valid(_page_drawer) and _page_drawer.visible and _current_page == page_id:
		_close_page_drawer()
		return
	_current_page = page_id
	_page_dirty = true
	_preserve_page_scroll = false
	if is_instance_valid(_page_drawer):
		_page_drawer.visible = true
	if is_instance_valid(_game_header):
		_game_header.visible = false
	if is_instance_valid(_bottom_navigation):
		_bottom_navigation.visible = false
	_set_drawer_visuals(page_id)
	_update_nav()
	if is_instance_valid(_page_box):
		_render_page(GameState.get_summary())


func _close_page_drawer() -> void:
	_current_page = "overview"
	_preserve_page_scroll = false
	if is_instance_valid(_page_drawer):
		_page_drawer.visible = false
	if is_instance_valid(_game_header):
		_game_header.visible = true
	if is_instance_valid(_bottom_navigation):
		_bottom_navigation.visible = true
	if is_instance_valid(_drawer_animation):
		_drawer_animation.stop()
	_update_nav()


func _save_now() -> void:
	var ok := SaveManager.save_game()
	_notify("已保存当前进度。" if ok else "保存失败，请查看日志页。")


func _set_preset(preset: String, label: String) -> void:
	if GameState.set_production_preset(preset):
		_notify("已切换生产预设：%s。" % label)
	else:
		_notify("当前没有可用作物。")


func _select_single_crop(crop_id: String) -> void:
	var previous := _dominant_crop(GameState.farm.plan(), GameState.get_available_crops())
	if GameState.set_production_plan({crop_id: 1.0}):
		_crop_transition_from = previous
		_crop_transition_to = crop_id
		_crop_transition_pending = not previous.is_empty() and previous != crop_id
		_notify("已将生产计划切换为：%s。" % String(BalanceConfig.crop(crop_id).get("name", crop_id)))


func _buy_upgrade(upgrade_id: String, label: String) -> void:
	var result := GameState.buy_upgrade(upgrade_id, true)
	_notify("%s：购买 %d 级，消耗 %s。" % [label, int(result.get("bought", 0)), NumberFmt.magnitude(result.get("spent", BigMagnitude.zero()))])


func _buy_upgrade_once(upgrade_id: String, label: String) -> void:
	var result := GameState.buy_upgrade(upgrade_id, false)
	var message := "购买成功，消耗 %s" % NumberFmt.magnitude(result.get("cost", BigMagnitude.zero())) if bool(result.get("bought", false)) else _reason_text(String(result.get("reason", "")))
	_notify("%s：%s。" % [label, message])


func _choose_target(node_id: String) -> void:
	var result := GameState.choose_target(node_id)
	_notify("已选择：%s。" % String(BalanceConfig.node(node_id).get("name", node_id)) if bool(result.get("ok", false)) else "选择失败：%s。" % _reason_text(String(result.get("reason", ""))))


func _do_breakthrough() -> void:
	var result := GameState.attempt_breakthrough(9)
	if bool(result.get("success", false)):
		_notify("突破成功，进入雷劫结算。")
	elif not result.get("attempts", []).is_empty():
		_notify("本批次已结算 %d 次尝试，当前仍可继续推进。" % result["attempts"].size())
	else:
		_notify("暂时不能突破：%s。" % _reason_text(String(result.get("reason", ""))))


func _do_breakthrough_once() -> void:
	var result := GameState.attempt_breakthrough(1)
	if bool(result.get("success", false)):
		_notify("单次突破成功，进入雷劫结算。")
	elif not result.get("attempts", []).is_empty():
		_notify("单次突破未成功，保底与材料状态已更新。")
	else:
		_notify("暂时不能突破：%s。" % _reason_text(String(result.get("reason", ""))))


func _do_tribulation() -> void:
	var result := GameState.begin_tribulation()
	_notify("雷劫结算成功。" if bool(result.get("success", false)) else "雷劫暂未结算：%s。" % _reason_text(String(result.get("reason", ""))))


func _do_reincarnation() -> void:
	var result := GameState.reincarnate_now()
	_notify("轮回完成，进入第 %d 世。" % int(result.get("generation", GameState.run.generation)) if bool(result.get("can_reset", false)) else "暂时不能轮回：%s。" % _reason_text(String(result.get("reason", ""))))


func _confirm_reincarnation() -> void:
	_confirm_action("确认轮回", "轮回会重置本世修为和农场，但会保留历史、材料和道蕴。确定继续？", _do_reincarnation)


func _do_ascend() -> void:
	var result := GameState.ascend()
	_notify("飞升完成，法则 +%s。" % NumberFmt.counter(result.get("law_gain", BigCounter.zero())) if bool(result.get("ready", false)) else "暂时不能飞升：%s。" % _reason_text(String(result.get("reason", ""))))


func _confirm_ascend() -> void:
	_confirm_action("确认飞升", "飞升会结束当前道统并重置阶段状态。确定继续？", _do_ascend)


func _confirm_action(title: String, message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.add_theme_font_size_override("font_size", MIN_FONT_SIZE)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		action.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2(720, 300))


func _toggle_global_automation(enabled: bool) -> void:
	GameState.set_automation_enabled(enabled)
	_notify("已%s全部已解锁自动化。" % ("打开" if enabled else "关闭"))


func _toggle_blueprint(blueprint_id: String, enabled: bool) -> void:
	if GameState.set_blueprint_enabled(blueprint_id, enabled):
		_notify("%s：%s。" % [String(BLUEPRINT_NAMES.get(blueprint_id, blueprint_id)), "已开启" if enabled else "已关闭"])
	else:
		_notify("该蓝图尚未解锁。")


func _toggle_option(option_id: String, enabled: bool) -> void:
	if GameState.set_automation_option(option_id, enabled):
		_notify("自动化选项已%s。" % ("开启" if enabled else "关闭"))
	else:
		_notify("该选项当前不可用。")


func _set_budget(ratio: float) -> void:
	GameState.set_purchase_budget_ratio(ratio)
	_notify("自动购买预算已设置为 %.0f%%。" % (ratio * 100.0))


func _set_tribulation_mode(mode: String) -> void:
	if GameState.set_tribulation_mode(mode):
		_notify("雷劫模式：%s。" % _string_mode(mode))


func _notify(message: String) -> void:
	if not is_instance_valid(_notice_label):
		_notice_label = Label.new()
	_notice_label.text = message
	_page_dirty = true


func _next_action_text(summary: Dictionary) -> String:
	var target: Dictionary = summary["target"]
	if not GameState.run.pending_tribulation.is_empty():
		return "先结算雷劫，再进入下一境。"
	if not String(target.get("id", "")).is_empty() and bool(target.get("cultivation_ready", false)) and bool(target.get("materials_ready", false)):
		return "修为和材料已齐，执行一次突破批次。"
	if bool(GameState.get_reset_preview().get("can_reset", false)):
		return "本世已满足轮回条件，可领取道蕴收益。"
	return "继续生产，优先查看路线页的门槛和材料 ETA。"


func _target_name(target: Dictionary) -> String:
	var id := String(target.get("id", ""))
	return "暂无目标" if id.is_empty() else String(target.get("name", id))


func _plan_text(plan: Dictionary) -> String:
	var pieces: Array[String] = []
	for crop_id in plan:
		pieces.append("%s %.0f%%" % [String(BalanceConfig.crop(String(crop_id)).get("name", crop_id)), float(plan[crop_id]) * 100.0])
	return "、".join(pieces)


func _tier_name(tier: String) -> String:
	return String(TIER_NAMES.get(tier, tier))


func _node_names(ids: Array) -> String:
	var names: Array[String] = []
	for node_id in ids:
		names.append(String(BalanceConfig.node(String(node_id)).get("name", node_id)))
	return "、".join(names)


func _material_requirement_text(requirements: Dictionary) -> String:
	if requirements.is_empty():
		return "无"
	var names: Array[String] = []
	for material_id in requirements:
		names.append(String(BalanceConfig.MATERIALS.get(String(material_id), {}).get("name", material_id)))
	return "、".join(names)


func _node_state_text(row: Dictionary, active: bool) -> String:
	if active:
		return "当前目标 · %s" % ("已达标，可尝试" if bool(row["ready"]) else "正在积累")
	if bool(row["inherited"]):
		return "历史已入史"
	if bool(row["completed"]):
		return "本世已完成"
	if bool(row["legal"]):
		return "可选路线"
	return "前置不足"


func _status_text(status: String) -> String:
	match status:
		"RUNNING":
			return "运行中"
		"WAITING_TRIBULATION":
			return "等待雷劫"
		"ASCENDED":
			return "已飞升"
		_:
			return status


func _string_mode(mode: String) -> String:
	match mode:
		"safe":
			return "安全"
		"exact":
			return "精确"
		"manual":
			return "手动"
		_:
			return mode


func _receipt_line(item: Dictionary) -> String:
	var kind := String(item.get("kind", "batch"))
	var node_id := String(item.get("node_id", ""))
	var suffix := " · %s" % String(BalanceConfig.node(node_id).get("name", node_id)) if not node_id.is_empty() else ""
	match kind:
		"breakthrough_batch":
			return "突破批次%s · %d 次尝试" % [suffix, (item.get("attempts", []) as Array).size()]
		"tribulation":
			return "雷劫%s · %s" % [suffix, "成功" if String(item.get("result", {}).get("reason", "")) != "TRIBULATION_FAILED" else "失败"]
		"reincarnation":
			return "轮回 · 新发现 %d 个" % (item.get("discoveries", []) as Array).size()
		"ascension":
			return "飞升 · 法则收益 %s" % String(item.get("law_gain", "?"))
		"treasure_batch":
			return "宝阁入库 · 灵田灵机化作宝物"
		_:
			return "修行纪事%s" % suffix


func _receipt_icon_path(kind: String) -> String:
	match kind:
		"breakthrough_batch":
			return "res://assets/art/static/action_icon/action-icon-breakthrough.png"
		"tribulation":
			return "res://assets/art/static/navigation_icon/navigation-icon-tribulation.png"
		"reincarnation", "ascension":
			return "res://assets/art/static/navigation_icon/navigation-icon-reincarnation.png"
		"treasure_batch":
			return "res://assets/art/static/action_icon/action-icon-receipt.png"
		_:
			return "res://assets/art/static/action_icon/action-icon-info.png"


func _reason_text(reason: String) -> String:
	match reason:
		"":
			return "未说明"
		"NO_PENDING_TRIBULATION":
			return "当前没有待结算雷劫"
		"INSUFFICIENT_CULTIVATION":
			return "修为还未达到门槛"
		"INSUFFICIENT_MATERIALS":
			return "材料还未齐套"
		"BREAKTHROUGH_IN_PROGRESS":
			return "上一轮突破尚未完成"
		"NO_LEGAL_TARGET":
			return "没有合法路线目标"
		"ASCENSION_PREREQUISITE":
			return "飞升门槛尚未满足"
		"SAVE_FAILED":
			return "关键操作写入存档失败"
		"AWAITING_RESET":
			return "等待轮回或飞升"
		_:
			return "修行暂歇"


func _saved_time_text() -> String:
	if GameState.saved_at_unix <= 0:
		return "尚未保存"
	return Time.get_datetime_string_from_unix_time(GameState.saved_at_unix, true)
