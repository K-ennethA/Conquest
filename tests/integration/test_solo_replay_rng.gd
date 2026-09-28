extends GutTest

## A SOLO battle's replay re-rolls exactly the dice the battle rolled.
##
## A replay is not video: playback re-applies the recorded commands through the command seam
## ([CommandApplier] -> [NetGameRules]), which draws every roll from a generator derived from
## the command's stamped seed (or the recorded solo stream). So the LIVE solo battle must have
## drawn from that same generator, or every hit / miss / crit with a chance strictly between 0
## and 100 is re-decided on playback and the replay shows a battle that never happened (and
## trips its own checksum at the first turn end).
##
## This records a real solo exchange through BOTH local command paths -- the player's cast
## through the mounted [UnitActionsPanel], and the AI's through [BotTurnDriver] -- with a strike
## tuned so each swing is a genuine coin flip to hit and to crit, then plays the log back
## through the [ReplayDriver] on a fresh copy of the same board, and asserts the two battles are
## the same battle: HP after every command, no checksum divergence, identical final state.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const DUELIST_ID: StringName = &"test_rng_duelist"
## The strike's slot in the duelist's moveset.
const STRIKE_SLOT: int = 0
## Player casts + AI casts recorded (one of each per round).
const ROUNDS: int = 5

const HERO_CELL := Vector3i(1, 1, 0)
const FOE_CELL := Vector3i(2, 1, 0)

## Untyped on purpose (tests/README rule 3).
var _guard

var _map_root: Node3D = null
var _layout: Control = null
var _recorder: ReplayRecorder = null
var _prev_match_rng = null
var _prev_recording: bool = true


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	_guard = Guard.new()
	_guard.set_setting("auto_end_turn", true)
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_guard.set_setting("ai_difficulty", BotController.Difficulty.NORMAL)
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = true
	var ns = get_node_or_null("/root/NetSession")
	_prev_match_rng = ns.get("match_rng") if ns != null else null
	CharacterLibrary._cache[DUELIST_ID] = _make_duelist()


func after_each() -> void:
	_free_record_side()
	TurnSystemManager.active_turn_system = null
	CombatServices.clear()
	CombatServices.match_rng = null
	var ns = get_node_or_null("/root/NetSession")
	if ns != null:
		ns.set("match_rng", _prev_match_rng)
	ReplayPlayback.end_playback()
	ReplayRecorder.recording_enabled = _prev_recording
	_guard.restore()
	CharacterLibrary.clear_cache()


func _free_record_side() -> void:
	for node in [_recorder, _layout, _map_root]:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_recorder = null
	_layout = null
	_map_root = null


# --- Fixture ------------------------------------------------------------------

## A sturdy melee duelist whose strike is a coin flip: ~55% to hit (less the target's
## evasion) and 50% to crit, so a re-rolled swing differs from the recorded one about half the
## time. HP is deep enough that nobody dies inside the exchange.
func _make_duelist() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = DUELIST_ID
	c.display_name = "Duelist"
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 900
	c.base_attack = 30
	c.base_defense = 5
	c.base_magic = 4
	c.base_magic_defense = 5
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 1
	c.moveset = [_coin_flip_strike()] as Array[MoveResource]
	return c


func _coin_flip_strike() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_coin_flip_strike"
	m.display_name = "Coin-Flip Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = 0.55
	m.crit_chance = 0.5
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 12
	d.scaling_stat = "attack"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


func _cell_to_world(cell: Vector3i) -> Vector3:
	return BoardAdapter.new(CombatServices.GRID, []).cell_to_world(cell)


func _spawn(root: Node3D, cell: Vector3i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(DUELIST_ID)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character
	unit.position = _cell_to_world(cell)
	root.add_child(unit)
	owner.add_unit(unit)
	return unit


## The same two-unit battle, built fresh: the human's duelist faces the AI's across one cell,
## both named the way the battle names them, the human to move. {} when it cannot be built.
func _build_battle() -> Dictionary:
	var root := Node3D.new()
	root.name = "Map"
	add_child(root)

	var human := Player.new(0, "Human")
	var ai := Player.new(1, "AI")
	ai.is_ai = true
	var hero := _spawn(root, HERO_CELL, human)
	var foe := _spawn(root, FOE_CELL, ai)
	if hero == null or foe == null:
		return { "root": root }

	await get_tree().process_frame
	CombatServices.rebuild(root)
	var board = CombatServices.board()
	if board == null:
		return { "root": root }
	NetUnitIds.assign(board, true)

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(human)
	ts.register_player(ai)
	ts.start_turn_system()
	TurnSystemManager.active_turn_system = ts
	return {
		"root": root, "board": board, "ts": ts,
		"human": human, "ai": ai, "hero": hero, "foe": foe,
	}


func _settle() -> void:
	for _i in range(3):
		await get_tree().process_frame


func _hp_pair(battle: Dictionary) -> Array:
	return [int(battle["hero"].get_hp()), int(battle["foe"].get_hp())]


# --- The test -----------------------------------------------------------------

func test_a_recorded_solo_exchange_replays_the_same_rolls() -> void:
	var ns = get_node_or_null("/root/NetSession")
	if ns == null or not ns.has_method("begin_solo_match_rng"):
		pending("no NetSession autoload in this harness")
		return

	# ---- RECORD: a real solo battle, player via the panel, AI via the driver ----------------
	var live: Dictionary = await _build_battle()
	_map_root = live["root"]
	if not live.has("board"):
		pending("could not build the duel board (roster/board unavailable)")
		return

	ns.begin_solo_match_rng()
	var match_seed: int = int(ns.get("match_rng").match_seed)

	_recorder = ReplayRecorder.new()
	_recorder.auto_save = false
	add_child(_recorder)
	_recorder.begin({
		"rng": { "match_seed": match_seed },
		"unit_ids": ReplayLog.UNIT_IDS_SLOT,
	})

	_layout = LAYOUT.instantiate()
	add_child(_layout)
	var panel = _layout.unit_actions_panel
	var bot := BotTurnDriver.new()
	add_child_autofree(bot)
	if bot._timer != null:
		bot._timer.stop()
	await _settle()

	var ts: TurnSystemBase = live["ts"]
	var hero: Unit = live["hero"]
	var recorded_trace: Array = []
	for _round in range(ROUNDS):
		assert_eq(ts.get_current_active_player(), live["human"], "the human is up")
		# THE PLAYER PATH: select, pick the strike, click the foe -- exactly the player's input.
		panel._on_unit_selected(hero, hero.global_position)
		await get_tree().process_frame
		panel._on_move_selected(STRIKE_SLOT)
		panel.handle_move_target_selected(Cells.to_grid(FOE_CELL))
		await _settle()
		recorded_trace.append(_hp_pair(live))

		assert_eq(ts.get_current_active_player(), live["ai"],
			"the human's only unit acted, so the turn auto-ended to the AI")
		# THE AI PATH: the driver resolves the foe's turn (it strikes back where it stands).
		var guard: int = 0
		while ts.get_current_active_player() == live["ai"] and guard < 4:
			assert_true(await bot.act_for_turn_system(ts), "the AI acted on its turn")
			await _settle()
			guard += 1
		recorded_trace.append(_hp_pair(live))

	var log: Dictionary = _recorder.log.duplicate(true)
	var final_live_hash: String = ReplayLog.state_checksum(ReplayRecorder.board_state_rows())
	var casts: int = 0
	for entry in (log.get("entries", []) as Array):
		if int((entry["cmd"] as Dictionary).get(NetProtocol.KEY_TYPE, -1)) == NetProtocol.Action.CAST_MOVE:
			casts += 1
	assert_eq(casts, ROUNDS * 2, "every player and AI cast was recorded")
	assert_gt((log.get("checksums", []) as Array).size(), 0, "turn-end checksums were stamped")
	gut.p("recorded hp trace: %s" % [recorded_trace])

	# The whole exchange must actually have rolled: a trace where every swing landed the
	# same way would prove nothing about the dice.
	var distinct_deltas: Dictionary = {}
	var prev: Array = [900, 900]
	for pair in recorded_trace:
		distinct_deltas[(prev[0] - pair[0]) + (prev[1] - pair[1])] = true
		prev = pair
	assert_gt(distinct_deltas.size(), 1,
		"the coin-flip strike produced more than one outcome over the exchange")

	# Tear the recorded battle down completely before the playback board goes up.
	_free_record_side()
	TurnSystemManager.active_turn_system = null
	CombatServices.clear()
	CombatServices.match_rng = null

	# ---- PLAY BACK: a fresh copy of the same board, the recorded log, the replay driver ----
	var replay: Dictionary = await _build_battle()
	_map_root = replay["root"]
	if not replay.has("board"):
		pending("could not rebuild the duel board for playback")
		return
	var stream := MatchRng.new()
	stream.begin_from_seed(match_seed)
	var applier := CommandApplier.new(null, stream)

	var driver := ReplayDriver.new()
	driver.process_mode = Node.PROCESS_MODE_DISABLED
	driver.applier = applier
	driver.board_provider = func(): return CombatServices.board()
	driver.animation_gate = func(): return false
	add_child_autofree(driver)
	driver.setup(ReplayLog.validate(log))

	# One trace sample per CAST, which is what the recording sampled (one cast per phase; a
	# MOVE the AI might interleave would not change HP and is not sampled).
	var replayed_trace: Array = []
	for _i in range(64):
		var res: Dictionary = driver.step_one()
		if not bool(res.get("stepped", false)):
			break
		assert_true(bool(res.get("applied", false)),
			"recorded command %d applied on the replay board (%s)" % [_i, res.get("reason", "")])
		await _settle()
		if int(res.get("type", -1)) == NetProtocol.Action.CAST_MOVE:
			replayed_trace.append(_hp_pair(replay))
	gut.p("replayed hp trace: %s" % [replayed_trace])

	assert_eq(replayed_trace, recorded_trace,
		"every recorded hit, miss and crit re-rolls identically on playback")
	assert_false(driver.is_diverged(),
		"no turn-end checksum diverged during playback")
	assert_eq(ReplayLog.state_checksum(ReplayRecorder.board_state_rows()), final_live_hash,
		"and the replayed board ends in exactly the recorded state")
