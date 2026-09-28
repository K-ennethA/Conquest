extends GutTest

## OFFLINE-ONLY MAPS: a network versus match seats exactly two humans and runs NO AI on any
## peer, so a map that needs something else to take turns -- an AI-controlled neutral faction
## on slot 2 (Riftwood's jungle camps, King's Crossing's guardians) or AI-driven Siege creep
## waves down authored lanes -- used to be offered online and then stalled mid-match (the turn
## reached the neutral slot and nobody could ever act). The rule
## (MapCatalog.network_refusal / network_play_blocker) now refuses them at every door:
##
##   * the lobby's map rows (disabled, "Offline only", the reason as the tooltip),
##   * the dedicated server's --map (refused at boot) and its leader-config sanitiser,
##   * GameModeManager.apply_match_config -- every peer's last line before booting a battle.
##
## Offline pickers (single player / hot-seat) still offer them exactly as before.

const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")

const RIFTWOOD := "res://game/maps/resources/riftwood.tres"
const KINGS_CROSSING := "res://game/maps/resources/kings_crossing.tres"
const TWO_SEAT_MAPS: Array[String] = [
	"res://game/maps/resources/default_skirmish.tres",
	"res://game/maps/resources/castle_siege.tres",
	"res://game/maps/resources/river_crossing.tres",
	"res://game/maps/resources/proving_grounds.tres",
]

var _saved_mode: int = 0
var _saved_map: String = ""


func before_each() -> void:
	_saved_mode = GameSettings.game_mode
	_saved_map = GameSettings.get_selected_map()


func after_each() -> void:
	GameSettings.set_game_mode(_saved_mode)
	GameSettings.set_selected_map(_saved_map)
	MapRowBuilder.reset_catalog()


func _spawn(player_id: int, kind: String = "Start") -> Dictionary:
	return {"character_id": "tree_grunt", "player_id": player_id, "position": Vector2i(player_id, 0),
		"spawn_kind": kind}


# --- the rule (pure) ------------------------------------------------------------

func test_a_unit_on_a_third_slot_blocks_network_play() -> void:
	var res := MapResource.new()
	res.unit_spawns = [_spawn(0), _spawn(1), _spawn(2, "Reinforcement")] as Array[Dictionary]
	assert_eq(MapCatalog.network_play_blocker(res), MapCatalog.NET_REFUSAL_THIRD_FACTION,
		"a neutral / AI faction on slot 2 would get turns no seat can take")


func test_siege_creep_lanes_block_network_play() -> void:
	var res := MapResource.new()
	res.unit_spawns = [_spawn(0), _spawn(1)] as Array[Dictionary]
	res.lanes = [[Vector2i(0, 0), Vector2i(5, 5)]]
	assert_eq(MapCatalog.network_play_blocker(res), MapCatalog.NET_REFUSAL_AI_CREEPS,
		"creep waves are AI-driven, and network play runs no AI")


func test_a_plain_two_seat_map_has_no_blocker() -> void:
	var res := MapResource.new()
	res.unit_spawns = [_spawn(0), _spawn(1)] as Array[Dictionary]
	assert_eq(MapCatalog.network_play_blocker(res), "", "two seats, no AI: fine online")


func test_every_refusal_code_has_a_sentence() -> void:
	for code in [MapCatalog.NET_REFUSAL_UNREADABLE, MapCatalog.NET_REFUSAL_TOO_LARGE,
			MapCatalog.NET_REFUSAL_THIRD_FACTION, MapCatalog.NET_REFUSAL_AI_CREEPS]:
		assert_false(MapCatalog.describe_network_refusal(code).is_empty(), "%s explains itself" % code)
	assert_eq(MapCatalog.describe_network_refusal(""), "", "nothing to explain for an eligible map")
	assert_eq(MapCatalog.describe_network_refusal(MapCatalog.NET_REFUSAL_TOO_LARGE),
		MapRowBuilder.TOO_LARGE_TOOLTIP, "the existing 'too large' wording is unchanged")


# --- the shipped maps -------------------------------------------------------------

func test_riftwood_is_offline_only() -> void:
	assert_eq(MapCatalog.network_refusal(RIFTWOOD), MapCatalog.NET_REFUSAL_THIRD_FACTION,
		"Riftwood's jungle camps are an AI faction on slot 2")
	assert_false(MapCatalog.network_eligible(RIFTWOOD), "so it is not offered online")


func test_kings_crossing_is_offline_only() -> void:
	assert_eq(MapCatalog.network_refusal(KINGS_CROSSING), MapCatalog.NET_REFUSAL_THIRD_FACTION,
		"King's Crossing's guardians are an AI faction on slot 2")


func test_two_seat_maps_stay_network_eligible() -> void:
	for path in TWO_SEAT_MAPS:
		assert_eq(MapCatalog.network_refusal(path), "", "%s is still playable online" % path)


# --- the lobby rows -------------------------------------------------------------

# Riftwood itself is Inactive now (Siege is not selectable), so King's Crossing -- the other
# third-faction map, still Active -- is the one the online list must grey out.
func test_the_networked_list_disables_kings_crossing_and_says_why() -> void:
	var row := _row_for(MapRowBuilder.versus_rows(true), KINGS_CROSSING)
	assert_false(row.is_empty(), "King's Crossing is still LISTED online (greyed, not hidden)")
	assert_true(bool(row["disabled"]), "but it cannot be picked")
	assert_eq(String(row["tooltip"]),
		MapCatalog.describe_network_refusal(MapCatalog.NET_REFUSAL_THIRD_FACTION), "the reason is the tooltip")
	assert_eq(String(row["note"]), MapRowBuilder.OFFLINE_ONLY_NOTE, "and the row reads 'Offline only' at a glance")
	var button := MapRowBuilder.build_row_button(row)
	add_child_autofree(button)
	assert_true(button.disabled, "the rendered row is disabled")
	assert_eq(button.tooltip_text, String(row["tooltip"]), "and carries the sentence")


func test_the_local_list_still_offers_riftwood() -> void:
	var row := _row_for(MapRowBuilder.versus_rows(false, true), RIFTWOOD)
	assert_false(row.is_empty(), "listed for local play")
	assert_false(bool(row["disabled"]), "and selectable offline -- nothing is taken away there")


func _row_for(rows: Array, path: String) -> Dictionary:
	for row in rows:
		if row is Dictionary and String((row as Dictionary).get("path", "")) == path:
			return row
	return {}


# --- the server + every peer ----------------------------------------------------

func test_the_dedicated_sanitiser_drops_an_offline_only_pick() -> void:
	var clean := NetSessionNode._sanitize_config({"map_path": RIFTWOOD, "turn_system": 1})
	assert_false(clean.has("map_path"), "a leader cannot pick Riftwood on a dedicated server")
	assert_eq(int(clean.get("turn_system", -1)), 1, "the rest of the pick still applies")
	assert_eq(String(NetSessionNode._sanitize_config({"map_path": TWO_SEAT_MAPS[0]}).get("map_path", "")),
		TWO_SEAT_MAPS[0], "an ordinary map passes")


func test_the_dedicated_server_refuses_an_offline_only_map_at_boot() -> void:
	var session: NetSessionNode = NetSessionNode.new()
	var server := DedicatedServer.new()
	var err := server.start(PackedStringArray(["--server", "--port", "0", "--map", RIFTWOOD]), session)
	assert_eq(err, ERR_INVALID_PARAMETER, "--map riftwood is refused instead of hosting a match that would stall")
	assert_false(session.is_active(), "nothing was hosted")
	server.free()
	session.free()


func test_no_peer_boots_an_offline_only_map() -> void:
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	var boot := GameModeManager.apply_match_config({"map_path": RIFTWOOD, "turn_system": 0, "seed": 1})
	assert_eq(boot, "", "the match is refused on this peer")
	assert_eq(GameSettings.game_mode, GameSettings.GameMode.VERSUS, "and nothing was switched to network play")
	assert_eq(GameModeManager._offline_only_refusal, MapCatalog.NET_REFUSAL_THIRD_FACTION,
		"with the reason the menu message is built from")
	assert_true(GameModeManager.ABORT_TEXT.has(GameModeManager.OFFLINE_ONLY_MAP_REASON), "which has a sentence")
