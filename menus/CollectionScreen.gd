extends Control
class_name CollectionScreen

## The COLLECTION: browse the roster, see every cosmetic skin authored for a
## character, equip what you own, buy what you can afford, and roll the gacha.
##
## LAYOUT. Two columns under a header, over a bottom bar:
##   * LEFT  -- the roster rail. One row per character (name + element chip); the
##     active row takes the gold left-edge NavButtonActive treatment.
##   * RIGHT -- a card per look for the selected character: the DEFAULT look first,
##     then every skin. A card carries its name, blurb, rarity chip (grey/blue/gold),
##     a tint swatch, and exactly ONE call to action -- EQUIPPED (gold framed),
##     "Equip" (owned), "price + Buy" (buyable), or "Gacha only" (price 0).
##   * BOTTOM -- the live points balance (kept in step with the profile's
##     points_changed signal) and the GACHA ROLL button.
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

## Collection is reached through Profile now (Profile chip -> ProfileScreen -> Collection
## card), not directly off the main menu -- Back and ESC walk that same path in reverse.
const PROFILE_SCENE: String = "res://menus/ProfileScreen.tscn"

## Rarity chip / card-accent colours: grey, blue, gold.
const RARITY_COLORS: Array[Color] = [
	Color("9a93a8"),  # COMMON
	Color("4f8fe0"),  # RARE
	Color("e6a64b"),  # EPIC
]

const ROSTER_WIDTH: float = 300.0
const ROW_HEIGHT: float = 44.0

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
var _roster_column: VBoxContainer = null
var _cards_column: VBoxContainer = null
var _detail_title: Label = null
var _points_label: Label = null
var _status_label: Label = null
var _roll_button: Button = null
var _reveal_layer: Control = null
var _reveal_card: PanelContainer = null
var _reveal_body: VBoxContainer = null
var _reveal_flash: ColorRect = null

## character id -> its rail Button / name Label, for active-state restyling.
var _row_buttons: Dictionary = {}
var _row_labels: Dictionary = {}


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	add_child(page)

	page.add_child(_build_header())

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	page.add_child(_wrap_margin(body, 18, 0))

	body.add_child(_build_roster_panel())
	body.add_child(_build_detail_panel())

	page.add_child(_wrap_margin(_build_bottom_bar(), 18, 14))

	_build_reveal_layer()


## Wrap [param control] in a MarginContainer with horizontal [param h] and bottom
## [param v] margins, expanding to fill.
func _wrap_margin(control: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_bottom", v)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if (control.size_flags_vertical & Control.SIZE_EXPAND) != 0:
		m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(control)
	return m


func _build_header() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "Header"
	bar.add_theme_constant_override("separation", 14)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "< Back"
	back.custom_minimum_size = Vector2(120.0, 0.0)
	back.pressed.connect(_on_back_pressed)
	bar.add_child(back)

	var title := Label.new()
	title.text = "COLLECTION"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuTheme.style_title(title, 34)
	bar.add_child(title)

	# Balances the Back button so the title stays optically centered.
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(120.0, 0.0)
	bar.add_child(pad)

	return _wrap_margin(bar, 18, 0)


func _build_roster_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "RosterPanel"
	panel.custom_minimum_size = Vector2(ROSTER_WIDTH, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var header := Label.new()
	header.text = "ROSTER"
	MenuTheme.style_section_header(header)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_roster_column = VBoxContainer.new()
	_roster_column.name = "RosterColumn"
	_roster_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_column.add_theme_constant_override("separation", 2)
	scroll.add_child(_roster_column)

	for cid in _character_ids:
		_roster_column.add_child(_make_roster_row(cid))

	if _character_ids.is_empty():
		var empty := Label.new()
		empty.text = "No roster characters found."
		MenuTheme.style_caption(empty)
		_roster_column.add_child(empty)

	return panel


## One rail entry: a NavButton whose content (name + element chip) is drawn by an
## overlaid, click-through HBox, so the row highlights as a single target.
func _make_roster_row(character_id: StringName) -> Button:
	var res: CharacterResource = CharacterLibrary.get_character(character_id)
	var row := Button.new()
	row.name = "Row_" + String(character_id)
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.theme_type_variation = "NavButton"
	row.text = ""
	row.pressed.connect(_select_character.bind(character_id))

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14.0
	content.offset_right = -12.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)

	var name_label := Label.new()
	name_label.text = res.display_name if res != null else String(character_id)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	name_label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	content.add_child(name_label)

	var element: String = String(res.element) if res != null else ""
	if not element.is_empty():
		content.add_child(MenuTheme.make_chip(element.capitalize(), ConquestTheme.element_color(element)))

	_row_buttons[character_id] = row
	_row_labels[character_id] = name_label
	return row


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DetailPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	_detail_title = Label.new()
	_detail_title.text = "SKINS"
	MenuTheme.style_section_header(_detail_title)
	column.add_child(_detail_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_cards_column = VBoxContainer.new()
	_cards_column.name = "CardsColumn"
	_cards_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_column.add_theme_constant_override("separation", 8)
	scroll.add_child(_cards_column)

	return panel


func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	panel.name = "BottomBar"

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	panel.add_child(bar)

	_points_label = Label.new()
	_points_label.text = "0 PTS"
	_points_label.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	_points_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_points_label)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	_status_label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	bar.add_child(_status_label)

	var hint := Label.new()
	hint.text = "Duplicates refund %d pts" % SkinLibrary.DUPLICATE_REFUND
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MenuTheme.style_caption(hint)
	bar.add_child(hint)

	_roll_button = Button.new()
	_roll_button.name = "RollButton"
	_roll_button.text = "GACHA ROLL  (%d pts)" % SkinShop.GACHA_COST
	_roll_button.theme_type_variation = "SelectedButton"
	_roll_button.pressed.connect(_on_roll_pressed)
	bar.add_child(_roll_button)

	return panel


## The reveal overlay: a dimming scrim plus a centered card the roll result is
## rendered into. Built once, hidden, and reused for every roll.
func _build_reveal_layer() -> void:
	_reveal_layer = Control.new()
	_reveal_layer.name = "RevealLayer"
	_reveal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_layer.visible = false
	add_child(_reveal_layer)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(MenuTheme.DARK.r, MenuTheme.DARK.g, MenuTheme.DARK.b, 0.82)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP (not IGNORE): the scrim swallows clicks so the shop behind it cannot be
	# operated while a reveal is up.
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_reveal_layer.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_layer.add_child(center)

	_reveal_card = PanelContainer.new()
	_reveal_card.name = "RevealCard"
	_reveal_card.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(_reveal_card)

	_reveal_body = VBoxContainer.new()
	_reveal_body.add_theme_constant_override("separation", 10)
	_reveal_card.add_child(_reveal_body)

	# Rarity flash: a full-card colour wash tweened out over the reveal.
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
		button.theme_type_variation = "NavButtonActive" if active else "NavButton"
		var label: Label = _row_labels.get(cid, null)
		if label != null and is_instance_valid(label):
			label.add_theme_color_override("font_color", MenuTheme.GOLD if active else MenuTheme.CREAM_DIM)


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
		var note := Label.new()
		note.text = "No skins authored for %s yet." % char_name
		MenuTheme.style_caption(note)
		_cards_column.add_child(note)


## The always-owned baseline look. Equipping it clears the character's skin.
func _make_default_card(character_id: String, equipped_id: String) -> PanelContainer:
	var is_equipped: bool = equipped_id.is_empty()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(MenuTheme.BORDER, is_equipped))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	row.add_child(_make_swatch(SkinResource.DEFAULT_TINT))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)

	var title := Label.new()
	title.text = "Default"
	title.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	text.add_child(title)

	var blurb := Label.new()
	blurb.text = "The canonical look. Always available."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	blurb.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
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
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	row.add_child(_make_swatch(skin.tint))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	text.add_child(head)

	var title := Label.new()
	title.text = skin.display_name
	title.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	head.add_child(title)

	head.add_child(MenuTheme.make_chip(skin.rarity_name().to_upper(), accent))

	if not skin.description.is_empty():
		var blurb := Label.new()
		blurb.text = skin.description
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(320.0, 0.0)
		blurb.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		blurb.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
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
		var tag := Label.new()
		tag.text = "EQUIPPED"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		tag.add_theme_color_override("font_color", MenuTheme.GOLD)
		column.add_child(tag)
		return column

	if owned:
		var equip_button := Button.new()
		equip_button.text = "Equip"
		equip_button.pressed.connect(_on_equip_pressed.bind(character_id, skin_id))
		column.add_child(equip_button)
		return column

	if skin != null and skin.is_buyable():
		var price := Label.new()
		price.text = "%d pts" % skin.price
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		price.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		column.add_child(price)

		var buy_button := Button.new()
		buy_button.text = "Buy"
		buy_button.disabled = _shop == null or _shop.points() < skin.price
		buy_button.pressed.connect(_on_buy_pressed.bind(skin_id))
		column.add_child(buy_button)
		return column

	var locked := Label.new()
	locked.text = "Gacha only"
	locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	locked.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	locked.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	column.add_child(locked)
	return column


## Card frame: the rarity-accented left edge, upgraded to a full gold border when
## this look is the one currently worn.
func _card_style(accent: Color, equipped: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = MenuTheme.card_box(accent)
	if equipped:
		box.set_border_width_all(2)
		box.border_width_left = 5
		box.border_color = MenuTheme.GOLD
	return box


func _make_swatch(color: Color) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(46.0, 46.0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = MenuTheme.BORDER
	frame.add_theme_stylebox_override("panel", sb)
	return frame


## Chip / accent colour for a [enum SkinResource.Rarity]. Static + total so the
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
		_set_status("Could not equip that skin.")
	_rebuild_cards()


func _on_buy_pressed(skin_id: String) -> void:
	if _shop == null:
		return
	var skin: SkinResource = SkinLibrary.find(skin_id)
	var result: Dictionary = _shop.buy(skin)
	if bool(result.get("ok", false)):
		# A just-bought skin goes straight on -- that is what the player wanted; it
		# is one click to put the default back. equip() re-verifies ownership.
		_shop.equip(String(skin.character_id), skin_id)
		_set_status("Unlocked %s." % skin.display_name)
	else:
		_set_status(_reason_text(String(result.get("reason", ""))))
	_refresh_points()
	_rebuild_cards()


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
		_set_status(_reason_text(String(result.get("reason", ""))))


func _on_points_changed(_balance: int) -> void:
	_refresh_points()


func _refresh_points() -> void:
	var balance: int = _shop.points() if _shop != null else 0
	if _points_label != null:
		_points_label.text = "%d PTS" % balance
	if _roll_button != null:
		_roll_button.disabled = _shop == null or not _shop.can_roll()


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


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

	var heading := Label.new()
	heading.text = "DUPLICATE" if is_dup else "NEW SKIN"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	heading.add_theme_color_override("font_color", accent)
	_reveal_body.add_child(heading)

	var swatch_row := HBoxContainer.new()
	swatch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	swatch_row.add_theme_constant_override("separation", 10)
	_reveal_body.add_child(swatch_row)
	swatch_row.add_child(_make_swatch(skin.tint if skin != null else SkinResource.DEFAULT_TINT))

	var name_label := Label.new()
	name_label.text = skin.display_name if skin != null else String(result.get("skin_id", ""))
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	swatch_row.add_child(name_label)

	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveal_body.add_child(chip_row)
	var rarity_name: String = skin.rarity_name() if skin != null else "Common"
	chip_row.add_child(MenuTheme.make_chip(rarity_name.to_upper(), accent))

	var owner_line := Label.new()
	if skin != null:
		var owner_res: CharacterResource = CharacterLibrary.get_character(skin.character_id)
		owner_line.text = "for %s" % (owner_res.display_name if owner_res != null else String(skin.character_id))
	else:
		owner_line.text = ""
	owner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuTheme.style_caption(owner_line)
	_reveal_body.add_child(owner_line)

	if is_dup:
		var refund := Label.new()
		refund.text = "Already owned -- refunded %d pts." % int(result.get("refund", 0))
		refund.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		refund.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		refund.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		_reveal_body.add_child(refund)

	var close := Button.new()
	close.text = "Continue"
	close.pressed.connect(_hide_reveal)
	_reveal_body.add_child(close)

	_reveal_layer.visible = true
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


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(PROFILE_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		# ESC dismisses an open reveal first, then leaves the screen.
		if _reveal_layer != null and _reveal_layer.visible:
			_hide_reveal()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
