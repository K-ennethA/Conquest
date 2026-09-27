class_name MenuKit
extends RefCounted

## Building blocks for out-of-battle screens, so every screen shares the same
## page structure, header, footer and widgets:
##
##   var page := MenuKit.build_page(self, ["Single Player"], "Choose a Battlefield",
##           "Pick where the battle is fought.")
##   page.body.add_child(...)                     # the screen's content (expands)
##   page.actions.add_child(MenuKit.button("Back", MenuKit.GHOST))
##
## build_page lays out:  backdrop | [breadcrumb / title / subtitle]  body  [hints .. actions]
## All widgets use [MenuTheme] type variations -- no per-screen styleboxes.

const PRIMARY := &"PrimaryButton"
const GHOST := &"GhostButton"
const CARD := &"OptionCard"


## A laid-out page. Returns { root, header, breadcrumb, title, subtitle, body,
## footer, hints, actions }. [param crumbs] is the path BEFORE this screen.
static func build_page(screen: Control, crumbs: Array, title: String, subtitle: String = "",
		with_backdrop: bool = true) -> Dictionary:
	screen.theme = MenuTheme.build()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if with_backdrop:
		var bd := MenuBackdrop.new()
		bd.name = "Backdrop"
		screen.add_child(bd)

	var margin := MarginContainer.new()
	margin.name = "Page"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", MenuTheme.SP_PAGE)
	margin.add_theme_constant_override("margin_right", MenuTheme.SP_PAGE)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 22)
	screen.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", MenuTheme.SP_L)
	margin.add_child(col)

	var header := header_block(crumbs, title, subtitle)
	col.add_child(header["root"])

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(body)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", MenuTheme.SP_XL)
	col.add_child(footer)

	var hints := HBoxContainer.new()
	hints.name = "Hints"
	hints.add_theme_constant_override("separation", MenuTheme.SP_XL)
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.alignment = BoxContainer.ALIGNMENT_BEGIN
	footer.add_child(hints)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", MenuTheme.SP_L)
	actions.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(actions)

	return {
		"root": margin, "column": col, "header": header["root"],
		"breadcrumb": header["breadcrumb"], "title": header["title"],
		"subtitle": header["subtitle"], "body": body, "footer": footer,
		"hints": hints, "actions": actions,
	}


## Breadcrumb ("CONQUEST / VERSUS"), big title, gold rule, and a one-line subtitle.
static func header_block(crumbs: Array, title: String, subtitle: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.name = "Header"
	box.add_theme_constant_override("separation", 2)

	var crumb := Label.new()
	crumb.name = "Breadcrumb"
	crumb.theme_type_variation = &"SectionLabel"
	var parts: Array = ["CONQUEST"]
	for c in crumbs:
		parts.append(String(c).to_upper())
	crumb.text = "  /  ".join(parts)
	box.add_child(crumb)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", MenuTheme.SP_L)
	box.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.name = "Title"
	title_lbl.theme_type_variation = &"TitleLabel"
	title_lbl.text = title
	title_row.add_child(title_lbl)

	var rule := ColorRect.new()
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(72, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)

	var sub := Label.new()
	sub.name = "Subtitle"
	sub.theme_type_variation = &"DimLabel"
	sub.text = subtitle
	sub.visible = subtitle != ""
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	# Breathing room between the rule and the subtitle.
	box.move_child(rule, 2)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(gap)
	box.move_child(gap, 3)

	return {"root": box, "breadcrumb": crumb, "title": title_lbl, "subtitle": sub}


# --- Widgets ------------------------------------------------------------------

## A themed button. [param variation]: MenuKit.PRIMARY / GHOST / "" (default).
static func button(text: String, variation: StringName = &"", min_width: float = 0.0,
		min_height: float = 50.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(min_width, min_height)
	b.focus_mode = Control.FOCUS_ALL
	MenuNav.hover_focus(b)
	return b


static func label(text: String, variation: StringName = &"", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func section(text: String) -> Label:
	return label(text.to_upper(), &"SectionLabel")


static func card(variation: StringName = &"Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


## Small rounded chip: [param text] on a tinted pill. [param color] tints the
## border + fill; text stays high-contrast.
static func badge(text: String, color: Color = MenuTheme.GOLD, filled: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var fill := color if filled else Color(color.r, color.g, color.b, 0.16)
	p.add_theme_stylebox_override("panel", MenuTheme.pill_box(fill, color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	l.add_theme_color_override("font_color", MenuTheme.INK if filled else color.lightened(0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## "Label  value" stat pair stacked (value big, label small gold caps).
static func stat_block(caption: String, value: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := section(caption)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(c)
	var val := label(value, &"SubheadingLabel")
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(val)
	return v


## Footer control hint: a key-cap pill + what it does. The key text follows the
## active device (keyboard vs gamepad).
static func key_hint(keyboard_key: String, pad_button: String, action_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_S)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	var sb := MenuTheme.box(MenuTheme.PANEL_HI, MenuTheme.BORDER, 1, 6, 9, 2)
	sb.border_width_bottom = 3
	cap.add_theme_stylebox_override("panel", sb)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var k := Label.new()
	k.text = pad_button if MenuNav.using_gamepad() else keyboard_key
	k.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	k.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	cap.add_child(k)
	row.add_child(cap)
	var l := label(action_text, &"DimLabel")
	l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row


## The standard "Enter Select / Esc Back" hint pair.
static func add_standard_hints(hints: Container, select_text: String = "Select",
		back_text: String = "Back") -> void:
	hints.add_child(key_hint("Enter", "A", select_text))
	hints.add_child(key_hint("Esc", "B", back_text))


## A selectable card Button whose content is a VBox of children you supply.
## Returns { button, content } -- add labels to content (they ignore the mouse).
static func option_card(min_size: Vector2, toggle: bool = false) -> Dictionary:
	var b := Button.new()
	b.theme_type_variation = CARD
	b.toggle_mode = toggle
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18 if side in ["left", "right"] else 14)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", MenuTheme.SP_S)
	m.add_child(v)
	# Keyboard / pad focus lifts the card like a mouse hover does.
	b.focus_entered.connect(func() -> void:
		if not b.button_pressed:
			b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover")))
	b.focus_exited.connect(func() -> void: b.remove_theme_stylebox_override("normal"))
	# A Button does not size to its children: grow it to fit the content.
	m.minimum_size_changed.connect(func() -> void:
		var need: float = maxf(min_size.y, m.get_combined_minimum_size().y)
		if absf(b.custom_minimum_size.y - need) > 0.5:
			b.custom_minimum_size.y = need)
	return {"button": b, "content": v, "margin": m}


## Make every Control under [param node] ignore the mouse (content inside cards).
static func ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_mouse(c)


## Inline status line with a tone: "", "info", "ok", "warn", "error".
static func set_status(l: Label, text: String, tone: String = "") -> void:
	if l == null:
		return
	l.text = text
	var c := MenuTheme.TEXT_DIM
	match tone:
		"info": c = MenuTheme.ACCENT
		"ok": c = MenuTheme.SUCCESS
		"warn": c = MenuTheme.WARNING
		"error": c = MenuTheme.DANGER
	l.add_theme_color_override("font_color", c)


## Colour for an element name (menus-side twin of ConquestTheme.element_color).
static func element_color(element: String) -> Color:
	match element.to_lower():
		"dark", "shadow": return Color("9b7be0")
		"earth", "stone": return Color("c9955a")
	return ConquestTheme.element_color(element)


## A large "pick one" card: accent bar, title, tagline, body, bullet list and an
## optional illustration row. Returns the Button (content ignores the mouse).
static func choice_card(title: String, tagline: String, body: String, bullets: Array = [],
		accent: Color = MenuTheme.GOLD, illustration: Control = null,
		min_size: Vector2 = Vector2(420, 330)) -> Button:
	var parts := option_card(min_size)
	var b: Button = parts["button"]
	var v: VBoxContainer = parts["content"]
	v.add_theme_constant_override("separation", MenuTheme.SP_M)

	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(48, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(bar)

	var t := label(title, &"HeadingLabel")
	t.add_theme_font_size_override("font_size", 30)
	v.add_child(t)
	var tl := label(tagline.to_upper(), &"SectionLabel")
	tl.add_theme_color_override("font_color", accent.lightened(0.2))
	v.add_child(tl)

	if illustration != null:
		v.add_child(illustration)

	var bd := label(body, &"DimLabel", true)
	v.add_child(bd)

	for line in bullets:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", MenuTheme.SP_S)
		var dot := label("+", &"")
		dot.add_theme_color_override("font_color", accent)
		row.add_child(dot)
		var bl := label(String(line), &"", true)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		row.add_child(bl)
		v.add_child(row)
	ignore_mouse(b)
	MenuNav.hover_focus(b)
	return b


## A row of small team-coloured pips -- a tiny turn-order diagram.
## [param sequence] is e.g. "BBBB|RRRR" (B = blue team, R = red team, | = gap).
static func pip_row(sequence: String, caption: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in sequence:
		if ch == "|":
			var arrow := label(">", &"MutedLabel")
			row.add_child(arrow)
			continue
		var pip := PanelContainer.new()
		var col := MenuTheme.TEAM_BLUE if ch == "B" else MenuTheme.TEAM_RED
		pip.add_theme_stylebox_override("panel", MenuTheme.box(col, col.lightened(0.35), 1, 5, 0, 0))
		pip.custom_minimum_size = Vector2(20, 20)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	if caption != "":
		var c := label(caption, &"MutedLabel")
		c.add_theme_constant_override("margin_left", 8)
		row.add_child(c)
	return row
