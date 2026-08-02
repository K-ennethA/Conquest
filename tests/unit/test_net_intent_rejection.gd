extends GutTest

# The PLAYER-FACING wording for a command the server refused.
#
# When the authority rejects an intent the client's command simply never happens. Until the
# battle HUD grew a toast for it that was completely silent -- the player clicked, nothing
# moved, and nothing said why. NetProtocol.describe_intent_rejection is the ONE place that
# turns the wire reason into a line, and it is pure: no autoloads, no tree, no session. That
# is what makes it testable here and what keeps NetToast a thin renderer.
#
# Also pinned: the wire strings themselves. They are protocol, so a rename is a protocol
# change -- these assertions are the tripwire.


# --- The wire vocabulary is stable -------------------------------------------

func test_the_rejection_reasons_are_the_wire_strings():
	# These travel between machines. Changing one silently would leave a client on an older
	# build unable to explain a rejection it still receives.
	assert_eq(NetProtocol.INTENT_OK, "", "an empty reason means ACCEPTED everywhere in this API")
	assert_eq(NetProtocol.INTENT_MALFORMED, "malformed", "the malformed-command reason")
	assert_eq(NetProtocol.INTENT_UNKNOWN_ACTOR, "unknown_actor", "the no-such-actor reason")
	assert_eq(NetProtocol.INTENT_NOT_YOUR_TURN, "not_your_turn", "the turn-ownership reason")
	assert_eq(NetProtocol.INTENT_REJECTED_BY_GAME, "rejected_by_game", "the game-rules reason")


# --- The command half of the line --------------------------------------------

func test_each_command_names_itself():
	assert_eq(NetProtocol.describe_action(NetProtocol.make_move_unit(1, Vector2i.ZERO)), "Move",
		"a reposition reads as a Move")
	assert_eq(NetProtocol.describe_action(NetProtocol.make_cast_move(1, 0, Vector2i.ZERO)), "Attack",
		"a cast reads as an Attack -- 'cast' is not the word the HUD uses anywhere else")
	assert_eq(NetProtocol.describe_action(NetProtocol.make_wait_unit(1)), "Wait",
		"waiting names itself")
	assert_eq(NetProtocol.describe_action(NetProtocol.make_end_turn(0)), "End turn",
		"ending the turn names itself")


func test_an_unnameable_action_degrades_to_a_generic_label():
	assert_eq(NetProtocol.describe_action(null), "Command",
		"no action at all still produces a printable label")
	assert_eq(NetProtocol.describe_action({}), "Command",
		"a payload with no type is generic, never a crash")
	assert_eq(NetProtocol.describe_action("not a dictionary"), "Command",
		"an off-the-wire value of the wrong TYPE is generic too")


# --- The whole line ----------------------------------------------------------

func test_out_of_turn_reads_as_the_thing_the_player_did():
	var line := NetProtocol.describe_intent_rejection(
		NetProtocol.INTENT_NOT_YOUR_TURN, NetProtocol.make_move_unit(4, Vector2i(2, 2)))
	assert_eq(line, "Move rejected — not your turn",
		"the toast names WHAT was refused and WHY, in the player's words")


func test_every_known_reason_has_plain_wording():
	# No reason may leak its wire string (an underscore) into the player's face.
	for reason in [NetProtocol.INTENT_MALFORMED, NetProtocol.INTENT_UNKNOWN_ACTOR,
			NetProtocol.INTENT_NOT_YOUR_TURN, NetProtocol.INTENT_REJECTED_BY_GAME]:
		var line: String = NetProtocol.describe_intent_rejection(reason, NetProtocol.make_wait_unit(1))
		assert_true(line.begins_with("Wait rejected — "),
			"'%s' produces the standard '<command> rejected — <why>' shape" % reason)
		assert_false(line.contains("_"),
			"'%s' is rendered as words, never as its wire string" % reason)


func test_an_unknown_reason_is_shown_rather_than_swallowed():
	# A newer host may reject for a reason this build has never heard of. Showing the raw
	# (de-underscored) reason is strictly better than a command vanishing in silence.
	var line := NetProtocol.describe_intent_rejection("unit_is_stunned", null)
	assert_eq(line, "Command rejected — unit is stunned",
		"an unrecognised reason is still surfaced, tidied into words")


func test_an_empty_reason_still_produces_a_line():
	var line := NetProtocol.describe_intent_rejection("", NetProtocol.make_end_turn(0))
	assert_eq(line, "End turn rejected — refused by the host",
		"a reasonless rejection still tells the player their command did not happen")
