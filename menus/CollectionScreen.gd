extends Control
class_name CollectionScreen

## The COLLECTION: browse the roster, see every cosmetic skin authored for a
## character, equip what you own, buy what you can afford, and roll the gacha.
##
## LAYOUT (the shared grove page, [MenuKit.build_page] -- see docs/UI_STYLE.md):
##   * HEADER -- breadcrumb / title, with the live points balance at the right of the
##     title row (kept in step with the profile's points_changed signal).
##   * LEFT   -- the roster rail. One "MenuItem" row per character (name + element
##     badge); the active row holds the pressed gold ribbon wash + leaf marker.
##   * RIGHT  -- a card per look for the selected character: the DEFAULT look first,
##     then every skin. A card carries a crest in the look's tint, its name, blurb,
##     rarity badge (grey/blue/gold), and exactly ONE call to action -- EQUIPPED (gold
##     frame + crest), "Equip" (owned), "price + Buy" (buyable), or "Gacha only" (price 0).
##   * FOOTER -- the status line and the duplicate-refund note in the hints, Back and the
##     gold GACHA ROLL call to action on the right.
##
## THE UI NEVER DECIDES ANYTHING. Every rule -- can they afford it, do they own it,
## is it even buyable, what did the roll land, what does a duplicate refund -- lives
## in [SkinShop] and is re-checked there on the way through. A card's button state is
## only a HINT; pressing it re-runs the whole check. That is why a stale screen (a
## background purchase, a mid-session profile change) cannot overspend.
##
## NO PROFILE? STILL OPENS. The PlayerProfile autoload is resolved with
## get_node_or_null and every call is guarded inside [SkinShop], so the screen opens
## and reads as "0 points, nothing owned" rather than crashing when the autoload is
## absent (tests, headless, load-order shifts).
##
## RNG. A fresh, randomized, LOCAL RandomNumberGenerator drives the gacha. Cosmetic
## rolls are client-local and must never draw from the deterministic match RNG that
## networked peers replay -- see [SkinLibrary].
##
## Input: Up / Down walk the roster (focusing a row shows its looks), Right moves into the
## look cards, Confirm presses; Cancel (Esc / B) closes an open reveal first, then goes back.

## Collection is reached through Profile (Profile chip -> ProfileScreen -> Collection
## card), not directly off the main menu -- Back and Cancel walk that same path in reverse.
const PROFILE_SCENE: String = "res://menus/ProfileScreen.tscn"

## Rarity badge / card-accent colours: grey, blue, gold (grove tokens).
const RARITY_COLORS: Array[Color] = [
	MenuTheme.TEXT_MUTED,  # COMMON
	MenuTheme.ACCENT,      # RARE
	MenuTheme.GOLD,        # EPIC
]

const ROSTER_WIDTH: float = 300.0
const ROW_HEIGHT: float = 46.0

# --- State ---
## Injected/resolved profile (PlayerProfile autoload in game, a mock in tests).
var _profile: Object = null
var _shop: SkinShop = null

## Roster ids in display order, and the one currently shown on the right.
var _character_ids: Array[StringName] = []
var _selected_character: StringName = &""

## Cosmetic-local gacha RNG. NOT the match RNG (see the class note).
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- UI refs ---
var _page_root: Control = null
var _roster_column: VBoxContainer = null
var _roster_group: ButtonGroup = ButtonGroup.new()
var _cards_column: VBoxContainer = null
var _detail_title: Label = null
var _points_label: Label = null
var _status_label: Label = null
var _roll_button: Button = null
var _back_button: Button = null
var _reveal_layer: Control = null
var _reveal_card: PanelContainer = null
var _reveal_body: VBoxContainer = null
var _reveal_flash: ColorRect = null

## character id -> its rail Button / name Label, for active-state restyling.
var _row_buttons: Dictionary = {}
var _row_labels: Dictionary = {}


func _ready() -> void:
	# Cosmetic-local seed: a skin roll is client-side vanity, never match state.
	_rng.randomize()

	if _profile == null:
		_profile = get_node_or_null("/root/PlayerProfile")
	if _shop == null:
		_shop = SkinShop.new(_profile)
	_connect_profile()

	_collect_characters()
	_build_ui()
	if not _character_ids.is_empty():
		_select_character(_character_ids[0])
		_focus_later(_row_buttons.get(_character_ids[0], null))
	else:
		_focus_later(_back_button)
	_refresh_points()


## Inject the profile (tests, or a host screen that owns it). Safe before or after
## _ready; refreshes the view when the screen is already built.
func set_profile(profile: Object) -> void:
	_profile = profile
	if _shop == null:
		_shop = SkinShop.new(profile)
	else:
		_shop.set_profile(profile)
	_connect_profile()
	if _cards_column != null:
		_rebuild_cards()
		_refresh_points()


func _connect_profile() -> void:
	if _profile == null or not _profile.has_signal("points_changed"):
		return
	if _profile.is_connected("points_changed", _on_points_changed):
		return
	_profile.connect("points_changed", _on_points_changed)


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

## Every roster character that resolves, ordered by display name so the rail is
## stable and scannable. Characters with no skins yet are still listed -- their card
## column shows the default look plus a "no skins" note, which reads better than a
## roster that silently hides half the cast.
func _collect_characters() -> void:
	var rows: Array = []
	for raw_id in CharacterLibrary.all_ids():
		var cid: StringName = StringName(raw_id)
		var res: CharacterResource = CharacterLibrary.get_character(cid)
		if res == null:
			continue
		rows.append({ "id": cid, "name": res.display_name })
	rows.sort_custom(func(a, b) -> bool: return String(a["name"]) < String(b["name"]))
	_character_ids.clear()
	for row in rows:
		_character_ids.append(row["id"])


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var page := MenuKit.build_page(self, ["Profile"], "Collection",
		"Equip a look for each character, buy what you can afford, or roll the gacha.")
	_page_root = page.root

	# Live balance at the right end of the title row.
	var title_row := (page.title as Control).get_parent() as HBoxContainer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	_points_label = MenuKit.label("0 PTS", &"HeadingLabel")
	_points_label.name = "PointsLabel"
	_points_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_points_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_points_label)

	var body := HBoxContainer.new()
	body.name = "Columns"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", MenuTheme.SP_XL)
	page.body.add_child(body)

	body.add_child(_build_roster_panel())
	body.add_child(_build_detail_panel())
	# The rows are in the themed tree now. "MenuItem" has no hover_pressed state of its
	# own (it would fall back to Button's solid gold plate and swallow the row's label), so
	# a hovered ACTIVE row keeps the active row's ribbon wash.
	for cid in _row_buttons:
		var row: Button = _row_buttons[cid]
		row.add_theme_stylebox_override("hover_pressed", row.get_theme_stylebox("pressed"))

	# Footer: status + refund note on the left, Back / Roll on the right.
	_status_label = MenuKit.label("", &"DimLabel")
	_status_label.name = "StatusLabel"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.hints.add_child(MenuKit.key_hint("Esc", "B", "Back"))
	page.hints.add_child(_status_label)
	var refund := MenuKit.label("Duplicates refund %d pts" % SkinLibrary.DUPLICATE_REFUND, &"MutedLabel")
	refund.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page.hints.add_child(refund)

	_back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_button.name = "BackButton"
	_back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_button)

	_roll_button = MenuKit.button("Gacha Roll  (%d pts)" % SkinShop.GACHA_COST, MenuKit.PRIMARY, 260, 54)
	_roll_button.name = "RollButton"
	_roll_button.pressed.connect(_on_roll_pressed)
	page.actions.add_child(_roll_button)

	_build_reveal_layer()


func _build_roster_panel() -> Control:
	var panel := MenuKit.card()
	panel.name = "RosterPanel"
	panel.custom_minimum_size = Vector2(ROSTER_WIDTH, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", MenuTheme.SP_S)
	panel.add_child(column)

	column.add_child(MenuKit.section("Roster"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)

	_roster_column = VBoxContainer.new()
	_roster_column.name = "RosterColumn"
	_roster_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_column.add_theme_constant_override("separation", 2)
	scroll.add_child(_roster_column)

	for cid in _character_ids:
		_roster_column.add_child(_make_roster_row(cid))

	if _character_ids.is_empty():
		_roster_column.add_child(MenuKit.label("No roster characters found.", &"MutedLabel", true))

	return panel


## One rail entry: a "MenuItem" toggle row (the grove's command-list row -- gold ribbon
## wash + leaf marker on focus, held on while it is the active character) whose content
## (name + element badge) is drawn by an overlaid, click-through HBox, so the row
## highlights as a single target.
func _make_roster_row(character_id: StringName) -> Button:
	var res: CharacterResource = CharacterLibrary.get_character(character_id)
	var row := Button.new()
	row.name = "Row_" + String(character_id)
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.theme_type_variation = &"MenuItem"
	row.text = ""
	row.toggle_mode = true
	row.button_group = _roster_group
	row.focus_mode = Control.FOCUS_ALL
	row.pressed.connect(_select_character.bind(character_id))
	# Walking the rail with the D-pad / arrows shows each character's looks as it lands.
	row.focus_entered.connect(func() -> void:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _selected_character != character_id:
			_select_character(character_id))
	MenuNav.hover_focus(row)

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 30.0  # clear of the MenuItem leaf marker
	content.offset_right = -10.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", MenuTheme.SP_S)
	row.add_child(content)

	var name_label := Label.new()
	name_label.text = res.display_name if res != null else String(character_id)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", MenuTheme.heading_font(1))
	name_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	name_label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	content.add_child(name_label)

	var element: String = String(res.element) if res != null else ""
	if not element.is_empty():
		var badge := MenuKit.badge(element.capitalize(), MenuKit.element_color(element))
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(badge)

	_row_buttons[character_id] = row
	_row_labels[character_id] = name_label
	return row


func _build_detail_panel() -> Control:
	var panel := MenuKit.card()
	panel.name = "DetailPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", MenuTheme.SP_S)
	panel.add_child(column)

	_detail_title = MenuKit.section("Skins")
	column.add_child(_detail_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 4)
	pad.add_theme_constant_override("margin_right", 14)  # clear of the scrollbar
	scroll.add_child(pad)

	_cards_column = VBoxContainer.new()
	_cards_column.name = "CardsColumn"
	_cards_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_column.add_theme_constant_override("separation", MenuTheme.SP_M)
	pad.add_child(_cards_column)

	return panel


## The reveal overlay: a dimming scrim plus a centered crest card the roll result is
## rendered into. Built once, hidden, and reused for every roll.
func _build_reveal_layer() -> void:
	_reveal_layer = Control.new()
	_reveal_layer.name = "RevealLayer"
	_reveal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_layer.visible = false
	add_child(_reveal_layer)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(MenuTheme.BG_DEEP, 0.82)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP (not IGNORE): the scrim swallows clicks so the shop behind it cannot be
	# operated while a reveal is up.
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_reveal_layer.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_layer.add_child(center)

	_reveal_card = MenuKit.card(&"CrestCard")
	_reveal_card.name = "RevealCard"
	_reveal_card.custom_minimum_size = Vector2(440.0, 0.0)
	center.add_child(_reveal_card)

	_reveal_body = VBoxContainer.new()
	_reveal_body.add_theme_constant_override("separation", MenuTheme.SP_M)
	_reveal_card.add_child(_reveal_body)

	# Rarity flash: a colour wash over the card, tweened out over the reveal.
	_reveal_flash = ColorRect.new()
	_reveal_flash.name = "RarityFlash"
	_reveal_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_reveal_card.add_child(_reveal_flash)


# ---------------------------------------------------------------------------
# Roster selection
# ---------------------------------------------------------------------------

func _select_character(character_id: StringName) -> void:
	_selected_character = character_id
	_sync_roster_highlight()
	_rebuild_cards()


func _sync_roster_highlight() -> void:
	for cid in _row_buttons.keys():
		var button: Button = _row_buttons[cid]
		if button == null or not is_instance_valid(button):
			continue
		var active: bool = cid == _selected_character
		button.set_pressed_no_signal(active)
		var label: Label = _row_labels.get(cid, null)
		if label != null and is_instance_valid(label):
			label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE if active else MenuTheme.TEXT_DIM)


# ---------------------------------------------------------------------------
# Skin cards
# ---------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if _cards_column == null:
		return
	for child in _cards_column.get_children():
		_cards_column.remove_child(child)
		child.queue_free()

	var res: CharacterResource = CharacterLibrary.get_character(_selected_character)
	var char_name: String = res.display_name if res != null else String(_selected_character)
	if _detail_title != null:
		_detail_title.text = "%s  --  LOOKS" % char_name.to_upper()

	var char_id: String = String(_selected_character)
	if char_id.is_empty():
		return

	var equipped: String = _shop.equipped_for(char_id) if _shop != null else ""

	_cards_column.add_child(_make_default_card(char_id, equipped))

	var skins: Array[SkinResource] = SkinLibrary.all_for_character(_selected_character)
	for skin in skins:
		_cards_column.add_child(_make_skin_card(skin, equipped))

	if skins.is_empty():
		_cards_column.add_child(MenuKit.label("No skins authored for %s yet." % char_name, &"MutedLabel", true))


## The always-owned baseline look. Equipping it clears the character's skin.
func _make_default_card(character_id: String, equipped_id: String) -> PanelContainer:
	var is_equipped: bool = equipped_id.is_empty()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(MenuTheme.BORDER, is_equipped))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(row)

	row.add_child(_make_swatch(SkinResource.DEFAULT_TINT, _initial_for(character_id)))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)

	text.add_child(MenuKit.label("Default", &"SubheadingLabel"))
	var blurb := MenuKit.label("The canonical look. Always available.", &"DimLabel", true)
	blurb.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	text.add_child(blurb)

	row.add_child(_make_action_column(is_equipped, true, null, character_id, ""))
	return card


func _make_skin_card(skin: SkinResource, equipped_id: String) -> PanelContainer:
	var skin_id: String = String(skin.id)
	var is_equipped: bool = skin_id == equipped_id
	var owned: bool = _shop != null and _shop.owns(skin_id)
	var accent: Color = rarity_color(skin.rarity)

	var card := PanelContainer.new()
	card.name = "Card_" + skin_id
	card.add_theme_stylebox_override("panel", _card_style(accent, is_equipped))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(row)

	row.add_child(_make_swatch(skin.tint, _initial_for(String(skin.character_id))))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.SP_S)
	text.add_child(head)

	head.add_child(MenuKit.label(skin.display_name, &"SubheadingLabel"))
	var chip := MenuKit.badge(skin.rarity_name().to_upper(), accent)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chip)

	if not skin.description.is_empty():
		var blurb := MenuKit.label(skin.description, &"DimLabel", true)
		blurb.custom_minimum_size = Vector2(320.0, 0.0)
		blurb.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		text.add_child(blurb)

	row.add_child(_make_action_column(is_equipped, owned, skin, String(skin.character_id), skin_id))
	return card


## The single call-to-action for a card, in priority order: EQUIPPED > Equip
## (owned) > price + Buy (buyable) > "Gacha only". The button state is a HINT --
## [SkinShop] re-checks ownership and balance when it is pressed.
func _make_action_column(is_equipped: bool, owned: bool, skin: SkinResource,
		character_id: String, skin_id: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(150.0, 0.0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)

	if is_equipped:
		var tag := MenuKit.badge("EQUIPPED", MenuTheme.GOLD, true)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(tag)
		return column

	if owned:
		var equip_button := MenuKit.button("Equip", &"", 140, 44)
		equip_button.pressed.connect(_on_equip_pressed.bind(character_id, skin_id))
		column.add_child(equip_button)
		return column

	if skin != null and skin.is_buyable():
		var price := MenuKit.label("%d pts" % skin.price, &"DimLabel")
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		column.add_child(price)

		var buy_button := MenuKit.button("Buy", &"", 140, 44)
		buy_button.disabled = _shop == null or _shop.points() < skin.price
		buy_button.pressed.connect(_on_buy_pressed.bind(skin_id))
		column.add_child(buy_button)
		return column

	var locked := MenuKit.label("Gacha only", &"MutedLabel")
	locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(locked)
	return column


## Card frame: a grove card with the rarity edge, upgraded to a gold frame with the top
## crest when this look is the one currently worn (a hero surface, per the style rules).
func _card_style(accent: Color, equipped: bool) -> OrnateStyleBox:
	var box: OrnateStyleBox = MenuTheme.accented_card(accent, SIDE_LEFT, MenuTheme.PANEL, 0.96, equipped)
	if equipped:
		box.border_color = MenuTheme.GOLD
		box.border_width = 2.5
		box.inner_line_color = Color(MenuTheme.GOLD_LITE, 0.6)
		box.ornament_color = MenuTheme.GOLD_LITE
	box.content_margin_left = 18.0
	box.content_margin_right = 16.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	return box


## The look's tint shown as a heraldic crest carrying the character's initial -- the
## same shield the squad picker uses, filled with the skin's colour.
func _make_swatch(color: Color, letter: String = "", px: float = 52.0) -> Control:
	var crest := MenuKit.crest(letter, color, MenuTheme.GOLD_DK, px)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return crest


func _initial_for(character_id: String) -> String:
	var res: CharacterResource = CharacterLibrary.get_character(StringName(character_id))
	var n: String = res.display_name if res != null else character_id
	return n.substr(0, 1).to_upper() if not n.is_empty() else "?"


## Badge / accent colour for a [enum SkinResource.Rarity]. Static + total so the
## mapping is assertable without a screen.
static func rarity_color(rarity: int) -> Color:
	if rarity < 0 or rarity >= RARITY_COLORS.size():
		return RARITY_COLORS[0]
	return RARITY_COLORS[rarity]


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_equip_pressed(character_id: String, skin_id: String) -> void:
	if _shop == null:
		return
	if _shop.equip(character_id, skin_id):
		_set_status("")
	else:
		_set_status("Could not equip that skin.", "warn")
	_rebuild_cards()
	_refocus_rail()


func _on_buy_pressed(skin_id: String) -> void:
	if _shop == null:
		return
	var skin: SkinResource = SkinLibrary.find(skin_id)
	var result: Dictionary = _shop.buy(skin)
	if bool(result.get("ok", false)):
		# A just-bought skin goes straight on -- that is what the player wanted; it
		# is one click to put the default back. equip() re-verifies ownership.
		_shop.equip(String(skin.character_id), skin_id)
		_set_status("Unlocked %s." % skin.display_name, "ok")
	else:
		_set_status(_reason_text(String(result.get("reason", ""))), "warn")
	_refresh_points()
	_rebuild_cards()
	_refocus_rail()


func _on_roll_pressed() -> void:
	if _shop == null:
		return
	var result: Dictionary = _shop.roll(_rng)
	_refresh_points()
	_rebuild_cards()
	if bool(result.get("ok", false)):
		_set_status("")
		_show_reveal(result)
	else:
		_set_status(_reason_text(String(result.get("reason", ""))), "warn")


func _on_points_changed(_balance: int) -> void:
	_refresh_points()


func _refresh_points() -> void:
	var balance: int = _shop.points() if _shop != null else 0
	if _points_label != null:
		_points_label.text = "%d PTS" % balance
	if _roll_button != null:
		_roll_button.disabled = _shop == null or not _shop.can_roll()


func _set_status(message: String, tone: String = "") -> void:
	if _status_label != null:
		MenuKit.set_status(_status_label, message, tone)


## The cards were rebuilt under the pressed button, which took keyboard / pad focus with
## it: hand focus back to the active roster row so navigation never lands on nothing.
func _refocus_rail() -> void:
	if not is_inside_tree():
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		return
	_focus_later(_row_buttons.get(_selected_character, _back_button))


func _reason_text(reason: String) -> String:
	match reason:
		SkinShop.REASON_INSUFFICIENT:
			return "Not enough points."
		SkinShop.REASON_ALREADY_OWNED:
			return "Already owned."
		SkinShop.REASON_NOT_BUYABLE:
			return "That skin is gacha-only."
		SkinShop.REASON_NO_PROFILE:
			return "No player profile available."
		SkinShop.REASON_EMPTY_POOL:
			return "No skins available to roll."
		_:
			return "That did not work."


# ---------------------------------------------------------------------------
# Reveal
# ---------------------------------------------------------------------------

func _show_reveal(result: Dictionary) -> void:
	if _reveal_layer == null or _reveal_body == null:
		return
	for child in _reveal_body.get_children():
		_reveal_body.remove_child(child)
		child.queue_free()

	var skin: SkinResource = SkinLibrary.find(String(result.get("skin_id", "")))
	var rarity: int = int(result.get("rarity", SkinResource.Rarity.COMMON))
	var accent: Color = rarity_color(rarity)
	var is_dup: bool = bool(result.get("is_duplicate", false))

	# The card's frame takes the rarity colour (the crest stays gold).
	var frame := MenuTheme.card_box(MenuTheme.PANEL, accent)
	frame.crest = true
	frame.border_width = 2.5
	_reveal_card.add_theme_stylebox_override("panel", frame)

	var heading := MenuKit.label("DUPLICATE" if is_dup else "NEW SKIN", &"TitleLabel")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", accent.lightened(0.25))
	_reveal_body.add_child(heading)

	var rule := GroveRule.new()
	rule.centered = true
	rule.color = accent
	rule.custom_minimum_size = Vector2(240.0, 12.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reveal_body.add_child(rule)

	var swatch_row := HBoxContainer.new()
	swatch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	swatch_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	_reveal_body.add_child(swatch_row)
	var owner_id: String = String(skin.character_id) if skin != null else ""
	swatch_row.add_child(_make_swatch(skin.tint if skin != null else SkinResource.DEFAULT_TINT,
		_initial_for(owner_id) if not owner_id.is_empty() else "?", 72.0))

	var name_label := MenuKit.label(skin.display_name if skin != null else String(result.get("skin_id", "")),
		&"HeadingLabel")
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	swatch_row.add_child(name_label)

	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveal_body.add_child(chip_row)
	var rarity_name: String = skin.rarity_name() if skin != null else "Common"
	chip_row.add_child(MenuKit.badge(rarity_name.to_upper(), accent))

	var owner_line := MenuKit.label("", &"DimLabel")
	if skin != null:
		var owner_res: CharacterResource = CharacterLibrary.get_character(skin.character_id)
		owner_line.text = "for %s" % (owner_res.display_name if owner_res != null else String(skin.character_id))
	owner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal_body.add_child(owner_line)

	if is_dup:
		var refund := MenuKit.label("Already owned -- refunded %d pts." % int(result.get("refund", 0)), &"MutedLabel")
		refund.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_reveal_body.add_child(refund)

	var close := MenuKit.button("Continue", MenuKit.PRIMARY, 220, 54)
	close.name = "ContinueButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_hide_reveal)
	_reveal_body.add_child(close)

	_reveal_layer.visible = true
	# Modal for keyboard / pad too: the scrim eats clicks, this keeps focus from walking
	# out to the page behind it.
	_set_page_focusable(false)
	_play_reveal_flash(accent)
	close.grab_focus()


## Rarity flash + card fade-in, gated on the presentation setting: with animations
## off the reveal simply appears at full strength (no tween, no wait).
func _play_reveal_flash(accent: Color) -> void:
	if _reveal_card == null or _reveal_flash == null:
		return
	if not _animations_on():
		_reveal_card.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_reveal_flash.color = Color(accent.r, accent.g, accent.b, 0.0)
		return
	_reveal_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_reveal_flash.color = Color(accent.r, accent.g, accent.b, 0.75)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_reveal_card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18)
	tween.tween_property(_reveal_flash, "color", Color(accent.r, accent.g, accent.b, 0.0), 0.45)


func _animations_on() -> bool:
	var settings: Node = get_node_or_null("/root/GameSettings")
	if settings == null or not settings.has_method("animations_on"):
		return true
	return bool(settings.animations_on())


func _hide_reveal() -> void:
	if _reveal_layer != null:
		_reveal_layer.visible = false
	_set_page_focusable(true)
	if _roll_button != null and not _roll_button.disabled:
		_focus_later(_roll_button)
	else:
		_refocus_rail()


## Take every focusable control on the page out of (or back into) focus navigation while
## the reveal is up. Original focus modes are remembered per control.
func _set_page_focusable(enabled: bool) -> void:
	if _page_root != null and is_instance_valid(_page_root):
		_walk_focus(_page_root, enabled)


func _walk_focus(node: Node, enabled: bool) -> void:
	if node is Control:
		var c := node as Control
		if enabled:
			if c.has_meta(&"_modal_focus_mode"):
				c.focus_mode = c.get_meta(&"_modal_focus_mode")
				c.remove_meta(&"_modal_focus_mode")
		elif c.focus_mode != Control.FOCUS_NONE:
			c.set_meta(&"_modal_focus_mode", c.focus_mode)
			c.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_walk_focus(child, enabled)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	MenuNav.change_scene(self, PROFILE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not MenuNav.is_back_event(event):
		return
	get_viewport().set_input_as_handled()
	# Cancel dismisses an open reveal first, then leaves the screen.
	if _reveal_layer != null and _reveal_layer.visible:
		_hide_reveal()
	else:
		_on_back_pressed()


## [MenuNav.focus_deferred], but safe when the control leaves the tree first (a repaint
## rebuilt it, or the screen closed) -- grab_focus() on a detached control is an engine error.
func _focus_later(c: Control) -> void:
	if c == null:
		return
	# Captured by instance id, not by reference: a freed capture is itself an engine error.
	var id: int = c.get_instance_id()
	(func() -> void:
		var ctl := instance_from_id(id) as Control
		if ctl != null and ctl.is_inside_tree() and ctl.is_visible_in_tree():
			ctl.grab_focus()).call_deferred()
