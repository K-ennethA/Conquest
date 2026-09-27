extends Control

## Between-round reward step: after clearing a round you pick one power-up (augment)
## to stack onto your build, then the next round loads. This is the real "pick 1 of N"
## draft screen -- a centered row of rarity-framed cards on the shared menu page
## (MenuTheme navy + gold, MenuKit header / footer), keyboard / pad navigable.
##
## Flow: _ready reads ArenaController (autoload), shows the cleared round number, rolls
## the draft options, and renders one clickable card per Augment. Clicking a card calls
## ArenaController.choose_augment(that_augment), which grants it and advances to the next
## round. If the pool is empty (not wired yet) a single "Continue" -> choose_augment(null)
## keeps the loop moving. Never crashes when the controller is null or options are empty.

const CARD_SIZE := Vector2(250.0, 330.0)

# Warm palette. Pulled from ConquestTheme when present, else tasteful hardcoded
# fallbacks so a missing constant can never crash this screen.
var _bg_top: Color = Color(0.10, 0.075, 0.05, 1.0)
var _bg_bottom: Color = Color(0.05, 0.035, 0.02, 1.0)
var _card_fill: Color = Color("2c2114")
var _card_fill_hover: Color = Color("3a2c1a")
var _ink: Color = Color("2a1608")
var _cream: Color = Color("fcefd6")
var _cream_dim: Color = Color("e7d3ad")
var _amber: Color = Color("e6a64b")
var _amber_lite: Color = Color("f0c072")
var _brown_dk: Color = Color("37220f")


var _cards: Array[Button] = []


func _ready() -> void:
	_load_palette()

	var arena: Node = get_node_or_null("/root/ArenaController")
	var round_num: int = 0
	if arena != null and arena.has_method("current_round"):
		round_num = int(arena.current_round())

	var page := MenuKit.build_page(self, ["Arena"],
		"Round %d Cleared" % round_num, "Choose one power-up to carry into the next round.")
	var body: VBoxContainer = page["body"]
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	# Only "Choose" applies here (there is no going back from a cleared round).
	(page["hints"] as HBoxContainer).add_child(MenuKit.key_hint("Enter", "A", "Choose"))

	# --- Options -------------------------------------------------------------
	var options: Array = []
	if arena != null and arena.has_method("roll_draft_options"):
		var rolled: Variant = arena.roll_draft_options()
		if rolled is Array:
			options = rolled

	if options.is_empty():
		_build_continue(body, arena)
	else:
		_build_card_row(body, options, arena)
		if not _cards.is_empty():
			MenuNav.focus_deferred(_cards[0])


# --- Continue (empty pool) --------------------------------------------------

func _build_continue(page: VBoxContainer, arena: Node) -> void:
	var note: Label = MenuKit.label("No augments available yet.", &"DimLabel")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(note)

	var cont: Button = MenuKit.button("Continue", MenuKit.PRIMARY, 240.0, 52.0)
	MenuNav.focus_deferred(cont)

	# Center the fixed-width button within the full-width page column.
	var wrap: HBoxContainer = HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(cont)
	page.add_child(wrap)

	cont.pressed.connect(func() -> void:
		if arena != null and arena.has_method("choose_augment"):
			arena.choose_augment(null))


# --- Card row ---------------------------------------------------------------

func _build_card_row(page: VBoxContainer, options: Array, arena: Node) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	page.add_child(row)

	for opt in options:
		row.add_child(_build_card(opt, arena))


func _build_card(opt: Object, arena: Node) -> Control:
	var accent: Color = _rarity_color(opt)
	var rarity_text: String = _rarity_name(opt)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	var normal_box: OrnateStyleBox = _card_box(_card_fill, accent.darkened(0.15), 2)
	var hover_box: OrnateStyleBox = _card_box(_card_fill_hover, accent, 3)
	hover_box.crest = true
	hover_box.crest_color = accent
	# Focus / hover glows gold (the menus' focus colour) around the rarity frame.
	hover_box.shadow_color = Color(MenuTheme.GOLD.r, MenuTheme.GOLD.g, MenuTheme.GOLD.b, 0.35)
	hover_box.shadow_size = 16
	hover_box.shadow_offset = Vector2.ZERO
	card.add_theme_stylebox_override("panel", normal_box)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Rarity ribbon.
	var rarity_label: Label = Label.new()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_override("font", MenuTheme.heading_font(2))
	rarity_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	rarity_label.add_theme_color_override("font_color", accent.lightened(0.25))
	rarity_label.text = rarity_text.to_upper()
	rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rarity_label)

	# Name.
	var name_label: Label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", MenuTheme.heading_font(1))
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", _cream)
	name_label.text = _augment_name(opt)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	var sep: HSeparator = HSeparator.new()
	var sep_box: StyleBoxFlat = StyleBoxFlat.new()
	sep_box.bg_color = accent
	sep_box.content_margin_top = 1.0
	sep_box.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_box)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sep)

	# Description.
	var desc_label: Label = Label.new()
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	desc_label.add_theme_color_override("font_color", _cream_dim)
	desc_label.text = _augment_description(opt)
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_label)

	# Stat bonuses.
	var stats: Array = _stat_lines(opt)
	if not stats.is_empty():
		var stat_box: VBoxContainer = VBoxContainer.new()
		stat_box.add_theme_constant_override("separation", 3)
		stat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for line in stats:
			var s_label: Label = Label.new()
			s_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
			s_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
			s_label.text = String(line)
			s_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stat_box.add_child(s_label)
		col.add_child(stat_box)

	# Full-card clickable overlay with hover highlight.
	var hit: Button = Button.new()
	hit.flat = true
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.focus_mode = Control.FOCUS_ALL
	hit.tooltip_text = _augment_description(opt)
	var transparent: StyleBoxEmpty = StyleBoxEmpty.new()
	hit.add_theme_stylebox_override("normal", transparent)
	hit.add_theme_stylebox_override("hover", transparent)
	hit.add_theme_stylebox_override("pressed", transparent)
	hit.add_theme_stylebox_override("focus", transparent)
	card.add_child(hit)

	# Mouse hover moves focus; focus (mouse, keys or pad) lifts the card.
	MenuNav.hover_focus(hit)
	hit.focus_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", hover_box)
		card.scale = Vector2(1.03, 1.03))
	hit.focus_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", normal_box)
		card.scale = Vector2(1.0, 1.0))
	_cards.append(hit)
	hit.pressed.connect(func() -> void:
		if arena != null and arena.has_method("choose_augment"):
			arena.choose_augment(opt))

	# Keep scale centered on the card.
	card.pivot_offset = CARD_SIZE * 0.5

	return card


# --- Styleboxes -------------------------------------------------------------

## An augment card: the grove frame edged in the rarity colour (rarity stripe on top).
func _card_box(fill: Color, border: Color, border_w: int) -> OrnateStyleBox:
	var sb := MenuTheme.card_box(fill, border, fill.a if fill.a > 0.0 else 0.96)
	sb.border_width = float(border_w)
	sb.accent_color = border
	sb.accent_side = SIDE_TOP
	sb.accent_width = 4.0
	sb.set_content_margin_all(0.0)
	return sb


func _button_box(fill: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = _brown_dk
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 9.0
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb


# --- Augment field access (all null/duck-typed-safe) ------------------------

func _augment_name(opt: Object) -> String:
	if opt != null and "display_name" in opt:
		return String(opt.display_name)
	return "Augment"


func _augment_description(opt: Object) -> String:
	if opt != null and "description" in opt:
		return String(opt.description)
	return ""


func _rarity_index(opt: Object) -> int:
	if opt != null and "rarity" in opt:
		return int(opt.rarity)
	return 0


func _rarity_color(opt: Object) -> Color:
	match _rarity_index(opt):
		0: return Color("aab3cf")  # COMMON  - cool grey
		1: return Color("4a90e2")  # RARE    - blue
		2: return Color("a860e0")  # EPIC    - purple
		3: return Color("f0c040")  # LEGENDARY - gold
	return Color("aab3cf")


func _rarity_name(opt: Object) -> String:
	match _rarity_index(opt):
		0: return "Common"
		1: return "Rare"
		2: return "Epic"
		3: return "Legendary"
	return "Common"


## Turn stat_bonuses {"max_health": 3, ...} into ["+3 Max HP", ...].
func _stat_lines(opt: Object) -> Array:
	var lines: Array = []
	if opt == null or not ("stat_bonuses" in opt):
		return lines
	var bonuses: Variant = opt.stat_bonuses
	if not (bonuses is Dictionary):
		return lines
	for key in bonuses.keys():
		var raw: Variant = bonuses[key]
		var value: int = 0
		if raw is int or raw is float:
			value = int(raw)
		var sign_str: String = "+" if value >= 0 else ""
		lines.append("%s%d %s" % [sign_str, value, _stat_display_name(String(key))])
	return lines


func _stat_display_name(key: String) -> String:
	match key:
		"max_health", "max_hp", "health", "hp": return "Max HP"
		"attack", "atk": return "Attack"
		"defense", "def": return "Defense"
		"move", "movement": return "Move"
		"evasion", "evade": return "Evasion"
		"speed", "spd": return "Speed"
		"range": return "Range"
	# Fallback: prettify the raw key ("crit_chance" -> "Crit Chance").
	return key.replace("_", " ").capitalize()


# --- Palette load -----------------------------------------------------------

## Pull the warm colours from ConquestTheme. It is a script class_name (verified
## present, with all constants used below), so this resolves at author time; the
## hardcoded defaults above stand in if the class is ever removed. Each assignment
## is a plain constant read -- none can fail at runtime once the script parses.
func _load_palette() -> void:
	_card_fill = MenuTheme.PANEL
	_card_fill_hover = MenuTheme.PANEL_HI
	_ink = MenuTheme.INK
	_cream = MenuTheme.CREAM
	_cream_dim = MenuTheme.TEXT_DIM
	_amber = MenuTheme.GOLD
	_amber_lite = MenuTheme.GOLD_LITE
	_brown_dk = MenuTheme.BG_DEEP
	_bg_top = MenuTheme.BG
	_bg_bottom = MenuTheme.BG_DEEP
