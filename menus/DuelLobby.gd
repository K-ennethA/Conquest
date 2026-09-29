extends Control

class_name DuelLobby

## The ONLINE DUEL lobby (docs/design/DECISIONS.md #32), embedded by [NetworkMultiplayerSetup]
## in place of the map lobby when the Versus screen chose Duel. One screen for both hosts:
##
##   PLAYER-HOSTED (host = seat 0): the host sets the FORMAT (Singles 1v1 / Trio 3v3 / Full 6v6
##   -- [DuelFormat]), the stage and the weather (set_match_config, which clears everyone's
##   Ready). Each seat builds its TEAM for that format from the duel-eligible roster
##   ([DuelNetConfig.eligible_ids] -- humans and creatures alike; no repeats under the species
##   clause) and announces it on the lobby channel ([constant DuelNetConfig.MSG_PICK]). Both
##   press Ready; the HOST folds both teams into the start ([method DuelNetConfig.final_config]
##   -> [method NetSessionNode.start_match]). Every peer then re-validates the teams while
##   building the duel (a wrong size, a repeat or a non-eligible unit refuses the match
##   everywhere).
##
##   DEDICATED SERVER (both seats are clients): the same teams and Ready; the slot-0 client
##   (the lobby leader, when the server did not lock it with --stage / --duel-format) sets the
##   format / stage / weather; the server collects the teams and starts the match itself.
##
## No items or skins: an online duel is the two teams, straight. Picking is locked while you
## are Ready (un-ready to change). GameModeManager loads the duel on every machine.
## Keys: Left / Right (or Q / E) on the unit card cycle the selected team slot; the slot chips
## above it choose which slot you edit; Enter on Ready.

signal game_starting()

const READY_TEXT := "READY"
const UNREADY_TEXT := "NOT READY -- CHANGE TEAM"
## The format a new player-host's lobby starts on (the owner: online duels are team fights).
const DEFAULT_FORMAT := DuelFormat.TRIO

## The session this lobby talks to (default: the NetSession autoload; tests inject theirs).
var net_session: Node = null
var is_host: bool = false
var local_player_name: String = ""

## Our lead (a duel-eligible roster id) and our whole TEAM (lead first, the format's size), and
## the other seats' announced teams {slot: [ids]}.
var pick: String = ""
var team: Array = []
var remote_picks: Dictionary = {}
## The format the lobby plays (the host's / leader's config; Trio by default for a new host).
var format: DuelFormat = null
## The team slot the carousel edits.
var edit_slot: int = 0

# Widgets (public: tests drive them).
var ready_button: Button
var unit_card: Button
var stage_option: OptionButton
var weather_option: OptionButton
var format_option: OptionButton

var _ids: Array[StringName] = []
var _pick_index: int = 0
var _weathers: Array[StringName] = []
var _ready_pressed: bool = false
var _start_requested: bool = false
var _mirroring: bool = false
var _last_roster_size: int = 0
var _players_list: VBoxContainer
var _status: Label
var _card_parts: Dictionary = {}
var _team_row: HBoxContainer = null


func _ready() -> void:
	_ensure_theme()
	if net_session == null:
		set_net_session(get_node_or_null("/root/NetSession"))
	_ids = DuelNetConfig.eligible_ids()
	_build_ui()


func _exit_tree() -> void:
	set_net_session(null)


## Point the lobby at [param source] (a NetSessionNode). Idempotent.
func set_net_session(source) -> void:
	if net_session == source:
		return
	_bind(net_session, false)
	net_session = source
	_bind(net_session, true)


func _bind(session, attach: bool) -> void:
	if session == null or not is_instance_valid(session):
		return
	for pair in [["lobby_message", _on_lobby_message], ["roster_changed", _on_roster_changed],
			["config_changed", _on_config_changed]]:
		var sig := StringName(String(pair[0]))
		if not session.has_signal(sig):
			continue
		var bound: bool = session.is_connected(sig, pair[1])
		if attach and not bound:
			session.connect(sig, pair[1])
		elif not attach and bound:
			session.disconnect(sig, pair[1])


## Called by the setup screen once hosting / seated.
func initialize(as_host: bool, player_name: String) -> void:
	is_host = as_host
	local_player_name = player_name
	var slot := _local_slot()
	if format == null:
		format = DuelNetConfig.format_of(net_session.get_match_config()) \
			if _session_ok() and not is_host else DuelFormat.preset(DEFAULT_FORMAT)
	set_team(DuelNetConfig.default_team(maxi(slot, 0), format))
	if is_host and _session_ok() and not _dedicated():
		# The host's defaults are the lobby's config from the start (the joiner mirrors them).
		net_session.set_match_config({DuelNetConfig.KEY_STAGE: DuelNetConfig.DEFAULT_STAGE,
			DuelNetConfig.KEY_WEATHER: DuelNetConfig.DEFAULT_WEATHER,
			DuelNetConfig.KEY_FORMAT: format.to_dict()})
	_sync_format_option()
	_refresh_settings_enabled()
	_refresh_players()
	_update_ready_button()
	MenuNav.focus_deferred(unit_card)


# --- Session helpers ------------------------------------------------------------------

func _session_ok() -> bool:
	return net_session != null and is_instance_valid(net_session) \
		and net_session.has_method("is_connected_session") and bool(net_session.is_connected_session())


func _local_slot() -> int:
	return int(net_session.local_slot()) if net_session != null and net_session.has_method("local_slot") else (0 if is_host else 1)


func _dedicated() -> bool:
	return net_session != null and net_session.has_method("is_dedicated_server") and bool(net_session.is_dedicated_server())


## May this player set stage / weather? (The player-host, or a dedicated server's leader.)
func settings_editable() -> bool:
	if not _session_ok():
		return is_host
	return bool(net_session.is_lobby_leader()) if net_session.has_method("is_lobby_leader") else is_host


# --- Picks ------------------------------------------------------------------------------

## Put [param id] in the edited team slot (a repeat under the species clause swaps places).
func _set_pick(id: String) -> void:
	if not DuelNetConfig.is_eligible(id):
		return
	if team.is_empty():
		team = [id]
	edit_slot = clampi(edit_slot, 0, team.size() - 1)
	var at := team.find(id)
	if at >= 0 and at != edit_slot and _fmt().species_clause:
		team[at] = team[edit_slot]
	team[edit_slot] = id
	_after_team_change()


## Replace our whole team with [param ids] (fitted to the format: size, species clause).
func set_team(ids: Array) -> void:
	team = DuelNetConfig.fill_team(DuelNetConfig.clean_team(ids), maxi(_local_slot(), 0), _fmt())
	edit_slot = clampi(edit_slot, 0, team.size() - 1)
	_after_team_change()


## Choose which team slot the carousel edits.
func select_team_slot(i: int) -> void:
	if _ready_pressed or team.is_empty():
		return
	edit_slot = clampi(i, 0, team.size() - 1)
	var k := _ids.find(StringName(String(team[edit_slot])))
	_pick_index = maxi(k, 0)
	_refresh_card()
	_refresh_team_row()


func _after_team_change() -> void:
	pick = String(team[0]) if not team.is_empty() else ""
	var i := _ids.find(StringName(String(team[edit_slot]))) if not team.is_empty() else -1
	_pick_index = maxi(i, 0)
	_refresh_card()
	_refresh_team_row()
	_refresh_players()
	_announce_pick()


## The format in force (Singles until one is known).
func _fmt() -> DuelFormat:
	return format if format != null else DuelFormat.preset(DuelFormat.SINGLES)


## Cycle the edited team slot's unit by [param step] (locked while Ready; a species clause
## skips units already on the team).
func cycle_pick(step: int) -> void:
	if _ready_pressed or _ids.is_empty():
		return
	for _i in range(_ids.size()):
		_pick_index = posmod(_pick_index + step, _ids.size())
		var id := String(_ids[_pick_index])
		if not _fmt().species_clause or not (id in team) or team.find(id) == edit_slot:
			break
	_set_pick(String(_ids[_pick_index]))


func _announce_pick() -> void:
	if _session_ok() and pick != "":
		net_session.send_lobby_message(DuelNetConfig.MSG_PICK, {"character_id": pick, "team": team.duplicate()})


func _on_lobby_message(message_type: String, data: Dictionary, from_slot: int) -> void:
	if message_type != DuelNetConfig.MSG_PICK or from_slot < 0:
		return
	# Untrusted: only duel-eligible ids are kept (the start re-validates anyway).
	var t := DuelNetConfig.clean_team(data.get("team", []))
	if t.is_empty():
		t = DuelNetConfig.clean_team(data.get("character_id", ""))
	if not t.is_empty():
		remote_picks[from_slot] = t
	_refresh_players()


## Every seat's team as the start will read it ({slot: [ids]}).
func picks() -> Dictionary:
	var out := remote_picks.duplicate()
	var me := _local_slot()
	if me >= 0 and not team.is_empty():
		out[me] = team.duplicate()
	return out


# --- Ready / start --------------------------------------------------------------------------

func _on_ready_pressed() -> void:
	_ready_pressed = not _ready_pressed
	if _session_ok():
		net_session.set_ready(_ready_pressed)
	_update_ready_button()
	_try_start()


func _update_ready_button() -> void:
	if ready_button == null:
		return
	ready_button.text = UNREADY_TEXT if _ready_pressed else READY_TEXT
	ready_button.tooltip_text = "Un-ready to change your team." if _ready_pressed else "Ready with this team."
	for b in [unit_card, _card_parts.get("prev"), _card_parts.get("next")]:
		if b is Button:
			(b as Button).disabled = _ready_pressed
	_refresh_team_row()


## Player-host: both seats ready -> start with both picks + the stage / weather.
func _try_start() -> void:
	if not is_host or _start_requested or not _session_ok() or _dedicated():
		return
	if not net_session.can_start_match():
		return
	var cfg: Dictionary = net_session.get_match_config()
	var final := DuelNetConfig.final_config(picks(),
		String(cfg.get(DuelNetConfig.KEY_STAGE, DuelNetConfig.DEFAULT_STAGE)),
		String(cfg.get(DuelNetConfig.KEY_WEATHER, DuelNetConfig.DEFAULT_WEATHER)), _fmt())
	if net_session.start_match(final):
		_start_requested = true
		MenuKit.set_status(_status, "Starting the duel...", "ok")
		game_starting.emit()


func _process(_delta: float) -> void:
	# The last ready flag may land a frame after ours (the roster broadcast): keep trying.
	if is_host and _ready_pressed and not _start_requested:
		_try_start()


func _on_roster_changed(roster: Dictionary) -> void:
	# A newcomer never saw our earlier announcement: say it again.
	if roster.size() > _last_roster_size:
		_announce_pick()
	_last_roster_size = roster.size()
	# A seat left: forget its pick. Config changes clear ready flags; mirror ours.
	var seated: Array = []
	var my_ready := _ready_pressed
	for pid in roster:
		var r: Dictionary = roster[pid]
		seated.append(int(r.get("slot", -1)))
		if int(r.get("slot", -1)) == _local_slot():
			my_ready = bool(r.get("ready", false))
	for slot in remote_picks.keys():
		if not (int(slot) in seated):
			remote_picks.erase(slot)
	if _ready_pressed and not my_ready and not _start_requested:
		_ready_pressed = false
		_update_ready_button()
	_refresh_players()
	_refresh_settings_enabled()


func _on_config_changed(config: Dictionary) -> void:
	_mirroring = true
	var stage := String(config.get(DuelNetConfig.KEY_STAGE, DuelNetConfig.DEFAULT_STAGE))
	for i in DuelSetup.STAGES.size():
		if String(DuelSetup.STAGES[i][0]) == stage and stage_option != null:
			stage_option.select(i)
	var weather := StringName(String(config.get(DuelNetConfig.KEY_WEATHER, DuelNetConfig.DEFAULT_WEATHER)))
	var wi := _weathers.find(weather)
	if wi >= 0 and weather_option != null:
		weather_option.select(wi)
	if config.has(DuelNetConfig.KEY_FORMAT):
		var f := DuelNetConfig.format_of(config)
		if format == null or f.to_dict() != format.to_dict():
			format = f
			set_team(team)   # refit our team to the new size (and tell the others)
	_sync_format_option()
	_mirroring = false
	_refresh_settings_enabled()


func _on_settings_changed(_index: int) -> void:
	if _mirroring or not settings_editable() or not _session_ok():
		return
	var f := DuelFormat.preset(DuelFormat.MENU_IDS[clampi(format_option.selected, 0, DuelFormat.MENU_IDS.size() - 1)])
	net_session.set_match_config({
		DuelNetConfig.KEY_STAGE: String(DuelSetup.STAGES[stage_option.selected][0]),
		DuelNetConfig.KEY_WEATHER: String(_weathers[weather_option.selected]),
		DuelNetConfig.KEY_FORMAT: f.to_dict(),
	})
	if is_host and not _dedicated():
		# The host's own lobby does not hear its config echo: apply the new format here.
		_on_config_changed(net_session.get_match_config())


## Show the format in force on the Format option (without re-sending it).
func _sync_format_option() -> void:
	if format_option == null:
		return
	var was := _mirroring
	_mirroring = true
	var i := DuelFormat.MENU_IDS.find(_fmt().id)
	if i >= 0:
		format_option.select(i)
	format_option.tooltip_text = _fmt().summary()
	_mirroring = was


# --- UI -------------------------------------------------------------------------------------

func _ensure_theme() -> void:
	var node: Node = get_parent()
	while node != null:
		if node is Control and (node as Control).theme != null:
			return
		node = node.get_parent()
	theme = MenuTheme.build()


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.name = "Columns"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	add_child(row)

	# Left: the players (slot, name, their unit, READY).
	var left := MenuKit.card()
	left.name = "PlayersCard"
	left.custom_minimum_size = Vector2(440, 0)
	row.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", MenuTheme.SP_M)
	left.add_child(lv)
	lv.add_child(MenuKit.section("Players"))
	_players_list = VBoxContainer.new()
	_players_list.name = "PlayersList"
	_players_list.add_theme_constant_override("separation", MenuTheme.SP_S)
	lv.add_child(_players_list)
	var note := MenuKit.label("The host picks the format. Build your team, no items. Changing the settings clears Ready.", &"MutedLabel", true)
	note.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	lv.add_child(note)

	# Right: your unit, the stage / weather, Ready.
	var right := VBoxContainer.new()
	right.name = "PickColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", MenuTheme.SP_M)
	row.add_child(right)
	right.add_child(MenuKit.section("Your team"))
	_team_row = HBoxContainer.new()
	_team_row.name = "TeamSlots"
	_team_row.add_theme_constant_override("separation", MenuTheme.SP_S)
	right.add_child(_team_row)
	var carousel := HBoxContainer.new()
	carousel.add_theme_constant_override("separation", MenuTheme.SP_S)
	right.add_child(carousel)
	var prev := MenuKit.button("‹", MenuKit.GHOST, 44)
	prev.name = "PrevUnit"
	prev.custom_minimum_size = Vector2(48, 72)
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prev.tooltip_text = "Previous unit"
	prev.pressed.connect(cycle_pick.bind(-1))
	carousel.add_child(prev)
	var parts := MenuKit.option_card(Vector2(400, 190))
	unit_card = parts["button"]
	unit_card.name = "UnitCard"
	unit_card.pressed.connect(cycle_pick.bind(1))
	MenuNav.hover_focus(unit_card)
	carousel.add_child(unit_card)
	var next := MenuKit.button("›", MenuKit.GHOST, 44)
	next.name = "NextUnit"
	next.custom_minimum_size = Vector2(48, 72)
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next.tooltip_text = "Next unit"
	next.pressed.connect(cycle_pick.bind(1))
	carousel.add_child(next)
	var v: VBoxContainer = parts["content"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var crest := MenuKit.crest("?", MenuTheme.GOLD, ConquestTheme.TEAM_BLUE, 48)
	head.add_child(crest)
	var names := VBoxContainer.new()
	head.add_child(names)
	var title := MenuKit.label("", &"SubheadingLabel")
	names.add_child(title)
	var badge := ElementVisuals.make_badge(&"", MenuTheme.FS_CAPTION)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	names.add_child(badge)
	var stats := MenuKit.label("", &"DimLabel")
	stats.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	v.add_child(stats)
	var moves := MenuKit.label("", &"", true)
	moves.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	v.add_child(moves)
	MenuKit.ignore_mouse(unit_card)
	_card_parts = {"crest": crest, "title": title, "badge": badge, "stats": stats, "moves": moves,
		"prev": prev, "next": next}

	var opts := GridContainer.new()
	opts.name = "DuelOptions"
	opts.columns = 4
	opts.add_theme_constant_override("h_separation", MenuTheme.SP_M)
	right.add_child(opts)
	format_option = _option(opts, "Format", DuelFormat.MENU_IDS.map(func(id): return DuelFormat.preset(id).display_name + " " + DuelFormat.preset(id).versus_label()))
	stage_option = _option(opts, "Stage", DuelSetup.STAGES.map(func(s): return s[1]))
	_weathers = [&"clear"]
	for w in Weather.all_ids():
		if w != &"clear":
			_weathers.append(w)
	weather_option = _option(opts, "Weather", _weathers.map(func(w):
		var wr = Weather.get_weather(w)
		return wr.display_name if wr != null else String(w)))
	stage_option.item_selected.connect(_on_settings_changed)
	weather_option.item_selected.connect(_on_settings_changed)
	format_option.item_selected.connect(_on_settings_changed)

	ready_button = MenuKit.button(READY_TEXT, MenuKit.PRIMARY, 260)
	ready_button.name = "ReadyButton"
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ready_button.pressed.connect(_on_ready_pressed)
	right.add_child(ready_button)
	_status = MenuKit.label("", &"DimLabel", true)
	_status.name = "LobbyStatus"
	right.add_child(_status)

	unit_card.focus_neighbor_bottom = unit_card.get_path_to(stage_option)
	_refresh_card()


func _option(grid: GridContainer, caption: String, items: Array) -> OptionButton:
	var l := MenuKit.label(caption, &"DimLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	var o := OptionButton.new()
	o.name = caption + "Option"
	o.custom_minimum_size = Vector2(180, 40)
	for item in items:
		o.add_item(String(item))
	grid.add_child(o)
	return o


func _refresh_settings_enabled() -> void:
	var on := settings_editable()
	for o in [format_option, stage_option, weather_option]:
		if o != null:
			o.disabled = not on
			o.tooltip_text = "" if on else "The host sets the format, stage and weather."


## The team slot chips: one per member (the edited one highlighted); click / tap to edit it.
func _refresh_team_row() -> void:
	if _team_row == null:
		return
	_team_row.visible = team.size() > 1
	# One chip per possible slot, built once and reused (a rebuild on every pick would churn nodes).
	while _team_row.get_child_count() < DuelFormat.MAX_TEAM:
		var i := _team_row.get_child_count()
		var nb := MenuKit.button("", MenuKit.GHOST, 110)
		nb.name = "TeamSlot%d" % i
		nb.custom_minimum_size = Vector2(110, 40)
		nb.tooltip_text = "Lead" if i == 0 else "Bench %d" % i
		nb.pressed.connect(select_team_slot.bind(i))
		_team_row.add_child(nb)
	for i in range(_team_row.get_child_count()):
		var b := _team_row.get_child(i) as Button
		b.visible = i < team.size()
		if not b.visible:
			continue
		var ch := CharacterLibrary.get_character(StringName(String(team[i])))
		b.text = "%d  %s" % [i + 1, ch.display_name if ch != null else String(team[i])]
		b.theme_type_variation = MenuKit.PRIMARY if i == edit_slot else MenuKit.GHOST
		b.disabled = _ready_pressed


func _refresh_card() -> void:
	if _card_parts.is_empty() or team.is_empty():
		return
	var shown := String(team[clampi(edit_slot, 0, team.size() - 1)])
	var ch := CharacterLibrary.get_character(StringName(shown))
	if ch == null:
		return
	var compiled: DuelCharacter = DuelMoveCompiler.compile(ch, DuelRuleset.load_default())["character"]
	var team := ConquestTheme.TEAM_BLUE if _local_slot() <= 0 else ConquestTheme.TEAM_RED
	(_card_parts["title"] as Label).text = ch.display_name
	MenuKit.set_crest(_card_parts["crest"], ch.display_name, ConquestTheme.element_color(String(ch.element)), team)
	ElementVisuals.update_badge(_card_parts["badge"], ch.element)
	(_card_parts["stats"] as Label).text = "HP %d · ATK %d · DEF %d · SPD %d" % [ch.base_health,
		ch.base_attack, ch.base_defense, ch.base_speed]
	var lines: Array[String] = []
	for i in range(compiled.move_count()):
		var m := compiled.get_move(i)
		lines.append("•  " + ("★ " if MoveResource.is_ultimate_move(m, i) else "") + m.display_name)
	(_card_parts["moves"] as Label).text = "\n".join(lines)
	MenuKit.accent_card(unit_card, ConquestTheme.element_color(String(ch.element)))


func _refresh_players() -> void:
	if _players_list == null:
		return
	for c in _players_list.get_children():
		_players_list.remove_child(c)
		c.queue_free()
	var rows := {}
	var me := _local_slot()
	if _session_ok() and net_session.has_method("get_roster"):
		var roster: Dictionary = net_session.get_roster()
		for pid in roster:
			var r: Dictionary = roster[pid]
			var slot := int(r.get("slot", -1))
			rows[slot] = {"name": String(r.get("name", "")), "ready": bool(r.get("ready", false))}
	elif local_player_name != "":
		rows[maxi(me, 0)] = {"name": local_player_name, "ready": _ready_pressed}
	var all := picks()
	for slot in [0, 1]:
		var r: Dictionary = rows.get(slot, {"name": "", "ready": false})
		_players_list.add_child(_player_row(slot, String(r["name"]), slot == me, bool(r["ready"]),
			_team_names(all.get(slot, []))))


## "Vineweave · Geode · Petalfang" for an announced team ("" when there is none).
static func _team_names(ids) -> String:
	var names: Array[String] = []
	for id in DuelNetConfig.clean_team(ids):
		var ch := CharacterLibrary.get_character(StringName(String(id)))
		names.append(ch.display_name if ch != null else String(id))
	return " · ".join(names)


func _player_row(slot: int, player_name: String, you: bool, is_ready: bool, unit_id: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "PlayerRow%d" % slot
	var team_color := MenuTheme.TEAM_BLUE if slot == 0 else MenuTheme.TEAM_RED
	var sb := MenuTheme.inset_box()
	sb.border_color = MenuTheme.GOLD_DK if you else MenuTheme.BORDER_SOFT
	sb.accent_color = team_color if player_name != "" else Color(team_color, 0.3)
	sb.accent_width = 4.0
	sb.content_margin_left = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", MenuTheme.SP_M)
	p.add_child(h)
	var tag := MenuKit.label("P%d" % (slot + 1), &"SectionLabel")
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var shown := (player_name + ("  (you)" if you else "")) if player_name != "" else "Waiting for a player..."
	var n := MenuKit.label(shown, &"" if player_name != "" else &"MutedLabel")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(n)
	if player_name != "":
		var u := MenuKit.label(unit_id if unit_id != "" else "choosing...", &"DimLabel")
		u.name = "UnitLabel"
		u.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(u)
		var pill := MenuKit.badge("READY" if is_ready else "NOT READY",
			MenuTheme.SUCCESS if is_ready else MenuTheme.TEXT_MUTED, is_ready)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pill)
	return p


## Left / Right (or Q / E) on the focused unit card cycle it.
func _input(event: InputEvent) -> void:
	if unit_card == null or get_viewport() == null or get_viewport().gui_get_focus_owner() != unit_card:
		return
	if event.is_action_pressed("ui_left") or MenuNav.is_prev_event(event):
		get_viewport().set_input_as_handled()
		cycle_pick(-1)
	elif event.is_action_pressed("ui_right") or MenuNav.is_next_event(event):
		get_viewport().set_input_as_handled()
		cycle_pick(1)
