extends GutTest

## The menu structure of docs/design/DECISIONS.md #30-32, on the REAL screens (rendered nodes,
## keys, routing):
##   Main menu  Solo / Online / Compendium / Map Creator (+ Resume / Continue rows) -- no Versus row
##   Solo       Story / Campaign / Skirmish / Arena Run -- no Duel card, no Challenges card
##   Online     Versus / Challenges / Arena (COMING SOON, disabled)
##   Versus     MODE (Conquest | Duel) x WHERE (Network | Same device)
## Nobody presses through a real scene change (it would swap GUT's scene out): a handler is
## called on a screen taken OUT of the tree (MenuNav.change_scene is then a no-op), and the
## wiring is read off the live `pressed` connections.

const DESIGN := Vector2i(1280, 720)

var _prev_size: Vector2i
var _prev_net_mode: String
var _prev_versus_mode: String


func before_all() -> void:
	_prev_size = get_tree().root.size
	get_tree().root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_size


func before_each() -> void:
	_prev_net_mode = NetworkMultiplayerSetup.requested_mode
	_prev_versus_mode = MultiplayerModeSelection.last_mode


func after_each() -> void:
	NetworkMultiplayerSetup.requested_mode = _prev_net_mode
	MultiplayerModeSelection.last_mode = _prev_versus_mode
	NetSession.lobby_mode = NetProtocol.MODE_CONQUEST


func _open(script_path: String) -> Control:
	var screen := Control.new()
	screen.set_script(load(script_path))
	add_child_autofree(screen)
	for i in range(4):
		await get_tree().process_frame
	return screen


## Detach [param screen] so its handlers run without changing scene.
func _detach(screen: Control) -> void:
	screen.get_parent().remove_child(screen)
	screen.queue_free()


func _targets(b: Button) -> Array:
	return b.pressed.get_connections().map(func(c): return (c["callable"] as Callable).get_method())


## The screen's own handlers wired to [param b] (global listeners -- click sounds -- excluded).
func _own_targets(b: Button, screen: Object) -> Array:
	return b.pressed.get_connections().filter(func(c): return (c["callable"] as Callable).get_object() == screen)


func _labels(root: Node) -> String:
	var out := ""
	if root is Label:
		out += (root as Label).text + "\n"
	for c in root.get_children():
		out += _labels(c)
	return out


# --- Main menu --------------------------------------------------------------------

func test_main_menu_rows_are_solo_online_compendium_map_creator() -> void:
	var menu := await _open("res://menus/MainMenu.gd")
	var ids: Array = MainMenu.ENTRIES.map(func(e): return e["id"])
	assert_eq(ids, ["solo", "online", "compendium", "map_creator", "quit"], "the decision-30 rows")
	assert_null(menu.find_child("VersusButton", true, false), "no top-level Versus row")
	var online := menu.find_child("OnlineButton", true, false) as Button
	assert_not_null(online, "an Online row")
	assert_eq(online.text, "Online")
	assert_eq(int(MainMenu.ENTRIES[1]["key"]), KEY_2, "Online is key 2")
	assert_true("_on_online_pressed" in _targets(online), "it opens the Online screen")
	assert_true(ResourceLoader.exists(MainMenu.ONLINE_SCENE), "which exists")
	assert_false(String(MainMenu.ENTRIES[0]["desc"]).contains("Duel"), "Solo no longer promises duels")


# --- Solo --------------------------------------------------------------------------

func test_solo_is_story_campaign_skirmish_arena() -> void:
	var screen := await _open("res://menus/SoloModeSelect.gd")
	var row := screen.find_child("ModeCards", true, false) as HBoxContainer
	var names: Array = row.get_children().map(func(c): return String(c.name))
	assert_eq(names, ["StoryCard", "CampaignCard", "SkirmishCard", "ArenaRunCard"], "Story first, four cards")
	assert_null(screen.find_child("DuelCard", true, false), "no Duel card (duels live in Story + Online)")
	assert_null(screen.find_child("ChallengesCard", true, false), "Challenges moved to Online")
	var hint := screen.find_child("KeyHint", true, false) as Label
	assert_eq(hint.text, "1 Story  •  2 Campaign  •  3 Skirmish  •  4 Arena Run", "renumbered keys")
	for c in row.get_children():
		assert_true((c as Control).get_global_rect().end.x <= DESIGN.x + 0.5, "%s fits 1280 wide" % c.name)


# --- Online hub ------------------------------------------------------------------

func test_online_hub_offers_versus_challenges_and_a_coming_soon_arena() -> void:
	var hub := await _open("res://menus/OnlineHub.gd")
	var row := hub.find_child("OnlineCards", true, false)
	assert_eq(row.get_children().map(func(c): return String(c.name)), ["VersusCard", "ChallengesCard", "ArenaCard"])
	var versus := hub.find_child("VersusCard", true, false) as Button
	var challenges := hub.find_child("ChallengesCard", true, false) as Button
	var arena := hub.find_child("ArenaCard", true, false) as Button
	assert_true("_on_versus_pressed" in _targets(versus), "Versus opens the Versus screen")
	assert_true("_on_challenges_pressed" in _targets(challenges), "Challenges opens the browser")
	assert_eq(OnlineHub.CHALLENGE_BROWSE_SCENE, "res://menus/ChallengeBrowse.tscn", "the existing ChallengeBrowse")
	assert_true(ResourceLoader.exists(OnlineHub.VERSUS_SCENE) and ResourceLoader.exists(OnlineHub.CHALLENGE_BROWSE_SCENE))
	assert_true(arena.disabled, "Arena is disabled")
	assert_eq(arena.focus_mode, Control.FOCUS_NONE, "and skipped by keyboard / pad focus")
	assert_true(_own_targets(arena, hub).is_empty(), "nothing behind it")
	assert_true(_labels(arena).contains(OnlineHub.COMING_SOON), "clearly marked COMING SOON")
	var hint := hub.find_child("KeyHint", true, false) as Label
	assert_true(hint.text.contains("1 Versus") and hint.text.contains("2 Challenges"), hint.text)
	for c in row.get_children():
		assert_true((c as Control).get_global_rect().end.x <= DESIGN.x + 0.5, "%s fits 1280 wide" % c.name)


func test_challenges_back_returns_to_online() -> void:
	assert_eq(ChallengeBrowse.ONLINE_SCENE, "res://menus/OnlineHub.tscn", "Challenges' Back goes to Online")


# --- Versus ------------------------------------------------------------------------

func test_versus_picks_mode_then_where() -> void:
	MultiplayerModeSelection.last_mode = NetProtocol.MODE_CONQUEST
	var v := await _open("res://menus/MultiplayerModeSelection.gd") as MultiplayerModeSelection
	for n in ["ConquestCard", "DuelCard", "NetworkMultiplayerButton", "LocalMultiplayerButton", "BackButton"]:
		assert_not_null(v.find_child(n, true, false), n)
	assert_true(v.conquest_button.button_pressed, "Conquest is selected by default")
	assert_eq(v.conquest_button.button_group, v.duel_button.button_group, "one mode at a time")
	v.select_mode(NetProtocol.MODE_DUEL)
	assert_true(v.duel_button.button_pressed and not v.conquest_button.button_pressed, "Duel selected")
	assert_true(_labels(v).contains("(DUEL)"), "the where row names the mode")
	var hint := v.find_child("KeyHint", true, false) as Label
	assert_eq(hint.text, "1 Conquest  •  2 Duel  •  3 Network  •  4 Same device")
	assert_true("_on_network_multiplayer_pressed" in _targets(v.network_multiplayer_button))
	assert_true("_on_local_multiplayer_pressed" in _targets(v.local_multiplayer_button))
	# Keyboard / pad: Down from a mode card reaches the where row.
	assert_eq(v.conquest_button.get_node(v.conquest_button.focus_neighbor_bottom), v.network_multiplayer_button)
	assert_eq(v.local_multiplayer_button.get_node(v.local_multiplayer_button.focus_neighbor_top), v.duel_button)
	# Network carries the chosen mode to the host / join screen.
	_detach(v)
	v._on_network_multiplayer_pressed()
	assert_eq(NetworkMultiplayerSetup.requested_mode, NetProtocol.MODE_DUEL, "Duel -> a duel lobby")
	v.select_mode(NetProtocol.MODE_CONQUEST)
	v._on_network_multiplayer_pressed()
	assert_eq(NetworkMultiplayerSetup.requested_mode, NetProtocol.MODE_CONQUEST, "Conquest -> the map lobby")
	assert_eq(MultiplayerModeSelection.ONLINE_SCENE, "res://menus/OnlineHub.tscn", "Back goes to Online")
	assert_eq(MultiplayerModeSelection.DUEL_SETUP_SCENE, "res://menus/DuelSetup.tscn", "same-device duel = DuelSetup")


func test_the_network_screen_follows_the_chosen_mode() -> void:
	NetworkMultiplayerSetup.requested_mode = NetProtocol.MODE_DUEL
	var s := await _open("res://menus/NetworkMultiplayerSetup.gd")
	assert_eq(NetSession.lobby_mode, NetProtocol.MODE_DUEL, "the session hosts / joins a duel lobby")
	assert_true(_labels(s).contains(NetworkMultiplayerSetup.TITLE_DUEL), "titled Network Duel")
	assert_true(_labels(s).to_upper().contains("ONLINE"), "breadcrumb starts at Online")
	s.queue_free()
	await get_tree().process_frame
	NetworkMultiplayerSetup.requested_mode = NetProtocol.MODE_CONQUEST
	var c := await _open("res://menus/NetworkMultiplayerSetup.gd")
	assert_eq(NetSession.lobby_mode, NetProtocol.MODE_CONQUEST, "back to the map lobby")
	assert_true(_labels(c).contains(NetworkMultiplayerSetup.TITLE_SETUP))


func test_the_duel_lobby_offers_only_eligible_units() -> void:
	var lobby := DuelLobby.new()
	add_child_autofree(lobby)
	await get_tree().process_frame
	lobby.initialize(true, "Host")
	assert_eq(lobby.pick, "vineweave", "the host's seat defaults to side A's unit")
	var seen := {}
	for i in range(DuelNetConfig.eligible_ids().size()):
		assert_true(DuelNetConfig.is_eligible(lobby.pick), "%s is duel-eligible" % lobby.pick)
		seen[lobby.pick] = true
		lobby.cycle_pick(1)
	assert_false(seen.has("bastion"), "a kit that cannot damage is never offered")
	assert_eq(seen.size(), DuelNetConfig.eligible_ids().size(), "the carousel walks the whole eligible roster")
	assert_not_null(lobby.ready_button, "a Ready button")
	assert_not_null(lobby.stage_option, "the host's stage option")
