extends GutTest

## The two PURE halves of the pre-battle VS clash intro ([VersusIntro]):
##
##   1. WHO GETS ONE -- the eligibility gate, every mode x networked x replay combination.
##   2. WHAT IT SAYS -- the card assembler, including the two rules the whole feature turns on:
##      a rank chip is only ever shown where a REAL profile backs it, and missing cosmetic data
##      degrades the card instead of blocking the match.
##
## Both are `static` and side-effect free, so this suite needs no scene, no autoload and no
## socket. The RENDERED half (a mounted intro's actual Labels) is pinned separately, against
## the real booted battle, in integration/test_versus_intro_boot.gd.

const Intro := preload("res://game/ui/screens/VersusIntro.gd")


# =====================================================================================
#  1. ELIGIBILITY
# =====================================================================================

## A context with everything switched off. Each test flips only what it is about, so a new
## suppression key added later defaults to "not suppressing" and cannot silently pass.
func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"replay": false,
		"resumed": false,
		"arena": false,
		"challenge": false,
		"campaign": false,
		"king_of_hill": false,
		"networked": false,
		"game_mode": Intro.MODE_VERSUS,
		"opponent_is_ai": false,
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


func test_the_mode_constant_still_matches_the_real_enum() -> void:
	# MODE_VERSUS is spelled as a literal in VersusIntro (a const cannot read an autoload's
	# enum). If GameSettings ever reorders GameMode, this is what catches it -- otherwise the
	# gate would silently start scoring the wrong mode.
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	assert_eq(Intro.MODE_VERSUS, int(GameSettings.GameMode.VERSUS),
		"the intro's mode discriminator is GameSettings.GameMode.VERSUS")


# --- The two modes that DO show -----------------------------------------------

func test_a_local_hotseat_versus_match_shows_the_intro() -> void:
	assert_true(Intro.should_show(_ctx()),
		"two humans on one box starting a versus match is exactly what the reveal is for")


func test_a_networked_versus_match_shows_the_intro() -> void:
	assert_true(Intro.should_show(_ctx({"networked": true})),
		"a live networked match shows it -- each machine plays its own copy")


func test_a_networked_match_shows_it_whatever_the_menu_mode_says() -> void:
	# NetSession is the authority on "this is a live match against another person"; the menu's
	# game_mode is only consulted for LOCAL play.
	assert_true(Intro.should_show(_ctx({"networked": true, "game_mode": 0})),
		"a live networked match is a versus match even if GameSettings still says otherwise")


# --- Everything that does NOT -------------------------------------------------

func test_solo_skirmish_never_shows_the_intro() -> void:
	assert_false(Intro.should_show(_ctx({"game_mode": 0})),
		"single player versus the AI gets no two-player clash card")


func test_a_local_versus_match_against_a_bot_never_shows_it() -> void:
	# The suppression that covers king-of-the-hill-vs-AI and anything else launched through the
	# versus mode with a bot in the other seat: there is no second player to introduce.
	assert_false(Intro.should_show(_ctx({"opponent_is_ai": true})),
		"a bot opponent is not a versus intro, whatever mode booted the battle")


func test_a_bot_opponent_does_not_suppress_a_networked_match() -> void:
	# A neutral camp or a bot-flagged slot in a live networked match must not cost the two
	# humans their reveal -- the networked branch is decided before the AI check.
	assert_true(Intro.should_show(_ctx({"networked": true, "opponent_is_ai": true})),
		"a live networked match still shows it even with an AI-flagged third party on the board")


func test_every_mode_controller_suppresses_it() -> void:
	for key in ["arena", "challenge", "campaign", "king_of_hill"]:
		assert_false(Intro.should_show(_ctx({key: true})),
			"%s owns its own battle framing -- no versus intro" % key)
		assert_false(Intro.should_show(_ctx({key: true, "networked": true})),
			"%s suppresses it even in a networked match" % key)


func test_replay_playback_never_shows_it() -> void:
	assert_false(Intro.should_show(_ctx({"replay": true})),
		"watching a recording is not a match starting")
	assert_false(Intro.should_show(_ctx({"replay": true, "networked": true})),
		"and a recording of a networked match is still a recording")


func test_a_resumed_mid_battle_save_never_shows_it() -> void:
	assert_false(Intro.should_show(_ctx({"resumed": true})),
		"a restored save resumes a battle already in progress -- there is nothing to introduce")


func test_an_empty_context_shows_nothing() -> void:
	# Every key defaults to "no", and with no game_mode the local branch cannot qualify. This is
	# what a bare harness (or a future caller that forgets a key) scores.
	assert_false(Intro.should_show({}),
		"an unknown context never mounts the overlay")


## The complete matrix, spelled out, so a change to the gate has to face every combination at
## once rather than the handful a targeted test happens to cover.
func test_the_full_eligibility_matrix() -> void:
	var rows: Array = [
		# [suppressor, networked, game_mode, opponent_is_ai, expected]
		["", false, Intro.MODE_VERSUS, false, true],   # local hotseat versus
		["", true, Intro.MODE_VERSUS, false, true],    # networked versus
		["", true, 0, false, true],                    # networked, menu says solo
		["", false, 0, false, false],                  # solo skirmish vs AI
		["", false, 2, false, false],                  # MULTIPLAYER enum but no live session
		["", false, Intro.MODE_VERSUS, true, false],   # local versus vs a bot (KOTH vs AI)
		["arena", false, Intro.MODE_VERSUS, false, false],
		["arena", true, Intro.MODE_VERSUS, false, false],
		["challenge", false, Intro.MODE_VERSUS, false, false],
		["challenge", true, Intro.MODE_VERSUS, false, false],
		["campaign", false, Intro.MODE_VERSUS, false, false],
		["campaign", true, Intro.MODE_VERSUS, false, false],
		["king_of_hill", false, Intro.MODE_VERSUS, false, false],
		["king_of_hill", true, Intro.MODE_VERSUS, false, false],
		["replay", false, Intro.MODE_VERSUS, false, false],
		["replay", true, Intro.MODE_VERSUS, false, false],
		["resumed", false, Intro.MODE_VERSUS, false, false],
		["resumed", true, Intro.MODE_VERSUS, false, false],
	]
	for row in rows:
		var overrides: Dictionary = {
			"networked": bool(row[1]),
			"game_mode": int(row[2]),
			"opponent_is_ai": bool(row[3]),
		}
		if not String(row[0]).is_empty():
			overrides[String(row[0])] = true
		assert_eq(Intro.should_show(_ctx(overrides)), bool(row[4]),
			"gate(%s, networked=%s, mode=%s, ai=%s)" % [row[0], row[1], row[2], row[3]])


# =====================================================================================
#  2. CARD ASSEMBLY
# =====================================================================================

func _networked_sources(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"networked": true,
		"local_name": "Ardent",
		"local_rank": "Veteran",
		"local_points": 1800,
		"local_character_id": "vineweave",
		"peer_card": { "name": "Ivy", "rank_name": "Knight", "lifetime_points": 4200 },
		"roster_name": "",
		"opponent_name": "",
		"opponent_character_id": "blightcap",
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


# --- The networked case -------------------------------------------------------

func test_a_networked_match_reads_the_opponents_announced_card() -> void:
	var cards: Dictionary = Intro.assemble_cards(_networked_sources())
	var opponent: Dictionary = cards["opponent"]

	assert_eq(String(opponent["name"]), "Ivy", "the opponent is named from their own card")
	assert_eq(String(opponent["rank_name"]), "Knight", "and carries the rank they announced")
	assert_true(bool(opponent["show_points"]), "and their lifetime points line is shown")
	assert_eq(int(opponent["lifetime_points"]), 4200, "with the figure they announced")


func test_the_local_side_always_comes_from_the_local_profile() -> void:
	var cards: Dictionary = Intro.assemble_cards(_networked_sources())
	var local: Dictionary = cards["local"]

	assert_eq(String(local["name"]), "Ardent", "the left card is this machine's player")
	assert_eq(String(local["rank_name"]), "Veteran",
		"whose rank comes from the local profile, never from the wire")
	assert_true(bool(local["show_points"]), "and whose lifetime points are always shown")
	assert_eq(int(local["lifetime_points"]), 1800, "read straight off the profile")


func test_a_missing_peer_card_degrades_to_name_only() -> void:
	# An older peer that predates the profile_info exchange, or a lobby message that never
	# arrived. Cosmetic data must never block the match.
	var cards: Dictionary = Intro.assemble_cards(
		_networked_sources({"peer_card": {}, "roster_name": "Ivy"}))
	var opponent: Dictionary = cards["opponent"]

	assert_eq(String(opponent["name"]), "Ivy",
		"the server-owned roster name still names them")
	assert_eq(String(opponent["rank_name"]), "",
		"but no rank is invented for a peer that never announced one")
	assert_false(bool(opponent["show_points"]),
		"and no points line, rather than a confident zero")


func test_a_peer_with_neither_card_nor_roster_name_still_gets_a_card() -> void:
	var cards: Dictionary = Intro.assemble_cards(
		_networked_sources({"peer_card": {}, "roster_name": ""}))

	assert_eq(String((cards["opponent"] as Dictionary)["name"]), MatchPeerInfo.DEFAULT_NAME,
		"the placeholder name is used rather than a blank card -- the intro still plays")


func test_a_card_without_a_points_field_shows_no_points_line() -> void:
	# MatchPeerInfo always normalises the field in, but a future/degraded source might not, and
	# an absent figure must not render as "0 lifetime pts".
	var cards: Dictionary = Intro.assemble_cards(
		_networked_sources({"peer_card": {"name": "Ivy", "rank_name": "Knight"}}))
	var opponent: Dictionary = cards["opponent"]

	assert_eq(String(opponent["rank_name"]), "Knight", "the announced rank still shows")
	assert_false(bool(opponent["show_points"]), "but an absent points figure shows nothing")


func test_a_blank_announced_rank_means_no_chip() -> void:
	var cards: Dictionary = Intro.assemble_cards(
		_networked_sources({"peer_card": {"name": "Ivy", "rank_name": "   ", "lifetime_points": 10}}))

	assert_eq(String((cards["opponent"] as Dictionary)["rank_name"]), "",
		"whitespace is not a rank -- the chip is omitted rather than rendered empty")


# --- The hotseat case ---------------------------------------------------------

func _hotseat_sources(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"networked": false,
		"local_name": "Player 1",
		"local_rank": "Recruit",
		"local_points": 120,
		"local_character_id": "vineweave",
		"opponent_name": "Player 2",
		"opponent_character_id": "blightcap",
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


func test_a_hotseat_guest_never_gets_a_rank_chip() -> void:
	# THE rule this feature turns on. There is exactly one profile on this machine; borrowing
	# its rank for whoever is sitting in the second seat would be a lie about who they are.
	var cards: Dictionary = Intro.assemble_cards(_hotseat_sources())
	var opponent: Dictionary = cards["opponent"]

	assert_eq(String(opponent["name"]), "Player 2", "the guest is named")
	assert_eq(String(opponent["rank_name"]), "",
		"but carries NO rank -- no profile on this box backs one")
	assert_false(bool(opponent["show_points"]),
		"and no lifetime points either, for the same reason")


func test_a_hotseat_guest_gets_no_rank_even_when_one_is_offered() -> void:
	# Belt to the braces above: a caller that puts a peer card in the sources for a LOCAL match
	# (a stale card left by a previous networked match, say) must not leak it onto the guest.
	var cards: Dictionary = Intro.assemble_cards(_hotseat_sources({
		"peer_card": { "name": "Ivy", "rank_name": "Mythic", "lifetime_points": 99999 },
		"roster_name": "Ivy",
	}))
	var opponent: Dictionary = cards["opponent"]

	assert_eq(String(opponent["name"]), "Player 2",
		"a local match names the guest from local context, never from a peer card")
	assert_eq(String(opponent["rank_name"]), "", "and still shows no rank chip")
	assert_false(bool(opponent["show_points"]), "and still shows no points")


func test_the_local_player_keeps_their_real_rank_in_a_hotseat_match() -> void:
	var local: Dictionary = Intro.assemble_cards(_hotseat_sources())["local"]

	assert_eq(String(local["rank_name"]), "Recruit",
		"the machine's owner has a real profile, so their chip is real data")
	assert_true(bool(local["show_points"]), "and their points line is shown")


# --- Defaults / coercion -------------------------------------------------------

func test_nameless_sources_fall_back_to_the_slot_labels() -> void:
	var cards: Dictionary = Intro.assemble_cards({})

	assert_eq(String((cards["local"] as Dictionary)["name"]), "Player 1",
		"an unnamed local side is still labelled")
	assert_eq(String((cards["opponent"] as Dictionary)["name"]), "Player 2",
		"and so is an unnamed local opponent")
	assert_eq(String((cards["local"] as Dictionary)["rank_name"]), "",
		"with no profile behind it, even the local card shows no chip")


func test_a_negative_points_figure_can_never_render() -> void:
	var cards: Dictionary = Intro.assemble_cards({"local_points": -50})
	assert_eq(int((cards["local"] as Dictionary)["lifetime_points"]), 0,
		"points are clamped at zero -- a corrupt profile reads as none, never as a negative")


func test_the_portrait_character_rides_each_card() -> void:
	var cards: Dictionary = Intro.assemble_cards(_networked_sources())
	assert_eq(String((cards["local"] as Dictionary)["character_id"]), "vineweave",
		"the local card fronts our first squad character")
	assert_eq(String((cards["opponent"] as Dictionary)["character_id"]), "blightcap",
		"and the opponent card fronts theirs")


func test_a_junk_peer_card_does_not_break_assembly() -> void:
	# peer_card originates as untrusted peer input. MatchPeerInfo normalises it, but this
	# assembler is handed the result and must fail closed on anything that slips through.
	var cards: Dictionary = Intro.assemble_cards(
		_networked_sources({"peer_card": "not a dictionary", "roster_name": "Ivy"}))

	assert_eq(String((cards["opponent"] as Dictionary)["name"]), "Ivy",
		"a non-Dictionary card is treated as no card at all, and the roster name answers")
