extends CanvasLayer

class_name UnitDetailPage

## The full-screen UNIT DETAIL page -- the one place that answers "tell me everything
## about this unit".
##
## WHY IT EXISTS. The left-hand battle card used to try to be both surfaces at once: a
## live HP/status readout AND a stat sheet AND an ability list, in a 260px column. The
## ability list was always the loser (it was reported cut off), the stats were duplicated
## in the right sidebar's "Unit Summary" dropdown, and the damage maths already had its
## own owner in [CombatForecastPanel]. So the two jobs were split:
##
##   * [UnitInfoPanel] -- the COMPACT battle card. HP, four effective stat chips, statuses.
##     Never blocks the map, never scrolls, fixed height. Battle-relevant only.
##   * THIS PAGE -- everything general. Full stat table with base → effective deltas, ALL
##     abilities with their descriptions, ALL moves with live cooldown state, and every
##     active status with what it does and how long it lasts. It deliberately BLOCKS the
##     map, because reading a stat sheet is not something you do mid-aim.
##
## REUSE, NOT A REWRITE. Every card on this page is built by [UnitPageContent], which was
## extracted from the Compendium's [UnitGallery] so the roster browser and this overlay
## cannot drift about what a move card says. The only things this file adds are the shell,
## the identity header, and the live-state plumbing (a unit's [MovesetController] /
## [AbilitySystem] / [StatusController] handed to the shared builders).
##
## LAYERING + PAUSE. Its own CanvasLayer at [constant OVERLAY_LAYER] (130) -- above the
## turn wipe (128) and every HUD panel, BELOW [PauseMenu] (140), so pausing still wins.
## It does NOT pause the tree: a networked match keeps running by design, and freezing the
## simulation because one player opened a stat sheet would desync the other. It is an
## overlay, not a pause.
##
## RETURN CONTRACT. Opening and closing this page touches NOTHING but its own visibility:
## it never emits a GameEvent, never deselects, never marks an action. ESC (or the Close
## button) puts the player back in the battle exactly as they left it, with the same unit
## selected and the same command stage staged.
##
## READ-ONLY BY CONSTRUCTION. It works for the player's OWN units and for an inspected
## ENEMY exactly the same way, because it only ever READS -- there is no control on the
## page that can act.
##
## LOOK (docs/UI_STYLE.md). A crested grove-frame card with the OWNER's team colour down
## its left edge (team = edge), a heraldic crest portrait (element field, team rim --
## element = crest), the unit's name in gold Cinzel, and a key-cap footer.
##
## INPUT. Modal while open: the root is in [constant InputActions.OVERLAY_GROUP] (so the
## board cursor / map menu / unit panels ignore input underneath) and stops the mouse.
## Cancel (ESC / B) or the CLOSE button closes it; the cursor keys / D-pad
## / left stick scroll the sheet; touch drags the scroll region and taps CLOSE.

## Above TurnTransition (128) / UltimateCutIn (124) / ActionAnnouncer (120); below
## PauseMenu (140), which must always be able to draw over this.
const OVERLAY_LAYER: int = 130

## Group every instance joins, so [method open_for] can find the one this battle already
## mounted instead of stacking a second overlay per call site (the battle card and the
## action panel both open it).
const GROUP := "unit_detail_page"

## Secondary text on the page (the grove's TEXT_MUTED).
const MUTED := MenuTheme.TEXT_MUTED

## Pixels one cursor press scrolls the sheet.
const SCROLL_STEP: int = 64

## The card never grows past this, however wide the window is -- a 1600px-wide wall of
## body text is unreadable, and the page is a document, not a dashboard.
const MAX_CARD_WIDTH: float = 860.0

## Window margin around the card.
const MARGIN: float = 28.0

## Portrait plate on the identity header.
const PORTRAIT_SIZE: float = 96.0

## Widest the identity header's element badge may claim. Generous next to the card's
## compact 72px sibling -- this page is a document, not a 260px column.
const ELEMENT_BADGE_MAX_WIDTH: float = 140.0

# --- Nodes (built in code -- no .tscn, like PauseMenu / SettingsPanel) ---------
var _root: Control = null
var _backdrop: ColorRect = null
var _card: PanelContainer = null
var _portrait_plate: PanelContainer = null
var _portrait_monogram: Label = null
var _portrait_texture: TextureRect = null
var _name_label: Label = null
## The unit's elemental TYPE, beside its name. Hidden for a unit with no element.
var _element_badge: PanelContainer = null
var _tags_label: Label = null
var _owner_label: Label = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _hints: HBoxContainer = null
var _close_button: Button = null

## The unit currently on the page (never mutated -- see the READ-ONLY note above).
var _unit = null
var _open: bool = false


func _ready() -> void:
	layer = OVERLAY_LAYER
	# ALWAYS so the page keeps drawing and answering ESC if something else pauses the tree
	# underneath it. It never pauses the tree ITSELF -- see the class note.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_build()
	_set_visible(false)


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

## Open the page for [param unit], mounting the battle's single instance if one is not
## already in the tree. [param context] is any node inside the tree (a panel, a button) --
## only used to reach the SceneTree.
##
## Returns the page, or null when there is no tree to mount into (a detached control in a
## test harness), so a caller can assert on it without special-casing.
static func open_for(context: Node, unit) -> UnitDetailPage:
	if context == null or not is_instance_valid(context) or not context.is_inside_tree():
		return null
	var tree := context.get_tree()
	if tree == null:
		return null

	var page: UnitDetailPage = null
	for node in tree.get_nodes_in_group(GROUP):
		if node is UnitDetailPage and is_instance_valid(node):
			page = node as UnitDetailPage
			break
	if page == null:
		page = UnitDetailPage.new()
		page.name = "UnitDetailPage"
		tree.root.add_child(page)

	page.open(unit)
	return page


func open(unit) -> void:
	"""Show the page for [param unit]. A null / freed unit is ignored rather than opening
	an empty page -- the DETAILS affordance is only reachable with a selection, so an
	empty page would only ever mean something upstream lost its subject."""
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return
	_unit = unit
	_fit_card_width()
	_populate(unit)
	_refresh_hints()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	_set_visible(true)
	if _close_button != null:
		_close_button.grab_focus()


func close() -> void:
	"""Return to the battle. Drops the page's reference to the unit so a unit that dies
	while the page is shut is not held alive by this overlay."""
	_unit = null
	_set_visible(false)


func toggle(unit) -> void:
	if _open:
		close()
	else:
		open(unit)


func is_open() -> bool:
	return _open


## The unit the page is currently showing, or null. Read-only accessor for tests and for
## a caller that wants to avoid re-opening the page on the same unit.
func current_unit():
	return _unit


func _set_visible(shown: bool) -> void:
	_open = shown
	visible = shown
	if _root != null:
		_root.visible = shown


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not event.is_pressed():
		return
	# `_input` (not `_unhandled_input`) and the event is CONSUMED, which is what keeps the
	# ESC chain airtight: UILayoutManager opens the pause menu from `_unhandled_input` and
	# UnitActionsPanel backs out a command stage from its own `_input`, so with the page up
	# neither of them ever sees the press. Exactly one thing happens per Escape. The named
	# CANCEL action rides along (the pad's B, and any rebinding), and a raw Escape still
	# works in a stripped harness with no InputMap. (Deliberately NOT unit_info: the press
	# that opens the page is not consumed by its opener, and would close it again here.)
	if event.is_action_pressed("ui_cancel") \
			or _is_pressed(event, InputActions.CANCEL) \
			or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE):
		close()
		_consume()
		return
	# Keyboard / pad scrolling of the sheet (the mouse wheel and touch drag are the scroll
	# container's own).
	var step: int = 0
	if _is_pressed(event, InputActions.CURSOR_DOWN) or event.is_action_pressed("ui_down"):
		step = SCROLL_STEP
	elif _is_pressed(event, InputActions.CURSOR_UP) or event.is_action_pressed("ui_up"):
		step = -SCROLL_STEP
	if step != 0 and _scroll != null:
		_scroll.scroll_vertical += step
		_consume()


func _consume() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## [param event] presses the named [param action] (skipped when the action is not in the
## InputMap, e.g. a stripped test harness).
static func _is_pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the page deliberately blocks the map underneath it. A click that
	# reached the board through a full-screen document would move a unit the player cannot
	# even see.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# The grove menu theme, like PauseMenu -- reading a stat sheet steps out of the battle
	# frame, and it is also the theme every UnitPageContent card is authored against.
	_root.theme = MenuTheme.build()
	# Board / map-menu / unit-panel handlers skip gameplay input while this root is visible.
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(MenuTheme.BG_DEEP, 0.82)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	var centre := MarginContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		centre.add_theme_constant_override("margin_" + side, int(MARGIN))
	_root.add_child(centre)

	# MEASURED FAILURE, and the reason the card is parented straight to the margin frame
	# rather than to a CenterContainer: a [CenterContainer] sizes its child to the child's
	# MINIMUM, and the minimum height of a VERTICALLY SCROLLING [ScrollContainer] is zero.
	# So the card measured 228px tall -- the header, the footer and NOTHING BETWEEN -- and
	# every section below (stats, moves, abilities, statuses) was built, parented, and
	# allotted no height at all. On screen: "clicking details doesn't show full details".
	# The old suite read Label text out of the node tree, so it never noticed.
	#
	# A MarginContainer honours size flags, so SIZE_FILL vertically hands the card the whole
	# window and the scroll region finally has room to be a document. The width is still
	# capped -- see _fit_card_width -- because a 1600px-wide wall of body text is unreadable.
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.size_flags_vertical = Control.SIZE_FILL
	_card.add_theme_stylebox_override("panel", _card_box(MenuTheme.GOLD_DK))
	centre.add_child(_card)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 2)
	_card.add_child(pad)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	column.add_child(_build_header())
	var rule := ConquestTheme.accent_rule(MenuTheme.GOLD, 0.0, 12.0)
	rule.size_flags_horizontal = Control.SIZE_FILL
	column.add_child(rule)

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 18)
	column.add_child(footer)

	# Key-cap hints for the live bindings ("[Up]/[Down] Scroll"), left of the button.
	_hints = HBoxContainer.new()
	_hints.name = "Hints"
	_hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hints.add_theme_constant_override("separation", 18)
	footer.add_child(_hints)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "CLOSE (ESC)"
	# >=44px hit target (touch-readiness) -- this page is the phone build's stat sheet.
	_close_button.custom_minimum_size = Vector2(160, 44)
	_close_button.pressed.connect(close)
	footer.add_child(_close_button)
	_refresh_hints()

	# The card is SHRINK_CENTER horizontally, so its width IS its minimum width -- which
	# therefore has to be restated whenever the window changes. Never wider than
	# MAX_CARD_WIDTH, and never wider than the window (the phone build's case).
	_root.resized.connect(_fit_card_width)
	_fit_card_width()


## The page card: the grove frame with its gold crest on top (a hero surface) and
## [param edge] -- the owner's team colour once a unit is shown -- down its left side.
static func _card_box(edge: Color) -> StyleBox:
	var sb := MenuTheme.accented_card(edge, SIDE_LEFT, MenuTheme.PANEL, 0.97, true)
	sb.border_color = MenuTheme.BORDER.lerp(edge, 0.4)
	sb.content_margin_left = 24
	sb.content_margin_right = 22
	sb.content_margin_top = 20
	sb.content_margin_bottom = 16
	return sb


## The glyph for [param action] right now ("Esc", or the pad button), or [param fallback].
static func _glyph(action: StringName, fallback: String) -> String:
	var g: String = ConquestTheme.action_glyph(action)
	return g if g != "" else fallback


## Rebuild the footer hints and the Close label for the live bindings (the pad's buttons
## once a gamepad is connected).
func _refresh_hints() -> void:
	var cancel_key: String = _glyph(InputActions.CANCEL, "Esc")
	if _close_button != null:
		_close_button.text = "CLOSE (%s)" % cancel_key.to_upper()
	if _hints == null:
		return
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	var up: String = _glyph(InputActions.CURSOR_UP, "Up")
	var down: String = _glyph(InputActions.CURSOR_DOWN, "Down")
	_hints.add_child(ConquestTheme.key_hint("%s / %s" % [up, down], "Scroll"))
	_hints.add_child(ConquestTheme.key_hint(cancel_key, "Close"))


func _fit_card_width() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	var available: float = MAX_CARD_WIDTH
	if _root != null and is_instance_valid(_root) and _root.size.x > 0.0:
		available = _root.size.x - MARGIN * 2.0
	_card.custom_minimum_size.x = maxf(0.0, minf(MAX_CARD_WIDTH, available))


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 16)

	_portrait_plate = PanelContainer.new()
	_portrait_plate.name = "Portrait"
	_portrait_plate.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(_portrait_plate)

	_portrait_monogram = Label.new()
	_portrait_monogram.name = "Monogram"
	_portrait_monogram.text = "?"
	_portrait_monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A crest initial: the Cinzel display face with an engraved shadow.
	_portrait_monogram.add_theme_font_override("font", MenuTheme.display_font(0))
	_portrait_monogram.add_theme_font_size_override("font_size", 44)
	_portrait_monogram.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_portrait_monogram.add_theme_constant_override("shadow_offset_y", 2)
	_portrait_plate.add_child(_portrait_monogram)

	_portrait_texture = TextureRect.new()
	_portrait_texture.name = "PortraitTexture"
	_portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_IGNORE_SIZE, always. A TextureRect's default EXPAND_KEEP_SIZE reports the
	# TEXTURE's size as its minimum, and PortraitCache captures at 256x256 -- that is the
	# exact trap that blew the left column apart before this redesign. Never reintroduce it.
	_portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_texture.visible = false
	_portrait_plate.add_child(_portrait_texture)

	var identity := VBoxContainer.new()
	identity.name = "Identity"
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 4)
	header.add_child(identity)

	# Name + element badge on ONE row. The element is an identity fact, so it belongs in
	# the identity header rather than in the stat table -- and inline with the name it is
	# free: a FONT_CAPTION (12px) pill is ~19px tall against a FONT_TITLE (22px) name at
	# ~29px, so the row's height is still the name's and the header does not grow. The
	# only cost is horizontal, and the header has 700+px to give.
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 10)
	identity.add_child(name_row)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.add_theme_font_override("font", MenuTheme.heading_font(2))
	_name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	_name_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)

	_element_badge = ElementVisuals.make_badge(
			&"", MenuTheme.FONT_CAPTION, ELEMENT_BADGE_MAX_WIDTH)
	name_row.add_child(_element_badge)

	_tags_label = Label.new()
	_tags_label.name = "TagsLabel"
	_tags_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	_tags_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tags_label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	identity.add_child(_tags_label)

	_owner_label = Label.new()
	_owner_label.name = "OwnerLabel"
	_owner_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	_owner_label.add_theme_color_override("font_color", MUTED)
	identity.add_child(_owner_label)

	return header


# ---------------------------------------------------------------------------
# Population
# ---------------------------------------------------------------------------

func _populate(unit) -> void:
	var character = unit.character_resource if "character_resource" in unit else null

	_populate_identity(unit, character)

	if _body == null:
		return
	UnitPageContent.clear_container(_body)

	_add_section("Statistics")
	_body.add_child(UnitPageContent.build_stat_table(character, unit))

	_add_section("Active statuses")
	var status_cards: Array = UnitPageContent.build_status_cards(unit)
	if status_cards.is_empty():
		_body.add_child(UnitPageContent.muted_label("No active statuses."))
	else:
		for card in status_cards:
			_body.add_child(card)

	_add_section("Moves")
	var move_count: int = 0
	if character != null:
		for i in range(character.move_count()):
			var move: MoveResource = character.get_move(i)
			if move == null:
				continue
			_body.add_child(UnitPageContent.build_move_card(
					move, UnitPageContent.live_move_state(unit, move)))
			move_count += 1
	if move_count == 0:
		_body.add_child(UnitPageContent.muted_label("No moves."))

	_add_section("Abilities")
	var ability_count: int = 0
	for ability in UnitPageContent.abilities_of(unit):
		if ability == null:
			continue
		_body.add_child(UnitPageContent.build_ability_card(
				ability, UnitPageContent.live_ability_state(unit, ability)))
		ability_count += 1
	if ability_count == 0:
		_body.add_child(UnitPageContent.muted_label("No abilities."))

	if character != null:
		var description: String = String(character.description).strip_edges()
		if description != "":
			_add_section("Description")
			_body.add_child(UnitPageContent.wrapped_label(description))


func _add_section(title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_body.add_child(spacer)
	_body.add_child(UnitPageContent.section_header(title))


func _populate_identity(unit, character) -> void:
	var display: String = ""
	if unit.has_method("get_display_name"):
		display = String(unit.get_display_name()).strip_edges()
	if display == "" and character != null:
		display = String(character.display_name)
	if _name_label != null:
		_name_label.text = display if display != "" else "Unknown unit"

	# Same badge, same colour source, same vocabulary as the compact battle card's.
	ElementVisuals.update_badge(
			_element_badge, ElementVisuals.of_unit(unit), ELEMENT_BADGE_MAX_WIDTH)

	if _tags_label != null:
		var tags: String = UnitPageContent.identity_tags(character)
		var skin: String = _skin_name(unit)
		if skin != "":
			tags = "%s  -  Skin: %s" % [tags, skin] if tags != "" else "Skin: %s" % skin
		_tags_label.text = tags if tags != "" else "No character resource on this unit."

	if _owner_label != null:
		_owner_label.text = _owner_text(unit)

	_paint_portrait(unit, character, display)


## "Player 1" / "Enemy (Bot)" / "Neutral" -- who this unit belongs to, which is the whole
## reason the page has to work for an inspected ENEMY as readily as for your own unit.
func _owner_text(unit) -> String:
	if not unit.has_method("get_owner_player"):
		return ""
	var player = unit.get_owner_player()
	if player == null:
		return "Unowned"
	var label: String = ""
	if player.has_method("get_display_name"):
		label = String(player.get_display_name())
	if label == "":
		label = "Player %d" % int(player.player_id) if "player_id" in player else "Player"
	if "is_neutral" in player and bool(player.is_neutral):
		return "%s  (neutral)" % label
	if "is_ai" in player and bool(player.is_ai):
		return "%s  (AI)" % label
	return label


## The equipped skin's display name, or "" for the default look. Read off the unit's own
## `_applied_skin_id` latch (the id it is actually WEARING) rather than re-asking the
## wardrobe policy, so this needs no knowledge of whose profile a skin came from.
func _skin_name(unit) -> String:
	if not ("_applied_skin_id" in unit):
		return ""
	var skin_id: String = String(unit.get("_applied_skin_id"))
	if skin_id == "":
		return ""
	var skin: SkinResource = SkinLibrary.find(skin_id)
	if skin != null and String(skin.display_name) != "":
		return String(skin.display_name)
	return UnitPageContent.humanize_id(skin_id)


## The identity plate: a real captured portrait when one is available, otherwise the
## element-coloured monogram the rest of the game falls back to.
func _paint_portrait(unit, character, display: String) -> void:
	if _portrait_plate == null:
		return

	var element: String = String(unit.get_element()) if unit.has_method("get_element") else ""
	var base: Color = ConquestTheme.element_color(element)
	# Team = edge: the owner's seat colour rims the crest and stripes the card's left side.
	var team: Color = ConquestTheme.team_color(ConquestTheme.owner_of(unit))
	if _card != null:
		_card.add_theme_stylebox_override("panel", _card_box(team))

	if _portrait_monogram != null:
		_portrait_monogram.text = display.substr(0, 1).to_upper() if display != "" else "?"
		_portrait_monogram.add_theme_color_override("font_color", base.lightened(0.7))

	var texture: Texture2D = null
	if character != null and character.portrait != null:
		texture = character.portrait
	else:
		# PortraitCache is an autoload; resolved by path so a headless harness without it
		# simply keeps the monogram rather than erroring.
		var cache := get_node_or_null("/root/PortraitCache")
		var character_id: String = unit.get_unit_type() if unit.has_method("get_unit_type") else ""
		if cache != null and cache.has_method("get_cached") and character_id != "":
			texture = cache.get_cached(character_id)

	if _portrait_texture != null:
		_portrait_texture.texture = texture
		_portrait_texture.visible = texture != null
	if _portrait_monogram != null:
		_portrait_monogram.visible = texture == null

	# Element = crest: the heraldic SHIELD (element field, team rim, gold inner line) behind
	# the monogram; a captured portrait sits in a notched frame of the same colours instead,
	# since a square image does not fit a shield's point.
	if texture == null:
		_portrait_plate.add_theme_stylebox_override("panel",
				MenuTheme.crest_box(base, team, PORTRAIT_SIZE))
	else:
		var frame := MenuTheme.plate_box(base.darkened(0.45), team, 10.0, 4.0, 4.0, 2.5)
		frame.inner_line_color = Color(MenuTheme.GOLD_LITE, 0.5)
		frame.inner_inset = 4.0
		_portrait_plate.add_theme_stylebox_override("panel", frame)
