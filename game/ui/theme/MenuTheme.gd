class_name MenuTheme
extends RefCounted

## Theme for the out-of-battle menus (main menu, setup, map/roster select) in the
## sleeker dark "Pokemon Legends" register: deep translucent panels, light cream
## text, and a warm gold accent that ties back to the battle HUD ([ConquestTheme]).
## Apply with [code]control.theme = MenuTheme.build()[/code] on a menu scene root.

const DARK := Color("17141f")
const PANEL := Color("1c1930")
const PANEL_HI := Color("2a2542")
const BORDER := Color("4a4368")
const GOLD := Color("e6a64b")
const GOLD_DK := Color("b27f2b")
const CREAM := Color("f2ead6")
const CREAM_DIM := Color("b7adc6")
const INK := Color("17141f")


static func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.bg_color.a = 0.94
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = BORDER
	sb.set_content_margin_all(12)
	return sb


static func _button_box(fill: Color, border: Color, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func _selected_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func build() -> Theme:
	var t := Theme.new()

	# Panels
	t.set_stylebox("panel", "Panel", _panel_box())
	t.set_stylebox("panel", "PanelContainer", _panel_box())

	# Labels: light cream on the dark ground.
	t.set_color("font_color", "Label", CREAM)

	# Buttons: dark translucent, gold-edged on hover, gold text on hover/press.
	t.set_stylebox("normal", "Button", _button_box(Color(PANEL.r, PANEL.g, PANEL.b, 0.85), BORDER))
	t.set_stylebox("hover", "Button", _button_box(PANEL_HI, GOLD, 2))
	t.set_stylebox("pressed", "Button", _button_box(DARK, GOLD_DK, 2))
	t.set_stylebox("disabled", "Button", _button_box(Color(PANEL.r, PANEL.g, PANEL.b, 0.5), BORDER))
	var focus := _button_box(Color(0, 0, 0, 0), GOLD, 2)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", CREAM_DIM)

	# OptionButton mirrors Button.
	t.set_stylebox("normal", "OptionButton", _button_box(Color(PANEL.r, PANEL.g, PANEL.b, 0.85), BORDER))
	t.set_stylebox("hover", "OptionButton", _button_box(PANEL_HI, GOLD, 2))
	t.set_stylebox("pressed", "OptionButton", _button_box(DARK, GOLD_DK, 2))
	t.set_stylebox("focus", "OptionButton", focus)
	t.set_color("font_color", "OptionButton", CREAM)
	t.set_color("font_hover_color", "OptionButton", GOLD)

	# ItemList (map/roster lists): dark rows, gold selection.
	t.set_stylebox("panel", "ItemList", _panel_box())
	t.set_color("font_color", "ItemList", CREAM)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", GOLD)
	t.set_stylebox("selected", "ItemList", _selected_box(GOLD))
	t.set_stylebox("selected_focus", "ItemList", _selected_box(GOLD))
	t.set_stylebox("hovered", "ItemList", _selected_box(PANEL_HI))
	t.set_stylebox("cursor", "ItemList", _button_box(Color(0, 0, 0, 0), GOLD, 1))
	t.set_stylebox("cursor_unfocused", "ItemList", _button_box(Color(0, 0, 0, 0), BORDER, 1))

	# LineEdit (address/port/name fields on the network screens).
	var line_box := _button_box(Color(DARK.r, DARK.g, DARK.b, 0.85), BORDER)
	t.set_stylebox("normal", "LineEdit", line_box)
	t.set_stylebox("focus", "LineEdit", _button_box(Color(DARK.r, DARK.g, DARK.b, 0.9), GOLD, 2))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", CREAM_DIM)
	t.set_color("caret_color", "LineEdit", GOLD)

	# "SelectedButton" variation: a chosen option reads as a solid gold chip with
	# ink text, replacing the old modulate-tint hack. Apply per-button with
	# [code]button.theme_type_variation = "SelectedButton"[/code].
	t.set_type_variation("SelectedButton", "Button")
	t.set_stylebox("normal", "SelectedButton", _button_box(GOLD, GOLD, 2))
	t.set_stylebox("hover", "SelectedButton", _button_box(GOLD, CREAM, 2))
	t.set_stylebox("pressed", "SelectedButton", _button_box(GOLD_DK, GOLD, 2))
	t.set_stylebox("focus", "SelectedButton", focus)
	t.set_color("font_color", "SelectedButton", INK)
	t.set_color("font_hover_color", "SelectedButton", INK)
	t.set_color("font_pressed_color", "SelectedButton", INK)

	return t


# --- Shared styling helpers -------------------------------------------------
# One gold/cream treatment for every dark menu, so titles and footers read the
# same wherever they appear. These override label_settings (which otherwise wins
# over theme colors) by clearing it first.

## Gold accent title, centered. Use on a screen's main heading.
static func style_title(label: Label, size: int = 34) -> void:
	if label == null:
		return
	label.label_settings = null
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_font_size_override("font_size", size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Dim cream subheading that sits under a title.
static func style_subtitle(label: Label) -> void:
	if label == null:
		return
	label.label_settings = null
	label.add_theme_color_override("font_color", CREAM_DIM)
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Small, muted footer hint (e.g. keyboard shortcuts). Reads as a caption, not
## debug text.
static func style_caption(label: Label) -> void:
	if label == null:
		return
	label.label_settings = null
	label.add_theme_color_override("font_color", CREAM_DIM)
	label.add_theme_font_size_override("font_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 1, 1, 0.75)


## Ensure a full-rect [constant DARK] backdrop behind [param root]'s content.
## Reuses an existing child named "Background" when present (updating its color),
## otherwise inserts one as the first child. Returns the ColorRect.
static func apply_backdrop(root: Control) -> ColorRect:
	if root == null:
		return null
	var existing := root.get_node_or_null("Background")
	if existing is ColorRect:
		existing.color = DARK
		return existing
	var rect := ColorRect.new()
	rect.name = "Background"
	rect.color = DARK
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	root.move_child(rect, 0)
	return rect
