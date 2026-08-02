extends GutTest

# The connect-time build gate: NetProtocol.validate_hello.
#
# Why this suite exists: two machines running mismatched builds must refuse each other
# WHEN THEY CONNECT, not silently desync on the first command. validate_hello is the pure
# function the server runs before a joining peer is given a roster slot, so it is testable
# without a socket -- which is the whole point of keeping it pure.
#
# The contract it pins:
#   * PROTOCOL_VERSION difference  -> REFUSED (reason "version_mismatch").
#   * game version difference only -> ADMITTED, flagged "build_differs" (an editor run
#     joining an exported build is a legitimate two-machine test setup).
#   * anything that is not a well-shaped hello -> REFUSED ("malformed_hello").

const HOST_PV := 1
const HOST_GAME := "0.1.0"


func _hello(pv: int, game: String, player_name: String = "Bob") -> Dictionary:
	return {
		NetProtocol.KEY_HELLO_NAME: player_name,
		NetProtocol.KEY_HELLO_PV: pv,
		NetProtocol.KEY_HELLO_GAME: game,
	}


# --- accept path -------------------------------------------------------------

func test_matching_versions_are_accepted() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(HOST_PV, HOST_GAME), HOST_PV, HOST_GAME)
	assert_true(result["accepted"], "same protocol + same build joins")
	assert_eq(result["reason"], NetProtocol.REJECT_NONE, "an accepted hello carries no reason")
	assert_false(result["build_differs"], "identical game versions are not flagged")
	assert_eq(result["name"], "Bob", "the joiner's name survives validation")


func test_own_hello_is_accepted_by_own_build() -> void:
	# The everyday case: both machines run the same exe, so make_hello must satisfy the gate.
	var result: Dictionary = NetProtocol.validate_hello(NetProtocol.make_hello("Alice"))
	assert_true(result["accepted"], "this build accepts its own hello")
	assert_eq(result["client_pv"], NetProtocol.PROTOCOL_VERSION, "hello stamps the live protocol version")
	assert_false(result["build_differs"], "same build, so no version difference is reported")


func test_blank_name_falls_back_to_player() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(HOST_PV, HOST_GAME, "   "), HOST_PV, HOST_GAME)
	assert_true(result["accepted"], "a nameless joiner is still a legal joiner")
	assert_eq(result["name"], "Player", "blank names become 'Player' rather than an empty roster entry")


# --- protocol mismatch = the rejection this suite is named for ---------------

func test_newer_client_protocol_is_rejected() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(HOST_PV + 1, "0.2.0"), HOST_PV, HOST_GAME)
	assert_false(result["accepted"], "a client on a newer protocol is refused")
	assert_eq(result["reason"], NetProtocol.REJECT_VERSION_MISMATCH, "and says why")


func test_older_client_protocol_is_rejected() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(HOST_PV - 1, "0.0.9"), HOST_PV, HOST_GAME)
	assert_false(result["accepted"], "a client on an older protocol is refused too")
	assert_eq(result["reason"], NetProtocol.REJECT_VERSION_MISMATCH, "same reason in both directions")


func test_rejection_reports_both_sides_versions() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(9, "9.9.9"), HOST_PV, HOST_GAME)
	assert_eq(result["host_pv"], HOST_PV, "host protocol version is reported back")
	assert_eq(result["client_pv"], 9, "client protocol version is reported back")
	assert_eq(result["host_game"], HOST_GAME, "host build string is reported back")
	assert_eq(result["client_game"], "9.9.9", "client build string is reported back")


func test_describe_rejection_names_both_builds() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(9, "9.9.9"), HOST_PV, HOST_GAME)
	var text: String = NetProtocol.describe_rejection(String(result["reason"]), result)
	assert_true(text.contains(HOST_GAME), "the message tells the player the host's build")
	assert_true(text.contains("9.9.9"), "and their own build")


# --- game-version difference is advisory, never fatal ------------------------

func test_different_game_version_still_joins_but_is_flagged() -> void:
	var result: Dictionary = NetProtocol.validate_hello(_hello(HOST_PV, "dev"), HOST_PV, HOST_GAME)
	assert_true(result["accepted"], "an editor run may join an exported host on the same protocol")
	assert_true(result["build_differs"], "but the difference is flagged for desync hunts")


# --- malformed input ---------------------------------------------------------

func test_non_dictionary_hello_is_rejected() -> void:
	assert_eq(NetProtocol.validate_hello("hello", HOST_PV, HOST_GAME)["reason"],
		NetProtocol.REJECT_MALFORMED_HELLO, "a string is not a hello")
	assert_eq(NetProtocol.validate_hello(null, HOST_PV, HOST_GAME)["reason"],
		NetProtocol.REJECT_MALFORMED_HELLO, "null is not a hello")


func test_hello_missing_or_mistyped_fields_is_rejected() -> void:
	assert_false(NetProtocol.validate_hello({"name": "Bob"}, HOST_PV, HOST_GAME)["accepted"],
		"no version fields at all")
	assert_false(NetProtocol.validate_hello({"pv": "1", "game": "0.1.0"}, HOST_PV, HOST_GAME)["accepted"],
		"a string protocol version is not an int")
	assert_false(NetProtocol.validate_hello({"pv": 1}, HOST_PV, HOST_GAME)["accepted"],
		"missing game version")


func test_validate_hello_does_not_mutate_its_input() -> void:
	var hello: Dictionary = _hello(HOST_PV, HOST_GAME)
	var before: int = hello.size()
	NetProtocol.validate_hello(hello, HOST_PV, HOST_GAME)
	assert_eq(hello.size(), before, "the gate is pure -- it never stamps the caller's dictionary")


# --- version string sourcing -------------------------------------------------

func test_local_game_version_is_never_empty() -> void:
	var version: String = NetProtocol.local_game_version()
	assert_ne(version, "", "a build always reports SOME version string")
	var declared: String = String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if declared == "":
		assert_eq(version, NetProtocol.GAME_VERSION_FALLBACK,
			"an unversioned project reports the 'dev' fallback")
	else:
		assert_eq(version, declared, "a versioned project reports application/config/version")
