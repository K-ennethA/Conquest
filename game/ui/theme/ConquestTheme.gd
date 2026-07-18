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
const AMBER := Color("e6a64b")
const AMBER_LITE := Color("f0c072")
const AMBER_DK := Color("c6822f")
const BROWN := Color("5a3a1e")
const BROWN_DK := Color("37220f")
const INK := Color("43290f")
const INK_SOFT := Color("7a5a38")
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

	# Labels default to dark ink (readable on the amber panels). Panels that
	# render text over darker plates set CREAM locally.
	t.set_color("font_color", "Label", INK)

	# Buttons: amber, brighten on hover, sink on press, cream focus ring.
	t.set_stylebox("normal", "Button", _button_box(AMBER_LITE))
	t.set_stylebox("hover", "Button", _button_box(AMBER_LITE.lightened(0.08)))
	t.set_stylebox("pressed", "Button", _button_box(AMBER_DK))
	t.set_stylebox("disabled", "Button", _button_box(AMBER.darkened(0.12), BROWN_DK))
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


## Colour for a move/ability element tag; falls back to amber for unknowns.
static func element_color(element: String) -> Color:
	match element.to_lower():
		"ember", "fire": return EL_EMBER
		"frost", "water", "ice": return EL_FROST
		"arcane", "magic": return EL_ARCANE
		"holy", "light": return EL_HOLY
		"nature", "earth": return EL_NATURE
		_: return AMBER
