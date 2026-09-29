extends GutTest

## The online TURN CLOCK's pure parts and its UI seams: the presets / budgets / wording
## ([NetTurnClock]), the wire additions ([NetProtocol]), the dedicated server's config
## sanitiser, the local Speed First clock staying off online, the HUD chip in network mode
## ([TurnTimer]), the timeout toast ([NetToast]), and the visible FORFEIT entry of the battle
## Map Menu ([MapMenu]) and the online corner ([NetMatchBar]).


class FakeSession extends Node:
	signal turn_clock_changed(clock: Dictionary)
	signal turn_timed_out(slot: int, action: Dictionary, strikes: int)
	var networked := true
	var forfeits := 0
	var slot := 1
	var remaining := -1
	func is_networked_match() -> bool:
		return networked
	func forfeit_match() -> bool:
		forfeits += 1
		return true
	func local_slot() -> int:
		return slot
	func turn_clock() -> Dictionary:
		return {}
	func turn_clock_remaining_ms() -> int:
		return remaining
	func get_match_config() -> Dictionary:
		return {NetTurnClock.CONFIG_AFK_LIMIT: 3}


class FakePause extends Node:
	var forfeited := 0
	var requested := 0
	func forfeit_now() -> void:
		forfeited += 1
	func request_forfeit() -> void:
		requested += 1


# --- Presets ------------------------------------------------------------------------------------

func test_presets_and_the_default() -> void:
	assert_eq(NetTurnClock.DEFAULT_PRESET, NetTurnClock.PRESET_STANDARD, "Standard by default")
	assert_eq(NetTurnClock.PRESET_IDS, [NetTurnClock.PRESET_RAPID, NetTurnClock.PRESET_STANDARD, NetTurnClock.PRESET_RELAXED] as Array[String])
	assert_false(NetTurnClock.PRESETS.has("off"), "no Off preset online (owner: every online mode is timed)")
	assert_eq(NetTurnClock.normalise_preset("RAPID"), NetTurnClock.PRESET_RAPID)
	assert_eq(NetTurnClock.normalise_preset("off"), NetTurnClock.PRESET_STANDARD, "unknown -> Standard, never off")
	assert_eq(NetTurnClock.normalise_preset(null), NetTurnClock.PRESET_STANDARD)
	assert_eq(NetTurnClock.label(NetTurnClock.PRESET_RELAXED), "Relaxed")
	assert_eq(NetTurnClock.picker_items().size(), 3)


func test_budgets_per_kind() -> void:
	# Standard: Traditional 90s per side + 5s per unit, Speed First 20s per unit, duel 30s per action.
	assert_eq(NetTurnClock.budget_ms("standard", NetTurnClock.KIND_SIDE, 0), 90000)
	assert_eq(NetTurnClock.budget_ms("standard", NetTurnClock.KIND_SIDE, 4), 110000, "+5s per living unit")
	assert_eq(NetTurnClock.budget_ms("standard", NetTurnClock.KIND_UNIT, 9), 20000, "Speed First ignores the army size")
	assert_eq(NetTurnClock.budget_ms("standard", NetTurnClock.KIND_ACTION), 30000)
	assert_lt(NetTurnClock.budget_ms("rapid", NetTurnClock.KIND_UNIT), NetTurnClock.budget_ms("standard", NetTurnClock.KIND_UNIT), "Rapid is tighter")
	assert_gt(NetTurnClock.budget_ms("relaxed", NetTurnClock.KIND_UNIT), NetTurnClock.budget_ms("standard", NetTurnClock.KIND_UNIT), "Relaxed is looser")
	for id in NetTurnClock.PRESET_IDS:
		for kind in [NetTurnClock.KIND_SIDE, NetTurnClock.KIND_UNIT, NetTurnClock.KIND_ACTION]:
			assert_gt(NetTurnClock.budget_ms(id, kind, 3), NetTurnClock.WARNING_SECONDS * 1000, "%s/%s gives more than the warning band" % [id, kind])
	assert_eq(NetTurnClock.budget_ms("relaxed", NetTurnClock.KIND_SIDE, 6, 1234), 1234, "the test override wins")


func test_afk_limit_and_formatting() -> void:
	assert_eq(NetTurnClock.DEFAULT_AFK_LIMIT, 3)
	assert_eq(NetTurnClock.normalise_afk_limit(-4), 0)
	assert_eq(NetTurnClock.normalise_afk_limit(99), NetTurnClock.MAX_AFK_LIMIT)
	assert_eq(NetTurnClock.normalise_afk_limit("x"), NetTurnClock.DEFAULT_AFK_LIMIT)
	assert_eq(NetTurnClock.format_ms(95000), "1:35")
	assert_eq(NetTurnClock.format_ms(200), "0:01", "rounds up")
	assert_eq(NetTurnClock.format_ms(-5), "0:00")
	assert_string_contains(NetTurnClock.describe("standard"), "90s per side")


func test_timeout_wording() -> void:
	assert_eq(NetTurnClock.describe_timeout(NetProtocol.end_turn(0), true), "Time's up — your turn ended")
	assert_eq(NetTurnClock.describe_timeout(NetProtocol.wait("1:0"), false), "Time's up — opponent's unit waits")
	assert_string_contains(NetTurnClock.describe_timeout(NetProtocol.end_turn(0), true, 2, 3), "one more and you forfeit")
	assert_false("forfeit" in NetTurnClock.describe_timeout(NetProtocol.end_turn(0), false, 2, 3), "no warning for the opponent's strikes")


# --- Wire -----------------------------------------------------------------------------------------

func test_protocol_bump_and_timeout_stamp() -> void:
	assert_eq(NetProtocol.PROTOCOL_VERSION, 6, "6 = the online turn clock + party duels")
	var a := NetProtocol.end_turn(1)
	assert_false(NetProtocol.is_timeout(a))
	a[NetProtocol.KEY_TIMEOUT] = true
	assert_true(NetProtocol.is_timeout(a))
	assert_true(NetProtocol.is_well_formed(a), "the stamp does not change the action's shape")
	assert_false(NetProtocol.is_timeout(null))


func test_the_server_sanitiser_keeps_only_known_presets() -> void:
	assert_eq(NetSessionNode._sanitize_config({"turn_clock": "rapid"}).get("turn_clock", ""), "rapid")
	assert_false(NetSessionNode._sanitize_config({"turn_clock": "off"}).has("turn_clock"), "unknown / off dropped")
	assert_false(NetSessionNode._sanitize_config({"turn_clock": 3}).has("turn_clock"))
	assert_true("turn_clock" in NetSessionNode.CONFIG_KEYS, "a lobby leader may set it")


func test_a_submitted_intent_never_carries_a_timeout() -> void:
	# submit_intent strips the stamp (only the host's clock issues timeouts); here the session is
	# not in a match, so it refuses outright -- the strip is covered over a socket in
	# test_net_turn_clock.gd.
	var ns := NetSessionNode.new()
	add_child_autofree(ns)
	var a := NetProtocol.end_turn(0)
	a[NetProtocol.KEY_TIMEOUT] = true
	assert_false(ns.submit_intent(a))
	assert_true(ns.turn_clock().is_empty(), "no clock outside a match")
	assert_eq(ns.turn_clock_remaining_ms(), -1)
	assert_eq(ns.turn_clock_slot(), -1)


func test_the_dedicated_server_flags() -> void:
	var opts := DedicatedServer.parse_args(PackedStringArray(["--server", "--turn-clock", "rapid", "--afk-limit", "5", "--turn-clock-ms", "900"]))
	assert_eq(String(opts["turn_clock"]), "rapid")
	assert_eq(int(opts["afk_limit"]), 5)
	assert_eq(int(opts["turn_clock_ms"]), 900)


# --- The local Speed First clock stays off online --------------------------------------------------

func test_the_local_speed_clock_is_off_in_a_network_match() -> void:
	var prev: int = GameSettings.game_mode
	var ts := SpeedFirstTurnSystem.new()
	GameSettings.game_mode = GameSettings.GameMode.MULTIPLAYER
	assert_eq(ts._configured_turn_timer_seconds(), 0, "online the host's clock rules -- a local expiry would desync")
	GameSettings.game_mode = prev
	ts.free()


# --- HUD chip (network mode) ------------------------------------------------------------------------

func test_the_chip_renders_a_network_clock_and_never_expires_it() -> void:
	var fake := FakeSession.new()
	add_child_autofree(fake)
	var chip := TurnTimer.new()
	chip.session = fake
	add_child_autofree(chip)
	assert_false(chip.visible, "hidden until a clock opens")
	fake.remaining = 12400
	fake.turn_clock_changed.emit({"slot": 0, "remaining_ms": 12400, "budget_ms": 20000, "key": "k"})
	assert_true(chip.visible and chip.is_net_mode(), "shown in network mode")
	assert_eq(chip.caption_text(), TurnTimer.CAPTION_THEIRS, "slot 0's clock on seat 1 = OPPONENT")
	assert_eq(chip.readout_text(), "13")
	fake.remaining = 3000
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(chip.readout_text(), "3", "follows the session's deadline")
	assert_eq(chip.band(), 2, "urgent under 5s")
	fake.remaining = 0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(chip.readout_text(), "0", "holds at zero")
	assert_true(chip.visible and chip.is_running(), "no local expiry: the host decides")
	fake.turn_timed_out.emit(0, NetProtocol.end_turn(0), 1)
	assert_eq(chip.caption_text(), TurnTimer.CAPTION_TIMEOUT)
	fake.turn_clock_changed.emit({"slot": 1, "remaining_ms": 90000, "budget_ms": 90000, "key": "k2"})
	assert_eq(chip.caption_text(), TurnTimer.CAPTION_TIMEOUT, "TIME'S UP holds briefly over the next clock")
	assert_true(chip.is_own_clock(), "seat 1's own clock now")
	fake.turn_clock_changed.emit({})
	assert_false(chip.visible, "hidden when the host stops the clock")
	assert_false(chip.is_net_mode())


func test_the_toast_announces_a_timeout() -> void:
	var toast := NetToast.new()
	add_child_autofree(toast)
	toast._on_turn_timed_out(0, NetProtocol.end_turn(0), 1)
	assert_string_contains(toast.current_text(), "Time's up", "timeouts are announced")


# --- Forfeit: the Map Menu and the online corner --------------------------------------------------

func test_the_map_menu_offers_forfeit_online_with_a_confirm() -> void:
	var fake := FakeSession.new()
	add_child_autofree(fake)
	var pause := FakePause.new()
	add_child_autofree(pause)
	var menu := MapMenu.new()
	menu.net_session = fake
	menu.pause_menu = pause
	add_child_autofree(menu)
	assert_true(menu.can_open(), "online the menu opens on either seat's turn")
	menu.open()
	assert_true(MapMenu.LABEL_FORFEIT in menu.button_texts(), "Forfeit is on the main page online")
	menu.show_page(MapMenu.Page.CONFIRM_FORFEIT)
	await get_tree().process_frame
	assert_eq(menu.button_texts(), PackedStringArray([MapMenu.LABEL_FORFEIT, "Cancel"]), "asks first")
	var yes: Button = null
	for c in menu._body.get_children():
		if c is Button and (c as Button).text == MapMenu.LABEL_FORFEIT and not c.is_queued_for_deletion():
			yes = c
	assert_not_null(yes)
	yes.pressed.emit()
	assert_eq(pause.forfeited, 1, "the pause menu's forfeit path runs (NetSession.forfeit_match semantics)")
	assert_false(menu.is_open(), "the menu closed")


func test_the_map_menu_forfeit_falls_back_to_the_session() -> void:
	var fake := FakeSession.new()
	add_child_autofree(fake)
	var menu := MapMenu.new()
	menu.net_session = fake
	add_child_autofree(menu)
	fake.networked = false
	menu._do_forfeit()
	assert_eq(fake.forfeits, 0, "never outside a live network match")


func test_no_forfeit_entry_offline() -> void:
	var fake := FakeSession.new()
	fake.networked = false
	add_child_autofree(fake)
	var menu := MapMenu.new()
	menu.net_session = fake
	add_child_autofree(menu)
	menu.open()
	assert_false(MapMenu.LABEL_FORFEIT in menu.button_texts(), "solo / hot-seat: no Forfeit row")


func test_the_online_corner_shows_the_clock_and_a_forfeit_button() -> void:
	var fake := FakeSession.new()
	add_child_autofree(fake)
	var pause := FakePause.new()
	add_child_autofree(pause)
	var bar := NetMatchBar.new()
	bar.session = fake
	bar.pause_menu = pause
	add_child_autofree(bar)
	assert_not_null(bar.timer, "the clock chip")
	assert_eq(bar.timer.session, fake, "follows the same session")
	assert_true(bar.forfeit_button.visible, "Forfeit is always visible")
	assert_eq(bar.forfeit_button.text, NetMatchBar.LABEL_FORFEIT)
	bar.forfeit_button.pressed.emit()
	assert_eq(pause.requested, 1, "opens the pause menu's forfeit confirm")
	assert_eq(fake.forfeits, 0, "nothing forfeited before the confirm")


# --- Lobbies: the host / leader picks the preset ------------------------------------------------

func test_the_map_lobby_picks_the_turn_clock() -> void:
	var lobby := Control.new()
	lobby.set_script(load("res://menus/CollaborativeLobby.gd"))
	add_child_autofree(lobby)
	await get_tree().process_frame
	lobby.initialize(true, "Host")
	var opt: OptionButton = lobby.turn_clock_option
	assert_not_null(opt, "a Turn clock picker")
	assert_eq(opt.item_count, 3, "Rapid / Standard / Relaxed -- no Off")
	assert_eq(lobby.turn_clock_pick(), NetTurnClock.DEFAULT_PRESET, "Standard by default")
	assert_false(opt.disabled, "the host picks")
	opt.select(0)
	opt.item_selected.emit(0)
	assert_eq(lobby.turn_clock_pick(), NetTurnClock.PRESET_RAPID)
	var cfg: Dictionary = lobby._build_start_config("res://game/maps/resources/default_skirmish.tres")
	assert_eq(String(cfg.get(NetTurnClock.CONFIG_PRESET, "")), NetTurnClock.PRESET_RAPID, "the start carries the pick")


func test_the_map_lobby_guest_only_sees_the_clock() -> void:
	var lobby := Control.new()
	lobby.set_script(load("res://menus/CollaborativeLobby.gd"))
	add_child_autofree(lobby)
	await get_tree().process_frame
	lobby.initialize(false, "Guest")
	assert_true(lobby.turn_clock_option.disabled, "a guest cannot change the host's clock")
	lobby._on_session_config_changed({NetTurnClock.CONFIG_PRESET: NetTurnClock.PRESET_RELAXED})
	assert_eq(lobby.turn_clock_pick(), NetTurnClock.PRESET_RELAXED, "it mirrors the host's pick")


func test_the_duel_lobby_picks_the_turn_clock() -> void:
	var lobby := DuelLobby.new()
	add_child_autofree(lobby)
	await get_tree().process_frame
	lobby.initialize(true, "Host")
	assert_not_null(lobby.turn_clock_option, "a Turn clock picker")
	assert_eq(lobby.turn_clock_pick(), NetTurnClock.DEFAULT_PRESET)
	lobby.turn_clock_option.select(2)
	assert_eq(lobby.turn_clock_pick(), NetTurnClock.PRESET_RELAXED)
	lobby._on_config_changed({NetTurnClock.CONFIG_PRESET: NetTurnClock.PRESET_RAPID})
	assert_eq(lobby.turn_clock_pick(), NetTurnClock.PRESET_RAPID, "mirrors the session config")
