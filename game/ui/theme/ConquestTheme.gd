class_name ConquestTheme
extends RefCounted

## Central visual theme for Conquest's UI -- the "Fire Emblem warm amber" look
## (approved battle-HUD concept): amber panels with dark brown rounded frames,
## crisp readable text, cyan HP bars, and refined command buttons.
##
## Built in code (rather than a hand-authored .tres) so the whole palette lives
## in one reviewable place and panels can pull individual styleboxes to convert
## incrementally. Apply the whole theme to a UI subtree with
## [code]control.theme = ConquestTheme.build()[/code], and convert a panel's own
## background with [method style_panel_background].

# --- Palette ---------------------------------------------------------------
# INK / INK_SOFT are deliberately darker than a "brown" midtone -- deep
# espresso, near-black -- so default and disabled text keep strong contrast
# against the light AMBER / AMBER_LITE fills (see build()).
const AMBER := Color("e6a64b")
const AMBER_LITE := Color("f0c072")
const AMBER_DK := Color("c6822f")
const BROWN := Color("5a3a1e")
const BROWN_DK := Color("37220f")
const INK := Color("2a1608")
const INK_SOFT := Color("5c4020")
const CREAM := Color("fcefd6")
const CREAM_DIM := Color("e7d3ad")
const PLATE_BG := Color("2c2114")
const HP_CYAN := Color("37cde6")
const HP_TRACK := Color("241a10")
const HIT_ORANGE := Color("f0913c")

# Element / move-type accents (Pokemon-style colour coding).
const EL_EMBER := Color("e8623c")
const EL_FROST := Color("3fa9e0")
const EL_ARCANE := Color("a860e0")
const EL_HOLY := Color("e8b93a")
const EL_NATURE := Color("5fb84e")
const EL_STEEL := Color("c9cbd6")

# --- Command-button role fills ---------------------------------------------
# Three button roles share the warm palette but carry different weight so the
# "important vs secondary vs destructive" signal reads at a glance. A parallel
# panel tags its buttons with set_meta("style_role", "secondary"|"destructive");
# absent/unknown meta = primary. apply_button_role() reads that meta.
const BTN_PRIMARY := AMBER_LITE            # default warm amber (highest weight)
const BTN_SECONDARY := Color("a8946e")     # muted low-contrast amber-grey
const BTN_DESTRUCTIVE := Color("b5522f")   # ember red-brown (still in-palette)

# --- Type scale ------------------------------------------------------------
# One shared 720p-tuned scale so panels stop hand-setting per-widget font sizes.
# Applied as the theme's Label/Button defaults in build(); panels reference the
# constants for code-built widgets. Body is kept >= 13 for legibility at 720p.
const FONT_TITLE := 18
const FONT_HEADER := 15
const FONT_BODY := 13
const FONT_CAPTION := 11


# --- Public stylebox factories (reusable per-panel) ------------------------

## The signature amber card/panel: warm fill, dark brown rounded frame, soft drop.
static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = AMBER
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = BROWN
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb


## A darker inset "plate" used behind values (HP number, forecast stats).
static func plate_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE_BG
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(2)
	sb.border_color = BROWN_DK
	sb.set_content_margin_all(8)
	return sb


static func _button_box(fill: Color, border: Color = BROWN) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func _focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(2)
	sb.border_color = CREAM
	return sb


static func _progress_track() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = HP_TRACK
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = BROWN_DK
	return sb


static func _progress_fill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	return sb


# --- Assemble the Theme ----------------------------------------------------

static func build() -> Theme:
	var t := Theme.new()

	# Panels
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())

	# Shared type scale: default body size on the common text widgets so panels
	# stop needing per-widget font-size overrides. Any authored per-widget
	# override still wins over these defaults, so existing panels are unaffected.
	t.set_font_size("font_size", "Label", FONT_BODY)
	t.set_font_size("font_size", "Button", FONT_BODY)
	t.set_font_size("font_size", "OptionButton", FONT_BODY)

	# Labels default to dark ink (readable on the amber panels). Panels that
	# render text over darker plates set CREAM locally.
	t.set_color("font_color", "Label", INK)

	# Buttons: amber, brighten on hover, sink on press, cream focus ring.
	t.set_stylebox("normal", "Button", _button_box(AMBER_LITE))
	t.set_stylebox("hover", "Button", _button_box(AMBER_LITE.lightened(0.08)))
	t.set_stylebox("pressed", "Button", _button_box(AMBER_DK))
	# Disabled fill is pulled further from AMBER (and desaturated toward BROWN)
	# than before so the "greyed out" state is visually obvious, while
	# font_disabled_color (INK_SOFT, darkened below) still reads clearly on it
	# instead of washing out.
	t.set_stylebox("disabled", "Button", _button_box(AMBER.darkened(0.24).lerp(BROWN, 0.15), BROWN_DK))
	t.set_stylebox("focus", "Button", _focus_box())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", BROWN_DK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", INK_SOFT)

	# OptionButton (difficulty dropdown, etc.) mirrors Button.
	t.set_stylebox("normal", "OptionButton", _button_box(AMBER_LITE))
	t.set_stylebox("hover", "OptionButton", _button_box(AMBER_LITE.lightened(0.08)))
	t.set_stylebox("pressed", "OptionButton", _button_box(AMBER_DK))
	t.set_stylebox("focus", "OptionButton", _focus_box())
	t.set_color("font_color", "OptionButton", INK)

	# ProgressBar -> cyan HP-bar look.
	t.set_stylebox("background", "ProgressBar", _progress_track())
	t.set_stylebox("fill", "ProgressBar", _progress_fill(HP_CYAN))
	t.set_color("font_color", "ProgressBar", CREAM)

	return t


# --- Helpers ---------------------------------------------------------------

## Give a background Panel/PanelContainer node the amber card look, overriding any
## older (e.g. dark) stylebox it shipped with. Safe no-op on null.
static func style_panel_background(node: Control) -> void:
	if node != null and (node is Panel or node is PanelContainer):
		node.add_theme_stylebox_override("panel", panel_box())


## Apply the whole amber look to [param root] and its subtree: set the theme,
## amber-ify every panel background, and strip baked-in font colours / per-button
## colour styleboxes so everything shares the one look. Each HUD panel calls this
## on itself in _ready, so it works no matter when/where the panel is added.
static func apply_to(root: Control) -> void:
	if root == null:
		return
	root.theme = build()
	_restyle(root)


static func _restyle(node: Node) -> void:
	for child in node.get_children():
		if child is Panel or child is PanelContainer:
			style_panel_background(child)
		# Labels: drop any baked font colour so they inherit the panel default.
		if child is Label and child.has_theme_color_override("font_color"):
			child.remove_theme_color_override("font_color")
		# OptionButton IS-A Button, so test it FIRST (the more specific type):
		# dropdowns have no role hierarchy, so strip any baked overrides back to the
		# theme default rather than giving them a command-button role.
		if child is OptionButton:
			if child.has_theme_color_override("font_color"):
				child.remove_theme_color_override("font_color")
			for s in ["normal", "hover", "pressed", "disabled", "focus"]:
				if child.has_theme_stylebox_override(s):
					child.remove_theme_stylebox_override(s)
		# Plain buttons: apply the role variant (primary/secondary/destructive) instead
		# of stripping to a single flat amber -- preserves the command hierarchy.
		elif child is Button:
			apply_button_role(child)
		_restyle(child)


## Apply the amber command-button look for [param button]'s declared role, read
## from set_meta("style_role", ...). Three warm-palette weights:
##   "" / unknown / "primary" -> bright amber (default, highest weight)
##   "secondary"              -> muted amber-grey (low contrast, de-emphasised)
##   "destructive"            -> ember red-brown (a warning, still in-palette)
## Overrides normal/hover/pressed/disabled + the matching font colours, so a
## panel can tag intent once and get a consistent, hierarchy-preserving button.
static func apply_button_role(button: Button) -> void:
	var role := String(button.get_meta("style_role", ""))
	var fill: Color = BTN_PRIMARY
	var border: Color = BROWN
	var font: Color = INK
	var font_hover: Color = BROWN_DK
	var font_pressed: Color = CREAM
	match role:
		"secondary":
			fill = BTN_SECONDARY
			border = BROWN
		"destructive":
			fill = BTN_DESTRUCTIVE
			border = BROWN_DK
			# The red-brown fill is dark, so cream text keeps contrast in every state.
			font = CREAM
			font_hover = CREAM
			font_pressed = CREAM
		_:
			fill = BTN_PRIMARY
			border = BROWN
	button.add_theme_stylebox_override("normal", _button_box(fill, border))
	button.add_theme_stylebox_override("hover", _button_box(fill.lightened(0.08), border))
	button.add_theme_stylebox_override("pressed", _button_box(fill.darkened(0.16), border))
	button.add_theme_stylebox_override("disabled",
			_button_box(fill.darkened(0.24).lerp(BROWN, 0.15), BROWN_DK))
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_pressed)
	button.add_theme_color_override("font_disabled_color", INK_SOFT)


## Colour for a move/ability element tag; falls back to amber for unknowns.
static func element_color(element: String) -> Color:
	match element.to_lower():
		"ember", "fire": return EL_EMBER
		"frost", "water", "ice": return EL_FROST
		"arcane", "magic": return EL_ARCANE
		"holy", "light": return EL_HOLY
		"nature", "earth", "wind": return EL_NATURE
		"steel", "metal", "physical": return EL_STEEL
		_: return AMBER
