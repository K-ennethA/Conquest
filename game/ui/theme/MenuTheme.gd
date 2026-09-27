class_name MenuTheme
extends RefCounted

## The ONE theme for every out-of-battle screen (main menu, mode / turn-system /
## map / squad pickers, network lobby, Compendium, Arena setup), and the token +
## frame source the battle HUD ([ConquestTheme]) builds on. The look is
## "illuminated grove heraldry": deep navy cards drawn by [OrnateStyleBox] (notched
## corners, fine grain, inset gold filigree, gold clasps, crests on hero cards),
## Cinzel capitals for titles / headings / buttons, heraldic unit crests and
## element gems. See docs/UI_STYLE.md.
##
## Apply with [code]control.theme = MenuTheme.build()[/code] on a screen root; the
## subtree inherits it. Everything a screen needs beyond plain controls is exposed
## as a named THEME TYPE VARIATION (set [code]theme_type_variation[/code]) so
## screens never hand-roll styleboxes:
##
##   Buttons    "PrimaryButton"  gold call-to-action (Start / Confirm)
##              "GhostButton"    quiet secondary action (Back, Leave)
##              "MenuItem"       main-menu row (gold ribbon wash + leaf marker on focus)
##              "OptionCard"     big selectable card whose content is child labels
##   Panels     "Card"           grove-frame card (default PanelContainer look)
##              "CrestCard"      the same with the gold crest on its top edge
##              "InsetPanel"     sunken notched well (previews, lists, fields)
##              "Pill"           pointed tag chip (badges)
##              "Ribbon"         swallow-tailed title ribbon
##   Labels     "DisplayLabel"   game-title size   "TitleLabel"  screen title
##              "HeadingLabel"   pane heading      "SectionLabel" gold small caps
##              "DimLabel"       secondary text    "MutedLabel"   tertiary / hints
##
## Sizes are in the project's 1280x720 base units (canvas_items stretch), so body
## text (18) renders at ~22px on a 1600x900 window and ~27px at 1080p. Nothing is
## smaller than FS_CAPTION (15 -> ~19px at 1600x900).
##
## Contrast (WCAG, on PANEL): CREAM ~14:1, TEXT_DIM ~10:1, TEXT_MUTED ~6:1, INK on
## GOLD ~9:1 -- no low-contrast grey-on-dark text anywhere.

# --- Palette tokens ----------------------------------------------------------
const BG_DEEP := Color("0b0f1e")      # page ground / fade colour
const BG := Color("121833")           # backdrop gradient top
const PANEL := Color("172043")        # raised panel fill
const PANEL_HI := Color("223063")     # hover / focused fill
const PANEL_SUNK := Color("0e1430")   # inset wells, fields
const BORDER := Color("3a4b86")       # default panel / control edge
const BORDER_SOFT := Color("27345f")  # hairlines, separators
const GOLD := Color("e8b454")         # THE accent: focus, selection, headings
const GOLD_LITE := Color("f7d68a")
const GOLD_DK := Color("a97a2c")
const CREAM := Color("f5eedc")        # primary text
const TEXT_DIM := Color("cdd1e4")     # secondary text
const TEXT_MUTED := Color("9ba5c8")   # tertiary text / hints (still >= 6:1)
const INK := Color("141a30")          # text on gold
const ACCENT := Color("6cc4ff")       # info
const SUCCESS := Color("74d68e")
const DANGER := Color("ff8070")
const WARNING := Color("ffc857")
const TEAM_BLUE := Color("4a90d9")
const TEAM_RED := Color("d94a4a")

# Legacy aliases (older screens / galleries reference these names).
const DARK := BG_DEEP
const CREAM_DIM := TEXT_DIM

# --- Type scale (base units) --------------------------------------------------
const FS_DISPLAY := 72
const FS_TITLE := 40
const FS_HEADING := 26
const FS_SUBHEADING := 21
const FS_BODY := 18
const FS_SMALL := 16
const FS_CAPTION := 15

# --- Spacing scale ------------------------------------------------------------
const SP_XS := 4
const SP_S := 8
const SP_M := 12
const SP_L := 16
const SP_XL := 24
const SP_XXL := 32
const SP_PAGE := 48   # page side gutter

const RADIUS := 10


# --- Element crest palette (ONE source; ConquestTheme / MenuKit read these) -------
const EL_FIRE := Color("e8663a")      # ember
const EL_WATER := Color("2fb3a8")     # tide teal
const EL_NATURE := Color("6cbf4a")    # grove green
const EL_WIND := Color("9fc6e8")      # pale sky
const EL_EARTH := Color("d19a4a")     # amber / geode
const EL_HOLY := Color("f0c850")      # sun gold
const EL_DARK := Color("a172e0")      # blight violet
const EL_ARCANE := Color("b070e8")
const EL_STEEL := Color("c9cbd6")


# --- Fonts -------------------------------------------------------------------
# Display face: Cinzel (SIL OFL 1.1, fonts/Cinzel-OFL.txt) -- engraved Roman capitals
# for titles, headings, commands and crests. Body text stays the engine's sans
# for readability.
const FONT_DISPLAY_PATH := "res://game/ui/theme/fonts/Cinzel-Black.woff2"
const FONT_HEADING_PATH := "res://game/ui/theme/fonts/Cinzel-Bold.woff2"

static var _font_cache: Dictionary = {}


## The engine's default font, emboldened -- used for body emphasis (names, values).
static func bold_font(embolden: float = 0.55, spacing: int = 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = embolden
	if spacing != 0:
		fv.spacing_glyph = spacing
	return fv


static func _face(path: String) -> Font:
	if _font_cache.has(path):
		return _font_cache[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null:
		f = ThemeDB.fallback_font
	_font_cache[path] = f
	return f


## Cinzel Bold (headings, commands, section tags). Falls back to the engine font
## for glyphs Cinzel lacks (arrows, symbols).
static func heading_font(spacing: int = 1) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = _face(FONT_HEADING_PATH)
	fv.fallbacks = [ThemeDB.fallback_font]
	if spacing != 0:
		fv.spacing_glyph = spacing
	return fv


## Cinzel Black (screen titles, the game title, phase banners).
static func display_font(spacing: int = 2) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = _face(FONT_DISPLAY_PATH)
	fv.fallbacks = [ThemeDB.fallback_font]
	if spacing != 0:
		fv.spacing_glyph = spacing
	return fv


# --- Stylebox factories (public so screens can build one-off pieces) ----------

## A plain flat box (fields, bars, key caps -- anything that should stay quiet).
static func box(fill: Color, border: Color = BORDER, border_w: int = 2,
		radius: int = RADIUS, margin_h: float = 16.0, margin_v: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = true
	return sb


static func _margins(sb: StyleBox, h: float, v: float) -> void:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v


## The GROVE FRAME -- Conquest's signature card: notched corners, a gradient navy
## fill with a fine diagonal grain and soft inner vignette, the outer edge, an inset
## gold filigree line and gold clasps on the four notches. [param fill] / [param
## border] tint it; [param alpha] lets HUD cards sit translucently over the board.
static func card_box(fill: Color = PANEL, border: Color = BORDER, alpha: float = 0.96) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.shape = OrnateStyleBox.Shape.CHAMFER
	sb.corner = 13.0
	sb.bg_color = Color(fill.lightened(0.06), alpha)
	sb.bg_color_end = Color(fill.darkened(0.3), alpha)
	sb.border_color = border
	sb.border_width = 1.5
	sb.inner_line_color = Color(GOLD, 0.34)
	sb.inner_inset = 6.0
	sb.ornament = OrnateStyleBox.Ornament.CLASP
	sb.ornament_color = Color(GOLD, 0.95)
	sb.ornament_size = 3.4
	sb.hatch_alpha = 0.035
	sb.hatch_spacing = 5.0
	sb.vignette_alpha = 0.32
	sb.vignette_width = 18.0
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12.0
	sb.shadow_offset = Vector2(0, 5)
	_margins(sb, 22, 18)
	return sb


## A grove frame with a team / element stripe down one side and (optionally) the
## top crest -- unit cards, forecast sides, the command menu.
static func accented_card(accent: Color, side: Side = SIDE_LEFT, fill: Color = PANEL,
		alpha: float = 0.96, with_crest: bool = false) -> OrnateStyleBox:
	var sb := card_box(fill, accent.darkened(0.1), alpha)
	sb.accent_color = Color(accent, 0.9)
	sb.accent_side = side
	sb.accent_width = 4.0
	sb.crest = with_crest
	return sb


## Sunken well (previews, lists, stat plates): notched, darker, stronger vignette,
## no ornaments.
static func inset_box() -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.corner = 7.0
	sb.bg_color = Color(PANEL_SUNK.darkened(0.1), 0.92)
	sb.bg_color_end = Color(PANEL_SUNK.lightened(0.03), 0.92)
	sb.border_color = BORDER_SOFT
	sb.border_width = 1.0
	sb.hatch_alpha = 0.025
	sb.hatch_spacing = 5.0
	sb.vignette_alpha = 0.35
	sb.vignette_width = 10.0
	_margins(sb, 12, 10)
	return sb


## Pointed TAG chip (badges, statuses, squad slots).
static func pill_box(fill: Color, border: Color = Color(0, 0, 0, 0)) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.shape = OrnateStyleBox.Shape.TAG
	sb.corner = 9.0
	sb.bg_color = fill
	sb.border_color = border
	sb.border_width = 1.0 if border.a > 0.0 else 0.0
	_margins(sb, 14, 3)
	return sb


## Swallow-tailed RIBBON (card title strips, phase banners). [param notch] is the
## depth of the tails.
static func ribbon_box(fill: Color = PANEL_HI, border: Color = GOLD_DK, notch: float = 14.0) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.shape = OrnateStyleBox.Shape.BANNER
	sb.corner = notch
	sb.bg_color = fill.lightened(0.08)
	sb.bg_color_end = fill.darkened(0.25)
	sb.border_color = border
	sb.border_width = 1.5
	sb.inner_line_color = Color(GOLD, 0.3)
	sb.inner_inset = 4.0
	sb.hatch_alpha = 0.04
	sb.hatch_spacing = 5.0
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8.0
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = notch + 16.0
	sb.content_margin_right = notch + 16.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 6.0
	return sb


## Heraldic SHIELD for portraits / crests: element-coloured field, team-coloured rim,
## gold inner line.
static func crest_box(fill: Color, ring: Color, px: float = 48.0) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.shape = OrnateStyleBox.Shape.SHIELD
	sb.corner = maxf(3.0, px * 0.12)
	sb.bg_color = fill.darkened(0.15)
	sb.bg_color_end = fill.darkened(0.62)
	sb.border_color = ring
	sb.border_width = 3.0 if px >= 40.0 else 2.0
	sb.inner_line_color = Color(GOLD_LITE, 0.55)
	sb.inner_inset = 4.5 if px >= 40.0 else 3.5
	sb.hatch_alpha = 0.05
	sb.hatch_spacing = 4.0
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 4.0
	sb.shadow_offset = Vector2(0, 2)
	_margins(sb, 0, 0)
	# Lift the initial into the shield's broad upper body (the point is below).
	sb.content_margin_bottom = px * 0.16
	return sb


## A notched button plate.
static func plate_box(fill: Color, border: Color, corner: float = 8.0, margin_h: float = 20.0,
		margin_v: float = 11.0, border_w: float = 1.5) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.corner = corner
	sb.bg_color = fill.lightened(0.05) if fill.a > 0.0 else fill
	sb.bg_color_end = fill.darkened(0.2) if fill.a > 0.0 else fill
	sb.border_color = border
	sb.border_width = border_w
	sb.sheen = 0.07 if fill.a > 0.0 else 0.0
	_margins(sb, margin_h, margin_v)
	return sb


## Focus ring drawn OVER a control's normal/hover box: gold notched edge, soft glow
## and gold clasps -- unmistakable for keyboard / pad users.
static func focus_box(radius: int = RADIUS, color: Color = GOLD) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.draw_center = false
	sb.corner = float(radius) * 0.8 + 2.0
	sb.border_color = color
	sb.border_width = 2.5
	sb.expand_margin = 2.0
	sb.glow_color = Color(color, 0.32)
	sb.glow_size = 9.0
	sb.ornament = OrnateStyleBox.Ornament.CLASP
	sb.ornament_color = color.lightened(0.2)
	sb.ornament_size = 3.0
	sb.inner_inset = 2.0
	return sb


## Command-list / main-menu row: a gold ribbon wash that fades out to the right, a
## gold leaf marker at the left, and a hairline underline -- or fully clear at rest.
static func row_box(wash: Color, marker: Color, underline: Color, margin_l: float = 30.0,
		margin_r: float = 16.0, margin_v: float = 8.0) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.corner = 0.0
	sb.cut_corners = 0
	sb.gradient_horizontal = true
	sb.bg_color = wash
	sb.fade_out = true
	sb.draw_center = wash.a > 0.0
	sb.border_width = 0.0
	sb.marker_color = marker
	sb.marker_size = 7.0
	sb.accent_color = underline
	sb.accent_side = SIDE_BOTTOM
	sb.accent_width = 1.0
	sb.content_margin_left = margin_l
	sb.content_margin_right = margin_r
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


static func _menu_item_box(fill: Color, bar: Color) -> OrnateStyleBox:
	var sb := row_box(fill, bar, Color(bar, bar.a * 0.45), 38, 16, 8)
	sb.marker_size = 9.0
	return sb


# --- Theme assembly ------------------------------------------------------------

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_BODY
	var h_font := heading_font(1)
	var title_font := display_font(2)
	var disp_font := display_font(6)

	_build_panels(t)
	_build_labels(t, h_font, title_font, disp_font)
	_build_buttons(t, h_font)
	_build_inputs(t)
	_build_lists_and_tabs(t)
	return t


static func _build_panels(t: Theme) -> void:
	t.set_stylebox("panel", "Panel", card_box())
	t.set_stylebox("panel", "PanelContainer", card_box())
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", card_box())
	# CrestCard: the grove frame with the gold crest on its top edge (hero panels).
	t.set_type_variation("CrestCard", "PanelContainer")
	var crest_card := card_box()
	crest_card.crest = true
	t.set_stylebox("panel", "CrestCard", crest_card)
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", inset_box())
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", pill_box(PANEL_HI, BORDER))
	t.set_type_variation("Ribbon", "PanelContainer")
	t.set_stylebox("panel", "Ribbon", ribbon_box())

	var sep := StyleBoxLine.new()
	sep.color = Color(GOLD_DK, 0.55)
	sep.thickness = 1
	sep.grow_begin = -6
	sep.grow_end = -6
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER_SOFT
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	var tip := plate_box(PANEL_SUNK, GOLD_DK, 6.0, 12, 7, 1.0)
	tip.inner_line_color = Color(GOLD, 0.2)
	tip.inner_inset = 3.0
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)


static func _build_labels(t: Theme, h_font: Font, title_font: Font, disp_font: Font) -> void:
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "Label", FS_BODY)

	t.set_type_variation("DisplayLabel", "Label")
	t.set_font("font", "DisplayLabel", disp_font)
	t.set_font_size("font_size", "DisplayLabel", FS_DISPLAY)
	t.set_color("font_color", "DisplayLabel", GOLD_LITE)
	t.set_color("font_shadow_color", "DisplayLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "DisplayLabel", 0)
	t.set_constant("shadow_offset_y", "DisplayLabel", 5)
	t.set_color("font_outline_color", "DisplayLabel", Color("2a1804"))
	t.set_constant("outline_size", "DisplayLabel", 8)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title_font)
	t.set_font_size("font_size", "TitleLabel", FS_TITLE)
	t.set_color("font_color", "TitleLabel", GOLD_LITE)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_y", "TitleLabel", 3)

	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", h_font)
	t.set_font_size("font_size", "HeadingLabel", FS_HEADING)
	t.set_color("font_color", "HeadingLabel", CREAM)

	t.set_type_variation("SubheadingLabel", "Label")
	t.set_font("font", "SubheadingLabel", h_font)
	t.set_font_size("font_size", "SubheadingLabel", FS_SUBHEADING)
	t.set_color("font_color", "SubheadingLabel", CREAM)

	t.set_type_variation("SectionLabel", "Label")
	t.set_font("font", "SectionLabel", heading_font(2))
	t.set_font_size("font_size", "SectionLabel", FS_CAPTION)
	t.set_color("font_color", "SectionLabel", GOLD)

	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)

	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", TEXT_MUTED)
	t.set_font_size("font_size", "MutedLabel", FS_SMALL)

	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)


static func _build_buttons(t: Theme, h_font: Font) -> void:
	# Default Button: a notched navy plate; hover warms the edge to gold; focus adds
	# the gold ring + clasps; a toggled-on (pressed) button turns gold with ink text.
	var normal := plate_box(Color(PANEL, 0.94), BORDER)
	var hover := plate_box(PANEL_HI, GOLD_DK)
	hover.inner_line_color = Color(GOLD, 0.22)
	hover.inner_inset = 4.0
	var pressed := plate_box(GOLD, GOLD_LITE)
	pressed.sheen = 0.3
	var disabled := plate_box(Color(PANEL_SUNK, 0.7), BORDER_SOFT)
	disabled.sheen = 0.0
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, plate_box(GOLD_LITE, CREAM))
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus_box(8))
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, GOLD_LITE)
		t.set_color("font_focus_color", type, GOLD_LITE)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_disabled_color", type, Color(TEXT_MUTED, 0.85))
		t.set_font_size("font_size", type, FS_BODY)
		t.set_font("font", type, h_font)
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("arrow_margin", "OptionButton", 12)

	# PrimaryButton: the gilded call-to-action -- a pointed gold TAG with an inked
	# inner line, Cinzel caps.
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _primary_box(GOLD, GOLD_LITE))
	t.set_stylebox("hover", "PrimaryButton", _primary_box(GOLD_LITE, CREAM))
	t.set_stylebox("pressed", "PrimaryButton", _primary_box(GOLD_DK, GOLD))
	var pdis := _primary_box(PANEL_SUNK, BORDER_SOFT)
	pdis.inner_line_color = Color(BORDER_SOFT, 0.6)
	pdis.sheen = 0.0
	t.set_stylebox("disabled", "PrimaryButton", pdis)
	var pfocus := focus_box(RADIUS, CREAM)
	pfocus.shape = OrnateStyleBox.Shape.TAG
	pfocus.corner = 20.0
	pfocus.expand_margin = 3.0
	t.set_stylebox("focus", "PrimaryButton", pfocus)
	t.set_color("font_color", "PrimaryButton", INK)
	t.set_color("font_hover_color", "PrimaryButton", INK)
	t.set_color("font_focus_color", "PrimaryButton", INK)
	t.set_color("font_pressed_color", "PrimaryButton", INK)
	t.set_color("font_disabled_color", "PrimaryButton", TEXT_MUTED)
	t.set_font("font", "PrimaryButton", h_font)
	t.set_font_size("font_size", "PrimaryButton", FS_SUBHEADING)

	# GhostButton: quiet secondary action -- a clear notched outline.
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", plate_box(Color(0, 0, 0, 0.22), BORDER, 8.0, 22, 11))
	var ghov := plate_box(Color(PANEL_HI, 0.7), GOLD_DK, 8.0, 22, 11)
	ghov.inner_line_color = Color(GOLD, 0.2)
	ghov.inner_inset = 4.0
	t.set_stylebox("hover", "GhostButton", ghov)
	t.set_stylebox("pressed", "GhostButton", plate_box(PANEL_SUNK, GOLD_DK, 8.0, 22, 11))
	t.set_color("font_color", "GhostButton", TEXT_DIM)
	t.set_color("font_pressed_color", "GhostButton", GOLD_LITE)
	t.set_font("font", "GhostButton", h_font)

	# MenuItem: main-menu entries. Clear at rest; hover / focus unfurl a gold ribbon
	# wash with a leaf marker at the left, like an illuminated command list.
	t.set_type_variation("MenuItem", "Button")
	t.set_stylebox("normal", "MenuItem", _menu_item_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "MenuItem", _menu_item_box(Color(GOLD_DK, 0.2), Color(GOLD_DK, 0.9)))
	t.set_stylebox("pressed", "MenuItem", _menu_item_box(Color(GOLD, 0.34), GOLD_LITE))
	t.set_stylebox("focus", "MenuItem", _menu_item_box(Color(GOLD, 0.26), GOLD))
	t.set_color("font_color", "MenuItem", TEXT_DIM)
	t.set_color("font_hover_color", "MenuItem", CREAM)
	t.set_color("font_focus_color", "MenuItem", GOLD_LITE)
	t.set_color("font_pressed_color", "MenuItem", GOLD_LITE)
	t.set_color("font_hover_pressed_color", "MenuItem", GOLD_LITE)
	t.set_font("font", "MenuItem", heading_font(2))
	t.set_font_size("font_size", "MenuItem", 26)

	# OptionCard: a big selectable grove-frame card. Content is CHILD labels, so the
	# toggled-on state keeps a dark fill (labels stay readable) and says "selected"
	# with a gold frame, bright clasps and the top crest.
	t.set_type_variation("OptionCard", "Button")
	var oc := option_card_boxes()
	for state in oc:
		t.set_stylebox(state, "OptionCard", oc[state])
	var oc_focus := focus_box(14)
	oc_focus.corner = 15.0
	t.set_stylebox("focus", "OptionCard", oc_focus)


## The OptionCard state boxes (normal / hover / pressed / hover_pressed / disabled),
## optionally with an [param accent] stripe down the left edge (element / team).
static func option_card_boxes(accent: Color = Color(0, 0, 0, 0)) -> Dictionary:
	var normal := card_box()
	var hover := card_box(PANEL_HI, GOLD_DK)
	hover.inner_line_color = Color(GOLD, 0.5)
	var sel := card_box(PANEL_HI.lerp(GOLD_DK, 0.2), GOLD)
	sel.border_width = 2.5
	sel.inner_line_color = Color(GOLD_LITE, 0.6)
	sel.ornament_color = GOLD_LITE
	sel.crest = true
	var dis := card_box(PANEL_SUNK, BORDER_SOFT)
	dis.ornament_color = Color(GOLD_DK, 0.4)
	dis.inner_line_color = Color(GOLD, 0.12)
	if accent.a > 0.0:
		for sb in [normal, hover, sel]:
			sb.accent_color = Color(accent, 0.95)
			sb.accent_side = SIDE_LEFT
			sb.accent_width = 4.0
		dis.accent_color = Color(accent, 0.35)
		dis.accent_width = 4.0
	return {"normal": normal, "hover": hover, "pressed": sel, "hover_pressed": sel,
		"disabled": dis}


static func _primary_box(fill: Color, border: Color) -> OrnateStyleBox:
	var sb := OrnateStyleBox.new()
	sb.shape = OrnateStyleBox.Shape.TAG
	sb.corner = 18.0
	sb.bg_color = fill.lightened(0.12)
	sb.bg_color_end = fill.darkened(0.12)
	sb.border_color = border
	sb.border_width = 1.5
	sb.inner_line_color = Color(INK, 0.45)
	sb.inner_inset = 4.0
	sb.sheen = 0.35
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6.0
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func _build_inputs(t: Theme) -> void:
	var field := plate_box(PANEL_SUNK, BORDER, 6.0, 12, 9)
	field.sheen = 0.0
	var field_focus := plate_box(PANEL_SUNK, GOLD, 6.0, 12, 9)
	field_focus.sheen = 0.0
	var field_ro := plate_box(Color(PANEL_SUNK, 0.6), BORDER_SOFT, 6.0, 12, 9)
	field_ro.sheen = 0.0
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focus_box(6))
	t.set_stylebox("read_only", "LineEdit", field_ro)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("font_uneditable_color", "LineEdit", TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", GOLD_LITE)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	t.set_font_size("font_size", "LineEdit", FS_BODY)
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)

	# Check / toggle buttons: text only (the engine's toggle icon stays).
	var clear := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 10, 8)
	var wash := row_box(Color(GOLD_DK, 0.16), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10, 10, 8)
	for type in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, clear)
		t.set_stylebox("hover", type, wash)
		t.set_stylebox("pressed", type, clear)
		t.set_stylebox("hover_pressed", type, wash)
		t.set_stylebox("focus", type, focus_box(6))
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, GOLD_LITE)
		t.set_color("font_pressed_color", type, GOLD_LITE)
		t.set_color("font_hover_pressed_color", type, GOLD_LITE)
		t.set_color("font_focus_color", type, GOLD_LITE)
		t.set_font_size("font_size", type, FS_BODY)

	# Popups (OptionButton lists).
	var pop := plate_box(PANEL_SUNK, GOLD_DK, 8.0, 6, 6)
	pop.inner_line_color = Color(GOLD, 0.18)
	pop.inner_inset = 3.0
	pop.sheen = 0.0
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", row_box(Color(GOLD, 0.28), GOLD, Color(0, 0, 0, 0), 24, 8, 4))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", GOLD_LITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)
	t.set_font_size("font_size", "PopupMenu", FS_BODY)
	t.set_constant("v_separation", "PopupMenu", 10)

	# Sliders / progress.
	t.set_stylebox("slider", "HSlider", box(PANEL_SUNK, BORDER, 1, 2, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(GOLD_DK, GOLD_DK, 0, 2, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, GOLD, 0, 2, 0, 3))
	t.set_stylebox("background", "ProgressBar", box(PANEL_SUNK, BORDER_SOFT, 1, 2, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, GOLD, 0, 2, 0, 0))
	t.set_color("font_color", "ProgressBar", CREAM)


static func _build_lists_and_tabs(t: Theme) -> void:
	# ItemList: dark rows, gold selection.
	t.set_stylebox("panel", "ItemList", inset_box())
	t.set_stylebox("focus", "ItemList", focus_box(8))
	t.set_color("font_color", "ItemList", CREAM)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", GOLD_LITE)
	t.set_color("font_hovered_selected_color", "ItemList", INK)
	t.set_color("guide_color", "ItemList", Color(BORDER_SOFT, 0.6))
	t.set_font_size("font_size", "ItemList", FS_BODY)
	t.set_constant("v_separation", "ItemList", 8)
	var sel := plate_box(GOLD, GOLD_LITE, 5.0, 8, 4, 0.0)
	sel.sheen = 0.25
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("hovered", "ItemList", row_box(Color(GOLD_DK, 0.25), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8, 8, 4))
	var hsel := plate_box(GOLD_LITE, CREAM, 5.0, 8, 4, 0.0)
	t.set_stylebox("hovered_selected", "ItemList", hsel)
	t.set_stylebox("hovered_selected_focus", "ItemList", hsel)
	var cursor := plate_box(Color(0, 0, 0, 0), GOLD_LITE, 5.0, 8, 4, 1.5)
	cursor.draw_center = false
	t.set_stylebox("cursor", "ItemList", cursor)
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())

	# Tabs: the selected tab is a notched navy plate with a gold top edge.
	var top_cuts := OrnateStyleBox.CUT_TL | OrnateStyleBox.CUT_TR
	var tab_sel := plate_box(PANEL, GOLD_DK, 9.0, 22, 10, 1.0)
	tab_sel.cut_corners = top_cuts
	tab_sel.accent_color = GOLD
	tab_sel.accent_side = SIDE_TOP
	tab_sel.accent_width = 3.0
	tab_sel.hatch_alpha = 0.03
	var tab_un := plate_box(Color(PANEL_SUNK, 0.85), BORDER_SOFT, 9.0, 22, 10, 1.0)
	tab_un.cut_corners = top_cuts
	tab_un.sheen = 0.0
	var tab_hov := plate_box(PANEL_HI, BORDER, 9.0, 22, 10, 1.0)
	tab_hov.cut_corners = top_cuts
	var tab_focus := focus_box(8)
	tab_focus.cut_corners = top_cuts
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_sel)
		t.set_stylebox("tab_unselected", type, tab_un)
		t.set_stylebox("tab_hovered", type, tab_hov)
		t.set_stylebox("tab_focus", type, tab_focus)
		t.set_stylebox("tab_disabled", type, tab_un)
		t.set_color("font_selected_color", type, GOLD_LITE)
		t.set_color("font_unselected_color", type, TEXT_DIM)
		t.set_color("font_hovered_color", type, CREAM)
		t.set_font_size("font_size", type, FS_BODY)
		t.set_font("font", type, heading_font(1))
		t.set_constant("h_separation", type, 4)
	var tab_panel := card_box(PANEL, BORDER_SOFT, 0.92)
	tab_panel.cut_corners = OrnateStyleBox.CUT_TR | OrnateStyleBox.CUT_BR | OrnateStyleBox.CUT_BL
	tab_panel.shadow_size = 0.0
	_margins(tab_panel, 16, 14)
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# Scrollbars: slim gold grabber in a dark track.
	for type in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(PANEL_SUNK, 0.5), Color(0, 0, 0, 0), 0, 2, 4, 4)
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, box(GOLD_DK, GOLD_DK, 0, 2, 4, 4))
		t.set_stylebox("grabber_highlight", type, box(GOLD, GOLD, 0, 2, 4, 4))
		t.set_stylebox("grabber_pressed", type, box(GOLD_LITE, GOLD_LITE, 0, 2, 4, 4))
