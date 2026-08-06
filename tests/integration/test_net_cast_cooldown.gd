extends GutTest

## COOLDOWNS AND CHARGES ARE BOOKED ON THE APPLY SEAM, or a networked match has none.
##
## [method CommandApplier._apply_cast_move] performed the cast and consumed the caster's
## action but never called [method MovesetController.on_used], so in a NETWORKED match no
## move's cooldown started and no `max_uses` charge was spent -- on EITHER peer. Every
## cooldown move was spammable and every limited move was unlimited. Solo/hotseat booked
## correctly through [method UnitActionsPanel._execute_move_on_target], which is why this
## only ever showed up in MP (and, silently, in replays -- which apply through the same
## seam and so also never booked, diverging from the live battle they recorded).
##
## What this suite pins:
##   * BOOKING   -- an applied cast starts the cooldown and spends exactly ONE charge.
##   * ONCE      -- the applier is the SINGLE booking point; the local UI's networked branch
##                  returns before its own perform_move/on_used, so a cast can never be
##                  booked twice. Asserted with a sensitivity control so it is not vacuous.
##   * THE MAXI RULE -- a wait a RESOLUTION set for itself (MovesetController.cooldown_started,
##                  the hook Duskmaw's Voidstep charges its long teleport price with) survives
##                  the booking that follows it, because effects run inside perform_move and
##                  on_used starts at maxi(authored, remaining).
##   * LOCKSTEP  -- two peers applying the same command land on the same cooldown state, and
##                  the desync checksum (which hashes cooldown_remaining) agrees.
##   * REPLAY    -- a recorded cast, round-tripped through the replay codec and re-applied,
##                  reproduces the live cooldown state exactly.
##
## Integration rather than unit because the booking reads a REAL [MovesetController] child
## off a REAL [Unit] -- the very hook a mock would paper over.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const RNG_SEED := 0xBEEF01


# --- fixtures ------------------------------------------------------------------


## A move effect that only logs, so a cast can SUCCEED without needing damage, factions or
## a live target. Keeps every assertion below about the accounting and nothing else.
class MarkerEffect extends MoveEffect:
	func apply(ctx: MoveContext) -> void:
		ctx.results.append({ "effect": "marker", "cell": ctx.aim_cell })


## A move effect that charges its OWN wait during resolution, through the public
## [method MovesetController.cooldown_started] hook -- the same call Duskmaw's Voidstep makes
## when a cast STEPS rather than plants. Test-local on purpose: this pins the applier against
## the landed public API, not against any one effect's authoring.
class DynamicWaitEffect extends MoveEffect:
	var turns: int = 4

	func apply(ctx: MoveContext) -> void:
		ctx.results.append({ "effect": "dynamic_wait", "turns": turns })
		if ctx.caster == null or not ctx.caster.has_method("get_moveset_controller"):
			return
		var controller = ctx.caster.get_moveset_controller()
		if controller != null and controller.has_method("cooldown_started"):
			controller.cooldown_started(ctx.move, turns)


## A tile-targeted move carrying [param effect]. TILE rather than ENEMY so resolution needs
## no allegiance query -- the accounting is what is under test, not the targeting.
func _move(effect: MoveEffect, cooldown: int, max_uses: int = -1) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"net_booking_probe"
	m.display_name = "Probe"
	m.cooldown = cooldown
	m.max_uses = max_uses
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.TILE
	p.min_range = 1
	p.max_range = 4
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	m.effects = [effect] as Array[MoveEffect]
	return m


## A LIVE [Unit] whose slot-0 move is [param move]. Needed, not a double: the booking reads
## the real MovesetController child that [method Unit._setup_character_components] mounts.
func _caster(move: MoveResource) -> Unit:
	var c := CharacterResource.new()
	c.character_id = &"net_booking_caster"
	c.display_name = "Probe"
	c.base_health = 60
	c.base_attack = 10
	c.base_speed = 10
	c.base_movement = 4
	c.moveset = [move] as Array[MoveResource]
	var u := Unit.new()
	u.character_resource = c
	add_child_autofree(u)
	return u


## A whole one-caster battle plus the net seam that drives it: board, registry (the caster is
## net_id 1) and applier. Built fresh per peer/run so two of them are genuinely independent.
func _battle(move: MoveResource) -> Dictionary:
	var caster := _caster(move)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(1, 1))
	var reg := CommandApplier.UnitRegistry.new()
	reg.assign_map_units([caster])
	return {
		"caster": caster,
		"board": board,
		"reg": reg,
		"applier": CommandApplier.new(reg, null),
	}


## A resolved CAST_MOVE exactly as the authority stamps one before broadcasting it.
func _cast_cmd(seq: int = 1, aim: Vector2i = Vector2i(2, 1), slot: int = 0) -> Dictionary:
	return NetProtocol.stamp_resolution(
		NetProtocol.make_cast_move(1, slot, aim, 0), seq, RNG_SEED)


func _controller(battle: Dictionary) -> MovesetController:
	return (battle["caster"] as Unit).get_moveset_controller() as MovesetController


func _apply(battle: Dictionary, cmd: Dictionary) -> Dictionary:
	return (battle["applier"] as CommandApplier).apply_command(cmd, battle["board"])


# ===========================================================================
# BOOKING
# ===========================================================================


func test_an_applied_cast_starts_the_moves_cooldown() -> void:
	var move := _move(MarkerEffect.new(), 3)
	var battle := _battle(move)
	var mc := _controller(battle)
	assert_eq(mc.remaining(move), 0, "the move starts ready")

	var res := _apply(battle, _cast_cmd())

	assert_true(bool(res["ok"]), "the cast resolved through the apply seam")
	assert_eq(mc.remaining(move), 3,
		"and the apply seam started its authored 3-turn cooldown -- the whole bug: a networked "
		+ "cast used to leave the move ready, so it could be spammed every turn")
	assert_false(mc.can_use(move), "so the move is refused until the wait runs out")


func test_an_applied_cast_spends_exactly_one_charge() -> void:
	var move := _move(MarkerEffect.new(), 0, 2)
	var battle := _battle(move)
	var mc := _controller(battle)
	assert_eq(mc.uses_left(move), 2, "a max_uses 2 move starts with both charges")

	_apply(battle, _cast_cmd(1))
	assert_eq(mc.uses_left(move), 1, "one applied cast spends exactly one charge")

	_apply(battle, _cast_cmd(2))
	assert_eq(mc.uses_left(move), 0, "the second spends the last one")
	assert_false(mc.can_use(move), "and a limited move out of charges is refused")


func test_a_refused_cast_books_nothing() -> void:
	# CONQUEST.md rule 1: the refusal is a VALUE. Nothing may be spent for a cast the
	# executor rejected -- otherwise an out-of-range aim would cost a charge on both peers.
	var move := _move(MarkerEffect.new(), 3, 2)
	var battle := _battle(move)
	var mc := _controller(battle)

	var res := _apply(battle, _cast_cmd(1, Vector2i(11, 11)))

	assert_false(bool(res["ok"]), "an out-of-range aim is refused")
	assert_eq(mc.remaining(move), 0, "no cooldown was started")
	assert_eq(mc.uses_left(move), 2, "and no charge was spent")


# ===========================================================================
# ONCE -- the applier is the single booking point
# ===========================================================================


func test_a_networked_cast_is_booked_exactly_once() -> void:
	# HOW A NETWORKED CAST ACTUALLY FLOWS: the acting player's UI
	# (UnitActionsPanel._execute_move_on_target) takes its `_is_networked_match()` branch,
	# which submits the intent and RETURNS -- before its own perform_move, before its own
	# on_used. The applier then runs on every peer INCLUDING the submitter. So the sequence
	# below is the complete booking story for a networked cast, and it must decrement the
	# charge count by ONE.
	var move := _move(MarkerEffect.new(), 2, 5)
	var battle := _battle(move)
	var mc := _controller(battle)

	_apply(battle, _cast_cmd(1))   # the one and only booking site

	assert_eq(mc.uses_left(move), 4, "one networked cast spent exactly one charge")

	# SENSITIVITY CONTROL: prove the assertion above can actually see a double booking. A
	# submit-side on_used surviving alongside the apply-side one would land here.
	mc.on_used(move)
	assert_eq(mc.uses_left(move), 3,
		"a SECOND booking would be visible as a second charge spent -- so the count above is "
		+ "a real single-booking assertion, not a vacuous one")


# ===========================================================================
# THE MAXI RULE -- a wait the resolution set for itself survives the booking
# ===========================================================================


func test_a_wait_charged_during_resolution_survives_the_apply_side_booking() -> void:
	# The ordering trap, through the NETWORKED path this time: effects run INSIDE
	# perform_move, so the effect's cooldown_started(4) lands BEFORE on_used. on_used starts
	# the wait at maxi(authored, remaining), so the authored 1 may not stamp the 4 back down.
	# This is Duskmaw's Voidstep's whole cooldown model (short to plant, long to step) and it
	# was the ONLY cooldown that survived a networked cast while apply booked nothing at all.
	var effect := DynamicWaitEffect.new()
	effect.turns = 4
	var move := _move(effect, 1)
	var battle := _battle(move)
	var mc := _controller(battle)

	var res := _apply(battle, _cast_cmd())

	assert_true(bool(res["ok"]), "the cast resolved")
	assert_eq(mc.remaining(move), 4,
		"the 4-turn wait the RESOLUTION charged survives the booking that follows it -- "
		+ "on_used's maxi(authored, remaining) rule holds through the apply seam")
	assert_eq(mc.total(move), 4,
		"and the recharge readout counts down from 4, not from the authored 1")


func test_the_apply_seam_still_books_the_authored_wait_when_the_resolution_charges_less() -> void:
	# The mirror case: a resolution that set a SHORTER wait than the authored one must not
	# shorten the move. maxi runs both ways, and it must run the same way apply-side.
	var effect := DynamicWaitEffect.new()
	effect.turns = 1
	var move := _move(effect, 5)
	var battle := _battle(move)
	var mc := _controller(battle)

	_apply(battle, _cast_cmd())

	assert_eq(mc.remaining(move), 5,
		"the authored 5 wins over the resolution's shorter 1 -- exactly as on the local path")


# ===========================================================================
# LOCKSTEP -- both peers book identically, and the checksum sees it
# ===========================================================================


func test_two_peers_applying_one_cast_reach_the_same_cooldown_state() -> void:
	# Two independent battles = the two peers. Each applies the SAME stamped command through
	# its own applier, exactly as the live seam does (host via call_local, client via RPC).
	var peer_a := _battle(_move(MarkerEffect.new(), 3, 2))
	var peer_b := _battle(_move(MarkerEffect.new(), 3, 2))
	var cmd := _cast_cmd()

	_apply(peer_a, cmd.duplicate(true))
	_apply(peer_b, cmd.duplicate(true))

	var a_move: MoveResource = (peer_a["caster"] as Unit).get_move(0)
	var b_move: MoveResource = (peer_b["caster"] as Unit).get_move(0)
	assert_eq(_controller(peer_a).remaining(a_move), _controller(peer_b).remaining(b_move),
		"both peers booked the same cooldown")
	assert_eq(_controller(peer_a).uses_left(a_move), _controller(peer_b).uses_left(b_move),
		"and both spent the same charge")
	assert_eq(
		(peer_a["applier"] as CommandApplier).hash_match_state(peer_a["board"]),
		(peer_b["applier"] as CommandApplier).hash_match_state(peer_b["board"]),
		"so the desync checksum agrees across the two peers")


func test_the_desync_checksum_is_sensitive_to_the_cooldown_it_now_books() -> void:
	# hash_match_state hashes cooldown_remaining. Before this fix apply booked nothing, so
	# that component was permanently zero in networked play and any path that DID set a
	# cooldown (a resolution's own cooldown_started) was a latent divergence source. Proving
	# the hash moves with the cooldown is what makes the agreement above load-bearing.
	var move := _move(MarkerEffect.new(), 3)
	var battle := _battle(move)
	var applier: CommandApplier = battle["applier"]

	_apply(battle, _cast_cmd())
	var booked := applier.hash_match_state(battle["board"])
	_controller(battle).cooldown_started(move, 0)   # pretend one peer never booked it
	assert_ne(booked, applier.hash_match_state(battle["board"]),
		"a peer missing the cooldown hashes differently -- the checksum would have caught it")


# ===========================================================================
# REPLAY -- playback applies through the same seam, so it books too
# ===========================================================================


func test_a_recorded_cast_replays_to_the_same_cooldown_state() -> void:
	# ReplayDriver steps its log back through CommandApplier, so playback books cooldowns
	# exactly as the live battle did. Driven through the replay CODEC (encode -> decode) so
	# this is the real file round trip a .cqrep makes, not a hand-passed dictionary.
	var live := _battle(_move(MarkerEffect.new(), 3, 2))
	var cmd := _cast_cmd()
	_apply(live, cmd.duplicate(true))

	var recorded: Dictionary = ReplayLog.encode_command(cmd)
	var decoded: Dictionary = ReplayLog.decode_command(recorded)
	assert_false(decoded.is_empty(), "the cast survives the replay codec round trip")

	var playback := _battle(_move(MarkerEffect.new(), 3, 2))
	var res := _apply(playback, decoded)
	assert_true(bool(res["ok"]), "and re-applies during playback")

	var live_move: MoveResource = (live["caster"] as Unit).get_move(0)
	var back_move: MoveResource = (playback["caster"] as Unit).get_move(0)
	assert_eq(_controller(playback).remaining(back_move), _controller(live).remaining(live_move),
		"playback reaches the same cooldown the live cast booked")
	assert_eq(_controller(playback).uses_left(back_move), _controller(live).uses_left(live_move),
		"and the same charge count")
