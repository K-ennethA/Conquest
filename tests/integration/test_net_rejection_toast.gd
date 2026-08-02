extends GutTest

# The battle HUD's answer to a REFUSED command.
#
# A client never mutates the board itself: it submits an intent and the authority decides.
# When the authority says no, [signal NetSession.intent_rejected] is the only trace -- and
# before this overlay existed nothing listened, so the player clicked and the game did
# nothing, with no explanation. [NetToast] closes that loop.
#
# Driven through the REAL NetSession autoload's client-side entry point
# (_rpc_intent_rejected, which only emits -- no socket, nothing to connect, nothing that can
# hang a headless run), so what is proven is the actual wiring the battle uses: session signal
# -> mounted toast -> line on screen. The wording itself is pinned separately, as a pure
# function, in unit/test_net_intent_rejection.gd.
#
# Timing is asserted as CONFIGURATION, never by waiting: tests/README rule 7 forbids
# wall-clock waits, and "does it disappear after 2.5 seconds" is exactly the assertion that
# would cost 2.5 real seconds every run and flake on a loaded machine.


func _mount_toast() -> NetToast:
	var toast := NetToast.new()
	add_child_autofree(toast)
	return toast

## The live NetSession autoload, or null in a harness without it.
func _net() -> Node:
	return get_node_or_null("/root/NetSession")

## Push a rejection through the session exactly as the server's reply does on a client.
func _reject(action: Dictionary, reason: String) -> bool:
	var net := _net()
	if net == null:
		return false
	net._rpc_intent_rejected(action, reason)
	return true


# --- The wiring: a refused command reaches the screen ------------------------

func test_a_refused_command_appears_on_screen():
	var toast := _mount_toast()
	assert_false(toast.is_showing(), "a fresh battle HUD shows no notice")

	if not _reject(NetProtocol.make_cast_move(7, 3, Vector2i(1, 1)), NetProtocol.INTENT_NOT_YOUR_TURN):
		pending("no NetSession autoload in this harness")
		return

	assert_true(toast.is_showing(), "the refusal is surfaced instead of being silent")
	assert_eq(toast.current_text(), "Attack rejected — not your turn",
		"and it says which command was refused and why")


func test_the_shown_line_is_announced_for_listeners():
	var toast := _mount_toast()
	# Array, not an int counter: a lambda captures locals BY VALUE, so `count += 1` would bump
	# a private copy and this assertion would always read 0.
	var shown: Array = []
	toast.toast_shown.connect(func(text): shown.append(text))

	if not _reject(NetProtocol.make_move_unit(3, Vector2i(4, 4)), NetProtocol.INTENT_REJECTED_BY_GAME):
		pending("no NetSession autoload in this harness")
		return

	assert_eq(shown.size(), 1, "one rejection puts up exactly one toast")
	assert_eq(String(shown[0]), "Move rejected — the rules do not allow it",
		"and announces the exact line it displayed")


func test_a_second_rejection_replaces_the_first():
	# A rejection is about what the player JUST did, so the newest one must win outright --
	# queueing would leave a stale line explaining a command from several clicks ago.
	var toast := _mount_toast()
	if not _reject(NetProtocol.make_wait_unit(1), NetProtocol.INTENT_NOT_YOUR_TURN):
		pending("no NetSession autoload in this harness")
		return
	_reject(NetProtocol.make_end_turn(0), NetProtocol.INTENT_REJECTED_BY_GAME)

	assert_eq(toast.current_text(), "End turn rejected — the rules do not allow it",
		"the newest refusal is what the player sees")


func test_an_unmounted_toast_is_not_driven_by_the_session():
	# The overlay unhooks in _exit_tree: the session autoload outlives one battle, and a freed
	# HUD must never be called on the next one.
	var net := _net()
	if net == null:
		pending("no NetSession autoload in this harness")
		return
	var toast := NetToast.new()
	add_child(toast)
	await get_tree().process_frame
	remove_child(toast)
	toast.free()

	# The assertion IS that this does not error: an intent_rejected raised after the HUD is
	# gone must reach no stale listener (GUT fails the test on any engine error).
	net._rpc_intent_rejected(NetProtocol.make_wait_unit(1), NetProtocol.INTENT_NOT_YOUR_TURN)
	assert_true(true, "the session raises rejections harmlessly once the battle HUD is gone")


# --- Behaviour of the notice itself ------------------------------------------

func test_dismiss_takes_the_notice_off_screen():
	var toast := _mount_toast()
	toast.show_notice("Move rejected — not your turn")
	assert_true(toast.is_showing(), "the notice is up")

	toast.dismiss()

	assert_false(toast.is_showing(), "dismiss clears it immediately")
	assert_eq(toast.current_text(), "", "and it reports nothing on screen")


func test_an_empty_notice_is_never_shown():
	var toast := _mount_toast()
	toast.show_notice("   ")
	assert_false(toast.is_showing(), "a blank line is not worth a banner")


func test_it_auto_dismisses_in_about_two_and_a_half_seconds():
	# Asserted as configuration rather than by waiting (tests/README rule 7). The visible life
	# of a toast is fade-in + hold + fade-out.
	var total: float = NetToast.FADE_IN + NetToast.HOLD + NetToast.FADE_OUT
	assert_between(total, 2.0, 3.0,
		"a rejection notice lives about 2.5s -- long enough to read, short enough not to nag")
	assert_gt(NetToast.MIN_HOLD, 1.0,
		"and a fast Battle Speed can never scale the hold below a readable floor")


func test_the_notice_never_blocks_the_board():
	# It is information, not a decision: clicks must pass straight through to the board.
	var toast := _mount_toast()
	toast.show_notice("Move rejected — not your turn")
	var root: Control = toast.get_node("ToastRoot")
	assert_eq(root.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the toast is click-through, so it can never eat a board click")
	assert_eq(toast.layer, NetToast.OVERLAY_LAYER,
		"it draws on its own layer, above the action banner and below the cinematics")
	assert_gt(NetToast.OVERLAY_LAYER, ActionAnnouncer.OVERLAY_LAYER,
		"a rejection is never buried under a move announcement")
	assert_lt(NetToast.OVERLAY_LAYER, UltimateCutIn.OVERLAY_LAYER,
		"but a cut-in still owns the screen while it sweeps")
