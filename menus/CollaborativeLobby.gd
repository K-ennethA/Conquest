extends Control

class_name CollaborativeLobby

## Collaborative multiplayer lobby, embedded by [NetworkMultiplayerSetup] once this player is
## hosting (player-host) or seated (client). Two ways to play share this one screen:
##
##   PLAYER-HOSTED (the host is also seat 0):
##   - Host waits for the client to join; the client announces itself (lobby_hello)
##   - Both players see the map list (MapRowBuilder rows, networked eligibility) and vote
##   - If votes match: use that map. If votes differ: coin flip decides (host)
##   - Profile card + squad/loadout card are exchanged at the same two moments as always
##   - Both press Ready; the HOST finalises and hands the agreed map (plus its own match
##     settings, squad and a custom map's content) to [method NetSessionNode.start_match].
##     NetSession runs the commit round and GameModeManager loads the battle on every peer
##     -- this screen never changes scene itself.
##
##   DEDICATED SERVER (both players are clients; the server holds no seat):
##   - No handshake with a host lobby: map selection shows as soon as we are seated
##   - No votes / coin flip: the LOBBY LEADER (slot 0, when the server did not fix the
##     config) picks the map + turn system, pushed with set_match_config; everybody else
##     (and a locked server) sees the picker disabled and mirrors config_changed
##   - Ready -> set_ready(true); the server starts the match on its own
##
## A players panel lists the roster (slot, name, you, READY / NOT READY) in both modes.
##
## SKIN / LOGIC SPLIT. Every widget is built by a `_build_*` function or a row factory
## (`_player_row`, `_install_map_selector`) and only the `_present_*` / `_render_*` helpers
## touch styling; the flow / message / transport functions only read state, set texts and
## toggle visibility on the members below. Swapping the look means replacing the builders.

## The shared map-ROW model + renderer, used by the map-selection panel below (and by
## MatchSetup, which is why it is shared). Preloaded BY PATH, not by class_name: a brand new
## script is not in the project's global class cache until the next import.
const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")
## GameModeManager's script, for its STATIC client-side custom-map gate
## ([method _resolve_boot_map] delegates to it so the lobby and the battle loader can never
## disagree about which file a peer boots from).
const GameModeManagerScript := preload("res://systems/game_core/GameModeManager.gd")

signal lobby_ready()
signal game_starting(map_path: String)

const DEFAULT_MAP := "res://game/maps/resources/default_skirmish.tres"
## How many roster changes the host waits through for a start NetSession refused because a
## ready flag had not landed yet, before giving up and handing the Ready button back.
const MAX_START_RETRIES := 8
## How long the coin-flip result stays on screen before the host starts the match.
const COIN_FLIP_REVEAL_SEC := 2.0

# Copy (the words the flow puts on the widgets).
const READY_TEXT := "READY - START GAME"
const READY_TEXT_DEDICATED := "READY"
const WAITING_TEXT := "WAITING FOR OPPONENT..."
const VOTE_RULES_TEXT := "Click a map to vote. If you both choose different maps, a coin flip will decide!"
const SQUADS_PLAYER_HOSTED_TEXT := "Squads: each player fields their own Character Select pick."
const SQUADS_DEDICATED_TEXT := "Squads: map rosters on dedicated servers."

# Network state
var is_host: bool = false
var is_client_connected: bool = false
var local_player_name: String = ""
var remote_player_name: String = ""

# Map voting
var local_map_vote: String = ""
var remote_map_vote: String = ""
## The name that travelled WITH the opponent's vote. A community or player-authored map lives
## at a user:// path that means nothing on this machine, so when we cannot resolve the voted
## path locally this is the only thing that can be shown. Content itself never rides a vote --
## it ships once, from the host, with the match start.
var remote_map_vote_name: String = ""
var voting_complete: bool = false

# UI Elements (public: the lobby suites drive them)
var waiting_panel: Control
var map_selection_panel: Control
var map_selector: Node
var vote_status_label: Label
var ready_button: Button

# Host-only match config (Turn System + Best-of rounds). On a dedicated server the same panel
# is rebuilt as Turn System only and belongs to the lobby leader. Applied to GameSettings at
# start via apply_settings().
var versus_config_panel: MatchConfigPanel

# The online TURN CLOCK preset (NetTurnClock: Rapid / Standard / Relaxed -- every online match
# has a clock). Picked by the player-host (published with set_match_config so the joiner sees
# it) or a dedicated server's lobby leader (unless the server fixed it with --turn-clock).
var turn_clock_option: OptionButton

# Game mode manager
var game_mode_manager: Node

# --- Transport adapter --------------------------------------------------------
# The lobby's vote / ready / lobby-state / game-start messages have TWO possible carriers:
#
#   NetSession (preferred)  -- the consolidated host-authoritative transport. When Host/Join
#                              ran through it, it is the same session the battle reads, so the
#                              lobby and the battle share one connection.
#   GameModeManager (legacy) -- the old submit_action envelope. Kept as the fallback carrier
#                              so a lobby with no live session stays a silent, crash-free
#                              no-op (and the older suites that drive it stay meaningful).
#
# The choice is made per SEND, on whether NetSession currently holds a live connected peer,
# so nothing needs to be told which mode it is in. Receiving is symmetric: NetSession's
# lobby_message signal and the legacy direct call both land in handle_network_message().

## The transport to prefer. Defaults to the NetSession autoload; tests inject a stand-in via
## [method set_net_session]. Never assume it is the autoload -- always go through the helpers.
var net_session: Node = null

# --- Match-start / mode state --------------------------------------------------
## True on a dedicated server (decided at [method initialize]).
var _dedicated: bool = false
## The opponent announced player_ready (and has not re-voted since).
var _remote_ready: bool = false
## This player pressed Ready (and has not changed the map since).
var _ready_pressed: bool = false
## Our own roster ready flag has been seen TRUE since we pressed Ready -- so a later FALSE
## means the flags were cleared (config change / a peer left), not that it is still in flight.
var _ready_seen_in_roster: bool = false
## Host: finalise ran (single-shot guard; cleared by a refusal).
var _start_requested: bool = false
## Host: the start_match config waiting for the last ready flag to land, or {}.
var _pending_start_cfg: Dictionary = {}
var _start_retries: int = 0
## True while the UI is being set FROM the session (dedicated mirror), so picks made by code
## are never pushed back as the player's own.
var _mirroring: bool = false
## Dedicated: roster size last seen (a newcomer gets our profile card re-announced).
var _last_roster_size: int = 0
## True while handling a message that came off the live session (never our own echo).
var _inbound_relayed: bool = false
## The rows currently shown by [member map_selector] (same order as its buttons).
var _map_rows: Array = []
var _map_pick_enabled: bool = true

# Look-only references (set by the builders).
var _players_list: VBoxContainer
var _session_note: Label
var _squad_note: Label
var _settings_card: Control
var _settings_note: Label
var _waiting_title: Label
var _waiting_status: Label
var _map_subtitle: Label
var _map_holder: VBoxContainer


func _ready() -> void:
	print("[LOBBY] _ready() called")
	_ensure_theme()
	game_mode_manager = GameModeManager
	set_net_session(NetSession if typeof(NetSession) == TYPE_OBJECT else null)
	if not game_mode_manager:
		print("[LOBBY] WARNING: GameModeManager not found")
	_build_ui()
	print("[LOBBY] UI built successfully")


## Point this lobby at the transport it should prefer, subscribing to its inbound lobby
## messages (and, when it has them, its roster / config updates). Idempotent, and rebinding
## cleanly drops the previous source's subscriptions.
func set_net_session(source) -> void:
	if net_session == source:
		return
	_bind_session_signals(net_session, false)
	net_session = source
	_bind_session_signals(net_session, true)


func _bind_session_signals(session, attach: bool) -> void:
	if session == null or not is_instance_valid(session):
		return
	var pairs: Array = [
		["lobby_message", _on_net_lobby_message],
		["roster_changed", _on_session_roster_changed],
		["config_changed", _on_session_config_changed],
	]
	for pair in pairs:
		var sig: StringName = StringName(String(pair[0]))
		var handler: Callable = pair[1]
		if not session.has_signal(sig):
			continue
		var is_bound: bool = session.is_connected(sig, handler)
		if attach and not is_bound:
			session.connect(sig, handler)
		elif not attach and is_bound:
			session.disconnect(sig, handler)


func _exit_tree() -> void:
	# The autoload outlives this lobby; drop the subscriptions so a torn-down lobby can never
	# be woken by the next match's traffic.
	set_net_session(null)


## True when NetSession is the live transport for this process (a connected peer exists).
## False in solo/menu/test contexts, which is what routes sends down the legacy path.
func _net_active() -> bool:
	return net_session != null and is_instance_valid(net_session) \
		and net_session.has_method("is_connected_session") \
		and bool(net_session.is_connected_session())


func _session_has(method: String) -> bool:
	return net_session != null and is_instance_valid(net_session) and net_session.has_method(method)


## The live session is the authority (player-host). Reads is_host(), or the older is_server().
func _session_is_host() -> bool:
	if not _net_active():
		return false
	if _session_has("is_host"):
		return bool(net_session.is_host())
	if _session_has("is_server"):
		return bool(net_session.is_server())
	return false


func _session_is_dedicated() -> bool:
	return _net_active() and _session_has("is_dedicated_server") and bool(net_session.is_dedicated_server())


func _session_is_leader() -> bool:
	return _net_active() and _session_has("is_lobby_leader") and bool(net_session.is_lobby_leader())


func _seat_count() -> int:
	if _net_active() and "max_players" in net_session:
		return maxi(2, int(net_session.max_players))
	return 2


## Send one lobby message over whichever transport is live. NetSession wins whenever it holds
## a connected peer; otherwise the legacy submit_action envelope carries it. Null-safe on both
## branches, so a lobby with neither transport is a silent no-op rather than a crash.
func _send_lobby_message(message_type: String, data: Dictionary) -> void:
	if _net_active():
		net_session.send_lobby_message(message_type, data)
		return
	if game_mode_manager != null and is_instance_valid(game_mode_manager):
		game_mode_manager.submit_action(message_type, data)


## Inbound lobby message off NetSession. Same entry point the legacy path calls, so there is
## exactly one place each message type is handled. NetSession never echoes our own sends back,
## so this only ever carries the OTHER participant's traffic.
##
## The sender's roster SLOT is forwarded: the server stamps it from its own roster, so it is
## the trustworthy answer to "who said this" and is what keys the profile cards in
## [MatchPeerInfo]. The legacy carrier has no slot and passes the default -1.
func _on_net_lobby_message(message_type: String, data: Dictionary, from_slot: int) -> void:
	_inbound_relayed = true
	handle_network_message(message_type, data, from_slot)
	_inbound_relayed = false


## A message carrying OUR name is our own echo -- but only on the legacy carrier. The live
## session never echoes, so there a same-named opponent is still the opponent.
func _is_own_echo(sender_name: String) -> bool:
	return not _inbound_relayed and sender_name == local_player_name


func initialize(as_host: bool, player_name: String) -> void:
	"""Initialize the lobby as host or client"""
	is_host = as_host
	local_player_name = player_name

	# A NEW lobby means a new match: forget whatever the LAST match's opponent announced, so
	# the post-match summary can never attribute the previous opponent to this one -- and so
	# the previous match's replicated loadouts/skins can never be applied in this one (a
	# cleared MatchLoadouts also reads as INACTIVE, which is what keeps solo play untouched).
	MatchPeerInfo.clear()
	MatchLoadouts.clear()

	_remote_ready = false
	_ready_pressed = false
	_ready_seen_in_roster = false
	_start_requested = false
	_pending_start_cfg = {}
	_start_retries = 0
	_dedicated = not as_host and _session_is_dedicated()
	_present_mode()

	print("[LOBBY] Initialized as " + ("HOST" if is_host else ("CLIENT (dedicated server)" if _dedicated else "CLIENT")))
	print("[LOBBY] Player name: " + player_name)

	if is_host:
		_show_waiting_for_client()
		_start_monitoring_connections()
	elif _dedicated:
		# Both players are clients of a seatless server: there is no host lobby to answer a
		# hello, so the map selection opens as soon as we are seated. The leader's pick (or the
		# server's fixed config) is the map; the server starts once both are ready.
		is_client_connected = true
		_show_map_selection()
		_last_roster_size = int(net_session.player_count()) if _session_has("player_count") else 0
		_broadcast_profile_info()
		_mirror_dedicated_config(_session_config())
		if _session_is_leader():
			# Cloud behaviour: the leader publishes its defaults on join, so the server (and
			# the other player) always has a map to show.
			if local_map_vote.is_empty():
				local_map_vote = _default_dedicated_map()
			_select_map_row(local_map_vote)
			_push_dedicated_config()
			_update_vote_status()
			_update_dedicated_ready()
	elif _net_active():
		# NetSession client: the connection already exists (we only get here after being
		# seated), so announce ourselves. The host answers with the current lobby state --
		# which also closes the race where the host reached map selection before this lobby
		# node existed and its broadcast had nobody to land on.
		print("[LOBBY] Announcing to host over NetSession")
		_show_waiting_for_host()
		_send_lobby_message("lobby_hello", {"player_name": local_player_name})
		# ...and, in the same breath, who we ARE (rank + lifetime points). See
		# _broadcast_profile_info for why this rides the START of the match.
		_broadcast_profile_info()
		# ...and WHAT WE BRING: the equipped items + cosmetic skins the HOST must know before
		# it spawns our units. See _broadcast_match_loadout.
		_broadcast_match_loadout()
	else:
		# Client: Check if already connected (late join scenario)
		if game_mode_manager:
			var status = game_mode_manager.get_game_status()
			var network_stats = status.get("network_stats", {})
			var connection_status = network_stats.get("connection_status", "")

			if connection_status == "CONNECTED":
				print("[LOBBY] Client already connected, showing map selection immediately")
				_show_map_selection()
			else:
				print("[LOBBY] Client waiting for connection")
				_show_waiting_for_host()
		else:
			_show_waiting_for_host()
	_refresh_players()


# =============================================================================
# LOOK -- builders, factories and presenters (the only functions that style widgets)
# =============================================================================

const SIDE_WIDTH := 420.0


## Nested under an already-themed screen the lobby inherits its look; standalone (tests, a
## future skin host) it themes itself.
func _ensure_theme() -> void:
	var node: Node = get_parent()
	while node != null:
		if node is Control and (node as Control).theme != null:
			return
		node = node.get_parent()
	theme = MenuTheme.build()


func _build_ui() -> void:
	"""Build the lobby UI: players + match settings column | waiting card / map vote panel."""
	var row := HBoxContainer.new()
	row.name = "LobbyRow"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	add_child(row)

	_build_side_column(row)

	var stage := Control.new()
	stage.name = "Stage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(stage)
	_build_waiting_panel(stage)
	_build_map_selection_panel(stage)


func _build_side_column(parent: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "SideColumn"
	scroll.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var col := VBoxContainer.new()
	col.name = "SideCards"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", MenuTheme.SP_L)
	scroll.add_child(col)
	_build_players_card(col)
	_build_settings_card(col)


func _build_players_card(parent: Control) -> void:
	var card := MenuKit.card()
	card.name = "PlayersCard"
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(v)
	v.add_child(MenuKit.section("Players"))
	_session_note = MenuKit.label("", &"DimLabel", true)
	_session_note.name = "SessionNote"
	v.add_child(_session_note)
	_players_list = VBoxContainer.new()
	_players_list.name = "PlayersList"
	_players_list.add_theme_constant_override("separation", MenuTheme.SP_S)
	v.add_child(_players_list)
	_squad_note = MenuKit.label(SQUADS_PLAYER_HOSTED_TEXT, &"MutedLabel", true)
	_squad_note.name = "SquadNote"
	_squad_note.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	v.add_child(_squad_note)


func _build_settings_card(parent: Control) -> void:
	var card := MenuKit.card()
	card.name = "SettingsCard"
	parent.add_child(card)
	_settings_card = card
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(v)
	v.add_child(MenuKit.section("Match Settings"))
	_settings_note = MenuKit.label("", &"MutedLabel", true)
	_settings_note.name = "SettingsNote"
	_settings_note.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	v.add_child(_settings_note)
	versus_config_panel = MatchConfigPanel.new()
	versus_config_panel.name = "VersusConfigPanel"
	versus_config_panel.custom_minimum_size = Vector2(0, 110)
	versus_config_panel.visible = false
	v.add_child(versus_config_panel)
	versus_config_panel.configure(MatchConfigPanel.MODE_VERSUS)
	versus_config_panel.changed.connect(_on_settings_changed)
	v.add_child(_build_turn_clock_row())


## The Turn Clock picker row (every online match is timed; see NetTurnClock).
func _build_turn_clock_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "TurnClockRow"
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	var cap := MenuKit.label("Turn clock", &"DimLabel")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	turn_clock_option = OptionButton.new()
	turn_clock_option.name = "TurnClockOption"
	turn_clock_option.custom_minimum_size = Vector2(180, 40)
	for item in NetTurnClock.picker_items():
		turn_clock_option.add_item(String(item[1]))
		turn_clock_option.set_item_metadata(turn_clock_option.item_count - 1, String(item[0]))
	turn_clock_option.select(NetTurnClock.PRESET_IDS.find(NetTurnClock.DEFAULT_PRESET))
	turn_clock_option.tooltip_text = NetTurnClock.describe(NetTurnClock.DEFAULT_PRESET)
	turn_clock_option.item_selected.connect(_on_turn_clock_selected)
	row.add_child(turn_clock_option)
	return row


## The picked turn clock preset id.
func turn_clock_pick() -> String:
	if turn_clock_option == null or turn_clock_option.selected < 0:
		return NetTurnClock.DEFAULT_PRESET
	return NetTurnClock.normalise_preset(turn_clock_option.get_item_metadata(turn_clock_option.selected))


## Show [param preset] as the pick (mirroring the host's / server's config).
func _show_turn_clock(preset) -> void:
	if turn_clock_option == null:
		return
	var i := NetTurnClock.PRESET_IDS.find(NetTurnClock.normalise_preset(preset))
	if i >= 0 and i != turn_clock_option.selected:
		turn_clock_option.select(i)
	turn_clock_option.tooltip_text = NetTurnClock.describe(preset)


## May this player change the turn clock? The player-host, or a dedicated server's leader.
func _turn_clock_editable() -> bool:
	return _session_is_leader() if _dedicated else is_host


func _refresh_turn_clock_enabled() -> void:
	if turn_clock_option != null:
		turn_clock_option.disabled = not _turn_clock_editable()


func _on_turn_clock_selected(_index: int) -> void:
	turn_clock_option.tooltip_text = NetTurnClock.describe(turn_clock_pick())
	if _mirroring or not _turn_clock_editable():
		return
	if _dedicated:
		_reset_ready_after_change()
		_push_dedicated_config()
	elif is_host and _net_active() and _session_has("set_match_config"):
		# Published so the joiner's lobby shows it; the start carries it as well.
		net_session.set_match_config({NetTurnClock.CONFIG_PRESET: turn_clock_pick()})


func _build_waiting_panel(parent: Control) -> void:
	var card := MenuKit.card()
	card.name = "WaitingPanel"
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(card)
	waiting_panel = card
	var center := CenterContainer.new()
	card.add_child(center)
	var v := VBoxContainer.new()
	v.name = "VBoxContainer"
	v.custom_minimum_size = Vector2(460, 0)
	v.add_theme_constant_override("separation", MenuTheme.SP_M)
	center.add_child(v)
	var tag := MenuKit.section("Lobby")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	_waiting_title = MenuKit.label("Waiting for player...", &"HeadingLabel")
	_waiting_title.name = "WaitingTitle"
	_waiting_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_waiting_title)
	var rule := GroveRule.new()
	rule.centered = true
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(200, 10)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rule)
	_waiting_status = MenuKit.label("Please wait...", &"DimLabel", true)
	_waiting_status.name = "WaitingStatus"
	_waiting_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_waiting_status)


func _build_map_selection_panel(parent: Control) -> void:
	var panel := VBoxContainer.new()
	panel.name = "MapSelectionPanel"
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", MenuTheme.SP_M)
	parent.add_child(panel)
	map_selection_panel = panel

	panel.add_child(MenuKit.section("Choose the Battlefield"))
	_map_subtitle = MenuKit.label(VOTE_RULES_TEXT, &"DimLabel", true)
	_map_subtitle.name = "MapRules"
	panel.add_child(_map_subtitle)

	# Map list. Rows come from the SHARED builder (menus/MapRowBuilder.gd), so this panel and
	# MatchSetup badge every source identically -- builtin unbadged, CUSTOM for the player's
	# own creations, COMMUNITY for downloads -- and a map the OPPONENT could not be sent
	# (MapCatalog.network_eligible) renders disabled with one shared sentence. The list card
	# is the panel's ONE flexible region (720p budget: section 20 + rules 40 + list >= 240 +
	# the status/ready row 64 + gaps 36 = ~400 of the ~460 the page body has).
	_map_holder = VBoxContainer.new()
	_map_holder.name = "MapHolder"
	_map_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_map_holder)
	_install_map_selector(MapRowBuilder.versus_rows(true))

	var bottom := HBoxContainer.new()
	bottom.name = "VoteRow"
	bottom.add_theme_constant_override("separation", MenuTheme.SP_L)
	panel.add_child(bottom)

	var well := MenuKit.card(&"InsetPanel")
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(well)
	vote_status_label = MenuKit.label("Select a map to vote", &"", true)
	vote_status_label.name = "VoteStatus"
	vote_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	well.add_child(vote_status_label)

	ready_button = MenuKit.button(READY_TEXT, MenuKit.PRIMARY, 300, 56)
	ready_button.name = "ReadyButton"
	ready_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ready_button.disabled = true
	ready_button.pressed.connect(_on_ready_pressed)
	bottom.add_child(ready_button)


## (Re)build the map list from [param rows] (MapRowBuilder row dictionaries) and tag each row
## button with its path so the flow can select / lock rows by path.
func _install_map_selector(rows: Array) -> void:
	if _map_holder == null:
		return
	if map_selector != null and is_instance_valid(map_selector):
		_map_holder.remove_child(map_selector)
		map_selector.queue_free()
	_map_rows = rows
	map_selector = MapRowBuilder.build_list(true, _on_local_map_selected, rows)
	_map_holder.add_child(map_selector)
	var buttons: Array = _map_row_buttons()
	var i: int = 0
	for row in _map_rows:
		if not (row is Dictionary):
			continue
		if i >= buttons.size():
			break
		var b: Button = buttons[i]
		b.set_meta(&"map_path", String((row as Dictionary).get("path", "")))
		b.set_meta(&"row_disabled", bool((row as Dictionary).get("disabled", false)))
		i += 1


func _map_row_buttons() -> Array:
	var out: Array = []
	if map_selector == null or not is_instance_valid(map_selector):
		return out
	var box: Node = map_selector.find_child("Rows", true, false)
	if box == null:
		return out
	for child in box.get_children():
		if child is Button:
			out.append(child)
	return out


## Highlight the row for [param path] (and only it) without firing its pick handler.
func _select_map_row(path: String) -> void:
	for b in _map_row_buttons():
		var btn: Button = b
		btn.set_pressed_no_signal(path != "" and String(btn.get_meta(&"map_path", "")) == path)


## Lock / unlock the map picker (and, on a dedicated server, the turn-system panel).
func _set_map_pick_enabled(enabled: bool) -> void:
	_map_pick_enabled = enabled
	for b in _map_row_buttons():
		var btn: Button = b
		btn.disabled = (not enabled) or bool(btn.get_meta(&"row_disabled", false))
	if _dedicated and versus_config_panel != null:
		_set_subtree_enabled(versus_config_panel, enabled)
	_refresh_turn_clock_enabled()


func _set_subtree_enabled(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not enabled
		elif child is SpinBox:
			(child as SpinBox).editable = enabled
		_set_subtree_enabled(child, enabled)


## Dress the screen for the mode [method initialize] decided: button / rule / session copy,
## the dedicated map list (builtins only) and who sees the settings panel.
func _present_mode() -> void:
	if ready_button != null:
		ready_button.text = _ready_text()
	if _map_subtitle != null:
		_map_subtitle.text = _map_rules_text()
	if _session_note != null:
		_session_note.text = _session_text()
	if _squad_note != null:
		_squad_note.text = SQUADS_DEDICATED_TEXT if _dedicated else SQUADS_PLAYER_HOSTED_TEXT
	if _dedicated:
		# The server sanitises any non-res:// map away, so only shipped maps are offered.
		_install_map_selector(_dedicated_rows())
	if versus_config_panel != null:
		if _dedicated:
			_mirroring = true
			versus_config_panel.configure(MatchConfigPanel.MODE_LOCAL)  # turn system only
			_mirroring = false
		versus_config_panel.visible = is_host or _dedicated
	_refresh_turn_clock_enabled()
	if _settings_note != null:
		_settings_note.text = _settings_text()
	_set_map_pick_enabled(not _dedicated or _session_is_leader())


func _render_players(rows: Array) -> void:
	if _players_list == null:
		return
	for child in _players_list.get_children():
		_players_list.remove_child(child)
		child.queue_free()
	for r in rows:
		var row: Dictionary = r
		_players_list.add_child(_player_row(int(row.get("slot", 0)), String(row.get("name", "")),
			bool(row.get("you", false)), bool(row.get("ready", false))))


## One lobby row: team-coloured edge + crest, "P1", name (+ you), and a READY pill. An empty
## seat (name "") reads "Waiting for a player...".
func _player_row(slot: int, player_name: String, you: bool, is_ready: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var team := MenuTheme.TEAM_BLUE if slot == 0 else MenuTheme.TEAM_RED
	var row_sb := MenuTheme.inset_box()
	row_sb.border_color = MenuTheme.GOLD_DK if you else MenuTheme.BORDER_SOFT
	row_sb.accent_color = team if player_name != "" else Color(team, 0.3)
	row_sb.accent_width = 4.0
	row_sb.content_margin_left = 16
	row_sb.content_margin_top = 8
	row_sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", row_sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", MenuTheme.SP_M)
	p.add_child(h)
	var crest_letter := player_name.left(1) if player_name != "" else "?"
	var crest := MenuKit.crest(crest_letter, team if player_name != "" else MenuTheme.BORDER,
		MenuTheme.GOLD_DK if player_name != "" else MenuTheme.BORDER_SOFT, 36.0)
	h.add_child(crest)
	var tag := MenuKit.label("P%d" % (slot + 1), &"SectionLabel")
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	var shown := (player_name + ("  (you)" if you else "")) if player_name != "" else "Waiting for a player..."
	var n := MenuKit.label(shown, &"" if player_name != "" else &"MutedLabel")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(n)
	if player_name != "":
		var pill := MenuKit.badge("READY" if is_ready else "NOT READY",
			MenuTheme.SUCCESS if is_ready else MenuTheme.TEXT_MUTED, is_ready)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pill)
	return p


# --- Copy -----------------------------------------------------------------------

func _ready_text() -> String:
	return READY_TEXT_DEDICATED if _dedicated else READY_TEXT


func _map_rules_text() -> String:
	if not _dedicated:
		return VOTE_RULES_TEXT
	if _session_is_leader():
		return "You lead this lobby: choose the map and turn system. The match starts when both players are ready."
	return "The server (or the first player) chooses the map and turn system. The match starts when both players are ready."


func _session_text() -> String:
	if is_host:
		return "You are hosting. Your opponent joins with the address shown at the top of the screen."
	if _dedicated:
		return "Dedicated server -- the server holds no seat and starts the match once both players are ready."
	if _net_active():
		return "Connected to the host."
	return ""


func _settings_text() -> String:
	if is_host:
		return "Applied when the match starts."
	if _dedicated:
		return "You choose the turn system for this server." if _session_is_leader() \
			else "The server (or the first player) chooses the turn system."
	return "The host chooses the turn system and best-of."


# =============================================================================
# FLOW -- screens, votes, ready, start (no widget construction below this line)
# =============================================================================

func _show_waiting_for_client() -> void:
	"""Show waiting screen for host"""
	if not waiting_panel:
		print("[LOBBY] ERROR: waiting_panel is null")
		return

	waiting_panel.visible = true
	if map_selection_panel:
		map_selection_panel.visible = false

	if _waiting_title:
		_waiting_title.text = "Waiting for opponent..."
	if _waiting_status:
		# The real LAN address is shown by the setup screen above this lobby.
		_waiting_status.text = "Share the address shown at the top of the screen. Set the match up while you wait."

	# Reveal the host-only match settings (Turn System + Best-of).
	if versus_config_panel != null:
		versus_config_panel.visible = true
	_refresh_players()


func _show_waiting_for_host() -> void:
	"""Show waiting screen for client"""
	if not waiting_panel:
		print("[LOBBY] ERROR: waiting_panel is null")
		return

	waiting_panel.visible = true
	if map_selection_panel:
		map_selection_panel.visible = false

	if _waiting_title:
		_waiting_title.text = "Connected to host"
	if _waiting_status:
		_waiting_status.text = "Waiting for host to start map selection..."


func _show_map_selection() -> void:
	"""Show map selection screen"""
	print("[LOBBY] Showing map selection")

	if not waiting_panel or not map_selection_panel:
		print("[LOBBY] ERROR: UI panels not initialized")
		return

	waiting_panel.visible = false
	map_selection_panel.visible = true

	# Reset voting state
	local_map_vote = ""
	remote_map_vote = ""
	remote_map_vote_name = ""
	voting_complete = false
	_update_vote_status()
	_refresh_players()


func _start_monitoring_connections() -> void:
	"""Monitor for client connections (host only)"""
	if not is_host:
		return

	print("[LOBBY] Monitoring for client connections...")
	_check_for_connections()


func _check_for_connections() -> void:
	"""Check if client has connected"""
	if not is_host or is_client_connected:
		return

	if not game_mode_manager and not _net_active():
		print("[LOBBY] ERROR: no transport available for connection checking")
		return

	# Safety check - the lobby may have already been removed from the tree (e.g. scene
	# teardown mid-loop). get_tree() is null in that case, so bail before touching it.
	if not is_inside_tree():
		print("[LOBBY] Not in tree, stopping connection check")
		return

	await get_tree().create_timer(0.5).timeout

	# Safety check - don't loop forever
	if not is_inside_tree():
		print("[LOBBY] Not in tree anymore, stopping connection check")
		return

	var peer_count: int = _remote_peer_count()

	if peer_count > 0:
		print("[LOBBY] Client connected!")
		_admit_remote_player("Opponent")
	else:
		# Keep checking (but with safety limit)
		_check_for_connections()


## How many OTHER participants are present. Reads NetSession's roster when it is the live
## transport (authoritative, no polling of a second stack), and falls back to the legacy
## GameModeManager network stats otherwise.
func _remote_peer_count() -> int:
	if _net_active() and net_session.has_method("player_count"):
		return maxi(0, int(net_session.player_count()) - 1)
	if game_mode_manager == null or not is_instance_valid(game_mode_manager):
		return 0
	var status = game_mode_manager.get_game_status()
	var network_stats = status.get("network_stats", {})
	var connected_peers = network_stats.get("connected_peers", 0)
	# connected_peers is an integer (peer count), not an array -- guard both shapes.
	if connected_peers is int:
		return int(connected_peers)
	if connected_peers is Array:
		return (connected_peers as Array).size()
	return 0


## Host: the opponent is present -- move to map selection and tell them to do the same.
## Idempotent on the state flip but ALWAYS re-broadcasts, so a hello that arrives after the
## poll already flipped us still gets an answer.
func _admit_remote_player(player_name: String) -> void:
	if not is_host:
		return
	if not is_client_connected:
		is_client_connected = true
		remote_player_name = player_name
		_show_map_selection()
	_broadcast_lobby_state("map_selection")
	# The lobby has FORMED -- answer the newcomer with our own profile card, exactly as the
	# lobby_state answer above closes the "host got there first" race for map selection.
	_broadcast_profile_info()
	# ...and with our loadout + skins, which the CLIENT must know before it spawns our units.
	_broadcast_match_loadout()
	_refresh_players()


## Host: the opponent left before the match started. Back to waiting, with the lobby's
## per-opponent state forgotten, so the NEXT player to join starts from a clean vote.
func _on_opponent_left_lobby() -> void:
	print("[LOBBY] Opponent left the lobby -- waiting for a new one")
	is_client_connected = false
	remote_player_name = ""
	remote_map_vote = ""
	remote_map_vote_name = ""
	_remote_ready = false
	_ready_pressed = false
	_ready_seen_in_roster = false
	_start_requested = false
	_pending_start_cfg = {}
	MatchPeerInfo.clear()
	MatchLoadouts.clear()
	if ready_button != null:
		ready_button.disabled = true
		ready_button.text = _ready_text()
	_show_waiting_for_client()
	_start_monitoring_connections()


func _on_local_map_selected(map_path: String, map_resource: MapResource) -> void:
	"""Handle local player's map selection"""
	if _dedicated:
		if not _session_is_leader():
			_select_map_row(local_map_vote)  # the leader / server decides; undo the click
			return
		local_map_vote = map_path
		_reset_ready_after_change()
		_push_dedicated_config()
		_update_vote_status()
		return

	local_map_vote = map_path
	print("[LOBBY] Local vote: " + (map_resource.map_name if map_resource != null else map_path))

	# A new vote after Ready means "I changed my mind": that is not ready any more.
	_reset_ready_after_change()

	# Broadcast vote to other player
	_broadcast_map_vote(map_path)

	# Update UI
	_update_vote_status()

	# Enable ready button
	if ready_button:
		ready_button.disabled = false


## The map changed under a pressed Ready: withdraw it (on the session too) and hand the
## button back.
func _reset_ready_after_change() -> void:
	if _ready_pressed and _net_active() and _session_has("set_ready"):
		net_session.set_ready(false)
	_ready_pressed = false
	_ready_seen_in_roster = false
	if ready_button != null:
		ready_button.disabled = local_map_vote.is_empty()
		ready_button.text = _ready_text()


func _broadcast_map_vote(map_path: String) -> void:
	"""Broadcast map vote to other player.

	The vote carries the map's NAME alongside its path. The path is the identity both peers
	agree on, but a custom / community map's path is a user:// file the opponent has never
	seen, so without the name their vote line would read as a meaningless file stem. The name
	is display data only -- the map's CONTENT is never shipped by a vote (see
	_build_match_settings: it rides the host's start, once, after the vote is settled)."""
	_send_lobby_message("map_vote", {
		"player_name": local_player_name,
		"map_path": map_path,
		"map_name": MapCatalog.map_name_for(map_path),
	})
	print("[LOBBY] Broadcasted map vote: " + map_path)


## Announce THIS player's profile card -- display name, local rank name, lifetime points --
## to the other participant(s).
##
## WHY AT THE START: the post-match summary ([GameOverScreen]) wants to show who you beat and
## what rank they carry, but by the time a versus match ENDS the opponent may have forfeited,
## crashed or dropped, so there is nobody left to ask. The exchange therefore happens while
## the lobby is forming and the answer is parked in [MatchPeerInfo] until the summary reads it.
##
## Sent on the same lobby channel as the votes / ready flags / game-start payload, through the
## same [method _send_lobby_message] adapter, so it works on whichever transport is live and is
## a silent no-op when neither is.
func _broadcast_profile_info() -> void:
	_send_lobby_message("profile_info", _build_profile_info())


## This player's card. Every profile read is guarded: the autoload is absent in some harnesses,
## and an older build may not carry the rank accessors. Missing data degrades to a name-only
## card rather than blocking the send.
func _build_profile_info() -> Dictionary:
	var info: Dictionary = { "name": local_player_name, "rank_name": "", "lifetime_points": 0 }
	if typeof(PlayerProfile) != TYPE_OBJECT or PlayerProfile == null:
		return info
	var lifetime: int = 0
	if PlayerProfile.has_method("get_points_total"):
		lifetime = int(PlayerProfile.get_points_total())
	info["lifetime_points"] = lifetime
	if PlayerProfile.has_method("get_rank_name"):
		info["rank_name"] = str(PlayerProfile.get_rank_name())
	else:
		info["rank_name"] = RankLadder.rank_for(lifetime)
	return info


## The other participant announced its card. [param from_slot] is the SERVER's stamp of who
## sent it (-1 on the legacy carrier, which has no slots), and it is what the card is keyed
## by -- the payload is untrusted peer input and [MatchPeerInfo] normalises it on the way in.
func _handle_profile_info(data: Dictionary, from_slot: int) -> void:
	MatchPeerInfo.set_peer_info(from_slot, data)
	var announced: Dictionary = MatchPeerInfo.get_peer_info(from_slot)
	print("[LOBBY] Opponent profile: %s (%s, %d pts) in slot %d" % [
		String(announced.get("name", "")), String(announced.get("rank_name", "")),
		int(announced.get("lifetime_points", 0)), from_slot])
	# Name the opponent from their own announcement when the poll only had a placeholder.
	var announced_name: String = String(announced.get("name", "")).strip_edges()
	if not announced_name.is_empty() and (remote_player_name.is_empty() or remote_player_name == "Opponent"):
		remote_player_name = announced_name


## Announce what THIS player brings into the match: the characters they will field, the item
## equipped on each of them, their shared team items, and the cosmetic skin each one wears.
##
## WHY IT IS ITS OWN MESSAGE, NOT PART OF game_start. Items are real buffs, skins change what a
## unit LOOKS like, and the squad decides which units exist at all -- so BOTH machines need
## BOTH sides' data before a single unit spawns. game_start is host -> client only and has no
## client -> host twin, so widening it would replicate the host's side and nothing else (which
## is exactly what "host_squad" is, and exactly why a client's own pick used to reach nobody).
## This message is the "profile_info" shape instead: announced by whoever is announcing, keyed
## by the sender's server-stamped slot, parked in [MatchLoadouts] until the battle reads it.
## Host and client each send exactly one, at the same two moments the profile card is exchanged.
## (A dedicated match fields the map's rosters -- GameModeManager clears the cards -- so the
## dedicated flow does not announce one.)
##
## The local slot is recorded alongside, because it is what tells the battle which side is
## OURS -- our own units keep reading the local inventory/profile/pick, never a replicated card.
func _broadcast_match_loadout() -> void:
	if not _net_active():
		return
	if net_session.has_method("local_slot"):
		MatchLoadouts.set_local_slot(int(net_session.local_slot()))
	_send_lobby_message("match_loadout",
		MatchLoadouts.build_local_payload(_player_profile(), _local_squad()))


## This peer's own Character Select pick, or an empty Array where GameSettings is absent (a
## headless harness) or too old to answer. Empty means "field the map's authored roster for my
## slot", which is the pre-existing behaviour for a match launched without a pick.
func _local_squad() -> Array:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("get_selected_squad"):
		return GameSettings.get_selected_squad()
	return []


## The PlayerProfile autoload, or null where it is not registered (headless / tests). Fetched
## rather than referenced directly so a missing autoload degrades to "no skins" instead of
## failing to resolve.
func _player_profile() -> Object:
	if typeof(PlayerProfile) == TYPE_OBJECT and PlayerProfile != null:
		return PlayerProfile
	return null


## The other participant announced its squad + loadout + skins. [param from_slot] is the
## SERVER's stamp of who sent it, and it is what the card is keyed by -- the payload itself is
## untrusted peer input, so [MatchLoadouts] whitelists every id in it against the LOCAL
## character/item/skin libraries on the way in (an unknown or mis-scoped id is simply dropped).
func _handle_match_loadout(data: Dictionary, from_slot: int) -> void:
	MatchLoadouts.set_peer_loadout(from_slot, data)
	var stored: Dictionary = MatchLoadouts.get_peer_loadout(from_slot)
	print("[LOBBY] Opponent loadout in slot %d: %d unit(s), %d worn item(s), %d team item(s), %d skin(s)" % [
		from_slot, (stored["squad"] as Array).size(), (stored["equipped"] as Dictionary).size(),
		(stored["team"] as Array).size(), (stored["skins"] as Dictionary).size()])


func _broadcast_lobby_state(state: String) -> void:
	"""Broadcast lobby state change (host only)"""
	if not is_host:
		return

	_send_lobby_message("lobby_state", {
		"state": state
	})
	print("[LOBBY] Broadcasted lobby state: " + state)


func _display_name_for_vote(path: String, announced_name: String = "") -> String:
	"""Best-effort display name for a map vote.

	Resolution order: what THIS machine can read off the file ([method MapCatalog.map_name_for],
	which covers builtin .tres and user:// .json alike and never load()s a missing path), then
	the name the voter ANNOUNCED with their vote, then the file stem. The middle step is what
	makes an opponent's community map show as "Skirmish Arena" rather than "skirmish_arena" on a
	machine that does not have the file at all -- which is the normal case until the host ships
	the payload at the match start."""
	if path.is_empty():
		return ""
	var resolved: String = MapCatalog.map_name_for(path)
	if not resolved.is_empty():
		return resolved
	var announced: String = announced_name.strip_edges()
	if not announced.is_empty():
		return announced
	return path.get_file().get_basename()


func _update_vote_status() -> void:
	"""Update the vote status display"""
	if not vote_status_label:
		return

	var status_text = ""

	if _dedicated:
		if local_map_vote.is_empty():
			status_text = "Waiting for the lobby leader to choose a map..."
		elif _session_is_leader():
			status_text = "Map: " + _display_name_for_vote(local_map_vote) + "\nYou choose the map for this server."
		else:
			status_text = "Map: " + _display_name_for_vote(local_map_vote) + "\nChosen by the server (or the first player)."
		vote_status_label.text = status_text
		return

	if local_map_vote.is_empty():
		status_text = "Select a map to vote"
	elif remote_map_vote.is_empty():
		status_text = "You voted for: " + _display_name_for_vote(local_map_vote) + "\nWaiting for opponent's vote..."
	else:
		if local_map_vote == remote_map_vote:
			voting_complete = true
			status_text = "Both players chose: " + _display_name_for_vote(local_map_vote) + "\n✓ Ready to start!"
		else:
			voting_complete = true
			status_text = "You: " + _display_name_for_vote(local_map_vote) \
				+ " | Opponent: " + _display_name_for_vote(remote_map_vote, remote_map_vote_name) \
				+ "\nCoin flip will decide!"

	vote_status_label.text = status_text


func _on_ready_pressed() -> void:
	"""Handle ready button press"""
	if local_map_vote.is_empty() or _ready_pressed:
		return

	print("[LOBBY] Player ready, waiting for opponent...")
	_ready_pressed = true
	_ready_seen_in_roster = false

	if ready_button:
		ready_button.disabled = true
		ready_button.text = WAITING_TEXT

	# ORDER MATTERS: seat the ready flag on the session FIRST. The host's start_match reads the
	# roster flag, and both calls travel the same reliable channel -- so by the time the host
	# sees our player_ready below, our flag is already in its roster.
	if _net_active() and _session_has("set_ready"):
		net_session.set_ready(true)

	# Broadcast ready status
	_broadcast_ready()

	# Host: both voted and the opponent already said ready -> start.
	if is_host and voting_complete and not remote_map_vote.is_empty() and _remote_ready:
		_finalize_map_selection()
	_refresh_players()


func _broadcast_ready() -> void:
	"""Broadcast ready status"""
	_send_lobby_message("player_ready", {
		"player_name": local_player_name
	})


func _finalize_map_selection() -> void:
	"""Finalize map selection and start the match (HOST ONLY, player-hosted)."""
	print("[LOBBY] Finalizing map selection...")

	# Only host should finalize
	if not is_host:
		print("[LOBBY] Client waiting for host to finalize...")
		return
	if _start_requested:
		return  # single-shot: a repeated ready message must never start a second match
	if local_map_vote.is_empty() or remote_map_vote.is_empty():
		print("[LOBBY] Both players must vote before the match can start")
		return
	_start_requested = true

	# Apply the host's match settings locally BEFORE building the start config, so the chosen
	# turn system and best-of ride along.
	if versus_config_panel != null:
		versus_config_panel.apply_settings()

	# WHICH VOTES MAY WIN. The host is the only participant that ships map content, so a map it
	# cannot ship cannot be the match: the opponent's vote for a community map names a file that
	# exists only on THEIR disk, and either side's map may have grown past the payload cap since
	# it was listed. Filtering the CANDIDATES (rather than rejecting after the tie-break) means
	# such a pick simply loses the coin flip instead of killing the lobby. A builtin is always
	# eligible -- both machines already have it.
	var candidates: Array = _startable_votes()
	if candidates.is_empty():
		_refuse_start("That map cannot be played online (too large, or not on this machine). Pick another.")
		return

	var final_map: String = ""

	if candidates.size() == 1:
		final_map = String(candidates[0])
		if local_map_vote == remote_map_vote:
			print("[LOBBY] Both players chose same map: " + final_map)
		else:
			print("[LOBBY] Only one vote can be played online: " + final_map)
	else:
		# Coin flip (host decides)
		randomize()
		var coin_flip = randi() % 2
		final_map = String(candidates[coin_flip])

		var local_name: String = _display_name_for_vote(local_map_vote)
		var remote_name: String = _display_name_for_vote(remote_map_vote, remote_map_vote_name)
		var chosen_name: String = _display_name_for_vote(final_map, remote_map_vote_name)

		print("[LOBBY] Coin flip! Result: " + chosen_name)
		print("[LOBBY]   Your vote: " + local_name)
		print("[LOBBY]   Opponent vote: " + remote_name)

		# Show coin flip result
		if vote_status_label:
			vote_status_label.text = "Coin flip chose: " + chosen_name + "!"
		if is_inside_tree():
			await get_tree().create_timer(COIN_FLIP_REVEAL_SEC).timeout
		if not is_inside_tree() or not _start_requested:
			return  # the lobby closed (or the start was called off) during the reveal

	# Tell the client which map won (informational: its screen reads "Starting game with X";
	# the authoritative config arrives with NetSession's match_started).
	_broadcast_game_start(final_map)

	# Local bookkeeping for the start (our slot, the selected map, the game_starting signal).
	_start_game(final_map)

	# Hand the agreed match to NetSession: commit round, then match_started on every peer,
	# and GameModeManager loads the battle.
	_begin_net_match(final_map)


## The distinct votes this host could actually START on, in vote order (ours first). Pure enough
## to drive from a test: the only outside read is MapCatalog's per-path eligibility.
func _startable_votes() -> Array:
	var out: Array = []
	for vote in [local_map_vote, remote_map_vote]:
		var path: String = String(vote)
		if path.is_empty() or out.has(path):
			continue
		if MapCatalog.network_eligible(path):
			out.append(path)
	return out


## Host-side start of the NetSession match, guarded so it only fires when NetSession is the
## connected player-host transport. start_match merges [method _build_start_config] into the
## lobby config WITHOUT clearing ready flags and runs the commit round; match_started then
## fires on every peer. It refuses while a ready flag has not landed yet -- the attempt is then
## parked and retried on the next roster change (bounded; never twice once it succeeded).
## Returns true when the session accepted the start now.
func _begin_net_match(map_path: String) -> bool:
	if not _net_active() or not _session_is_host() or not _session_has("start_match"):
		return false
	_pending_start_cfg = _build_start_config(map_path)
	_start_retries = 0
	return _try_start_match()


func _try_start_match() -> bool:
	if _pending_start_cfg.is_empty() or not _session_has("start_match"):
		return false
	if bool(net_session.start_match(_pending_start_cfg)):
		print("[LOBBY] Match start accepted by the session")
		_pending_start_cfg = {}
		return true
	print("[LOBBY] Session not ready to start yet (a ready flag is still in flight)")
	return false


## The config handed to [method NetSessionNode.start_match] -- the keys GameModeManager reads
## on match_started. Built from the same MatchSettings the game_start message carries.
func _build_start_config(map_path: String) -> Dictionary:
	var settings: Dictionary = _build_match_settings(map_path)
	var squad: Array = []
	var raw_squad = settings.get("host_squad", [])
	if raw_squad is Array:
		squad = (raw_squad as Array).duplicate()
	var cfg: Dictionary = {
		"map_path": map_path,
		"turn_system": int(settings.get("turn_system", TurnSystemBase.TurnSystemType.TRADITIONAL)),
		"auto_end_turn": bool(GameSettings.auto_end_turn),
		"versus_rounds": int(settings.get("versus_rounds", 1)),
		"host_squad": squad,
		"map_json": String(settings.get("map_json", "")),
		NetTurnClock.CONFIG_PRESET: turn_clock_pick(),
	}
	if settings.has("map_payload"):
		cfg["map_payload"] = settings["map_payload"]
	return cfg


func _build_match_settings(map_path: String) -> Dictionary:
	"""The MatchSettings payload the host broadcasts so the client plays the SAME match instead
	of trusting its own local GameSettings. Shape:
	  {
	    map: String,                # builtin map resource path
	    map_json: String,           # validated custom-map JSON payload ("" for builtin)
	    turn_system: int,           # TurnSystemBase.TurnSystemType
	    versus_rounds: int,         # best-of round count
	    host_squad: Array,          # host's selected character ids (player slot 0)
	    map_payload: Dictionary,    # a non-builtin map's content (omitted for a builtin)
	  }
	The client keeps its OWN selected_squad for its slot; host_squad names slot 0's roster.
	Custom-map JSON is carried when present so a client that lacks the .tres can still build
	the board from the host's validated payload."""
	var map_json: String = ""
	if GameSettings.has_method("get_custom_map_json"):
		map_json = str(GameSettings.get_custom_map_json())
	var settings: Dictionary = {
		"map": map_path,
		"map_json": map_json,
		"turn_system": GameSettings.selected_turn_system,
		"versus_rounds": GameSettings.versus_rounds,
		"host_squad": GameSettings.get_selected_squad(),
	}
	var payload: Dictionary = _network_map_payload(map_path)
	if not payload.is_empty():
		settings["map_payload"] = payload
	return settings


## The map CONTENT a start must carry, or {} when it must carry none.
##
## A builtin is on both machines already, so shipping it would be pure waste -- "map" alone
## identifies it. Anything else (a Map Creator save, a community download) exists ONLY on this
## machine, so the board can only agree if the bytes travel: the client re-validates them and
## boots from them (see GameModeManager.resolve_boot_map). Over-cap or no-longer-valid maps
## return {}, and _finalize_map_selection refuses to start on them rather than sending half a
## match.
func _network_map_payload(map_path: String) -> Dictionary:
	if map_path.is_empty() or MapCatalog.is_builtin(map_path):
		return {}
	if not MapCatalog.network_eligible(map_path):
		return {}
	return MapCatalog.load_payload(map_path)


## Abandon a start that cannot be made safe, leaving the lobby usable. Used on BOTH sides:
## the host when the agreed map cannot be transmitted, the client when the host's payload does
## not survive validation. It is a returned/displayed outcome, never push_error -- a rejected
## peer payload is expected input, not a bug (tests/README.md rule 1) -- and it must never end
## with a match started from two different boards.
func _refuse_start(reason: String) -> void:
	print("[LOBBY] Match start refused: " + reason)
	_start_requested = false
	_pending_start_cfg = {}
	_ready_pressed = false
	_ready_seen_in_roster = false
	if vote_status_label != null:
		vote_status_label.text = reason
	if ready_button != null:
		ready_button.disabled = false
		ready_button.text = _ready_text()


func _broadcast_game_start(map_path: String) -> void:
	"""Broadcast game start with final map + the full MatchSettings payload (host only)."""
	if not is_host:
		return

	print("[LOBBY] Broadcasting game start with map: " + map_path)

	_send_lobby_message("game_start", _build_match_settings(map_path))


func _start_game(map_path: String) -> void:
	"""Local bookkeeping for the agreed map. The battle itself is loaded by GameModeManager when
	NetSession's match_started fires on this peer -- this screen never changes scene."""
	print("[LOBBY] Starting game with map: " + map_path)

	# Re-affirm which slot is OURS on the way into the battle. The announcement earlier in the
	# lobby already did this, but a peer seated after its lobby node existed would have stamped
	# -1 then; by now the roster is settled. Cheap, idempotent, and the difference between
	# "our units read the local inventory" and "nobody is equipped at all".
	if _net_active() and _session_has("local_slot"):
		MatchLoadouts.set_local_slot(int(net_session.local_slot()))

	# Update settings
	GameSettings.set_selected_map(map_path)

	# Emit signal
	game_starting.emit(map_path)


# --- Session updates (roster / config) ----------------------------------------------

func _on_session_roster_changed(_roster: Dictionary) -> void:
	if not _net_active():
		_refresh_players()
		return
	# Player-host: the opponent left before the match -> wait for a new one.
	if is_host and not _dedicated and is_client_connected and _session_has("player_count") \
			and int(net_session.player_count()) < _seat_count():
		_on_opponent_left_lobby()
	# Dedicated: a newcomer never heard our profile card -- announce it again.
	if _dedicated and _session_has("player_count"):
		var count: int = int(net_session.player_count())
		if count > _last_roster_size and _last_roster_size > 0:
			_broadcast_profile_info()
		_last_roster_size = count
	_watch_own_ready_flag()
	# Host: a start parked on a missing ready flag gets another go now.
	if not _pending_start_cfg.is_empty():
		_start_retries += 1
		if _start_retries > MAX_START_RETRIES:
			_refuse_start("The match could not start -- both players must be ready. Press Ready again.")
		else:
			_try_start_match()
	_refresh_players()


## Our own roster ready flag went back to FALSE after we saw it TRUE: the session cleared it
## (the map / settings changed, or a player left). Hand the Ready button back.
func _watch_own_ready_flag() -> void:
	if not _session_has("get_roster") or not _session_has("local_peer_id"):
		return
	var roster: Dictionary = net_session.get_roster()
	var me: int = int(net_session.local_peer_id())
	if not roster.has(me):
		return
	var entry: Dictionary = roster[me]
	if bool(entry.get("ready", false)):
		_ready_seen_in_roster = true
	elif _ready_seen_in_roster and _ready_pressed and not _start_requested and _pending_start_cfg.is_empty():
		_ready_seen_in_roster = false
		_ready_pressed = false
		if ready_button != null:
			ready_button.disabled = local_map_vote.is_empty()
			ready_button.text = _ready_text()
		_update_vote_status()
		if vote_status_label != null:
			vote_status_label.text += "\nThe lobby changed -- press Ready again."


func _on_session_config_changed(config: Dictionary) -> void:
	if _dedicated:
		_mirror_dedicated_config(config)
	elif not is_host and config.has(NetTurnClock.CONFIG_PRESET):
		# The player-host's turn clock pick, shown read-only.
		_mirroring = true
		_show_turn_clock(config[NetTurnClock.CONFIG_PRESET])
		_mirroring = false


func _session_config() -> Dictionary:
	if _session_has("get_match_config"):
		var cfg = net_session.get_match_config()
		if cfg is Dictionary:
			return cfg
	return {}


## Dedicated: show the server's config (map + turn system) as the current pick. The leader
## sees its own pick come back; everybody else (or everyone, on a locked server) follows it.
func _mirror_dedicated_config(config: Dictionary) -> void:
	var map_path: String = String(config.get("map_path", ""))
	if not map_path.is_empty():
		local_map_vote = map_path
	_mirroring = true
	_select_map_row(local_map_vote)
	if config.has("turn_system") and versus_config_panel != null:
		versus_config_panel.set_turn_system(int(config["turn_system"]))
	if config.has(NetTurnClock.CONFIG_PRESET):
		_show_turn_clock(config[NetTurnClock.CONFIG_PRESET])
	_mirroring = false
	_refresh_turn_clock_enabled()
	_set_map_pick_enabled(_session_is_leader())
	if _map_subtitle != null:
		_map_subtitle.text = _map_rules_text()
	if _settings_note != null:
		_settings_note.text = _settings_text()
	_update_vote_status()
	_update_dedicated_ready()


## Dedicated: Ready is available once a map is known and we have not pressed it yet.
func _update_dedicated_ready() -> void:
	if ready_button == null or _ready_pressed:
		return
	ready_button.disabled = local_map_vote.is_empty()
	ready_button.text = _ready_text()


## Dedicated leader: publish the current pick to the server (which sanitises it; only shipped
## res:// maps survive). Changing it clears everyone's ready flag -- see _watch_own_ready_flag.
func _push_dedicated_config() -> void:
	if _mirroring or not _dedicated or not _session_is_leader() or local_map_vote.is_empty():
		return
	if not MapCatalog.is_builtin(local_map_vote):
		return
	# Offline-only maps (an AI neutral faction, AI-driven Siege creeps) are refused by the server
	# too -- never publish a pick it would drop. Their rows are disabled, so this is belt and braces.
	if not MapCatalog.network_eligible(local_map_vote):
		return
	var turn_system: int = versus_config_panel.get_turn_system() if versus_config_panel != null \
		else int(GameSettings.selected_turn_system)
	net_session.set_match_config({
		"map_path": local_map_vote,
		"turn_system": turn_system,
		"auto_end_turn": true,
		NetTurnClock.CONFIG_PRESET: turn_clock_pick(),
	})


func _on_settings_changed() -> void:
	if _dedicated and not _mirroring:
		_reset_ready_after_change()
		_push_dedicated_config()


## The shipped (res://) maps the networked list offers -- all a dedicated server accepts.
func _dedicated_rows() -> Array:
	var out: Array = []
	for row in MapRowBuilder.versus_rows(true):
		if row is Dictionary and MapCatalog.is_builtin(String((row as Dictionary).get("path", ""))):
			out.append(row)
	return out


## The leader's default: the standard skirmish map when it is offered, else the first
## pickable row.
func _default_dedicated_map() -> String:
	var first: String = ""
	for row in _map_rows:
		if not (row is Dictionary) or bool((row as Dictionary).get("disabled", false)):
			continue
		var path: String = String((row as Dictionary).get("path", ""))
		if path == DEFAULT_MAP:
			return path
		if first.is_empty():
			first = path
	return first if not first.is_empty() else DEFAULT_MAP


## Rebuild the players panel from the roster (or, without a live session, from what this
## lobby knows about both sides).
func _refresh_players() -> void:
	_render_players(_roster_rows())


## [{slot, name, ready, you}] for every seat, sorted by slot; an empty seat has name "".
func _roster_rows() -> Array:
	var rows: Array = []
	if _net_active() and _session_has("get_roster"):
		var roster: Dictionary = net_session.get_roster()
		var my_slot: int = int(net_session.local_slot()) if _session_has("local_slot") else -1
		for pid in roster:
			var r = roster[pid]
			if not (r is Dictionary):
				continue
			var slot: int = int((r as Dictionary).get("slot", -1))
			rows.append({
				"slot": slot,
				"name": String((r as Dictionary).get("name", "")),
				"ready": bool((r as Dictionary).get("ready", false)),
				"you": slot == my_slot,
			})
	elif not local_player_name.is_empty():
		rows.append({"slot": 0 if is_host else 1, "name": local_player_name,
			"ready": _ready_pressed, "you": true})
		if is_client_connected or not remote_player_name.is_empty():
			rows.append({"slot": 1 if is_host else 0,
				"name": remote_player_name if not remote_player_name.is_empty() else "Opponent",
				"ready": _remote_ready, "you": false})
	var taken: Array = []
	for row in rows:
		taken.append(int(row["slot"]))
	for s in range(_seat_count()):
		if not taken.has(s):
			rows.append({"slot": s, "name": "", "ready": false, "you": false})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	return rows


# --- Queries (UI state, for the setup screen and tests) ---------------------------------

## May this player change the map right now? (False for a dedicated non-leader / locked server.)
func map_pick_enabled() -> bool:
	return _map_pick_enabled


## The map this lobby currently shows as picked: our vote, or the server's map on a dedicated
## server.
func selected_map_path() -> String:
	return local_map_vote


## True when this peer's Ready is also the match START (the player-host). On a dedicated server
## nobody in the lobby starts the match -- the server does, once both are ready.
func start_button_visible() -> bool:
	return is_host and not _dedicated and ready_button != null and ready_button.is_visible_in_tree()


# --- Network message handlers --------------------------------------------------------

func handle_network_message(message_type: String, data: Dictionary, from_slot: int = -1) -> void:
	"""Handle network messages from other player.

	[param from_slot] is the sender's roster slot as the SERVER stamped it. It is optional and
	defaults to -1 so every existing 2-argument caller (the legacy relay, the lobby suite)
	keeps working unchanged; only profile_info / match_loadout currently need it."""
	print("[LOBBY] handle_network_message called: " + message_type)

	match message_type:
		"lobby_hello":
			_handle_lobby_hello(data)
		"profile_info":
			_handle_profile_info(data, from_slot)
		"match_loadout":
			_handle_match_loadout(data, from_slot)
		"lobby_state":
			_handle_lobby_state(data)
		"map_vote":
			_handle_map_vote(data)
		"player_ready":
			_handle_player_ready(data)
		"game_start":
			_handle_game_start(data)
		_:
			print("[LOBBY] Unknown message type: " + message_type)


func _handle_lobby_hello(data: Dictionary) -> void:
	"""A joining client announced itself (NetSession path). Host-only: admit it and answer
	with the current lobby state, so the client never sits on 'waiting for host' because the
	host's broadcast went out before its lobby node existed."""
	if not is_host:
		return
	var player_name: String = str(data.get("player_name", "Opponent")).strip_edges()
	if player_name.is_empty():
		player_name = "Opponent"
	print("[LOBBY] Opponent announced itself: " + player_name)
	_admit_remote_player(player_name)


func _handle_lobby_state(data: Dictionary) -> void:
	"""Handle lobby state change from host"""
	var state: String = str(data.get("state", ""))
	print("[LOBBY] Received lobby state: " + state)

	match state:
		"map_selection":
			# Idempotent: the host answers the join hello AND its own roster poll, so this can
			# legitimately arrive twice. _show_map_selection() CLEARS both votes, so a repeat
			# once the player has already voted must be ignored, not replayed.
			if is_client_connected and map_selection_panel != null and map_selection_panel.visible:
				print("[LOBBY] Already in map selection - ignoring duplicate state message")
				return
			is_client_connected = true
			_show_map_selection()


func _handle_map_vote(data: Dictionary) -> void:
	"""Handle map vote from other player"""
	var player_name: String = str(data.get("player_name", ""))
	var map_path: String = str(data.get("map_path", ""))

	if _is_own_echo(player_name):
		print("[LOBBY] Ignoring own vote (player_name matches local_player_name)")
		return

	remote_map_vote = map_path
	# Display data only, and untrusted peer input -- coerced to a plain trimmed String so a
	# Dictionary/null in the payload can never reach a Label.
	remote_map_vote_name = str(data.get("map_name", "")).strip_edges()
	remote_player_name = player_name
	# A (re)vote means the opponent is choosing again -- their earlier Ready no longer stands.
	_remote_ready = false

	print("[LOBBY] Opponent voted for: " + _display_name_for_vote(map_path, remote_map_vote_name))

	_update_vote_status()
	_refresh_players()


func _handle_player_ready(data: Dictionary) -> void:
	"""Handle player ready from other player"""
	var player_name: String = str(data.get("player_name", ""))

	if _is_own_echo(player_name):
		print("[LOBBY] Ignoring own ready (player_name matches local_player_name)")
		return

	print("[LOBBY] Opponent is ready!")
	_remote_ready = true
	_refresh_players()

	# If we're also ready, finalize
	if not local_map_vote.is_empty() and ready_button and ready_button.disabled:
		print("[LOBBY] We're also ready! Finalizing map selection...")
		_finalize_map_selection()


func _handle_game_start(data: Dictionary) -> void:
	"""The host's final map (CLIENT ONLY, player-hosted). Validated here exactly as the battle
	loader will validate it, so a bad payload is refused with a message in the lobby; the
	battle itself is loaded by GameModeManager when NetSession's match_started arrives."""
	if is_host or _dedicated:
		print("[LOBBY] Ignoring game_start (host / dedicated server)")
		return

	var map_path: String = str(data.get("map", ""))
	var turn_system = data.get("turn_system", "")

	if map_path.is_empty():
		print("[LOBBY] ERROR: No map path in game_start message")
		return

	print("[LOBBY] Client received game start: " + map_path + " (turn system " + str(turn_system) + ")")

	# WHICH FILE THIS PEER BOOTS FROM. "map" is the host's own path -- meaningful to them, and
	# to us only when it is a builtin. A non-builtin map travels as CONTENT in "map_payload", and
	# that content is untrusted peer input: it goes through the catalog-strict gate and is
	# materialised into the session directory, or the match does not start at all. Never
	# push_error (an invalid payload is expected input, not a bug) and never fall through to a
	# same-named local file, which would put the two peers on different boards.
	var boot_path: String = _resolve_boot_map(map_path, data.get("map_payload", {}))
	if boot_path.is_empty():
		_refuse_start("The host's map could not be verified -- the match was not started.")
		return

	# Mirror the rest of the host's MatchSettings (GameModeManager applies the authoritative
	# copy from the match config again on match_started). The client keeps its OWN
	# selected_squad (its slot's roster); host_squad names slot 0. All optional.
	if turn_system is int:
		GameSettings.selected_turn_system = turn_system
	if data.has("versus_rounds") and GameSettings.has_method("set_versus_rounds"):
		GameSettings.set_versus_rounds(int(data.get("versus_rounds", 1)))
	if data.has("host_squad") and GameSettings.has_method("set_host_squad"):
		var host_squad = data.get("host_squad", [])
		if host_squad is Array:
			GameSettings.set_host_squad(host_squad)
	var custom_json: String = str(data.get("map_json", ""))
	if not custom_json.is_empty() and GameSettings.has_method("set_custom_map_json"):
		GameSettings.set_custom_map_json(custom_json)

	# Show starting message. Named from the file we will actually boot -- for a shipped map that
	# is the freshly installed session copy, whose map_info carries the author's own name.
	if vote_status_label:
		vote_status_label.text = "Starting game with: " + _display_name_for_vote(boot_path, remote_map_vote_name) + "!"
	if ready_button:
		ready_button.disabled = true

	_start_game(boot_path)


## The path THIS peer boots the battle from, or "" to refuse the match. Delegates to
## [method GameModeManager.resolve_boot_map] -- the same gate the battle loader runs on
## match_started -- so the lobby can never accept a map the loader would refuse:
##   * content shipped -> strict-validate + materialise it and boot from THAT copy;
##   * no content, builtin path -> boot the shipped map;
##   * no content, NON-builtin path -> refuse (a same-named local file would be two boards).
func _resolve_boot_map(map_path: String, raw_payload: Variant) -> String:
	return GameModeManagerScript.resolve_boot_map(map_path, raw_payload)
