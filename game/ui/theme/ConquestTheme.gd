class_name ConquestTheme
extends RefCounted

## The IN-BATTLE HUD theme. It shares every colour, type size and spacing token
## with the out-of-battle menus -- [MenuTheme] is the single token source -- so the
## battle screen reads as the same game: deep navy panels, warm gold accents and
## focus, cream text, team blue / red for sides.
##
## [method build] starts from [method MenuTheme.build] (buttons, tabs, sliders,
## scrollbars, tooltips, popups, labels all come from there) and layers the HUD
## specifics on top: slightly tighter, translucent panels that sit over the 3D
## board, HP-green progress bars, and the "HudCommand" command-list button used by
## the unit command menu and the map menu.
##
## Apply to a HUD subtree with [code]ConquestTheme.apply_to(control)[/code]; every
## battle panel calls it on itself in _ready. Reusable pieces (portrait emblem,
## chips, key caps, HP bars) are static factories below so panels never hand-roll
## styleboxes.
##
## Sizes are 1280x720 base units (canvas_items stretch): body text is 18, nothing a
## player must read is smaller than 16 (FS_SMALL); 15 is used only for gold
## small-caps section tags.

# --- Tokens (all from MenuTheme -- ONE source) -------------------------------
const BG_DEEP := MenuTheme.BG_DEEP
const PANEL := MenuTheme.PANEL
const PANEL_HI := MenuTheme.PANEL_HI
const PANEL_SUNK := MenuTheme.PANEL_SUNK
const BORDER := MenuTheme.BORDER
const BORDER_SOFT := MenuTheme.BORDER_SOFT
const GOLD := MenuTheme.GOLD
const GOLD_LITE := MenuTheme.GOLD_LITE
const GOLD_DK := MenuTheme.GOLD_DK
const CREAM := MenuTheme.CREAM
const TEXT_DIM := MenuTheme.TEXT_DIM
const TEXT_MUTED := MenuTheme.TEXT_MUTED
const INK := MenuTheme.INK            ## text ON gold
const ACCENT := MenuTheme.ACCENT
const SUCCESS := MenuTheme.SUCCESS
const DANGER := MenuTheme.DANGER
const WARNING := MenuTheme.WARNING

## Team colours: fills / rings / bars. The *_TEXT variants are lightened so they
## keep >= 4.5:1 contrast as text on a navy panel.
const TEAM_BLUE := MenuTheme.TEAM_BLUE
const TEAM_RED := MenuTheme.TEAM_RED
const TEAM_GREEN := Color("4fb56a")
const TEAM_GOLD := Color("d9b24a")
const TEAM_BLUE_TEXT := Color("8cc4ff")
const TEAM_RED_TEXT := Color("ff8f80")

## HP tiers (UI bars AND the 3D map bars share these).
const HP_HIGH := Color("5fd07e")
const HP_MID := Color("f0b440")
const HP_LOW := Color("f05a4a")
const HP_TRACK := Color("0a0e22")
const HP_LOSS := Color(1.0, 0.25, 0.2, 0.95)   ## "about to be lost" band

## Numbers in the combat forecast.
const DMG_COLOR := Color("ffb070")
const HIT_COLOR := CREAM
const CRIT_COLOR := Color("ffd65a")

# Type scale (MenuTheme's, plus HUD display sizes).
const FS_HUD_TITLE := 22
const FS_BODY := MenuTheme.FS_BODY          # 18
const FS_SMALL := MenuTheme.FS_SMALL        # 16
const FS_CAPTION := MenuTheme.FS_CAPTION    # 15 (gold section tags only)
const FS_COMMAND := 20
const FS_NAME := 22
const FS_BIG_NUMBER := 34
const FS_PHASE := 24

## Nodes carrying this meta (portraits, chips, key caps -- anything with a deliberate
## local style) are skipped, with their subtree, by [method apply_to]'s sweep.
const KEEP_META := &"hud_keep_style"

const MARGIN := 16.0          ## HUD safe margin from the screen edges (base units)
const RADIUS := 12

# --- Legacy aliases ---------------------------------------------------------------
# The old amber battle palette's names, remapped onto the navy tokens so any code
# still using them renders in the unified look. New code uses the tokens above.
const AMBER := GOLD
const AMBER_LITE := GOLD_LITE
const AMBER_DK := GOLD_DK
const BROWN := BORDER
const BROWN_DK := BG_DEEP
const INK_SOFT := TEXT_MUTED
const CREAM_DIM := TEXT_DIM
const PLATE_BG := PANEL_SUNK
const HP_CYAN := HP_HIGH
const HIT_ORANGE := DMG_COLOR

# Element / move-type accents (Pokemon-style colour coding).
const EL_EMBER := MenuTheme.EL_FIRE
const EL_FROST := MenuTheme.EL_WATER
const EL_ARCANE := MenuTheme.EL_ARCANE
const EL_HOLY := MenuTheme.EL_HOLY
const EL_NATURE := MenuTheme.EL_NATURE
const EL_STEEL := MenuTheme.EL_STEEL


# --- Stylebox factories ------------------------------------------------------------

## The HUD card: translucent navy over the board, soft edge, drop shadow.
static func panel_box(alpha: float = 0.94) -> OrnateStyleBox:
	var sb := MenuTheme.card_box(PANEL, BORDER, alpha)
	sb.corner = 11.0
	sb.vignette_width = 14.0
	sb.shadow_size = 10.0
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb

## A darker inset "plate" behind values (forecast numbers, stat grids).
## A HUD unit card (command menu, hover card): the grove frame with the owning
## side's team colour as its edge stripe and a team-tinted border. The unit's
## element lives in its crest (see [method portrait]).
static func unit_card_box(unit, alpha: float = 0.95) -> OrnateStyleBox:
	var team := team_color(owner_of(unit))
	var sb := panel_box(alpha)
	sb.accent_color = Color(team, 0.95)
	sb.accent_side = SIDE_LEFT
	sb.accent_width = 4.0
	sb.border_color = BORDER.lerp(team, 0.45)
	return sb


static func plate_box() -> OrnateStyleBox:
	var sb := MenuTheme.inset_box()
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Compact strip (turn chip, objective chip): same card, tighter margins.
static func chip_box(border: Color = BORDER, alpha: float = 0.94) -> OrnateStyleBox:
	var sb := MenuTheme.plate_box(Color(PANEL, alpha), border, 8.0, 16, 6, 1.5)
	sb.hatch_alpha = 0.03
	sb.hatch_spacing = 5.0
	sb.inner_line_color = Color(GOLD, 0.22)
	sb.inner_inset = 4.0
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 7.0
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func _command_box(fill: Color, bar: Color) -> OrnateStyleBox:
	return MenuTheme.row_box(fill, bar, Color(bar, bar.a * 0.4), 30, 12, 7)

# --- Assemble the Theme --------------------------------------------------------------

static func build() -> Theme:
	var t := MenuTheme.build()

	# HUD panels: translucent navy card.
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())

	# HP-style progress bars.
	t.set_stylebox("background", "ProgressBar", MenuTheme.box(HP_TRACK, BORDER_SOFT, 1, 4, 0, 0))
	t.set_stylebox("fill", "ProgressBar", MenuTheme.box(HP_HIGH, HP_HIGH, 0, 4, 0, 0))

	# A HUD button is a touch more compact than a menu button.
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, MenuTheme.plate_box(Color(PANEL_HI, 0.8), BORDER, 7.0, 16, 8))
		var hov := MenuTheme.plate_box(PANEL_HI, GOLD_DK, 7.0, 16, 8)
		hov.inner_line_color = Color(GOLD, 0.22)
		hov.inner_inset = 4.0
		t.set_stylebox("hover", type, hov)
		t.set_stylebox("pressed", type, MenuTheme.plate_box(GOLD, GOLD_LITE, 7.0, 16, 8))
		t.set_stylebox("disabled", type, MenuTheme.plate_box(Color(PANEL_SUNK, 0.7), BORDER_SOFT, 7.0, 16, 8))
		t.set_stylebox("focus", type, MenuTheme.focus_box(7))

	# HudCommand: an FE command-list entry. Transparent at rest; hover / focus light
	# a gold bar on the left with a navy wash. Text stays cream / gold on navy (never
	# light-on-light).
	t.set_type_variation("HudCommand", "Button")
	t.set_stylebox("normal", "HudCommand", _command_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "HudCommand", _command_box(Color(GOLD_DK, 0.22), Color(GOLD_DK, 0.9)))
	t.set_stylebox("pressed", "HudCommand", _command_box(Color(GOLD, 0.36), GOLD_LITE))
	t.set_stylebox("hover_pressed", "HudCommand", _command_box(Color(GOLD, 0.36), GOLD_LITE))
	t.set_stylebox("disabled", "HudCommand", _command_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("focus", "HudCommand", _command_box(Color(GOLD, 0.3), GOLD))
	t.set_color("font_color", "HudCommand", CREAM)
	t.set_color("font_hover_color", "HudCommand", GOLD_LITE)
	t.set_color("font_focus_color", "HudCommand", GOLD_LITE)
	t.set_color("font_pressed_color", "HudCommand", GOLD_LITE)
	t.set_color("font_hover_pressed_color", "HudCommand", GOLD_LITE)
	t.set_color("font_disabled_color", "HudCommand", Color(TEXT_MUTED.r, TEXT_MUTED.g, TEXT_MUTED.b, 0.75))
	t.set_font("font", "HudCommand", MenuTheme.heading_font(1))
	t.set_font_size("font_size", "HudCommand", FS_COMMAND)
	t.set_constant("h_separation", "HudCommand", 10)
	return t


# --- Helpers ----------------------------------------------------------------------

## Give a background Panel/PanelContainer node the HUD card look, overriding any
## older stylebox it shipped with. Safe no-op on null.
static func style_panel_background(node: Control) -> void:
	if node != null and (node is Panel or node is PanelContainer):
		# A panel that asked for a theme variation (Card / InsetPanel / Pill...) keeps it.
		if node.theme_type_variation != &"":
			return
		node.add_theme_stylebox_override("panel", panel_box())


## Apply the HUD theme to [param root] and its subtree: set the theme, restyle every
## panel background, and strip baked-in font colours / per-button styleboxes so
## everything shares the one look. Panels call this FIRST in their build step and
## layer their deliberate local overrides afterwards.
static func apply_to(root: Control) -> void:
	if root == null:
		return
	root.theme = build()
	_restyle(root)


static func _restyle(node: Node) -> void:
	for child in node.get_children():
		if child.has_meta(KEEP_META):
			continue
		if child is Panel or child is PanelContainer:
			style_panel_background(child)
		if (child is Label or child is Button) and child.has_theme_color_override("font_color"):
			child.remove_theme_color_override("font_color")
		if child is Button or child is OptionButton:
			for s in ["normal", "hover", "pressed", "disabled", "focus"]:
				if child.has_theme_stylebox_override(s):
					child.remove_theme_stylebox_override(s)
		_restyle(child)


## Colour for a move/ability element tag; falls back to gold for unknowns.
static func element_color(element: String) -> Color:
	match element.to_lower():
		"ember", "fire": return MenuTheme.EL_FIRE
		"frost", "water", "ice": return MenuTheme.EL_WATER
		"arcane", "magic": return MenuTheme.EL_ARCANE
		"holy", "light": return MenuTheme.EL_HOLY
		"nature", "grass", "plant": return MenuTheme.EL_NATURE
		"wind", "air": return MenuTheme.EL_WIND
		"earth", "stone", "gem", "rock": return MenuTheme.EL_EARTH
		"steel", "metal", "physical": return MenuTheme.EL_STEEL
		"dark", "shadow", "blight": return MenuTheme.EL_DARK
		_: return GOLD

## HP colour tier for a 0..1 fraction (same thresholds as the 3D map bar).
static func hp_color(frac: float) -> Color:
	if frac > 0.5:
		return HP_HIGH
	if frac > 0.25:
		return HP_MID
	return HP_LOW


## Recolour a ProgressBar's fill for [param frac] (idempotent).
static func tint_hp_bar(bar: ProgressBar, frac: float) -> void:
	if bar == null:
		return
	var c := hp_color(frac)
	bar.add_theme_stylebox_override("fill", MenuTheme.box(c, c.lightened(0.15), 0, 4, 0, 0))


## A slim HP bar (track + tier-coloured fill).
static func hp_bar(height: float = 10.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", MenuTheme.box(HP_TRACK, BORDER_SOFT, 1, 4, 0, 0))
	tint_hp_bar(bar, 1.0)
	return bar


## Team colour for a player: by seat (P1 blue, P2 red, P3 green, P4 gold).
static func team_color(player) -> Color:
	if player == null or not ("player_id" in player):
		return TEXT_MUTED
	match int(player.player_id):
		0: return TEAM_BLUE
		1: return TEAM_RED
		2: return TEAM_GREEN
		3: return TEAM_GOLD
	return TEXT_MUTED


## Team colour lightened for use as TEXT on a navy panel.
static func team_text_color(player) -> Color:
	if player == null or not ("player_id" in player):
		return TEXT_DIM
	match int(player.player_id):
		0: return TEAM_BLUE_TEXT
		1: return TEAM_RED_TEXT
	return team_color(player).lightened(0.35)


## The owning player of [param unit] (null-safe).
static func owner_of(unit):
	if unit != null and is_instance_valid(unit) and unit.has_method("get_owner_player"):
		return unit.get_owner_player()
	return null


## Big phase title for [param player]: "PLAYER PHASE" / "ENEMY PHASE" in single
## player, "YOUR TURN" / "OPPONENT'S TURN" in a network match, and the seat name
## ("PLAYER 2 PHASE") in local versus.
static func phase_title(player) -> String:
	if player == null:
		return "BATTLE"
	var gs = _autoload("GameSettings")
	var mode: int = int(gs.game_mode) if gs != null else 0
	if gs != null and mode == GameSettings.GameMode.MULTIPLAYER:
		return "YOUR TURN" if LocalPlayer.is_local_human(player) else "OPPONENT'S TURN"
	if gs != null and mode == GameSettings.GameMode.VERSUS and not bool(player.is_ai):
		return "PLAYER %d PHASE" % (int(player.player_id) + 1)
	return "ENEMY PHASE" if bool(player.is_ai) else "PLAYER PHASE"


## Short side tag for a unit's owner: "Ally" / "Enemy" (single player), "You" /
## "Opponent" (network), "Player N" (local versus).
static func side_label(player) -> String:
	if player == null:
		return "Neutral"
	var gs = _autoload("GameSettings")
	var mode: int = int(gs.game_mode) if gs != null else 0
	if gs != null and mode == GameSettings.GameMode.MULTIPLAYER:
		return "You" if LocalPlayer.is_local_human(player) else "Opponent"
	if gs != null and mode == GameSettings.GameMode.VERSUS:
		return "Player %d" % (int(player.player_id) + 1)
	return "Enemy" if bool(player.is_ai) else "Ally"


static func _autoload(node_name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(node_name)
	return null


# --- Widget factories ------------------------------------------------------------------

## Circular portrait emblem: the unit's initial on its element colour, ringed in
## its team colour (the same emblem the squad-select cards use).
static func portrait(letter: String, fill: Color, ring: Color, px: float = 48.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Portrait"
	p.set_meta(KEEP_META, true)
	p.add_theme_stylebox_override("panel", MenuTheme.crest_box(fill, ring, px))
	p.custom_minimum_size = Vector2(px * 0.86, px)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.name = "Initial"
	l.text = letter.left(1).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", MenuTheme.display_font(0))
	l.add_theme_font_size_override("font_size", int(px * 0.42))
	l.add_theme_color_override("font_color", fill.lightened(0.7))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

## Recolour / re-letter a [method portrait] in place.
static func set_portrait(p: PanelContainer, letter: String, fill: Color, ring: Color) -> void:
	if p == null:
		return
	var px := p.custom_minimum_size.y
	p.add_theme_stylebox_override("panel", MenuTheme.crest_box(fill, ring, px))
	var l := p.get_node_or_null("Initial") as Label
	if l != null:
		l.text = letter.left(1).to_upper()
		l.add_theme_color_override("font_color", fill.lightened(0.7))

## Portrait fill + ring for [param unit]: element colour inside, team colour ring.
static func unit_portrait_colors(unit) -> Array:
	var fill := GOLD
	if unit != null and is_instance_valid(unit) and unit.has_method("get_element"):
		fill = element_color(String(unit.get_element()))
	return [fill, team_color(owner_of(unit))]


## Small rounded chip: [param text] on a tinted pill; the border and text take
## [param color] (text lightened for contrast).
static func chip(text: String, color: Color, font_size: int = FS_SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_meta(KEEP_META, true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", chip_style(color))
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color.lightened(0.45))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


static func chip_style(color: Color) -> OrnateStyleBox:
	var sb := MenuTheme.pill_box(Color(color, 0.2), color)
	sb.content_margin_left = 13
	sb.content_margin_right = 13
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

## Key-cap pill ("E", "Esc", "A") in gold on a raised navy cap.
static func key_cap(text: String, font_size: int = FS_CAPTION) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.name = "KeyCap"
	cap.set_meta(KEEP_META, true)
	var sb := MenuTheme.box(PANEL_HI, BORDER, 1, 5, 7, 1)
	sb.border_width_bottom = 3
	cap.add_theme_stylebox_override("panel", sb)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var k := Label.new()
	k.name = "Key"
	k.text = text
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.add_theme_font_size_override("font_size", font_size)
	k.add_theme_color_override("font_color", GOLD_LITE)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(k)
	return cap


## Mark [param node] (and its subtree) as locally styled so [method apply_to]
## leaves it alone. Returns the node for chaining.
static func keep_style(node: Node) -> Node:
	if node != null:
		node.set_meta(KEEP_META, true)
	return node


## Short on-screen glyph for a key / button name ("Escape" -> "Esc").
static func short_key(key: String) -> String:
	match key:
		"Escape": return "Esc"
		"BackSpace", "Backspace": return "Bksp"
		"PageUp": return "PgUp"
		"PageDown": return "PgDn"
		"Space": return "Space"
	return key


## The glyph to show for an input [param action] right now ("E", "Esc", or the pad
## button when a gamepad is connected). "" for &"" / unbound.
static func action_glyph(action: StringName) -> String:
	if action == &"":
		return ""
	return short_key(InputActions.hint(action))


## Put a right-aligned hint INSIDE [param button] (a command-list row): a key cap
## showing [param key], or -- when [param note] is set -- a short muted note
## ("Done", "108/108 HP"). Replaces any previous hint. The button keeps its own
## left-aligned text.
static func set_button_hint(button: Button, key: String, note: String = "",
		note_color: Color = TEXT_MUTED) -> void:
	if button == null:
		return
	var hint := button.get_node_or_null("Hint") as HBoxContainer
	if hint == null:
		hint = HBoxContainer.new()
		hint.name = "Hint"
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.alignment = BoxContainer.ALIGNMENT_END
		hint.anchor_left = 1.0
		hint.anchor_right = 1.0
		hint.anchor_top = 0.0
		hint.anchor_bottom = 1.0
		hint.offset_left = -170.0
		hint.offset_right = -10.0
		hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		keep_style(hint)
		button.add_child(hint)
	for c in hint.get_children():
		hint.remove_child(c)
		c.queue_free()
	if note != "":
		var l := Label.new()
		l.name = "Note"
		l.text = note
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		l.add_theme_font_size_override("font_size", FS_CAPTION)
		l.add_theme_color_override("font_color", note_color)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_child(l)
	elif key != "":
		hint.add_child(key_cap(key))


## Footer hint: key cap + what it does ("[Esc] Close").
static func key_hint(key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keep_style(row)
	row.add_child(key_cap(key))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FS_CAPTION)
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


## Gold small-caps section tag.
static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = &"SectionLabel"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A thin gold accent rule.
static func accent_rule(color: Color = GOLD, width: float = 96.0, height: float = 10.0) -> Control:
	var r := GroveRule.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, height)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return r


## A card title strip: a swallow-tailed ribbon holding [param text] in Cinzel caps.
## [param accent] tints the ribbon's edge (team / element colour).
static func title_ribbon(text: String, accent: Color = GOLD_DK, font_size: int = FS_BODY) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "TitleRibbon"
	p.set_meta(KEEP_META, true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", MenuTheme.ribbon_box(PANEL_HI, accent, 12.0))
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", MenuTheme.heading_font(2))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", GOLD_LITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p
