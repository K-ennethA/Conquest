class_name MenuTheme
extends RefCounted

## The ONE theme for every out-of-battle screen (main menu, mode / turn-system /
## map / squad pickers, network lobby, Compendium, Arena setup). Deep navy panels,
## warm gold accents and cream text -- the "royal war-table" register of modern
## tactics menus -- tying back to the amber battle HUD ([ConquestTheme]) through
## the shared gold.
##
## Apply with [code]control.theme = MenuTheme.build()[/code] on a screen root; the
## subtree inherits it. Everything a screen needs beyond plain controls is exposed
## as a named THEME TYPE VARIATION (set [code]theme_type_variation[/code]) so
## screens never hand-roll styleboxes:
##
##   Buttons    "PrimaryButton"  gold call-to-action (Start / Confirm)
##              "GhostButton"    quiet secondary action (Back, Leave)
##              "MenuItem"       main-menu list entry (left aligned, gold bar on focus)
##              "OptionCard"     big selectable card whose content is child labels
##   Panels     "Card"           raised panel (default PanelContainer look)
##              "InsetPanel"     sunken well (previews, lists, fields)
##              "Pill"           small rounded chip background (badges, key glyphs)
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


# --- Fonts -------------------------------------------------------------------

## The engine's default font, emboldened -- used for titles and headings.
static func bold_font(embolden: float = 0.55, spacing: int = 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = embolden
	if spacing != 0:
		fv.spacing_glyph = spacing
	return fv


# --- Stylebox factories (public so screens can build one-off pieces) ----------

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


## Raised card: translucent navy, soft edge, drop shadow.
static func card_box(fill: Color = PANEL, border: Color = BORDER) -> StyleBoxFlat:
	var sb := box(Color(fill.r, fill.g, fill.b, 0.94), border, 1, 14, 20, 18)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func inset_box() -> StyleBoxFlat:
	return box(Color(PANEL_SUNK.r, PANEL_SUNK.g, PANEL_SUNK.b, 0.9), BORDER_SOFT, 1, 10, 12, 10)


static func pill_box(fill: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := box(fill, border, 1 if border.a > 0.0 else 0, 999, 10, 3)
	return sb


## Focus ring drawn OVER a control's normal/hover box: thick gold edge + glow.
static func focus_box(radius: int = RADIUS, color: Color = GOLD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(3)
	sb.border_color = color
	sb.set_expand_margin_all(2)
	sb.shadow_color = Color(color.r, color.g, color.b, 0.22)
	sb.shadow_size = 8
	sb.anti_aliasing = true
	return sb


static func _menu_item_box(fill: Color, bar: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_width_left = 5
	sb.border_color = bar
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 22
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb


# --- Theme assembly ------------------------------------------------------------

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_BODY
	var heading_font := bold_font(0.5)
	var title_font := bold_font(0.7, 2)
	var display_font := bold_font(0.9, 10)

	_build_panels(t)
	_build_labels(t, heading_font, title_font, display_font)
	_build_buttons(t, heading_font)
	_build_inputs(t)
	_build_lists_and_tabs(t)
	return t


static func _build_panels(t: Theme) -> void:
	t.set_stylebox("panel", "Panel", card_box())
	t.set_stylebox("panel", "PanelContainer", card_box())
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", card_box())
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", inset_box())
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", pill_box(PANEL_HI, BORDER))

	var sep := StyleBoxLine.new()
	sep.color = BORDER_SOFT
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER_SOFT
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	t.set_stylebox("panel", "TooltipPanel", box(PANEL_SUNK, GOLD_DK, 1, 6, 10, 6))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)


static func _build_labels(t: Theme, heading_font: Font, title_font: Font, display_font: Font) -> void:
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "Label", FS_BODY)

	t.set_type_variation("DisplayLabel", "Label")
	t.set_font("font", "DisplayLabel", display_font)
	t.set_font_size("font_size", "DisplayLabel", FS_DISPLAY)
	t.set_color("font_color", "DisplayLabel", GOLD_LITE)
	t.set_color("font_shadow_color", "DisplayLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "DisplayLabel", 0)
	t.set_constant("shadow_offset_y", "DisplayLabel", 4)
	t.set_color("font_outline_color", "DisplayLabel", Color("3a2408"))
	t.set_constant("outline_size", "DisplayLabel", 6)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title_font)
	t.set_font_size("font_size", "TitleLabel", FS_TITLE)
	t.set_color("font_color", "TitleLabel", CREAM)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_y", "TitleLabel", 3)

	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", heading_font)
	t.set_font_size("font_size", "HeadingLabel", FS_HEADING)
	t.set_color("font_color", "HeadingLabel", CREAM)

	t.set_type_variation("SubheadingLabel", "Label")
	t.set_font("font", "SubheadingLabel", heading_font)
	t.set_font_size("font_size", "SubheadingLabel", FS_SUBHEADING)
	t.set_color("font_color", "SubheadingLabel", CREAM)

	t.set_type_variation("SectionLabel", "Label")
	t.set_font("font", "SectionLabel", bold_font(0.45, 2))
	t.set_font_size("font_size", "SectionLabel", FS_CAPTION)
	t.set_color("font_color", "SectionLabel", GOLD)

	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)

	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", TEXT_MUTED)
	t.set_font_size("font_size", "MutedLabel", FS_SMALL)

	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)


static func _build_buttons(t: Theme, heading_font: Font) -> void:
	# Default Button: navy plate; hover lifts it; focus adds the gold ring; a
	# toggled-on (pressed) button turns gold with dark ink text.
	var normal := box(Color(PANEL.r, PANEL.g, PANEL.b, 0.92), BORDER, 2, RADIUS, 20, 11)
	var hover := box(PANEL_HI, GOLD_DK, 2, RADIUS, 20, 11)
	var pressed := box(GOLD, GOLD_LITE, 2, RADIUS, 20, 11)
	var disabled := box(Color(PANEL_SUNK.r, PANEL_SUNK.g, PANEL_SUNK.b, 0.7), BORDER_SOFT, 2, RADIUS, 20, 11)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, box(GOLD_LITE, GOLD_LITE, 2, RADIUS, 20, 11))
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus_box())
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, GOLD_LITE)
		t.set_color("font_focus_color", type, GOLD_LITE)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_disabled_color", type, Color(TEXT_MUTED.r, TEXT_MUTED.g, TEXT_MUTED.b, 0.85))
		t.set_font_size("font_size", type, FS_BODY)
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("arrow_margin", "OptionButton", 12)

	# PrimaryButton: the gold call-to-action.
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(GOLD, GOLD_LITE, 2, RADIUS, 28, 12))
	t.set_stylebox("hover", "PrimaryButton", box(GOLD_LITE, CREAM, 2, RADIUS, 28, 12))
	t.set_stylebox("pressed", "PrimaryButton", box(GOLD_DK, GOLD, 2, RADIUS, 28, 12))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(PANEL_SUNK.r, PANEL_SUNK.g, PANEL_SUNK.b, 0.8), BORDER_SOFT, 2, RADIUS, 28, 12))
	t.set_stylebox("focus", "PrimaryButton", focus_box(RADIUS, CREAM))
	t.set_color("font_color", "PrimaryButton", INK)
	t.set_color("font_hover_color", "PrimaryButton", INK)
	t.set_color("font_focus_color", "PrimaryButton", INK)
	t.set_color("font_pressed_color", "PrimaryButton", INK)
	t.set_color("font_disabled_color", "PrimaryButton", TEXT_MUTED)
	t.set_font("font", "PrimaryButton", heading_font)
	t.set_font_size("font_size", "PrimaryButton", FS_SUBHEADING)

	# GhostButton: quiet secondary action.
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", box(Color(0, 0, 0, 0.18), BORDER_SOFT, 2, RADIUS, 22, 11))
	t.set_stylebox("hover", "GhostButton", box(Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.7), GOLD_DK, 2, RADIUS, 22, 11))
	t.set_stylebox("pressed", "GhostButton", box(PANEL_SUNK, GOLD_DK, 2, RADIUS, 22, 11))
	t.set_color("font_color", "GhostButton", TEXT_DIM)
	t.set_color("font_pressed_color", "GhostButton", GOLD_LITE)

	# MenuItem: main-menu entries. Transparent at rest; focus/hover light a gold
	# bar on the left with a navy wash, like a tactics-game command list.
	t.set_type_variation("MenuItem", "Button")
	t.set_stylebox("normal", "MenuItem", _menu_item_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "MenuItem", _menu_item_box(Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.55), GOLD_DK))
	t.set_stylebox("pressed", "MenuItem", _menu_item_box(Color(GOLD.r, GOLD.g, GOLD.b, 0.25), GOLD_LITE))
	var mi_focus := _menu_item_box(Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.85), GOLD)
	mi_focus.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.18)
	mi_focus.shadow_size = 10
	t.set_stylebox("focus", "MenuItem", mi_focus)
	t.set_color("font_color", "MenuItem", TEXT_DIM)
	t.set_color("font_hover_color", "MenuItem", CREAM)
	t.set_color("font_focus_color", "MenuItem", GOLD_LITE)
	t.set_color("font_pressed_color", "MenuItem", GOLD_LITE)
	t.set_font("font", "MenuItem", heading_font)
	t.set_font_size("font_size", "MenuItem", 27)

	# OptionCard: a big selectable card. Content is CHILD labels, so the
	# toggled-on state keeps a dark fill (labels stay readable) and says
	# "selected" with a thick gold frame + warm tint instead.
	t.set_type_variation("OptionCard", "Button")
	var oc_normal := card_box()
	oc_normal.set_border_width_all(2)
	t.set_stylebox("normal", "OptionCard", oc_normal)
	var oc_hover := card_box(PANEL_HI, GOLD_DK)
	oc_hover.set_border_width_all(2)
	t.set_stylebox("hover", "OptionCard", oc_hover)
	var oc_sel := card_box(PANEL_HI.lerp(GOLD_DK, 0.22), GOLD)
	oc_sel.set_border_width_all(3)
	t.set_stylebox("pressed", "OptionCard", oc_sel)
	t.set_stylebox("hover_pressed", "OptionCard", oc_sel)
	var oc_dis := card_box(PANEL_SUNK, BORDER_SOFT)
	t.set_stylebox("disabled", "OptionCard", oc_dis)
	var oc_focus := focus_box(14)
	oc_focus.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.16)
	oc_focus.shadow_size = 10
	t.set_stylebox("focus", "OptionCard", oc_focus)


static func _build_inputs(t: Theme) -> void:
	var field := box(PANEL_SUNK, BORDER, 2, 8, 12, 9)
	var field_focus := box(PANEL_SUNK, GOLD, 2, 8, 12, 9)
	var field_ro := box(Color(PANEL_SUNK.r, PANEL_SUNK.g, PANEL_SUNK.b, 0.6), BORDER_SOFT, 2, 8, 12, 9)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focus_box(8))
	t.set_stylebox("read_only", "LineEdit", field_ro)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("font_uneditable_color", "LineEdit", TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", GOLD_LITE)
	t.set_color("selection_color", "LineEdit", Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
	t.set_font_size("font_size", "LineEdit", FS_BODY)
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)

	# Check / toggle buttons: text only (the engine's toggle icon stays).
	for type in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 10, 8))
		t.set_stylebox("hover", type, box(Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.6), Color(0, 0, 0, 0), 0, 8, 10, 8))
		t.set_stylebox("pressed", type, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 10, 8))
		t.set_stylebox("hover_pressed", type, box(Color(PANEL_HI.r, PANEL_HI.g, PANEL_HI.b, 0.6), Color(0, 0, 0, 0), 0, 8, 10, 8))
		t.set_stylebox("focus", type, focus_box(8))
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, GOLD_LITE)
		t.set_color("font_pressed_color", type, GOLD_LITE)
		t.set_color("font_hover_pressed_color", type, GOLD_LITE)
		t.set_color("font_focus_color", type, GOLD_LITE)
		t.set_font_size("font_size", type, FS_BODY)

	# Popups (OptionButton lists).
	t.set_stylebox("panel", "PopupMenu", box(PANEL_SUNK, GOLD_DK, 2, 8, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(PANEL_HI, GOLD, 1, 6, 8, 4))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", GOLD_LITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)
	t.set_font_size("font_size", "PopupMenu", FS_BODY)
	t.set_constant("v_separation", "PopupMenu", 10)

	# Sliders / progress.
	t.set_stylebox("slider", "HSlider", box(PANEL_SUNK, BORDER, 1, 4, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(GOLD_DK, GOLD_DK, 0, 4, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, GOLD, 0, 4, 0, 3))
	t.set_stylebox("background", "ProgressBar", box(PANEL_SUNK, BORDER_SOFT, 1, 4, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, GOLD, 0, 4, 0, 0))
	t.set_color("font_color", "ProgressBar", CREAM)


static func _build_lists_and_tabs(t: Theme) -> void:
	# ItemList: dark rows, gold selection.
	t.set_stylebox("panel", "ItemList", inset_box())
	t.set_stylebox("focus", "ItemList", focus_box(10))
	t.set_color("font_color", "ItemList", CREAM)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", GOLD_LITE)
	t.set_color("font_hovered_selected_color", "ItemList", INK)
	t.set_color("guide_color", "ItemList", Color(BORDER_SOFT.r, BORDER_SOFT.g, BORDER_SOFT.b, 0.6))
	t.set_font_size("font_size", "ItemList", FS_BODY)
	t.set_constant("v_separation", "ItemList", 8)
	var sel := box(GOLD, GOLD, 0, 6, 8, 4)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("hovered", "ItemList", box(PANEL_HI, PANEL_HI, 0, 6, 8, 4))
	t.set_stylebox("hovered_selected", "ItemList", box(GOLD_LITE, GOLD_LITE, 0, 6, 8, 4))
	t.set_stylebox("hovered_selected_focus", "ItemList", box(GOLD_LITE, GOLD_LITE, 0, 6, 8, 4))
	var cursor := box(Color(0, 0, 0, 0), GOLD_LITE, 2, 6, 8, 4)
	cursor.draw_center = false
	t.set_stylebox("cursor", "ItemList", cursor)
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())

	# Tabs: selected tab is a raised navy plate with a gold top edge.
	var tab_sel := box(PANEL, BORDER, 0, 0, 22, 10)
	tab_sel.border_width_top = 3
	tab_sel.border_color = GOLD
	tab_sel.corner_radius_top_left = 8
	tab_sel.corner_radius_top_right = 8
	var tab_un := box(Color(PANEL_SUNK.r, PANEL_SUNK.g, PANEL_SUNK.b, 0.85), BORDER_SOFT, 0, 0, 22, 10)
	tab_un.corner_radius_top_left = 8
	tab_un.corner_radius_top_right = 8
	var tab_hov := box(PANEL_HI, BORDER, 0, 0, 22, 10)
	tab_hov.corner_radius_top_left = 8
	tab_hov.corner_radius_top_right = 8
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_sel)
		t.set_stylebox("tab_unselected", type, tab_un)
		t.set_stylebox("tab_hovered", type, tab_hov)
		t.set_stylebox("tab_focus", type, focus_box(8))
		t.set_stylebox("tab_disabled", type, tab_un)
		t.set_color("font_selected_color", type, GOLD_LITE)
		t.set_color("font_unselected_color", type, TEXT_DIM)
		t.set_color("font_hovered_color", type, CREAM)
		t.set_font_size("font_size", type, FS_BODY)
		t.set_constant("h_separation", type, 4)
	var tab_panel := box(Color(PANEL.r, PANEL.g, PANEL.b, 0.9), BORDER_SOFT, 1, 0, 16, 14)
	tab_panel.corner_radius_bottom_left = 12
	tab_panel.corner_radius_bottom_right = 12
	tab_panel.corner_radius_top_right = 12
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# Scrollbars: slim gold grabber in a dark track.
	for type in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(PANEL_SUNK.r, PANEL_SUNK.g, PANEL_SUNK.b, 0.5), Color(0, 0, 0, 0), 0, 6, 4, 4)
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, box(GOLD_DK, GOLD_DK, 0, 6, 4, 4))
		t.set_stylebox("grabber_highlight", type, box(GOLD, GOLD, 0, 6, 4, 4))
		t.set_stylebox("grabber_pressed", type, box(GOLD_LITE, GOLD_LITE, 0, 6, 4, 4))
