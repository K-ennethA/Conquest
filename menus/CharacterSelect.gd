extends Control

## Squad-picker screen shown before a battle, for every map mode (Skirmish / Siege / Local
## Versus / Local Siege), Arena, Challenge and Campaign launches. The player chooses which
## characters make up their player-0 squad, up to a mode-derived limit, then confirms into
## the battle.
##
## Launch paths (all change to THIS scene, then Character Select dispatches):
##   * Campaign launch  -- CampaignController stages a chapter (map already staged in
##                         GameSettings). MAX = the chapter's squad_size. Confirm locks the
##                         pick, stages the chapter's story intro, and loads GameWorld.tscn.
##   * Challenge launch -- ChallengeController stages a challenge (map already staged).
##                         MAX = the author's challenger_squad_size. Confirm locks the pick and
##                         loads GameWorld.tscn.
##   * Arena launch     -- MatchSetup (arena variant) stages a pending run on ArenaController.
##                         MAX = ArenaController.pending_squad_size(). Confirm calls
##                         begin_pending_run(), which starts the run AND changes scene itself.
##   * Map launch       -- MatchSetup stages GameSettings.selected_map_path and comes here.
##                         MAX = number of player-0 START spawn slots on that map. Confirm
##                         loads GameWorld.tscn itself.
##
## Layout (built in code with MenuKit / MenuTheme -- the "illuminated grove" look; the .tscn is
## just a Control root):
##   squad bar (numbered slots -- click one to unpick it -- + count)
##   unit card grid (crest / real portrait, element + role, key stats, pick-order badge)  |
##     detail pane for the focused / hovered unit (3D model or crest, tags, description, stat
##     bars, persistent ITEM with Equip, abilities, moves)
##   TEAM ITEMS chips (squad-wide equipment)
##   key hints + inline message  ..  Back / To Battle
## Every dependency is null-guarded: a missing autoload, an unreadable map, or an empty
## roster all degrade gracefully (fall back to MAX=4 / "Battle", or offer only BACK).

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const CAMPAIGN_SCREEN_SCENE := "res://menus/CampaignScreen.tscn"
const DEFAULT_MAX := 4
const GRID_COLUMNS := 3
## Crest sizes: the small shield on each roster card and the big one in the detail pane
## (shown when the unit has no 3D model to turn-table).
const CARD_CREST_PX := 46.0
const DETAIL_CREST_PX := 96.0

# Characters excluded from the pickable roster regardless of is_boss: the neutral
# beast and the summon-only undead body are never player squad picks.
const EXCLUDED_IDS := ["undead"]

## Stats shown as bars in the detail pane: [key, label].
const STAT_ROWS := [
	["health", "HP"], ["attack", "Attack"], ["defense", "Defense"], ["magic", "Magic"],
	["magic_defense", "Resist"], ["speed", "Speed"], ["movement", "Move"], ["range", "Range"],
]

## Optional override for where Back returns on a MAP launch. A caller that is not MatchSetup
## (e.g. a caller that is not MatchSetup) sets it before changing here, via
## [code]preload("res://menus/CharacterSelect.gd").return_scene = path[/code]; empty = Match
## Setup. Consumed (cleared) on Back and on Confirm so a stale value never leaks into a later
## launch. Campaign / Challenge / Arena launches always return to their own screens.
static var return_scene: String = ""

# --- Mode / selection state -------------------------------------------------
var _is_arena: bool = false
var _is_challenge: bool = false
var _is_campaign: bool = false
var _max_units: int = DEFAULT_MAX
var _destination: String = "Battle"
# Ordered list of chosen character_id STRINGS (click order preserved).
var _chosen_ids: Array = []
# character_id String -> its toggle Button, so we can refresh visuals / disabled state.
var _unit_buttons: Dictionary = {}
# character_id String -> the order badge on its card ("1", "2", ...).
var _order_badges: Dictionary = {}
# character_id String -> the crest on its card (a PortraitCache texture is stacked in it).
var _card_crests: Dictionary = {}
# character_id String -> roster entry Dictionary { id, name, element, role, stats, chr }.
var _entries: Dictionary = {}
var _stat_max: Dictionary = {}

# --- Live node refs ---------------------------------------------------------
var _counter_label: Label = null
var _message_label: Label = null
var _confirm_btn: Button = null
var _back_btn: Button = null
## The unit-card grid's scroller (null when the roster is empty).
var _roster_scroll: ScrollContainer = null
var _slots: HBoxContainer = null

# Detail pane refs.
var _detail_name: Label = null
var _detail_tags: HBoxContainer = null
var _detail_desc: Label = null
var _detail_stats: GridContainer = null
var _detail_model: UnitPreview3D = null
var _detail_emblem: PanelContainer = null
var _detail_action_hint: Label = null
var _detail_ability_box: VBoxContainer = null
var _detail_moves_box: VBoxContainer = null
## The character currently rendered in the details pane ("" = none). The Equip button acts
## on whoever is SHOWN, and a slow PortraitCache callback re-checks it before applying.
var _shown_id: String = ""

# --- Item loadout refs ------------------------------------------------------
# Equipment is PERSISTENT and profile-scoped (see [ItemInventory]) rather than part of the
# squad pick, so it is edited here but confirmed immediately: every change writes straight to
# the inventory and saves, and is in force the moment the player enters a battle -- including
# for characters they did not pick this time.
var _detail_item_label: Label = null
var _detail_item_btn: Button = null
## The TEAM ITEMS chips, one per [constant ItemInventory.TEAM_SLOTS].
var _team_chips: Array[Button] = []
## Shared picker for both surfaces. One popup, two modes -- see [method _open_item_popup].
var _item_popup: PopupMenu = null
## Item ids parallel to the popup's entries; index 0 is always the "No item" clear entry ("").
var _popup_item_ids: Array[String] = []
## Which surface opened the popup: a character id (UNIT scope) XOR a team slot index (>= 0).
var _popup_character_id: String = ""
var _popup_team_slot: int = -1

# --- Evolution (docs/design/EVOLUTION.md §5) ---------------------------------
## The GROWTH block in the detail pane (gems, stage badge, EVOLVE).
var _evo_block: EvolutionDetailBlock = null


func _ready() -> void:
	_resolve_mode()
	_build_ui()
	_refresh_selection_visuals()
	_refresh_team_chips()


# --- Mode + limit resolution ------------------------------------------------

## Decide which launch this is (Campaign / Challenge / Arena / Map) and compute the pick
## limit MAX.
func _resolve_mode() -> void:
	# Campaign launch: the map is already staged in GameSettings by CampaignController.
	# MAX = the chapter's squad_size. Confirm runs the normal map -> GameWorld path (the
	# map is staged), so only the pick cap + header + Back destination differ.
	var campaign := get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("has_pending_chapter") and campaign.has_pending_chapter():
		_is_campaign = true
		_destination = campaign.pending_name() if campaign.has_method("pending_name") else "Campaign"
		var chsize := DEFAULT_MAX
		if campaign.has_method("pending_squad_size"):
			chsize = int(campaign.pending_squad_size())
		_max_units = chsize if chsize > 0 else DEFAULT_MAX
		return

	# Challenge launch: the map is already staged in GameSettings by ChallengeController.
	# MAX = the author's challenger_squad_size. Confirm runs the normal map -> GameWorld
	# path (no special-casing needed there); only the pick limit + header differ.
	var challenge := get_node_or_null("/root/ChallengeController")
	if challenge != null and challenge.has_method("has_pending_challenge") and challenge.has_pending_challenge():
		_is_challenge = true
		_destination = challenge.pending_name() if challenge.has_method("pending_name") else "Challenge"
		var csize := DEFAULT_MAX
		if challenge.has_method("pending_squad_size"):
			csize = int(challenge.pending_squad_size())
		_max_units = csize if csize > 0 else DEFAULT_MAX
		return

	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run():
		_is_arena = true
		_destination = "Arena Run"
		var size := DEFAULT_MAX
		if arena.has_method("pending_squad_size"):
			size = int(arena.pending_squad_size())
		_max_units = size if size > 0 else DEFAULT_MAX
		return

	# Map launch: MAX = number of player-0 spawn slots on the selected map.
	_is_arena = false
	_max_units = DEFAULT_MAX
	_destination = "Battle"

	var settings := get_node_or_null("/root/GameSettings")
	var map_path := ""
	if settings != null and "selected_map_path" in settings:
		map_path = String(settings.selected_map_path)

	if map_path.is_empty():
		return

	var res := load(map_path) as MapResource
	if res == null:
		return

	if not String(res.map_name).is_empty():
		_destination = String(res.map_name)

	# Only START points are squad slots the player fills. A player-0 Respawn/Endless/
	# Reinforcement point is map FURNITURE (a base, a wave portal) that MapLoader fields
	# from the map's own data - counting those would offer picks that never land
	# (King's Crossing: 4 Start slots + 3 furniture points would read as a 7-pick squad).
	var player0_slots := 0
	for sd in res.unit_spawns:
		if sd is Dictionary and int(sd.get("player_id", 0)) == 0:
			var kind := String(sd.get("spawn_kind", MapResource.SPAWN_KIND_START))
			if kind == MapResource.SPAWN_KIND_START:
				player0_slots += 1

	_max_units = maxi(1, player0_slots) if player0_slots > 0 else DEFAULT_MAX


# --- UI construction --------------------------------------------------------

## Breadcrumb path BEFORE this screen ("CONQUEST / <mode> / <destination>").
func _crumbs() -> Array:
	if _is_campaign:
		return ["Campaign", _destination]
	if _is_challenge:
		return ["Challenges", _destination]
	if _is_arena:
		return ["Arena"]
	return [_map_mode_label(), _destination]


## Which map variant launched this pick. MatchSetup's static requested_mode is the source
## of truth for the local IA; GameSettings.game_mode is the fallback for any other caller.
func _map_mode_label() -> String:
	match MatchSetup.requested_mode:
		MatchConfigPanel.MODE_SIEGE:
			return "Siege"
		MatchConfigPanel.MODE_SIEGE_LOCAL:
			return "Local Siege"
		MatchConfigPanel.MODE_LOCAL:
			return "Local Versus"
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and "game_mode" in settings and settings.game_mode == GameSettings.GameMode.VERSUS:
		return "Local Versus"
	return "Skirmish"


func _build_ui() -> void:
	var page := MenuKit.build_page(self, _crumbs(), "Assemble Your Squad",
		"Choose up to %d unit%s for %s. Selected units deploy in the order you pick them." % [
			_max_units, "" if _max_units == 1 else "s", _destination])

	var roster := _build_roster()

	# --- Squad bar -----------------------------------------------------------
	var bar := HBoxContainer.new()
	bar.name = "SquadBar"
	bar.add_theme_constant_override("separation", MenuTheme.SP_M)
	page.body.add_child(bar)
	var bar_label := MenuKit.section("Squad")
	bar_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(bar_label)
	_slots = HBoxContainer.new()
	_slots.name = "Slots"
	_slots.add_theme_constant_override("separation", MenuTheme.SP_S)
	bar.add_child(_slots)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_counter_label = MenuKit.label("", &"HeadingLabel")
	_counter_label.name = "Counter"
	bar.add_child(_counter_label)

	# --- Grid + detail ---------------------------------------------------------
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	page.body.add_child(row)

	if roster.is_empty():
		# Degrade gracefully: no pickable characters -> message, BACK only.
		var empty_card := MenuKit.card()
		empty_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(empty_card)
		var empty_lbl := MenuKit.label("No characters are available to pick.", &"HeadingLabel")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_card.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "RosterScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = 2.3
		scroll.follow_focus = true
		row.add_child(scroll)
		_roster_scroll = scroll
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for side in ["left", "top", "bottom", "right"]:
			pad.add_theme_constant_override("margin_" + side, 12 if side != "right" else 18)
		scroll.add_child(pad)
		var grid := GridContainer.new()
		grid.name = "RosterGrid"
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", MenuTheme.SP_M)
		grid.add_theme_constant_override("v_separation", MenuTheme.SP_M)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(grid)
		for entry in roster:
			grid.add_child(_make_unit_cell(entry))
		row.add_child(_build_detail_pane())

	# --- Team items ------------------------------------------------------------
	# Directly above the confirm row: these shared slots buff EVERY unit fielded, so they read
	# as a squad-level decision rather than a per-character one.
	page.body.add_child(_build_team_items_row())

	# --- Inline message (limit-reached flash / item moves / guards) ------------
	_message_label = MenuKit.label("", &"")
	_message_label.name = "Message"
	_message_label.visible = false
	page.hints.add_child(_message_label)

	# --- Actions -------------------------------------------------------------
	_back_btn = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_btn)
	_confirm_btn = MenuKit.button("Start Run  >" if _is_arena else "To Battle  >", MenuKit.PRIMARY, 240, 54)
	_confirm_btn.name = "ConfirmButton"
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	# With no pickable roster there is nothing to confirm; hide it, offer only BACK.
	_confirm_btn.visible = not roster.is_empty()
	page.actions.add_child(_confirm_btn)
	MenuKit.add_standard_hints(page.hints, "Add / remove")
	page.hints.move_child(_message_label, page.hints.get_child_count() - 1)

	# Shared item picker, parented to the screen (not to a row) so it can be popped from
	# either the details pane or a team chip. Inherits the screen's grove theme.
	_item_popup = PopupMenu.new()
	_item_popup.name = "ItemPopup"
	_item_popup.id_pressed.connect(_on_item_popup_id_pressed)
	add_child(_item_popup)

	_update_counter()
	if not roster.is_empty():
		var first: Button = _unit_buttons[String(roster[0]["id"])]
		MenuNav.focus_deferred(first)
		# The deferred focus lands BEFORE the grid's first layout pass, so follow_focus scrolls
		# against zero-size rects and parks the grid at its max offset -- the first row opens
		# half cut off under the squad bar. Re-settle once the layout is real (one-shot, so a
		# freed screen simply drops the connection).
		get_tree().process_frame.connect(_settle_roster_scroll, CONNECT_ONE_SHOT)
		_show_detail(String(roster[0]["id"]))
		# Real portraits for the card crests (disk-cached after the first capture). Deferred:
		# PortraitCache parents its capture node under the current scene, which is still
		# setting up its children during _ready.
		call_deferred(&"_request_card_portraits")
	else:
		MenuNav.focus_deferred(_back_btn)


## Scroll the roster back to the top, then (re)reveal whatever card holds focus -- run one
## frame after _ready, once the grid has real sizes. See the call site in _build_ui.
func _settle_roster_scroll() -> void:
	if _roster_scroll == null or not is_instance_valid(_roster_scroll) or not _roster_scroll.is_inside_tree():
		return
	_roster_scroll.scroll_vertical = 0
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focused != null and _roster_scroll.is_ancestor_of(focused):
		_roster_scroll.ensure_control_visible(focused)


func _build_detail_pane() -> Control:
	var card := MenuKit.card(&"CrestCard")
	card.name = "UnitDetail"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(340, 0)

	# The pane carries the full kit (item, abilities, moves with descriptions), so it
	# scrolls rather than stretching the page.
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", MenuTheme.SP_S)
	scroll.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", MenuTheme.SP_L)
	v.add_child(top)
	var art := Control.new()
	art.custom_minimum_size = Vector2(110, 110)
	top.add_child(art)
	_detail_emblem = _emblem("?", MenuTheme.GOLD, DETAIL_CREST_PX)
	_detail_emblem.position = Vector2(14, 7)
	art.add_child(_detail_emblem)
	_add_portrait_slot(_detail_emblem, DETAIL_CREST_PX)
	_detail_model = UnitPreview3D.new()
	_detail_model.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(_detail_model)

	var id_col := VBoxContainer.new()
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.alignment = BoxContainer.ALIGNMENT_CENTER
	id_col.add_theme_constant_override("separation", 6)
	top.add_child(id_col)
	_detail_name = MenuKit.label("", &"HeadingLabel")
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_col.add_child(_detail_name)
	_detail_tags = HBoxContainer.new()
	_detail_tags.add_theme_constant_override("separation", 6)
	id_col.add_child(_detail_tags)
	_detail_action_hint = MenuKit.label("", &"MutedLabel")
	id_col.add_child(_detail_action_hint)
	# GROWTH (evolution): gems + EVOLVE up in the header, where they are seen without scrolling.
	_evo_block = EvolutionDetailBlock.new()
	_evo_block.evolve_requested.connect(_on_evolve_requested)
	id_col.add_child(_evo_block)

	_detail_desc = MenuKit.label("", &"DimLabel", true)
	_detail_desc.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_detail_desc.max_lines_visible = 3
	_detail_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_detail_desc)

	_detail_stats = GridContainer.new()
	_detail_stats.columns = 6
	_detail_stats.add_theme_constant_override("h_separation", MenuTheme.SP_M)
	_detail_stats.add_theme_constant_override("v_separation", 5)
	v.add_child(_detail_stats)

	# --- ITEM (persistent equipment) -----------------------------------------
	v.add_child(HSeparator.new())
	v.add_child(MenuKit.section("Item"))
	var item_row := HBoxContainer.new()
	item_row.name = "ItemRow"
	item_row.add_theme_constant_override("separation", MenuTheme.SP_S)
	v.add_child(item_row)
	_detail_item_label = MenuKit.label("", &"", true)
	_detail_item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_item_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_item_label.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	item_row.add_child(_detail_item_label)
	_detail_item_btn = MenuKit.button("Equip", &"", 104, 40)
	_detail_item_btn.name = "EquipButton"
	_detail_item_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_item_btn.pressed.connect(_on_equip_pressed)
	item_row.add_child(_detail_item_btn)

	# --- ABILITY -----------------------------------------------------------------
	v.add_child(HSeparator.new())
	v.add_child(MenuKit.section("Ability"))
	_detail_ability_box = VBoxContainer.new()
	_detail_ability_box.add_theme_constant_override("separation", 2)
	v.add_child(_detail_ability_box)

	# --- MOVES -------------------------------------------------------------------
	v.add_child(HSeparator.new())
	v.add_child(MenuKit.section("Moves"))
	_detail_moves_box = VBoxContainer.new()
	_detail_moves_box.add_theme_constant_override("separation", 6)
	v.add_child(_detail_moves_box)
	return card


## Assemble the sorted, filtered pickable roster. Each entry is a small Dictionary
## { id, name, element, role, stats, chr }.
func _build_roster() -> Array:
	var entries: Array = []
	var ids: Array = pickable_ids(CharacterLibrary.all_ids(), RosterLedger.unlocked_forms(),
		EvolutionRules.current().hide_locked_forms)
	for id in ids:
		var chr: CharacterResource = CharacterLibrary.get_character(id)
		var id_str := String(chr.character_id)
		var stats := {
			"health": chr.base_health, "attack": chr.base_attack, "defense": chr.base_defense,
			"magic": chr.base_magic, "magic_defense": chr.base_magic_defense,
			"speed": chr.base_speed, "movement": chr.base_movement, "range": chr.attack_range,
		}
		for k in stats:
			_stat_max[k] = maxi(int(_stat_max.get(k, 1)), int(stats[k]))
		var entry := {
			"id": id_str,
			"name": chr.display_name,
			"element": _element_label(chr.element),
			"role": _role_for(chr),
			"stats": stats,
			"chr": chr,
		}
		entries.append(entry)
		_entries[id_str] = entry
	entries.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return entries


## A unit card: element crest (real portrait once PortraitCache has one), name, element /
## role line, key stats, and an order badge once picked. Pressing toggles membership in the
## chosen squad; focusing or hovering it shows the unit in the detail pane.
func _make_unit_cell(entry: Dictionary) -> Control:
	var id_str := String(entry["id"])
	var parts := MenuKit.option_card(Vector2(236, 112), true)
	var btn: Button = parts["button"]
	btn.name = "Unit_" + id_str
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: MarginContainer = parts["margin"]
	# 10px sides / 8px crest gap: at 1280x720 a card is ~240px wide, and a three-digit HP
	# ("HP 108 · ATK 27 · SPD 12") needs every pixel of the text column beside the crest.
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	var content: VBoxContainer = parts["content"]

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	content.add_child(h)
	var ecol := MenuKit.element_color(String(entry["element"]))
	MenuKit.accent_card(btn, ecol)
	var emblem := _emblem(String(entry["name"]).left(1), ecol, CARD_CREST_PX)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_portrait_slot(emblem, CARD_CREST_PX)
	h.add_child(emblem)
	_card_crests[id_str] = emblem

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	var name_lbl := MenuKit.label(String(entry["name"]), &"SubheadingLabel")
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_lbl)
	var kind := MenuKit.label("%s  ·  %s" % [entry["element"], entry["role"]], &"")
	kind.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	kind.add_theme_color_override("font_color", ecol.lightened(0.35))
	kind.clip_text = true
	text.add_child(kind)
	var st: Dictionary = entry["stats"]
	var line := MenuKit.label("HP %d · ATK %d · SPD %d" % [st["health"], maxi(st["attack"], st["magic"]), st["speed"]], &"DimLabel")
	line.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	line.clip_text = true
	text.add_child(line)

	# Pick-order badge (top-right), shown when the unit is in the squad.
	var order := PanelContainer.new()
	var order_sb := MenuTheme.pill_box(MenuTheme.GOLD, MenuTheme.GOLD_LITE)
	order_sb.sheen = 0.35
	order_sb.content_margin_left = 12
	order_sb.content_margin_right = 12
	order.add_theme_stylebox_override("panel", order_sb)
	order.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	order.offset_left = -50
	order.offset_top = 12
	order.offset_right = -14
	order.offset_bottom = 36
	order.visible = false
	var order_lbl := MenuKit.label("1", &"")
	order_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_lbl.add_theme_color_override("font_color", MenuTheme.INK)
	order_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	order.add_child(order_lbl)
	btn.add_child(order)
	_order_badges[id_str] = order

	# Growth pips (bottom-right) for a unit growing toward an evolution.
	var pips := GrowthGems.card_pips(id_str)
	if pips != null:
		btn.add_child(pips)

	MenuKit.ignore_mouse(btn)
	MenuNav.hover_focus(btn)
	btn.focus_entered.connect(_show_detail.bind(id_str))
	btn.pressed.connect(_on_unit_pressed.bind(id_str))
	_unit_buttons[id_str] = btn
	return btn


## The unit's heraldic crest: element-coloured shield, gold rim, Cinzel initial.
func _emblem(letter: String, color: Color, px: float) -> PanelContainer:
	return MenuKit.crest(letter, color, MenuTheme.GOLD_DK, px)


# --- Portraits (PortraitCache) -------------------------------------------------
#
# Stack-and-swap, as in UnitInfoPanel / TurnQueue: the crest's Cinzel initial is the
# fallback shown immediately and whenever there is no real capture; a PortraitCache texture
# is stacked inside the shield and swapped in the moment its resolution callback fires.

## Stack a hidden portrait TextureRect inside [param crest], inset so the head-and-shoulders
## capture sits within the shield's rim.
func _add_portrait_slot(crest: PanelContainer, px: float) -> void:
	var inset := MarginContainer.new()
	inset.name = "PortraitInset"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left", int(px * 0.10))
	inset.add_theme_constant_override("margin_right", int(px * 0.10))
	inset.add_theme_constant_override("margin_top", int(px * 0.08))
	inset.add_theme_constant_override("margin_bottom", 0)
	inset.visible = false
	crest.add_child(inset)
	var rect := TextureRect.new()
	rect.name = "PortraitTex"
	# IGNORE_SIZE: the 256px capture must never grow the crest past its authored size.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(rect)


## Show [param tex] in [param crest] (null = back to the Cinzel initial).
func _set_crest_portrait(crest: PanelContainer, tex: Texture2D) -> void:
	if crest == null or not is_instance_valid(crest):
		return
	var inset := crest.get_node_or_null("PortraitInset") as Control
	if inset == null:
		return
	var rect := inset.get_node_or_null("PortraitTex") as TextureRect
	if rect != null:
		rect.texture = tex
	inset.visible = tex != null
	var initial := crest.get_node_or_null("Initial") as Control
	if initial != null:
		initial.visible = tex == null


## Portrait capture needs a renderer; headless runs (tests, the dedicated server) skip it so
## no capture node is ever parented into a test's scene.
func _portraits_enabled() -> bool:
	return DisplayServer.get_name() != "headless"


func _request_card_portraits() -> void:
	if not _portraits_enabled() or not is_inside_tree():
		return
	for id_str in _card_crests.keys():
		var cached: Texture2D = PortraitCache.get_cached(id_str)
		if cached != null:
			_set_crest_portrait(_card_crests[id_str], cached)
		else:
			PortraitCache.get_portrait(id_str, _on_card_portrait_resolved.bind(String(id_str)))


func _on_card_portrait_resolved(tex: Texture2D, id_str: String) -> void:
	if tex == null or not is_inside_tree():
		return
	_set_crest_portrait(_card_crests.get(id_str), tex)
	if id_str == _shown_id:
		_set_crest_portrait(_detail_emblem, tex)


## Repaint the detail crest's portrait for [param id_str]: an already-cached capture shows at
## once; otherwise the initial stays up and a request is issued. The callback re-checks
## [member _shown_id], so a slow first capture can never clobber a newer selection.
func _refresh_detail_portrait(id_str: String) -> void:
	_set_crest_portrait(_detail_emblem, null)
	if not _portraits_enabled() or not is_inside_tree():
		return
	var cached: Texture2D = PortraitCache.get_cached(id_str)
	if cached != null:
		_set_crest_portrait(_detail_emblem, cached)
		return
	PortraitCache.get_portrait(id_str, _on_detail_portrait_resolved.bind(id_str))


func _on_detail_portrait_resolved(tex: Texture2D, id_str: String) -> void:
	if tex == null or not is_inside_tree() or _shown_id != id_str:
		return
	_set_crest_portrait(_detail_emblem, tex)


# --- Detail pane -------------------------------------------------------------

func _show_detail(id_str: String) -> void:
	var entry: Dictionary = _entries.get(id_str, {})
	if entry.is_empty() or _detail_name == null:
		return
	_shown_id = id_str
	var chr: CharacterResource = entry["chr"]
	var ecol := MenuKit.element_color(String(entry["element"]))
	_detail_name.text = String(entry["name"])
	for c in _detail_tags.get_children():
		c.queue_free()
	_detail_tags.add_child(MenuKit.badge(String(entry["element"]), ecol))
	_detail_tags.add_child(MenuKit.badge(String(entry["role"]), MenuTheme.TEXT_DIM))
	if chr.movement_kind != CombatTypes.MovementKind.GROUND:
		_detail_tags.add_child(MenuKit.badge(String(CombatTypes.MovementKind.keys()[chr.movement_kind]).capitalize(), MenuTheme.ACCENT))
	_detail_desc.text = chr.description if chr.description != "" else "No field notes yet."

	# 3D turntable when the unit has a model; otherwise the crest (with its real portrait
	# stacked in once PortraitCache resolves one).
	var has_model := _detail_model.show_character(chr)
	_detail_model.visible = has_model
	_detail_emblem.visible = not has_model
	MenuKit.set_crest(_detail_emblem, String(entry["name"]), ecol)
	if not has_model:
		_refresh_detail_portrait(id_str)

	for c in _detail_stats.get_children():
		c.queue_free()
	var st: Dictionary = entry["stats"]
	for row in STAT_ROWS:
		var key: String = row[0]
		var name_l := MenuKit.label(row[1], &"DimLabel")
		name_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		name_l.custom_minimum_size = Vector2(62, 0)
		_detail_stats.add_child(name_l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = maxf(float(_stat_max.get(key, 1)), 1.0)
		bar.value = float(st[key])
		bar.custom_minimum_size = Vector2(40, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_detail_stats.add_child(bar)
		var val := MenuKit.label(str(st[key]), &"")
		val.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size = Vector2(30, 0)
		_detail_stats.add_child(val)

	_refresh_item_row()
	if _evo_block != null:
		_evo_block.show_for(id_str)
	_fill_abilities(chr)
	_fill_moves(chr)
	_update_detail_hint()


## Every ability (usually one): name + description.
func _fill_abilities(chr: CharacterResource) -> void:
	for child in _detail_ability_box.get_children():
		child.queue_free()
	if chr.ability_count() == 0:
		_detail_ability_box.add_child(_detail_body_label("None"))
		return
	for ab in chr.abilities:
		if ab == null:
			continue
		_detail_ability_box.add_child(_detail_title_label(ab.display_name, MenuTheme.CREAM))
		if not String(ab.description).is_empty():
			_detail_ability_box.add_child(_detail_body_label(ab.description))


## Every move: name in its element colour + description.
func _fill_moves(chr: CharacterResource) -> void:
	for child in _detail_moves_box.get_children():
		child.queue_free()
	if chr.move_count() == 0:
		_detail_moves_box.add_child(_detail_body_label("No moves."))
		return
	for i in range(chr.move_count()):
		var mv: MoveResource = chr.get_move(i)
		if mv == null:
			continue
		var mcol := MenuTheme.CREAM
		if not String(mv.element).is_empty():
			mcol = MenuKit.element_color(String(mv.element)).lightened(0.25)
		_detail_moves_box.add_child(_detail_title_label(mv.display_name, mcol))
		if not String(mv.description).is_empty():
			_detail_moves_box.add_child(_detail_body_label(mv.description))


func _detail_title_label(text: String, color: Color) -> Label:
	var lbl := MenuKit.label(text, &"")
	lbl.add_theme_font_override("font", MenuTheme.heading_font())
	lbl.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _detail_body_label(text: String) -> Label:
	var lbl := MenuKit.label(text, &"DimLabel", true)
	lbl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	return lbl


func _update_detail_hint() -> void:
	if _detail_action_hint == null or _shown_id == "":
		return
	if _chosen_ids.has(_shown_id):
		_detail_action_hint.text = "In squad (#%d)" % (_chosen_ids.find(_shown_id) + 1)
		_detail_action_hint.add_theme_color_override("font_color", MenuTheme.SUCCESS)
	else:
		_detail_action_hint.text = "Not in squad"
		_detail_action_hint.remove_theme_color_override("font_color")


# --- Item loadout -----------------------------------------------------------
#
# Two surfaces over the one static store ([ItemInventory]):
#   * the ITEM row in the details pane -- the UNIT-scope item worn by the character currently
#     shown, which buffs only that character;
#   * the TEAM ITEMS chips above the confirm row -- TEAM-scope items that buff EVERY unit.
#
# Both open the SAME picker. Every change is written and saved immediately (equipment is
# profile state, not part of this screen's squad pick), so backing out of the screen keeps it.
# You own COPIES, not slots: picking an item whose every copy is already in use MOVES it, and
# the inline message says where it came from.

## The TEAM ITEMS row: a section caption plus one chip per shared slot.
func _build_team_items_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "TeamItems"
	row.add_theme_constant_override("separation", MenuTheme.SP_M)

	var head := MenuKit.section("Team Items")
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)

	_team_chips.clear()
	for slot in range(ItemInventory.TEAM_SLOTS):
		var chip := MenuKit.button("", &"", 240, 42)
		chip.name = "TeamSlot%d" % (slot + 1)
		chip.clip_text = true
		chip.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		chip.pressed.connect(_on_team_chip_pressed.bind(slot))
		row.add_child(chip)
		_team_chips.append(chip)

	var note := MenuKit.label("Buffs every unit you field", &"MutedLabel")
	note.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	return row


## Repaint the ITEM row for whichever character the details pane is showing.
func _refresh_item_row() -> void:
	if _detail_item_label == null:
		return
	var item: ItemResource = null
	if not _shown_id.is_empty():
		item = ItemInventory.equipped_resource(_shown_id)
	if item == null:
		_detail_item_label.text = "No item"
		_detail_item_label.add_theme_color_override("font_color", MenuTheme.TEXT_MUTED)
	else:
		_detail_item_label.text = "%s  %s  --  %s" % [item.icon_hint, item.display_name, item.effect_summary()]
		_detail_item_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	if _detail_item_btn != null:
		_detail_item_btn.disabled = _shown_id.is_empty()


## Repaint the TEAM chips from the store.
func _refresh_team_chips() -> void:
	var slots: Array[String] = ItemInventory.team_items()
	for slot in range(_team_chips.size()):
		var chip: Button = _team_chips[slot]
		if chip == null:
			continue
		var slot_id: String = slots[slot] if slot < slots.size() else ""
		var item: ItemResource = ItemLibrary.get_item(slot_id)
		if item == null:
			chip.text = "Team Slot %d -- Empty" % (slot + 1)
			chip.tooltip_text = "Click to equip a team item (buffs every unit)."
		else:
			chip.text = "%s %s" % [item.icon_hint, item.display_name]
			chip.tooltip_text = "%s\n%s\nClick to change." % [item.description, item.effect_summary()]


func _on_equip_pressed() -> void:
	if _shown_id.is_empty():
		return
	_popup_character_id = _shown_id
	_popup_team_slot = -1
	_open_item_popup(ItemResource.Scope.UNIT)


func _on_team_chip_pressed(slot: int) -> void:
	_popup_character_id = ""
	_popup_team_slot = slot
	_open_item_popup(ItemResource.Scope.TEAM)


## Fill and show the shared picker with every OWNED item of [param scope]. The first entry is
## always "No item" (the clear action), so index 0 of [member _popup_item_ids] is always "".
## An item with no free copy left is labelled as a move, not hidden -- the player owns it, so
## they can always put it where they want it.
func _open_item_popup(scope: int) -> void:
	if _item_popup == null:
		return
	_item_popup.clear()
	_popup_item_ids.clear()

	_item_popup.add_item("No item")
	_popup_item_ids.append("")

	var owned: Array[ItemResource] = ItemInventory.owned_items_with_scope(scope)
	for item in owned:
		var label: String = "%s %s  --  %s" % [item.icon_hint, item.display_name, item.effect_summary()]
		if ItemInventory.free_copies(item.id) <= 0:
			label += "   (in use -- moves it here)"
		_item_popup.add_item(label)
		_popup_item_ids.append(String(item.id))

	if owned.is_empty():
		# Added LAST so it cannot shift the entry indices the handler maps back to ids.
		_item_popup.add_separator("Win battles and Arena runs to find items")

	_item_popup.reset_size()
	_item_popup.popup_centered()


func _on_item_popup_id_pressed(id: int) -> void:
	if id < 0 or id >= _popup_item_ids.size():
		return
	var item_id: String = _popup_item_ids[id]

	if _popup_team_slot >= 0:
		# set_team_item reports either "team slot N" (already display-ready) or a character id.
		var note: String = ItemInventory.set_team_item(_popup_team_slot, item_id)
		if not note.is_empty() and not note.begins_with("team slot"):
			note = _character_name(note)
		_report_move(item_id, note)
	elif not _popup_character_id.is_empty():
		var taken_from: String = ItemInventory.equip(_popup_character_id, item_id)
		_report_move(item_id, _character_name(taken_from) if not taken_from.is_empty() else "")
	else:
		return

	ItemInventory.save()
	_refresh_item_row()
	_refresh_team_chips()


## Tell the player when an equip MOVED an item ([param source] empty = nothing was moved).
func _report_move(item_id: String, source: String) -> void:
	if source.is_empty():
		_hide_message()
		return
	var item: ItemResource = ItemLibrary.get_item(item_id)
	var item_name: String = item.display_name if item != null else item_id
	_show_message("You own one %s -- moved it here from %s." % [item_name, source], "info")


## Display name for a character id (falls back to the raw id for an unknown one).
func _character_name(character_id: String) -> String:
	var entry: Dictionary = _entries.get(character_id, {})
	return String(entry["name"]) if not entry.is_empty() else character_id


# --- Evolution ----------------------------------------------------------------

## The pickable roster ids: every roster character minus bosses, [constant EXCLUDED_IDS] and
## -- when [param hide_locked] -- evolved forms not yet in [param unlocked] (an evolved form is
## an UNLOCK in open modes; its base form always stays pickable). Pure over its inputs plus
## the static content libraries, so it is unit-tested without the screen.
static func pickable_ids(all_ids: Array, unlocked: Array, hide_locked: bool) -> Array:
	var out: Array = []
	for id in all_ids:
		var chr: CharacterResource = CharacterLibrary.get_character(id)
		if chr == null or chr.is_boss:
			continue
		var id_str := String(chr.character_id)
		if id_str in EXCLUDED_IDS:
			continue
		if hide_locked and EvolutionLibrary.is_evolved_form(id_str) and not (id_str in unlocked):
			continue
		out.append(id_str)
	return out


## EVOLVE was pressed in the detail pane: play the Evolution screen over this one, and on a
## real evolution rebuild the roster (the new form is now pickable) with it in focus.
func _on_evolve_requested(uid: String, edges: Array) -> void:
	var screen := EvolutionScreen.open(self, uid, edges)
	var outcome: Array = await screen.finished
	if bool(outcome[0]) and outcome[1] != null and is_inside_tree():
		_rebuild_after_evolution(String((outcome[1] as EvolutionResource).to_id))


## Rebuild the whole screen in place, keeping the squad picked so far, and show [param focus_id].
func _rebuild_after_evolution(focus_id: String) -> void:
	# Only what _build_ui built (MenuKit.build_page's backdrop + page, and the item picker):
	# the Evolution screen and PortraitCache's capture node also live under this screen.
	for node_name in ["Backdrop", "Page", "ItemPopup"]:
		var child := get_node_or_null(NodePath(node_name))
		if child != null:
			remove_child(child)
			child.queue_free()
	_unit_buttons.clear()
	_order_badges.clear()
	_card_crests.clear()
	_entries.clear()
	_stat_max.clear()
	_shown_id = ""
	_build_ui()
	_refresh_selection_visuals()
	_refresh_team_chips()
	if _unit_buttons.has(focus_id):
		MenuNav.focus_deferred(_unit_buttons[focus_id])
		_show_detail(focus_id)
	var chr := CharacterLibrary.get_character(focus_id)
	if chr != null:
		_show_message("%s joined your roster." % chr.display_name, "info")


# --- Selection logic --------------------------------------------------------

func _on_unit_pressed(id_str: String) -> void:
	var btn: Button = _unit_buttons.get(id_str)
	if _chosen_ids.has(id_str):
		_chosen_ids.erase(id_str)
	else:
		# Enforce MAX: ignore a new pick once full, and flash the counter.
		if _chosen_ids.size() >= _max_units:
			if btn != null:
				btn.set_pressed_no_signal(false)
			_flash_limit()
			return
		_chosen_ids.append(id_str)
	_hide_message()
	if _shown_id != id_str:
		_show_detail(id_str)
	_refresh_selection_visuals()
	_update_counter()
	# A full squad: jump to the confirm button so Confirm again starts the battle.
	if _chosen_ids.size() >= _max_units and _confirm_btn != null and _confirm_btn.visible:
		_confirm_btn.grab_focus()


## A filled squad slot was clicked: unpick that unit.
func _on_slot_clicked(id_str: String) -> void:
	if not _chosen_ids.has(id_str):
		return
	_chosen_ids.erase(id_str)
	_hide_message()
	_refresh_selection_visuals()
	_update_counter()


## Keep every card's toggled state, order badge and dimming in sync with _chosen_ids.
func _refresh_selection_visuals() -> void:
	var full := _chosen_ids.size() >= _max_units
	for id_str in _unit_buttons.keys():
		var btn: Button = _unit_buttons[id_str]
		if btn == null:
			continue
		var selected: bool = _chosen_ids.has(id_str)
		btn.set_pressed_no_signal(selected)
		btn.modulate = Color(1, 1, 1, 1) if (selected or not full) else Color(1, 1, 1, 0.5)
		var badge: PanelContainer = _order_badges.get(id_str)
		if badge != null:
			badge.visible = selected
			if selected:
				(badge.get_child(0) as Label).text = str(_chosen_ids.find(id_str) + 1)

	if _confirm_btn != null:
		_confirm_btn.disabled = _chosen_ids.is_empty()
	_rebuild_slots()
	_update_detail_hint()


## Rebuild the squad-bar slots: a filled slot shows the picked unit in pick order and can be
## clicked to unpick it; an empty slot reads "Empty".
func _rebuild_slots() -> void:
	if _slots == null:
		return
	for c in _slots.get_children():
		c.queue_free()
	for i in _max_units:
		var filled := i < _chosen_ids.size()
		var text := "Empty"
		var color := MenuTheme.BORDER
		var id_str := ""
		var unit_name := ""
		if filled:
			id_str = String(_chosen_ids[i])
			unit_name = _character_name(id_str)
			var e: Dictionary = _entries.get(id_str, {})
			text = "%d  %s" % [i + 1, unit_name]
			color = MenuKit.element_color(String(e.get("element", "")))
		var slot := Button.new()
		slot.name = "Slot%d" % (i + 1)
		slot.text = text
		slot.custom_minimum_size = Vector2(150, 0)
		slot.clip_text = true
		# Mouse shortcut only: keyboard / pad players unpick on the cards themselves.
		slot.focus_mode = Control.FOCUS_NONE
		slot.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		var sb := _slot_box(color, filled, false)
		for state in ["normal", "pressed", "focus", "disabled"]:
			slot.add_theme_stylebox_override(state, sb)
		slot.add_theme_stylebox_override("hover", _slot_box(color, filled, true))
		slot.add_theme_color_override("font_color", MenuTheme.CREAM)
		slot.add_theme_color_override("font_hover_color", MenuTheme.GOLD_LITE)
		slot.add_theme_color_override("font_pressed_color", MenuTheme.GOLD_LITE)
		slot.add_theme_color_override("font_disabled_color", MenuTheme.TEXT_MUTED)
		if filled:
			slot.tooltip_text = "Click to remove %s" % unit_name
			slot.pressed.connect(_on_slot_clicked.bind(id_str))
		else:
			slot.disabled = true
		_slots.add_child(slot)


## Squad-slot pill: tinted in the picked unit's element colour, or a dim well when empty.
func _slot_box(color: Color, filled: bool, hover: bool) -> StyleBox:
	var fill := Color(0, 0, 0, 0.25)
	var edge := MenuTheme.BORDER
	if filled:
		fill = Color(color, 0.32 if hover else 0.2)
		edge = color.lightened(0.25) if hover else color
	var sb := MenuTheme.pill_box(fill, edge)
	sb.corner = 14.0
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if filled:
		sb.bg_color_end = Color(color.darkened(0.4), 0.25)
	return sb


func _update_counter() -> void:
	if _counter_label == null:
		return
	_counter_label.text = "%d / %d" % [_chosen_ids.size(), _max_units]
	_counter_label.add_theme_color_override("font_color",
		MenuTheme.GOLD_LITE if _chosen_ids.size() >= _max_units else MenuTheme.CREAM)


func _flash_limit() -> void:
	_show_message("Squad is full (%d). Deselect a unit to swap." % _max_units)


# --- Confirm / Back ---------------------------------------------------------

func _on_confirm_pressed() -> void:
	if _chosen_ids.is_empty():
		return
	return_scene = ""

	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("set_selected_squad"):
		settings.set_selected_squad(_chosen_ids)

	# Challenge launch: the map is already staged in GameSettings, so this is a normal
	# map -> GameWorld start. Tell the controller the pick is locked in (so nothing else
	# is misread as this challenge) and change scene below.
	if _is_challenge:
		var challenge := get_node_or_null("/root/ChallengeController")
		if challenge != null and challenge.has_method("notify_squad_confirmed"):
			challenge.notify_squad_confirmed()
		MenuNav.change_scene(self, GAME_WORLD_SCENE)
		return

	# Campaign launch mirrors a challenge: the map is staged, so this is a normal map ->
	# GameWorld start. Lock the pick in (so nothing else is misread as this chapter).
	if _is_campaign:
		var campaign := get_node_or_null("/root/CampaignController")
		if campaign != null and campaign.has_method("notify_squad_confirmed"):
			campaign.notify_squad_confirmed()
		# STORY (additive): a chapter with an authored intro is STAGED here and played by the
		# battle boot itself, over the loaded map (GameWorldManager._play_campaign_intro) --
		# never over this screen. Staging shows nothing and changes nothing about the launch
		# below, which stays the original, unchanged path for every chapter.
		if campaign != null and campaign.has_method("stage_intro_for_launch"):
			campaign.stage_intro_for_launch()
		MenuNav.change_scene(self, GAME_WORLD_SCENE)
		return

	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run():
		# Arena: begin_pending_run changes to the GameWorld scene itself -- do not
		# change scene here.
		arena.begin_pending_run(_chosen_ids)
		return

	MenuNav.change_scene(self, GAME_WORLD_SCENE)


func _on_back_pressed() -> void:
	# Challenge launch: drop the staged run (so nothing records a stray result) and return
	# to the challenge browser.
	if _is_challenge:
		return_scene = ""
		var challenge := get_node_or_null("/root/ChallengeController")
		if challenge != null and challenge.has_method("cancel"):
			challenge.cancel()
		MenuNav.change_scene(self, CHALLENGE_BROWSE_SCENE)
		return

	# Campaign launch: drop the staged run (so nothing records a stray result) and return
	# to the chapter list.
	if _is_campaign:
		return_scene = ""
		var campaign := get_node_or_null("/root/CampaignController")
		if campaign != null and campaign.has_method("cancel"):
			campaign.cancel()
		MenuNav.change_scene(self, CAMPAIGN_SCREEN_SCENE)
		return

	var arena := get_node_or_null("/root/ArenaController")
	if _is_arena and arena != null:
		return_scene = ""
		if arena.has_method("abort_run"):
			arena.abort_run()
		MatchSetup.requested_mode = MatchConfigPanel.MODE_ARENA
		MenuNav.change_scene(self, MATCH_SETUP_SCENE)
		return
	# Map launch: return to Match Setup in whatever map variant it was (skirmish / siege /
	# local), which its static requested_mode still holds -- or to the caller's override.
	var target := return_scene if not return_scene.is_empty() else MATCH_SETUP_SCENE
	return_scene = ""
	MenuNav.change_scene(self, target)


# --- Input ------------------------------------------------------------------

## Back = the shared cancel action (Esc / Backspace / pad B). Enter / pad A act on the
## focused control (toggle a card; a full squad moves focus to To Battle, so Enter again
## starts the battle).
func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


# --- Messages ---------------------------------------------------------------

## Inline status in the footer. [param tone]: "warn" (limits / guards) or "info" (item moves).
func _show_message(text: String, tone: String = "warn") -> void:
	if _message_label == null:
		return
	MenuKit.set_status(_message_label, text, tone)
	_message_label.visible = true


func _hide_message() -> void:
	if _message_label != null:
		_message_label.visible = false


# --- Helpers ----------------------------------------------------------------

## Capitalized element name for display; empty element reads as "Neutral".
func _element_label(element: StringName) -> String:
	var s := String(element)
	if s.is_empty():
		return "Neutral"
	return s.capitalize()


## A one-word battlefield role derived from base stats (display only).
func _role_for(chr: CharacterResource) -> String:
	if chr.attack_range >= 2:
		return "Caster" if chr.base_magic > chr.base_attack else "Ranged"
	if chr.base_magic > chr.base_attack:
		return "Caster"
	if chr.base_defense >= maxi(chr.base_attack, chr.base_speed):
		return "Defender"
	if chr.base_speed >= chr.base_attack:
		return "Skirmisher"
	return "Striker"
