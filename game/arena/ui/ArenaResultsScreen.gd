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

	theme = MenuTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background(victory, has_result)

	var page: VBoxContainer = VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 22)
	add_child(page)

	# --- Banner --------------------------------------------------------------
	var banner: Label = Label.new()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.theme_type_variation = &"DisplayLabel"
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
	subtitle.add_theme_font_size_override("font_size", MenuTheme.FS_SUBHEADING)
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
		reached.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
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
	# The shared menu backdrop (navy gradient + drifting motes).
	var bg := MenuBackdrop.new()
	bg.name = "Backdrop"
	add_child(bg)

	# Faint accent wash from the bottom -- gold on a win, dim red on a loss.
	var accent: Color = _amber
	if has_result:
		accent = _gold if victory else _defeat_red
	# A soft vertical gradient (no hard edge) rising from the bottom of the screen.
	var grad := Gradient.new()
	grad.set_color(0, Color(accent.r, accent.g, accent.b, 0.0))
	grad.set_color(1, Color(accent.r, accent.g, accent.b, 0.16))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 256
	var glow := TextureRect.new()
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = 0.35
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)



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

	var heading: Label = MenuKit.section("Final Squad")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	col.add_child(HSeparator.new())

	for entry in squad:
		if not (entry is Dictionary):
			continue
		col.add_child(_build_squad_row(entry))

	return panel


func _build_squad_row(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var unit_name := _humanize_id(String(entry.get("name", "")))
	row.add_child(ConquestTheme.portrait(unit_name, MenuTheme.GOLD, MenuTheme.TEAM_BLUE, 34.0))

	var name_label: Label = Label.new()
	name_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", _cream)
	name_label.text = _humanize_id(String(entry.get("name", "")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var count: int = int(entry.get("augment_count", 0))
	var aug_label: Label = Label.new()
	aug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	aug_label.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	aug_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	aug_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var noun: String = "augment" if count == 1 else "augments"
	aug_label.text = "%d %s" % [count, noun]
	row.add_child(aug_label)

	return row


# --- Return button ----------------------------------------------------------

func _build_return_button() -> Control:
	var btn: Button = MenuKit.button("Return to Menu", MenuKit.PRIMARY, 280.0, 56.0)
	MenuNav.focus_deferred(btn)

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
	var sb := MenuTheme.card_box()
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


# --- Palette load -----------------------------------------------------------

## The shared menu tokens (MenuTheme) -- navy + gold, same as every other screen.
func _load_palette() -> void:
	_plate_fill = MenuTheme.PANEL
	_ink = MenuTheme.INK
	_cream = MenuTheme.CREAM
	_cream_dim = MenuTheme.TEXT_DIM
	_amber = MenuTheme.GOLD
	_amber_lite = MenuTheme.GOLD_LITE
	_brown_dk = MenuTheme.BG_DEEP
	_gold = MenuTheme.GOLD_LITE
	_defeat_red = MenuTheme.DANGER
	_bg_top = MenuTheme.BG
	_bg_bottom = MenuTheme.BG_DEEP
