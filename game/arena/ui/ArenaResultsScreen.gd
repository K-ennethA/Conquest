extends Control

## End-of-run results for the Arena mode. Shown once a run finishes (all rounds cleared
## OR the squad was wiped), it reads the snapshot ArenaController stashed in `last_result`
## just before it discarded the run, so this screen needs no live run state.
##
## Flow: _ready pulls ArenaController.last_result (null-safe -- a missing controller or an
## empty dict falls back to a neutral summary), then renders a big VICTORY / DEFEAT banner,
## the round reached ("Reached round X of N"), the final squad with each unit's augment
## count, and a single "Return to Menu" button back to the main menu. Never crashes on a
## null controller or an empty / partial result.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

# Warm palette. Pulled from ConquestTheme when present, else tasteful hardcoded fallbacks
# so a missing constant can never crash this screen.
var _bg_top: Color = Color(0.10, 0.075, 0.05, 1.0)
var _bg_bottom: Color = Color(0.05, 0.035, 0.02, 1.0)
var _plate_fill: Color = Color("2c2114")
var _ink: Color = Color("2a1608")
var _cream: Color = Color("fcefd6")
var _cream_dim: Color = Color("e7d3ad")
var _amber: Color = Color("e6a64b")
var _amber_lite: Color = Color("f0c072")
var _brown_dk: Color = Color("37220f")

# Banner accents.
var _gold: Color = Color("f0c040")       # VICTORY -- triumphant
var _defeat_red: Color = Color("a83a3a") # DEFEAT  -- somber, dim red


func _ready() -> void:
	_load_palette()

	var result: Dictionary = _read_result()

	var victory: bool = bool(result.get("victory", false))
	var rounds_cleared: int = int(result.get("rounds_cleared", 0))
	var total_rounds: int = int(result.get("total_rounds", 0))
	var squad: Array = result.get("squad", []) if result.get("squad", []) is Array else []
	var has_result: bool = not result.is_empty()

	_build_background(victory, has_result)

	var page: VBoxContainer = VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 22)
	add_child(page)

	# --- Banner --------------------------------------------------------------
	var banner: Label = Label.new()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 72)
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.add_theme_constant_override("shadow_offset_x", 2)
	if not has_result:
		banner.text = "RUN COMPLETE"
		banner.add_theme_color_override("font_color", _amber_lite)
	elif victory:
		banner.text = "VICTORY"
		banner.add_theme_color_override("font_color", _gold)
	else:
		banner.text = "DEFEAT"
		banner.add_theme_color_override("font_color", _defeat_red)
	page.add_child(banner)

	# --- Subtitle / round reached -------------------------------------------
	var subtitle: Label = Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", _cream)
	if not has_result:
		subtitle.text = "The arena run has ended."
	elif victory:
		subtitle.text = "You cleared every round of the arena."
	else:
		subtitle.text = "Your squad fell in the arena."
	page.add_child(subtitle)

	if has_result:
		var reached: Label = Label.new()
		reached.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reached.add_theme_font_size_override("font_size", 18)
		reached.add_theme_color_override("font_color", _cream_dim)
		reached.text = "Reached round %d of %d" % [rounds_cleared, total_rounds]
		page.add_child(reached)

	# --- Squad summary -------------------------------------------------------
	if not squad.is_empty():
		page.add_child(_build_squad_panel(squad))

	# --- Return to Menu ------------------------------------------------------
	page.add_child(_build_return_button())


# --- Background -------------------------------------------------------------

func _build_background(victory: bool, has_result: bool) -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = _bg_top
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Faint accent wash from the bottom -- gold on a win, dim red on a loss.
	var accent: Color = _amber
	if has_result:
		accent = _gold if victory else _defeat_red
	var glow: ColorRect = ColorRect.new()
	glow.color = Color(accent.r, accent.g, accent.b, 0.12)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = 0.4
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var vignette: ColorRect = ColorRect.new()
	vignette.color = Color(_bg_bottom.r, _bg_bottom.g, _bg_bottom.b, 0.55)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	vignette.anchor_top = 0.55
	vignette.offset_top = 0.0
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


# --- Squad panel ------------------------------------------------------------

func _build_squad_panel(squad: Array) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _plate_box())
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(420.0, 0.0)
	margin.add_child(col)

	var heading: Label = Label.new()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", _amber_lite)
	heading.text = "FINAL SQUAD"
	col.add_child(heading)

	var sep: HSeparator = HSeparator.new()
	var sep_box: StyleBoxFlat = StyleBoxFlat.new()
	sep_box.bg_color = _amber.darkened(0.2)
	sep_box.content_margin_top = 1.0
	sep_box.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_box)
	col.add_child(sep)

	for entry in squad:
		if not (entry is Dictionary):
			continue
		col.add_child(_build_squad_row(entry))

	return panel


func _build_squad_row(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var name_label: Label = Label.new()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", _cream)
	name_label.text = _humanize_id(String(entry.get("name", "")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var count: int = int(entry.get("augment_count", 0))
	var aug_label: Label = Label.new()
	aug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	aug_label.add_theme_font_size_override("font_size", 16)
	aug_label.add_theme_color_override("font_color", _amber)
	var noun: String = "augment" if count == 1 else "augments"
	aug_label.text = "%d %s" % [count, noun]
	row.add_child(aug_label)

	return row


# --- Return button ----------------------------------------------------------

func _build_return_button() -> Control:
	var btn: Button = Button.new()
	btn.text = "Return to Menu"
	btn.custom_minimum_size = Vector2(260.0, 56.0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("normal", _button_box(_amber_lite))
	btn.add_theme_stylebox_override("hover", _button_box(_amber_lite.lightened(0.10)))
	btn.add_theme_stylebox_override("pressed", _button_box(_amber))
	btn.add_theme_color_override("font_color", _ink)
	btn.add_theme_color_override("font_hover_color", _brown_dk)

	var wrap: HBoxContainer = HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(btn)

	btn.pressed.connect(_on_return_pressed)
	return wrap


func _on_return_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# --- Result access ----------------------------------------------------------

## Read ArenaController.last_result null-safely; returns {} if the autoload or the
## member is missing (then the screen shows a neutral summary).
func _read_result() -> Dictionary:
	var arena: Node = get_node_or_null("/root/ArenaController")
	if arena == null:
		return {}
	if not ("last_result" in arena):
		return {}
	var raw: Variant = arena.last_result
	if raw is Dictionary:
		return raw
	return {}


# --- Helpers ----------------------------------------------------------------

## "vineweave" -> "Vineweave". Empty id -> "Unknown".
func _humanize_id(id: String) -> String:
	var trimmed: String = id.strip_edges()
	if trimmed == "":
		return "Unknown"
	return trimmed.replace("_", " ").capitalize()


func _plate_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _plate_fill
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = _brown_dk
	sb.set_content_margin_all(0.0)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
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


# --- Palette load -----------------------------------------------------------

## Pull the warm colours from ConquestTheme (a verified script class_name; resolves at
## author time). The hardcoded defaults above stand in if the class is ever removed.
func _load_palette() -> void:
	_plate_fill = ConquestTheme.PLATE_BG
	_ink = ConquestTheme.INK
	_cream = ConquestTheme.CREAM
	_cream_dim = ConquestTheme.CREAM_DIM
	_amber = ConquestTheme.AMBER
	_amber_lite = ConquestTheme.AMBER_LITE
	_brown_dk = ConquestTheme.BROWN_DK
	_gold = ConquestTheme.EL_HOLY
	_bg_top = ConquestTheme.INK.lerp(Color.BLACK, 0.15)
	_bg_bottom = ConquestTheme.BROWN_DK.darkened(0.35)
