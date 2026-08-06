extends Node3D
class_name MoveFXDispatcher

## THE DEFAULT MOVE-FX LAYER. Every move -- current and future, authored or not -- gets a
## readable cast accent, an element-tinted impact on EVERY cell it covers, and a sound,
## with zero authoring. Per-move bespoke FX is then a [MoveFXResource] hung off
## [member MoveResource.fx]; this class resolves override-else-default field by field.
##
## THE BUG THIS EXISTS FOR: "there is no visual indicator of Abyssal Maw damaging the
## area". Nothing in the visual layer drew a move's AREA -- [ImpactFX] sparks on
## `damage_dealt`, so a cell of the blast with nobody standing in it produced nothing at
## all, and a 3x3 eruption that caught one unit looked like a single-target poke. This
## layer draws the CELLS, so an empty cell erupts exactly as loudly as an occupied one.
##
## MOUNTING: a per-battle [Node3D] added to the 3D scene root by
## [code]GameWorldManager._setup_move_fx[/code], beside [DamageNumbers] and [ImpactFX].
## Freed and recreated on the next map load, so no eruption outlives its battle.
##
## IT LISTENS. IT NEVER ASKS. Every input is an EXISTING [GameEvents] signal, so not one
## line of combat, AI or UI code knows this layer exists and deleting the mount call
## removes it completely:
##   * `move_performed(caster, move)` -- the cast. Buffered and flushed DEFERRED, exactly
##     as [DamageNumbers] buffers, because the hits it produced were announced just BEFORE
##     it (see [method Unit.perform_move]) and the area derivation below needs them.
##   * `damage_dealt` / `unit_healed` -- this frame's landed cells, captured at signal
##     time (a killing blow frees the defender within the frame, so its cell must be read
##     NOW, never at flush time).
##   * `hazard_advanced(hazard, cells, next_cells, damage)` -- the ONE signal that already
##     carries CELLS. Both hazards ride it: a [TravelingHazard]'s band sweep and a
##     [DelayedBurstHazard]'s eruption (announced by [DelayedBurstStatus]). This is what
##     makes the maw fix exact rather than inferred.
##
## HOW THE DEFAULT AREA IS DERIVED (no signal carries the aim cell, and adding one would
## be a combat-code edit):
##   1. `origin` is the caster's cell off the live board.
##   2. A SELF-targeted pattern aims at `origin`. Done.
##   3. A SINGLE-cell pattern erupts on exactly the cells that were hit this frame.
##   4. An AREA pattern INFERS the aim: every cell within the move's effective range is a
##      candidate, and the winner is the one whose [method TargetingPattern.resolve_cells]
##      covers every hit cell while sitting closest to them (scan order is fixed, so the
##      inference is deterministic). The full resolved area is then what erupts -- empty
##      cells included. That is step (3) of the fix.
##   5. Anything unresolvable falls back to the hit cells alone, and a cast that hit
##      nothing at all renders the cast accent only. The inference is biased to
##      UNDER-draw: a missing ring is a cosmetic gap, a ring on the wrong tile is a lie.
## Nothing here re-implements a targeting rule -- the area comes from the move's own
## [TargetingPattern], so retuning a move retunes its FX with it.
##
## FOUR PROPERTIES IT IS BUILT AROUND -- do not "simplify" any of them away:
##  1. NOTHING registers with [UnitAnimator]'s busy registry. A cosmetic 0.45s eruption
##     must never be able to stall the AI's next action.
##  2. EVERY impact owns the tween that frees it, so the layer drains itself and a scene
##     change takes whatever is in flight with it.
##  3. NO BATTLE RNG. The shard scatter comes from a LOCAL [RandomNumberGenerator] seeded
##     from the CELL (the isolation rule [MapSurround] documents): never `randf()`, never
##     [MatchRng]. Two peers therefore draw identical FX and, more importantly, drawing FX
##     cannot move a lockstep stream by a single draw.
##  4. REPLAY-SAFE BY CONSTRUCTION. It subscribes to gameplay OUTCOME signals, not to the
##     command seam -- playback re-applies commands through the same
##     [method Unit.perform_move], so the identical signals fire and the identical FX
##     renders. It is not connected to `command_committed`, so a recorded battle and a
##     played-back one cannot double-fire. The one place a double IS possible is a hazard
##     announcing twice in a frame, and [method _claim_hazard] closes it.
##
## ANIMATIONS OFF: nothing visual is created at all -- but the SOUND still plays, which is
## the point of the setting (skip the motion, keep the feedback).

## Grid <-> world. A cell Vector2i(col,row) centres at
## GRID.calculate_map_position(Vector3(col, 0, row)) -- the same lookup [HazardVisualizer]
## and [TileEffectOverlay] place their per-cell meshes with, so every board overlay agrees
## about where a cell is.
const GRID: Grid = preload("res://board/Grid.tres")

## Group [ImpactFX] joins, so the particle spark can be REUSED from here without this layer
## holding a reference to (or a mount ordering dependency on) it.
const IMPACT_FX_GROUP := &"impact_fx"

## Meta key naming the cell an impact container belongs to. Read by
## [method live_impact_cells] -- and by the tests, which count erupting cells.
const CELL_META := &"move_fx_cell"

# --- Cast accent -------------------------------------------------------------
@export_group("Cast Accent")
## Authored seconds the caster's accent ring lives. Scaled by battle speed, then floored.
@export_range(0.05, 2.0, 0.01) var cast_time: float = 0.28
## Outer radius of the accent ring, in world units (a board cell is 2.0 across).
@export_range(0.1, 3.0, 0.05) var cast_radius: float = 0.85
## Height above the tile the accent ring floats at.
@export_range(0.0, 3.0, 0.05) var cast_height: float = 0.12

# --- Impact ------------------------------------------------------------------
@export_group("Impact")
## Authored seconds one cell's impact lives. Scaled by battle speed, then floored.
@export_range(0.05, 3.0, 0.01) var impact_time: float = 0.45
## Outer radius of the ground ring, in world units. Just under a cell half-width (1.0) so
## adjacent cells of one blast read as separate eruptions rather than one smear.
@export_range(0.1, 3.0, 0.05) var ring_radius: float = 0.92
## Ring thickness as a fraction of [member ring_radius]. Chunky on purpose.
@export_range(0.05, 0.9, 0.01) var ring_thickness: float = 0.34
## Height above the tile the ring floats at.
@export_range(0.0, 3.0, 0.05) var ring_height: float = 0.1
## Chunky low-poly chunks thrown up per cell. Flat-shaded boxes, not billboards.
@export_range(0, 12, 1) var shard_count: int = 5
## World size of one shard at rest.
@export_range(0.02, 1.0, 0.01) var shard_size: float = 0.24
## How far a shard is flung from the cell centre.
@export_range(0.1, 3.0, 0.05) var shard_spread: float = 0.7
## How high a shard is thrown.
@export_range(0.1, 3.0, 0.05) var shard_rise: float = 0.85
## Hard cap on simultaneous cell impacts, so a board-wide AoE cannot spawn a hundred.
@export_range(1, 128, 1) var max_live_impacts: int = 48

# --- Sound -------------------------------------------------------------------
@export_group("Sound")
## Default [AudioManager] cue for a cast. `sfx_attack` is the natural home: it is a mapped
## [AudioLibrary] slot that NOTHING currently plays (the audio layer wires it to
## `combat_initiated`, which no site in the game emits), so using it here adds a cast sound
## without doubling anything.
@export var default_cast_cue: StringName = &"sfx_attack"
## Default cue for an impact that produced NO damage announcement. See
## [method _play_cue_for_impact] for why a damaging impact deliberately stays silent here.
@export var default_impact_cue: StringName = &"sfx_hit"

# --- Detonation --------------------------------------------------------------
@export_group("Hazard Detonation")
## Burst multiplier for a [DelayedBurstHazard] eruption -- the ground opening is a bigger
## beat than a vine crawling one band forward.
@export_range(0.5, 4.0, 0.05) var detonation_burst_scale: float = 1.6
## Camera kick on an eruption, handed to [method CameraController.impulse_shake]. The
## camera clamps it and skips it entirely with animations off.
@export_range(0.0, 0.5, 0.01) var detonation_shake: float = 0.22
## Burst multiplier for a travelling hazard's band sweep.
@export_range(0.1, 4.0, 0.05) var sweep_burst_scale: float = 0.85

## Floor / ceiling on a scaled lifetime. Battle speed may shorten an effect, never past
## the point where it cannot be seen, and never so far that it outlives the next action.
const _LIFETIME_MIN: float = 0.12
const _LIFETIME_MAX: float = 2.5
## Widest area (in candidate aim cells) the aim inference will scan. A ceiling, not a
## tuning knob: past it the inference gives up and the hit cells alone erupt.
const _MAX_AIM_CANDIDATES: int = 512

## This frame's landed cells, captured at signal time. Cleared by the flush.
var _hit_cells: Array[Vector2i] = []
## How many damage announcements landed this frame (the audio layer already sounded each
## one -- see [method _play_cue_for_impact]).
var _hit_announcements: int = 0
## The cast behind this frame's hits, set by `move_performed` (which fires AFTER them) and
## cleared by the flush, so it can never be read as context for a LATER frame.
var _cast_move = null
var _cast_caster = null
## True while a deferred flush is already scheduled, so one AoE queues exactly one.
var _flush_queued: bool = false

## hazard instance id -> the process frame it last drew on. The double-fire guard: a hazard
## that announces twice in one frame erupts once. See property 4 in the class doc.
var _hazard_frames: Dictionary = {}

## Cached only on a HIT, so a late-registered autoload is still picked up.
var _game_settings_cached: Node = null


func _ready() -> void:
	name = "MoveFXDispatcher"
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe_connect(bus, &"move_performed", _on_move_performed)
	_safe_connect(bus, &"damage_dealt", _on_damage_dealt)
	_safe_connect(bus, &"unit_healed", _on_unit_healed)
	_safe_connect(bus, &"hazard_advanced", _on_hazard_advanced)


func _safe_connect(obj: Object, signal_name: StringName, callable: Callable) -> void:
	if obj != null and obj.has_signal(signal_name) and not obj.is_connected(signal_name, callable):
		obj.connect(signal_name, callable)


# --- Signal handlers ---------------------------------------------------------

## A hit landed. Record the CELL now -- a killing blow frees the defender within this
## frame, so reading its position at flush time would be reading a freed instance.
func _on_damage_dealt(_attacker = null, defender = null, damage = null) -> void:
	if typeof(damage) != TYPE_INT and typeof(damage) != TYPE_FLOAT:
		return
	if int(damage) <= 0:
		return
	_hit_announcements += 1
	_note_cell(defender)


func _on_unit_healed(unit = null, amount = null) -> void:
	if typeof(amount) != TYPE_INT and typeof(amount) != TYPE_FLOAT:
		return
	if int(amount) <= 0:
		return
	_note_cell(unit)


## The cast that produced this frame's landed cells, announced right after it resolved.
## Queues the flush even for a move that touched nobody: the flush is also what CLEARS the
## cast context, so a non-damaging cast can never linger as context for a later frame.
func _on_move_performed(caster = null, move = null) -> void:
	_cast_move = move
	_cast_caster = caster
	_queue_flush()


## A hazard acted on CELLS -- the one signal that already carries them.
##
## Both hazards ride it. An empty `cells` is the TELEGRAPH shape ([DelayedBurstEffect]
## announces the marked patch as `next_cells` with nothing current), and a telegraph is
## [HazardVisualizer]'s job, not an impact -- so it is dropped here rather than erupting a
## turn early.
func _on_hazard_advanced(hazard = null, cells = null, _next_cells = null, damage = null) -> void:
	if hazard == null or not (cells is Array) or (cells as Array).is_empty():
		return
	if not _claim_hazard(hazard):
		return

	# Duck-typed, not `is DelayedBurstHazard`: the two hazards are unrelated RefCounted
	# scripts and only one of them can erupt, so asking for the capability is both the
	# cheapest and the most honest test -- a future fused hazard gets the treatment free.
	var detonation: bool = (hazard is Object) and (hazard as Object).has_method("detonate")
	var spec: Dictionary = _hazard_spec(hazard, detonation)

	_play_cue_for_impact(spec)
	if not _fx_enabled():
		return
	for cell in (cells as Array):
		if cell is Vector2i:
			_spawn_impact(cell, spec)
	if detonation:
		_kick_camera(float(spec["shake"]))


# --- Deferred flush ----------------------------------------------------------

func _queue_flush() -> void:
	if _flush_queued:
		return
	_flush_queued = true
	call_deferred("_flush")


## Render this frame's cast: the accent at the caster, then the impact on every cell the
## move's own targeting pattern says it covered.
func _flush() -> void:
	_flush_queued = false
	var move = _cast_move
	var caster = _cast_caster
	var hits: Array[Vector2i] = _hit_cells.duplicate()
	var announcements: int = _hit_announcements
	_cast_move = null
	_cast_caster = null
	_hit_cells.clear()
	_hit_announcements = 0

	if move == null:
		return  # damage with no cast behind it (a tile tick, a status) -- ImpactFX has it

	var spec: Dictionary = _move_spec(move, announcements)
	var origin = _cell_of(caster)
	# Derived BEFORE the animations gate: it is pure math over the move's own targeting
	# pattern, and the SOUND below has to know whether anything actually erupted.
	var area: Array[Vector2i] = _derive_area(move, caster, origin, hits)

	_play_cue(StringName(spec["cast_cue"]))
	if not area.is_empty():
		_play_cue_for_impact(spec)

	if not _fx_enabled():
		return
	if origin != null:
		_spawn_cast_accent(origin, spec)
	for cell in area:
		_spawn_impact(cell, spec)
	if not area.is_empty():
		_kick_camera(float(spec["shake"]))


# --- Default area derivation -------------------------------------------------

## The cells this cast should erupt on. See the class doc for the full rule; every branch
## fails toward drawing LESS rather than drawing somewhere wrong.
func _derive_area(move, caster, origin, hits: Array[Vector2i]) -> Array[Vector2i]:
	if move == null or not move.has_method("targeting_for"):
		return hits
	var pattern: TargetingPattern = move.targeting_for(caster)
	if pattern == null or origin == null:
		return hits
	var from: Vector2i = origin

	# A SELF-cast aims at the caster. No inference needed, and it is the one case where a
	# move that announced nothing at all still has an area worth drawing -- a pure buff
	# would otherwise be the one cast on the board with no impact beat at all.
	if pattern.target_kind == CombatTypes.TargetKind.SELF:
		var self_area: Array[Vector2i] = pattern.resolve_cells(from, from)
		# resolve_cells strips the caster's own cell unless affects_caster_tile is set, so
		# the ordinary self-buff resolves to NOTHING. Draw the caster's cell anyway: for a
		# SELF pattern that cell is unambiguously what the move acted on.
		if self_area.is_empty():
			self_area.append(from)
		return self_area

	if pattern.area_shape == CombatTypes.AreaShape.SINGLE:
		return hits
	if hits.is_empty():
		return [] as Array[Vector2i]

	var aim = _infer_aim(pattern, move, caster, from, hits)
	if aim == null:
		return hits
	return pattern.resolve_cells(from, aim)


## The aim cell that best explains [param hits] for a caster on [param origin].
##
## Every cell within the move's effective reach is a candidate; a candidate qualifies when
## its resolved area COVERS every hit, and the winner is the qualifying candidate closest
## to them (summed Manhattan distance). The scan order is fixed -- ascending dy, then dx --
## so ties resolve identically every time and on every machine; there is no randomness and
## no dependence on dictionary order anywhere in here.
##
## Returns null when nothing qualifies, which the caller reads as "draw only what was
## actually hit".
func _infer_aim(pattern: TargetingPattern, move, caster, origin: Vector2i, hits: Array[Vector2i]):
	var reach: int = pattern.max_range
	if move.has_method("effective_max_range"):
		reach = int(move.effective_max_range(caster))
	reach = clampi(reach, 0, 64)
	var span: int = 2 * reach + 1
	if span * span > _MAX_AIM_CANDIDATES:
		return null

	var best = null
	var best_score: int = 0
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var candidate: Vector2i = origin + Vector2i(dx, dy)
			var distance: int = absi(dx) + absi(dy)
			if distance < pattern.min_range or distance > reach:
				continue
			var area: Array[Vector2i] = pattern.resolve_cells(origin, candidate)
			var score: int = 0
			var covers: bool = true
			for hit in hits:
				if not area.has(hit):
					covers = false
					break
				score += absi(hit.x - candidate.x) + absi(hit.y - candidate.y)
			if not covers:
				continue
			if best == null or score < best_score:
				best = candidate
				best_score = score
	return best


# --- Spec resolution (override-else-default) ---------------------------------

## The rendering spec for a CAST. Every field is the dispatcher's derivation unless the
## move's optional [MoveFXResource] authored one (see that class for the per-field
## sentinels). [param announcements] is how many `damage_dealt`s this frame produced --
## it decides only whether the impact cue plays.
func _move_spec(move, announcements: int) -> Dictionary:
	var element: String = ""
	if move != null and ("element" in move):
		element = String(move.element)
	var spec: Dictionary = _default_spec(ConquestTheme.element_color(element))
	spec["announced"] = announcements
	_apply_override(spec, _fx_override(move))
	return spec


## The rendering spec for a hazard. A hazard carries its own snapshotted `element` (frozen
## from the casting move), so an eruption is tinted by the move that opened it without this
## layer having to find that move again.
func _hazard_spec(hazard, detonation: bool) -> Dictionary:
	var element: String = ""
	if hazard is Object and ("element" in hazard):
		element = String(hazard.element)
	var spec: Dictionary = _default_spec(ConquestTheme.element_color(element))
	spec["burst_scale"] = detonation_burst_scale if detonation else sweep_burst_scale
	spec["ring_scale"] = detonation_burst_scale if detonation else 1.0
	spec["shake"] = detonation_shake if detonation else 0.0
	# A hazard's own damage total decides the cue exactly as a cast's does.
	spec["announced"] = 1 if _hazard_damaged(hazard) else 0
	return spec


func _default_spec(color: Color) -> Dictionary:
	return {
		"color": color,
		"burst_scale": 1.0,
		"ring": true,
		"ring_scale": 1.0,
		"cast_cue": default_cast_cue,
		"impact_cue": default_impact_cue,
		"shake": 0.0,
		"scene": null,
		"life_scale": 1.0,
		"announced": 0,
	}


## The [MoveFXResource] hung off [param move], or null. Duck-typed (`"fx" in move`) so a
## test double or a build whose MoveResource predates the field simply gets the defaults.
func _fx_override(move):
	if move == null or not (move is Object) or not ("fx" in move):
		return null
	var fx = move.fx
	if fx == null or not (fx is Resource):
		return null
	return fx


## Fold an override into [param spec], field by field, skipping every field left at its
## "not authored" sentinel. Duck-typed throughout: a resource missing a property (an older
## `.tres`, a stand-in) contributes nothing rather than erroring.
func _apply_override(spec: Dictionary, fx) -> void:
	if fx == null:
		return
	if ("color" in fx) and fx.has_method("has_color") and bool(fx.has_color()):
		spec["color"] = fx.color
	if "burst_scale" in fx:
		spec["burst_scale"] = maxf(0.05, float(fx.burst_scale))
	if "ring_enabled" in fx:
		spec["ring"] = bool(fx.ring_enabled)
	if "ring_scale" in fx:
		spec["ring_scale"] = maxf(0.05, float(fx.ring_scale))
	if ("cast_cue" in fx) and StringName(fx.cast_cue) != &"":
		spec["cast_cue"] = StringName(fx.cast_cue)
	if ("impact_cue" in fx) and StringName(fx.impact_cue) != &"":
		spec["impact_cue"] = StringName(fx.impact_cue)
	if "shake_strength" in fx:
		spec["shake"] = clampf(float(fx.shake_strength), 0.0, 0.5)
	if ("impact_scene" in fx) and fx.impact_scene is PackedScene:
		spec["scene"] = fx.impact_scene
	if "lifetime_scale" in fx:
		spec["life_scale"] = clampf(float(fx.lifetime_scale), 0.25, 4.0)


# --- Rendering ---------------------------------------------------------------

## A brief element-tinted ring under the caster. The attack CLIP itself is [UnitAnimator]'s
## job and already plays -- this is the accent that says which ELEMENT is being spent, and
## it is what gives a purely-supportive cast (no damage, no target) any feedback at all.
func _spawn_cast_accent(cell: Vector2i, spec: Dictionary) -> void:
	if not is_inside_tree():
		return
	if get_child_count() >= max_live_impacts:
		return
	# FOG: a cast accent under a caster you cannot see would draw a bright element-tinted
	# ring on an apparently empty tile. One additive check, live-read, at the last moment
	# before anything is built -- so a caster the vision core reveals by attacking still
	# gets its accent (the reveal lands before the announcement).
	if FogOfWarOverlay.cell_hidden(cell):
		return
	var color: Color = spec["color"]
	var container := Node3D.new()
	container.name = "CastAccent"
	container.set_meta(CELL_META, cell)
	add_child(container)
	container.global_position = _world_of(cell) + Vector3(0.0, cast_height, 0.0)

	var ring := _make_ring(cast_radius, ring_thickness, color)
	container.add_child(ring)

	var life: float = _life(cast_time, 1.0)
	container.scale = Vector3(0.35, 0.35, 0.35)
	var tween := container.create_tween()
	tween.set_parallel(true)
	tween.tween_property(container, "scale", Vector3.ONE, life) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, life) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free())


## ONE cell erupting: a flat ground ring plus chunky low-poly shards, both tinted from the
## same element vocabulary, plus a reused [ImpactFX] particle spark and (optionally) an
## authored scene. A cell with nobody standing in it renders exactly this -- which is the
## whole point of the layer.
func _spawn_impact(cell: Vector2i, spec: Dictionary) -> void:
	# create_tween() errors on a detached node, and these signals arrive during teardown as
	# readily as during play.
	if not is_inside_tree():
		return
	if get_child_count() >= max_live_impacts:
		return
	# FOG: an eruption is per-CELL, so this is where a 3x3 blast reaching into the mist gets
	# clipped -- the cells you can see erupt, the cells you cannot stay dark. That is the
	# genre answer to "what does a hit in fog look like": nothing at all.
	if FogOfWarOverlay.cell_hidden(cell):
		return

	var color: Color = spec["color"]
	var burst: float = float(spec["burst_scale"])
	var life: float = _life(impact_time, float(spec["life_scale"]))

	var container := Node3D.new()
	container.name = "Impact_%d_%d" % [cell.x, cell.y]
	container.set_meta(CELL_META, cell)
	add_child(container)
	container.global_position = _world_of(cell)

	var faders: Array[GeometryInstance3D] = []
	## Each entry: { "node": MeshInstance3D, "to": Vector3 } -- the shard and where it flies.
	var risers: Array[Dictionary] = []

	if bool(spec["ring"]):
		var ring := _make_ring(ring_radius * float(spec["ring_scale"]), ring_thickness, color)
		ring.position = Vector3(0.0, ring_height, 0.0)
		container.add_child(ring)
		faders.append(ring)

	# Deterministic scatter: seeded from the CELL, so the same cell always throws the same
	# chunks and nothing anywhere reads a shared generator. See property 3 in the class doc.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(cell)
	for i in range(shard_count):
		var angle: float = (float(i) / float(maxi(1, shard_count))) * TAU + rng.randf_range(-0.35, 0.35)
		var shard := _make_shard(shard_size * burst, color)
		shard.position = Vector3(cos(angle) * 0.12, ring_height, sin(angle) * 0.12)
		shard.rotation = Vector3(rng.randf_range(-1.0, 1.0), angle, rng.randf_range(-1.0, 1.0))
		container.add_child(shard)
		faders.append(shard)
		risers.append({
			"node": shard,
			"to": shard.position + Vector3(
				cos(angle) * shard_spread * burst,
				shard_rise * burst * rng.randf_range(0.6, 1.0),
				sin(angle) * shard_spread * burst),
		})

	if spec["scene"] is PackedScene:
		var authored: Node = (spec["scene"] as PackedScene).instantiate()
		container.add_child(authored)

	# REUSE, not a second particle system: the spark is [ImpactFX]'s, with its own headless
	# and animations-off guards, found through its group so nothing here depends on mount order.
	_request_spark(container.global_position, color, burst)

	var tween := container.create_tween()
	tween.set_parallel(true)
	for riser in risers:
		var node: Node3D = riser["node"]
		tween.tween_property(node, "position", riser["to"], life) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "scale", Vector3(0.2, 0.2, 0.2), life) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for fader in faders:
		tween.tween_property(fader, "transparency", 1.0, life) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free())


## A flat, chunky, unshaded ring lying on the ground -- low-poly by construction (few rings
## and few segments), so it reads as a faceted shockwave rather than a smooth decal.
func _make_ring(radius: float, thickness: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.outer_radius = maxf(0.05, radius)
	mesh.inner_radius = maxf(0.01, radius * (1.0 - clampf(thickness, 0.05, 0.9)))
	mesh.rings = 3
	mesh.ring_segments = 12

	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _flash_material(color)
	node.scale = Vector3(1.0, 0.25, 1.0)  # flattened onto the ground plane
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## One chunk of thrown-up ground: a flat-shaded box, deliberately faceted and deliberately
## LIT (unlike the ring), so the eruption has solid geometry in it and not only glow.
func _make_shard(size: float, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, size)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.roughness = 1.0
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.55
	# TRANSPARENCY_ALPHA (never DISABLED) is what makes GeometryInstance3D.transparency --
	# the property the fade tweens -- actually do anything.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Unshaded, glowing, alpha-blended: the flash look. Unshaded on purpose -- a ring that
## took the map's lighting would be invisible on a dark tile and blinding on a bright one.
func _flash_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.78)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.3
	material.render_priority = 3
	return material


## Ask the battle's [ImpactFX] layer for a spark here. A no-op when none is mounted (a
## minimal scene, a headless suite) -- the ring and the shards are the layer's own,
## rendering-device-free, contribution and stand on their own.
func _request_spark(world_pos: Vector3, color: Color, scale_mult: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var fx := tree.get_first_node_in_group(IMPACT_FX_GROUP)
	if fx == null or not is_instance_valid(fx) or not fx.has_method("burst_at"):
		return
	fx.burst_at(world_pos, color, scale_mult)


# --- Sound -------------------------------------------------------------------

## Play one mapped [AudioManager] cue. Resolved through the tree rather than the global so
## a headless suite with no audio autoload is silent instead of red; an unmapped or
## unassigned slot is already a documented no-op inside [method AudioManager.play_sfx], so
## a cue the library has no stream for costs nothing.
func _play_cue(cue: StringName) -> void:
	if cue == &"":
		return
	# An absolute lookup on an OFF-TREE node logs an engine error even though it returns
	# null (unit suites drive these handlers on a bare instance) - guard first, exactly as
	# the GameSettings bridge below does.
	if not is_inside_tree():
		return
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play_sfx"):
		return
	audio.play_sfx(cue)


## The impact cue FILLS SILENCE -- it plays only when the event announced no damage.
##
## The audio layer already plays `sfx_hit` once per `damage_dealt`, so sounding an impact
## that hit three units would triple a sound the player is already hearing. What had NO
## sound at all is the case this layer exists for: a maw erupting on empty ground, a sweep
## that caught nobody, an area move that missed. Those now land audibly. An override that
## names an [member MoveFXResource.impact_cue] does not change this rule -- it changes
## WHICH cue fills the silence, so a per-move sound can never double the hit either.
func _play_cue_for_impact(spec: Dictionary) -> void:
	if int(spec.get("announced", 0)) > 0:
		return
	_play_cue(StringName(spec["impact_cue"]))


# --- Helpers -----------------------------------------------------------------

## Record the board cell [param unit] currently stands on. Called at SIGNAL time; the unit
## may be freed before the deferred flush runs, which is exactly why only the cell is kept.
func _note_cell(unit) -> void:
	var cell = _cell_of(unit)
	if cell == null:
		return
	if not _hit_cells.has(cell):
		_hit_cells.append(cell)
	_queue_flush()


## [param unit]'s cell off the live board, or null when there is no board, no unit, or the
## unit is not on it. Never guessed from a world position: the board is the authority.
func _cell_of(unit):
	if unit == null or not is_instance_valid(unit):
		return null
	if typeof(CombatServices) != TYPE_OBJECT or CombatServices == null:
		return null
	var board = CombatServices.board()
	if board == null or not board.has_method("cell_of"):
		return null
	var cell: Vector2i = board.cell_of(unit)
	if cell == Vector2i(-1, -1):
		return null
	return cell


func _world_of(cell: Vector2i) -> Vector3:
	return GRID.calculate_map_position(Vector3(cell.x, 0, cell.y))


## Claim [param hazard]'s draw for THIS frame. False when it already drew this frame, which
## is the guard against a hazard announced twice (a manager tick plus a status expiry
## landing together, a replay driver re-entering). Bounded: the map is swept whenever it
## outgrows a handful of live hazards, so nothing accumulates across a battle.
func _claim_hazard(hazard) -> bool:
	var hid: int = hazard.get_instance_id() if hazard is Object else 0
	var frame: int = Engine.get_process_frames()
	if int(_hazard_frames.get(hid, -1)) == frame:
		return false
	if _hazard_frames.size() > 32:
		for key in _hazard_frames.keys():
			if int(_hazard_frames[key]) < frame:
				_hazard_frames.erase(key)
	_hazard_frames[hid] = frame
	return true


## Did this hazard's action announce damage THIS FRAME?
##
## Read off the same per-frame counter a cast uses, and it is exact: both hazards announce
## every bite through `damage_dealt` BEFORE they emit `hazard_advanced` (see
## [method DelayedBurstHazard.detonate] and [method TravelingHazard.advance]), and the
## counter is only cleared by the deferred flush, which cannot have run yet. Deliberately
## NOT read off `hazard.damage` -- that is the per-occupant number frozen at cast time, so
## a maw that erupted on empty ground would claim it had hit something.
func _hazard_damaged(_hazard) -> bool:
	return _hit_announcements > 0


## Deterministic per-cell seed (FNV-1a over the cell's coordinates), so the shard scatter is
## byte-identical on every machine and every replay without any generator being shared.
func _seed_for(cell: Vector2i) -> int:
	var hash_value: int = 2166136261
	for component in [cell.x, cell.y]:
		hash_value = (hash_value ^ (int(component) & 0xFFFF)) * 16777619
		hash_value = hash_value & 0x7FFFFFFF
	return hash_value


## Nudge the battle camera, when the live camera is our [CameraController] (duck-typed, so
## any other camera simply does not shake). The camera's OWN animations gate and its
## re-entrancy guard then apply, so several eruptions in a frame shake once.
func _kick_camera(strength: float) -> void:
	if strength <= 0.0 or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera = viewport.get_camera_3d()
	if camera != null and is_instance_valid(camera) and camera.has_method("impulse_shake"):
		camera.impulse_shake(strength)


## Every cell currently erupting -- what a test counts, and what a debug overlay would read.
func live_impact_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for child in get_children():
		if child != null and is_instance_valid(child) and child.has_meta(CELL_META):
			cells.append(child.get_meta(CELL_META))
	return cells


## Free every live effect at once (scene reset / test teardown). Immediate, not deferred,
## so a caller can assert on the empty state in the same frame.
func clear_effects() -> void:
	for child in get_children():
		if is_instance_valid(child):
			remove_child(child)
			child.free()


# --- GameSettings bridge -----------------------------------------------------
#
# Mirrors ImpactFX / DamageNumbers exactly: the autoload is optional, and an absent one
# behaves as "animations ON at scale 1.0" so a minimal/headless scene is unaffected.

func _game_settings() -> Node:
	if _game_settings_cached != null and is_instance_valid(_game_settings_cached):
		return _game_settings_cached
	# An absolute lookup on an OFF-TREE node logs an engine error even though it returns
	# null (headless tests drive handlers on a bare instance) - guard first.
	if not is_inside_tree():
		return null
	_game_settings_cached = get_node_or_null("/root/GameSettings")
	return _game_settings_cached


## False when the player has turned animations off -- then NOTHING visual is spawned.
## Sound is deliberately outside this gate: the setting turns off MOTION, not feedback.
func _fx_enabled() -> bool:
	var settings := _game_settings()
	if settings == null or not settings.has_method("animations_on"):
		return true
	return bool(settings.animations_on())


func _life(base_seconds: float, scale_mult: float) -> float:
	var settings := _game_settings()
	var seconds: float = base_seconds
	if settings != null and settings.has_method("scaled_time"):
		seconds = float(settings.scaled_time(base_seconds))
	return clampf(seconds * maxf(0.05, scale_mult), _LIFETIME_MIN, _LIFETIME_MAX)
