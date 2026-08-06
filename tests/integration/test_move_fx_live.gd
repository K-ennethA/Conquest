extends GutTest

## The default move-FX layer ON A REAL BOARD ([MoveFXDispatcher]).
##
## Nothing here is driven by hand: real character-backed [Unit]s stand on the real
## [CombatServices] board, a real [method Unit.perform_move] resolves through the real
## [MoveExecutor], and the dispatcher is mounted and hears the same [GameEvents] signals it
## hears in a battle. What is asserted is what the PLAYER would see -- how many cells lit
## up, where, in what colour, and that the board drains itself again afterwards.
##
## The maw case is driven through the production path too: a real [DelayedBurstHazard]
## armed on a real [DelayedBurstStatus], expired exactly as the turn-start tick expires it,
## which is what emits `hazard_advanced` with the blast cells.
##
## Harness shape (live map root + synthetic characters injected into [CharacterLibrary])
## follows `tests/integration/test_ai_live_board.gd`; the pure derivation/override maths
## lives in `tests/unit/test_move_fx_dispatcher.gd`.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const DISPATCHER := preload("res://game/visuals/MoveFXDispatcher.gd")
const MOVE_FX := preload("res://game/visuals/MoveFXResource.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const CASTER_ID: StringName = &"test_fx_caster"
const TARGET_ID: StringName = &"test_fx_target"

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

var _map_root: Node3D
var _fx: Node3D


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never the setter (which persists to user://settings.cfg).
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	CombatServices.clear()
	_map_root = null
	_fx = null
	_install_test_characters()


func after_each() -> void:
	if _fx != null and is_instance_valid(_fx):
		_fx.clear_effects()
	CombatServices.clear()
	_map_root = null
	CharacterLibrary.clear_cache()
	_guard.restore()


# --- Fixture ------------------------------------------------------------------

func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


func _install_test_characters() -> void:
	CharacterLibrary._cache[CASTER_ID] = _make_character(CASTER_ID, "FX Caster", 120, 30, _blast())
	CharacterLibrary._cache[TARGET_ID] = _make_character(TARGET_ID, "FX Target", 400, 10, _blast())


func _make_character(id: StringName, display: String, hp: int, atk: int,
		move: MoveResource) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = display
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = hp
	c.base_attack = atk
	c.base_defense = 4
	c.base_magic = 10
	c.base_magic_defense = 4
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 3
	c.moveset = [move] as Array[MoveResource]
	return c


## A 3x3 ember blast with reach 3 and an accuracy that overshoots any evasion, so the hit
## ALWAYS lands and the FX assertions never ride on a roll. Non-lethal against the fat
## target above, so the struck unit survives the frame the assertions run in.
func _blast() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_fx_blast"
	m.display_name = "Test Blast"
	m.element = &"ember"
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.accuracy = 5.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 3
	p.area_shape = CombatTypes.AreaShape.SQUARE
	p.area_size = 1
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 12
	d.scaling_stat = "magic"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.MAGICAL
	m.effects = [d]
	return m


func _spawn(character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character  # before add_child: _ready() builds stats from it
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## A live two-unit board with the FX layer mounted over it. Returns {} when the synthetic
## characters cannot be built, which callers treat as "skip".
func _build_battle() -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var side_a := Player.new(0, "A")
	var side_b := Player.new(1, "B")
	# Three cells apart on the Manhattan diagonal the blast's max_range (3) exactly reaches,
	# so a cast aimed at the target is legal and its 3x3 never covers the caster's own cell.
	var caster := _spawn(CASTER_ID, Vector2i(0, 0), side_a)
	var target := _spawn(TARGET_ID, Vector2i(2, 1), side_b)
	if caster == null or target == null:
		return {}

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)

	_fx = add_child_autofree(DISPATCHER.new())
	return {
		"caster": caster,
		"target": target,
		"board": CombatServices.board(),
	}


## Poll [param predicate] for at most [param max_frames] frames. The idiom from
## `tests/integration/test_mp_loopback.gd` -- bounded in FRAMES, never in wall clock.
func _await_until(predicate: Callable, max_frames: int) -> bool:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _impact_cells() -> Array[Vector2i]:
	return _fx.live_impact_cells()


# --- A real cast lights every cell of its area --------------------------------

func test_a_real_cast_erupts_on_every_cell_of_its_area() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty():
		pending("Could not build the synthetic characters (CharacterLibrary); skipping.")
		return
	var caster: Unit = battle["caster"]
	if battle["board"] == null:
		pending("CombatServices.board() is null after rebuild(); skipping.")
		return

	var result: Dictionary = caster.perform_move(0, Vector2i(2, 1), battle["board"])
	assert_true(bool(result.get("success", false)), "the test blast resolved on the live board")
	await get_tree().process_frame  # the dispatcher flushes DEFERRED, like DamageNumbers

	var cells: Array[Vector2i] = _impact_cells()
	# 9 blast cells + the caster's own cast accent. The accent carries the caster's cell,
	# which is outside the blast here, so the two never conflate.
	assert_true(cells.has(Vector2i(0, 0)),
		"the caster gets a cast accent on its own cell for every move it makes")
	var blast: int = 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cell := Vector2i(2 + dx, 1 + dy)
			assert_true(cells.has(cell), "blast cell (%d,%d) erupted" % [cell.x, cell.y])
			if cells.has(cell):
				blast += 1
	assert_eq(blast, 9,
		"all nine cells of the 3x3 lit up off ONE victim -- the empty ground erupts too")


func test_the_burst_is_tinted_by_the_moves_element() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return
	(battle["caster"] as Unit).perform_move(0, Vector2i(2, 1), battle["board"])
	await get_tree().process_frame

	var ember: Color = ConquestTheme.element_color("ember")
	var tinted: int = 0
	for child in _fx.get_children():
		for mesh in child.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).material_override != null:
				var mat: StandardMaterial3D = (mesh as MeshInstance3D).material_override
				if is_equal_approx(mat.emission.r, ember.r) and is_equal_approx(mat.emission.g, ember.g):
					tinted += 1
	assert_gt(tinted, 0,
		"the rendered meshes carry the move's element colour from the shared theme lookup")


func test_the_impacts_free_themselves() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return
	(battle["caster"] as Unit).perform_move(0, Vector2i(2, 1), battle["board"])
	await get_tree().process_frame
	assert_gt(_fx.get_child_count(), 0, "there is something in flight to drain")

	# Each impact owns the tween that frees it -- nothing tracks or reaps them from outside.
	var drained: bool = await _await_until(func(): return _fx.get_child_count() == 0, 1200)
	assert_true(drained,
		"every burst freed itself within its own lifetime -- the layer trends to empty")


# --- The Abyssal Maw detonation ------------------------------------------------

func test_a_maw_detonation_erupts_across_its_whole_patch() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return

	# The production path, end to end: a real hazard, armed on a real fuse, expired exactly
	# as the shared turn-start tick expires it. THAT is what emits hazard_advanced.
	var blast: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			blast.append(Vector2i(2 + dx, 2 + dy))
	var hazard := DelayedBurstHazard.new(blast, 15,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, battle["caster"])
	hazard.element = &"dark"

	var fuse := DelayedBurstStatus.new()
	fuse.arm(hazard)
	fuse.on_expire(battle["caster"], battle["board"])
	await get_tree().process_frame

	var cells: Array[Vector2i] = _impact_cells()
	for cell in blast:
		assert_true(cells.has(cell),
			"maw cell (%d,%d) erupted -- the whole 3x3 opens, not just the cells with victims"
				% [cell.x, cell.y])
	assert_true(hazard.is_expired(), "and the maw really did go off (it is spent)")


func test_a_maw_that_announces_twice_in_a_frame_erupts_once() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return

	var hazard := DelayedBurstHazard.new([Vector2i(1, 1)] as Array[Vector2i], 5,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, null)
	GameEvents.emit_signal(&"hazard_advanced", hazard, [Vector2i(1, 1)], [], 0)
	GameEvents.emit_signal(&"hazard_advanced", hazard, [Vector2i(1, 1)], [], 0)
	await get_tree().process_frame

	assert_eq(_fx.get_child_count(), 1,
		"the double-fire guard means a re-announced hazard opens the ground exactly once")


func test_a_maws_telegraph_does_not_erupt_a_turn_early() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return

	# The cast-time announcement is EMPTY current cells + the marked patch as next -- a
	# warning, which is HazardVisualizer's job. Erupting on it would spoil the counterplay.
	var hazard := DelayedBurstHazard.new([Vector2i(1, 1)] as Array[Vector2i], 5,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, null)
	GameEvents.emit_signal(&"hazard_advanced", hazard, [], [Vector2i(1, 1)], 0)
	await get_tree().process_frame

	assert_eq(_fx.get_child_count(), 0,
		"a telegraph draws no impact -- the ground opens when it opens, not when it is marked")


# --- The override changes what is RENDERED ------------------------------------

func test_an_override_changes_the_rendered_scale_and_colour() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return
	var caster: Unit = battle["caster"]

	# Baseline: the unauthored move.
	caster.perform_move(0, Vector2i(2, 1), battle["board"])
	await get_tree().process_frame
	var plain_ring: float = _widest_ring()
	assert_gt(plain_ring, 0.0, "the default cast rendered a ground ring to measure")
	_fx.clear_effects()

	# Same move, same cast, one authored FX resource.
	var override := MOVE_FX.new()
	override.color = Color(0.42, 0.24, 0.62, 1.0)
	override.burst_scale = 2.0
	override.ring_scale = 2.0
	caster.get_move(0).fx = override
	caster.perform_move(0, Vector2i(2, 1), battle["board"])
	await get_tree().process_frame

	assert_gt(_widest_ring(), plain_ring * 1.5,
		"the authored ring_scale really does render a wider ring")
	assert_true(_has_emission(override.color),
		"and the authored colour reaches the material, overriding the element tint")
	caster.get_move(0).fx = null


## The largest ground-ring outer radius currently rendered (0.0 when none is).
func _widest_ring() -> float:
	var widest: float = 0.0
	for child in _fx.get_children():
		for mesh in child.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).mesh is TorusMesh:
				widest = maxf(widest, float(((mesh as MeshInstance3D).mesh as TorusMesh).outer_radius))
	return widest


func _has_emission(color: Color) -> bool:
	for child in _fx.get_children():
		for mesh in child.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = (mesh as MeshInstance3D).material_override
				if is_equal_approx(mat.emission.r, color.r) and is_equal_approx(mat.emission.b, color.b):
					return true
	return false


# --- The animations toggle -----------------------------------------------------

func test_animations_off_spawns_nothing_visual() -> void:
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return

	_guard.set_setting("animations_enabled", false)
	(battle["caster"] as Unit).perform_move(0, Vector2i(2, 1), battle["board"])
	GameEvents.emit_signal(&"hazard_advanced",
		DelayedBurstHazard.new([Vector2i(1, 1)] as Array[Vector2i], 5,
			CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, null),
		[Vector2i(1, 1)], [], 0)
	await get_tree().process_frame

	assert_eq(_fx.get_child_count(), 0,
		"animations off means not one node is created -- neither for a cast nor for a hazard")


# --- It must not touch a battle RNG stream ------------------------------------

func test_rendering_consumes_no_shared_random_draw() -> void:
	# The pin [MapSurround] carries, applied to the one place this layer has any jitter at
	# all: the shard scatter. It is seeded from the CELL, so the process-wide generator must
	# come out of a full cast accent + nine cell impacts in EXACTLY the state it went in --
	# and a future "just use randf() for the angle" would turn this red immediately.
	#
	# SCOPE, stated rather than hidden: this measures the RENDERING path. The one global
	# draw anywhere near a cast is [AudioManager]'s pitch variance (`randf_range` inside
	# play_sfx), which every existing cue -- move, hit, turn start -- already makes; it is
	# the process generator and NOT a battle stream ([MatchRng] derives a fresh generator
	# per command seq), so it cannot move a lockstep roll. Driving the spawners directly
	# keeps this pin about the FX layer rather than about that.
	var battle: Dictionary = await _build_battle()
	if battle.is_empty() or battle["board"] == null:
		pending("no live board; skipping")
		return

	var move: MoveResource = (battle["caster"] as Unit).get_move(0)
	var spec: Dictionary = _fx._move_spec(move, 0)
	var area: Array[Vector2i] = _fx._derive_area(move, battle["caster"], Vector2i(0, 0),
		[Vector2i(2, 1)] as Array[Vector2i])
	assert_eq(area.size(), 9, "the derivation produced a full 3x3 to render (not a vacuous pin)")

	seed(987654321)
	var expected: int = randi()

	# NO frame boundary between the seed and the read: only FX code runs in between.
	seed(987654321)
	_fx._spawn_cast_accent(Vector2i(0, 0), spec)
	for cell in area:
		_fx._spawn_impact(cell, spec)
	var actual: int = randi()

	assert_eq(_fx.get_child_count(), 10,
		"ten nodes really were built -- one cast accent and nine cell impacts")
	assert_eq(actual, expected,
		"building them drew ZERO values from the shared generator -- the scatter is cell-seeded")
