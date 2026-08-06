extends Node3D

class_name DamageNumbers

## Floating combat numbers: the little "12" that pops off a struck unit and the
## green "+8" that rises off a healed one. Purely cosmetic feedback -- it reads the
## same [GameEvents] signals everything else in the visual layer reads and never
## touches combat state.
##
## MOUNTING: a per-battle [Node3D] added to the 3D scene root by
## [code]GameWorldManager._setup_damage_numbers[/code] (the same place
## [TileEffectOverlay] is mounted), freed and recreated on the next map load so no
## popup ever outlives its battle.
##
## THREE PROPERTIES THIS FILE IS BUILT AROUND -- do not "simplify" any of them away:
##
##  1. IT NEVER REGISTERS IN [UnitAnimator]'s BUSY REGISTRY. That registry is what the
##     AI driver polls before taking its next action; a cosmetic 0.7s number must never
##     be able to stall the enemy turn. Nothing here calls
##     [method UnitAnimator._anim_begin] / [code]_track[/code], and nothing ever should.
##  2. IT CAPTURES THE VICTIM'S POSITION IMMEDIATELY and then forgets the unit. A killing
##     blow frees the defender within the same frame, so a popup that held the node and
##     read [code]global_position[/code] later would be reading a freed instance.
##  3. EVERY POPUP OWNS ITS OWN TWEEN AND FREES ITSELF FROM ITS `finished` CALLBACK, so
##     the layer trends to empty on its own and a scene change frees whatever is in flight.
##
## CRIT DETECTION. [signal GameEvents.damage_dealt] carries only
## [code](attacker, defender, damage)[/code] -- there is no crit flag on the bus (the flag
## lives in the MoveExecutor result log, which the presentation layer cannot see), and the
## forecast panel only ever reads a crit PROBABILITY. So a crit is INFERRED, and the
## inference is deliberately biased toward FALSE NEGATIVES -- a missed crit is a plain
## white number, which is fine; a false gold number would lie to the player:
##
##   * hits are buffered and flushed DEFERRED. [method Unit.perform_move] emits
##     `move_performed` immediately AFTER `MoveExecutor.execute` returns, so by the time
##     the deferred flush runs the MoveResource that produced this frame's hits is known.
##   * [method MoveExecutor.preview_vs] then gives the NON-crit damage and the crit damage
##     for that exact caster/target pair, and `dealt >= crit_damage` (with
##     `crit_damage > damage`) means the roll landed.
##   * anything missing -- no move, a different caster, a freed participant, a multi-effect
##     move, environmental damage from a hazard or a status -- resolves to "not a crit".
##
## STATUS FEEDBACK. A poison tick used to be indistinguishable from a sword hit: the same
## plain white number, from nowhere, with no way to tell WHY the unit lost HP. Three
## additions close that, all riding the same buffer this file already had:
##
##   * a TICK is recoloured. [signal GameEvents.status_ticked] fires immediately after a
##     condition's effects resolve, so the damage_dealt / unit_healed it produced are
##     already sitting in `_pending` -- the handler simply TAGS this frame's untagged
##     entries for that unit with the condition, and the flush draws them in the status'
##     own colour with its glyph ("† 4" in toxic green rather than a bare white "4").
##     This is why HEALS are buffered too now instead of spawning inline: a regen tick has
##     to be taggable exactly like a poison tick, and one code path for both is what keeps
##     them from drifting.
##   * an APPLY shouts "POISONED" and an EXPIRE murmurs "Poisoned faded", above the tick
##     number so the two never overlap. Both spawn inline -- there is nothing to correlate.
##   * nothing here decides WHAT a status is or does; the words, glyph and colour all come
##     from [StatusVisuals], the same vocabulary the health-bar pips and hover chips use.
##
## SHIELD ABSORPTION. Damage a damage-soak shield ate is drawn as a SILVER "◊ N" instead of
## a white damage number, and only the remainder that actually reached HP is drawn as
## damage -- so a hit that a ward swallowed whole no longer looks like a hit the game
## forgot to apply. The split is sampled at announce time and comes from
## [method Unit.absorb_split]; the glyph and colour come from [ShieldVisuals], the same
## vocabulary the silver segment on every HP bar uses.

# --- Placement ---------------------------------------------------------------
@export_group("Placement")
## Height (world +Y) above the victim's origin the number spawns at. Above the health
## bar (1.8) so the two never overlap.
@export_range(0.0, 6.0, 0.05) var spawn_height: float = 2.2
## Horizontal jitter (+/- this many world units on X and Z) so several numbers landing
## on the same tile in one AoE do not stack into an unreadable smear.
@export_range(0.0, 1.5, 0.01) var spawn_jitter: float = 0.35
## How far the number drifts UP over its life.
@export_range(0.0, 3.0, 0.05) var float_height: float = 0.8
## Authored seconds a number lives (drift + fade). Scaled by battle speed and then
## floored, so a fast battle still leaves it on screen long enough to read.
@export_range(0.1, 3.0, 0.01) var float_time: float = 0.7
## Hard cap on live popups. A huge AoE cannot flood the board with labels.
@export_range(1, 128, 1) var max_live_popups: int = 24

# --- Look --------------------------------------------------------------------
@export_group("Look")
## Ordinary damage. Plain white reads on every terrain.
@export var damage_color: Color = Color(1.0, 1.0, 1.0)
## CRIT damage -- gold, and drawn bigger (see [member crit_size_scale]).
@export var crit_color: Color = Color(1.0, 0.82, 0.28)
## Healing, drawn as "+N".
@export var heal_color: Color = Color(0.42, 1.0, 0.52)
## Damage a SHIELD ate. Silver, matching the shield segment on every HP bar
## ([constant ShieldVisuals.SILVER]).
@export var shield_color: Color = Color(0.788, 0.796, 0.839)
## Base font size of an ordinary number.
@export_range(8, 192, 1) var font_size: int = 56
## Multiplier applied to [member font_size] for a status APPLIED / EXPIRED word label.
## Well under 1.0: these are words, not numbers, and they must never out-shout the damage
## they sit above.
@export_range(0.1, 1.5, 0.01) var status_label_scale: float = 0.5
## Extra world +Y a status APPLIED / EXPIRED label spawns at, on top of [member
## spawn_height], so a "POISONED" shout and the tick number it belongs to are legible at
## the same time instead of stacking on one another.
@export_range(0.0, 3.0, 0.05) var status_label_lift: float = 0.75
## How far an EXPIRED label's colour is faded toward grey. An expiry is good news being
## reported, not a new threat, so it is deliberately the quietest thing this layer draws.
@export_range(0.0, 1.0, 0.01) var status_expired_desaturation: float = 0.55
## Multiplier applied to [member font_size] for a crit, so a crit is unmistakable
## before the colour is even read.
@export_range(1.0, 3.0, 0.05) var crit_size_scale: float = 1.45
## Dark outline thickness. Numbers sit over lit 3D terrain, so an outline is what
## keeps them legible rather than optional polish.
@export_range(0, 64, 1) var outline_size: int = 16
@export var outline_color: Color = Color(0.06, 0.04, 0.03, 0.92)
## World size of one font pixel. Together with [member font_size] this sets how big
## the number is on the board.
@export_range(0.001, 0.05, 0.001) var pixel_size: float = 0.011

# --- Crit camera kick ---------------------------------------------------------
@export_group("Crit Camera Kick")
## Strength handed to [code]CameraController.impulse_shake[/code] when a crit lands.
## Tiny on purpose -- a nudge, not a screen-wrecker.
@export_range(0.0, 1.0, 0.01) var crit_shake_strength: float = 0.2

## Floor / ceiling on a popup's scaled lifetime. Battle speed may shorten it, but never
## past the point where the number cannot be read.
const _LIFETIME_MIN: float = 0.25
const _LIFETIME_MAX: float = 2.0

## This frame's buffered HP changes, flushed deferred (see the crit note in the class doc).
## Each entry: { "pos": Vector3, "amount": int, "absorbed": int, "attacker": Object,
## "defender": Object, "heal": bool, "status": StatusCondition|null }.
## `absorbed` is how much of `amount` a damage-soak shield ate, sampled at announce time
## (see [method _on_damage_dealt]); 0 for every unshielded hit and every heal.
## `pos` is the authoritative popup placement, captured at signal time; the two object
## refs are BEST-EFFORT crit context only and are re-validated before any use. `status` is
## filled in by [method _on_status_ticked] when this frame's change came from a condition.
var _pending: Array[Dictionary] = []
## True while a deferred flush is already scheduled, so one AoE queues exactly one.
var _flush_queued: bool = false

## The MoveResource behind the hits buffered this frame, and the instance id of the unit
## that cast it. Set by `move_performed` (which fires after the hits) and cleared by the
## flush, so it can never be read as context for a LATER frame's damage.
var _cast_move = null
var _cast_caster_id: int = 0

## Own RNG instance for the spawn jitter. Deliberately NOT the process-wide RNG:
## `randomize()` would reseed every other system (and every test) in the run.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Cached only on a HIT, so a late-registered autoload is still picked up.
var _game_settings_cached: Node = null


func _ready() -> void:
	name = "DamageNumbers"
	_rng.randomize()  # instance-local; does NOT touch the global RNG.
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe_connect(bus, &"damage_dealt", _on_damage_dealt)
	_safe_connect(bus, &"unit_healed", _on_unit_healed)
	_safe_connect(bus, &"move_performed", _on_move_performed)
	# Status feedback. Each is guarded by has_signal inside _safe_connect, so a build
	# where the status bus signals have not landed simply keeps the old behaviour.
	_safe_connect(bus, &"status_ticked", _on_status_ticked)
	_safe_connect(bus, &"status_applied", _on_status_applied)
	_safe_connect(bus, &"status_expired", _on_status_expired)


func _safe_connect(obj: Object, signal_name: StringName, callable: Callable) -> void:
	if obj != null and obj.has_signal(signal_name) and not obj.is_connected(signal_name, callable):
		obj.connect(signal_name, callable)


# --- Signal handlers ---------------------------------------------------------

## A hit landed. Capture the placement NOW (the defender may be freed this frame) and
## buffer it; the deferred flush decides crit vs. normal and does the spawning.
func _on_damage_dealt(attacker = null, defender = null, damage = null) -> void:
	if not _fx_enabled():
		return
	var amount: int = _as_amount(damage)
	if amount <= 0:
		return
	var pos = _anchor_of(defender)
	if pos == null:
		return
	# SHIELD ABSORPTION, decided HERE and not at flush time. `damage_dealt` is announced
	# BEFORE take_damage applies (DamageEffect and TravelingHazard both say so in their own
	# docs, and the kill-attribution order depends on it), so at this instant the defender's
	# shield is still whole -- read it now and the split is exact. By the deferred flush the
	# ward has already been burned and the information is gone.
	#
	# The split itself is Unit.absorb_split, the same function take_damage soaks with, so
	# the silver number cannot claim an absorption that did not happen. A defender with no
	# shield (or no shield concept at all -- the mocks) splits to 0 absorbed, and everything
	# below behaves exactly as it did before.
	var shield_before: int = ShieldVisuals.shield_of(defender)
	var absorbed: int = int(Unit.absorb_split(shield_before, amount).get("absorbed", 0))
	_pending.append({
		"pos": pos,
		"amount": amount,
		"absorbed": absorbed,
		"attacker": attacker,
		"defender": defender,
		"heal": false,
		"status": null,
	})
	if not _flush_queued:
		_flush_queued = true
		call_deferred("_flush_pending")


## A unit regained HP. Heals never crit, so nothing about the CRIT inference needs the
## deferral -- but a heal from a [RegenStatus] tick has to be recolourable by
## [method _on_status_ticked], which can only run after the heal was announced. So heals
## ride the same buffer as hits, and one flush styles both.
func _on_unit_healed(unit = null, amount = null) -> void:
	if not _fx_enabled():
		return
	var healed: int = _as_amount(amount)
	if healed <= 0:
		return
	var pos = _anchor_of(unit)
	if pos == null:
		return
	_pending.append({
		"pos": pos,
		"amount": healed,
		"absorbed": 0,   # a heal is never soaked
		"attacker": null,
		"defender": unit,
		"heal": true,
		"status": null,
	})
	if not _flush_queued:
		_flush_queued = true
		call_deferred("_flush_pending")


# --- Status feedback ---------------------------------------------------------

## A condition just ticked on [param unit]. Whatever HP it moved was announced a moment
## ago and is sitting UNTAGGED in `_pending`, so claim this frame's entries for that unit
## -- the flush then draws them in the status' colour with its glyph.
##
## "Untagged entries for this unit" is the whole attribution rule, and it is exact rather
## than a guess: a condition ticks only its OWN unit, and ticks resolve one at a time, so
## anything for that unit still unclaimed when this fires belongs to this condition. A
## sword hit landing on the same unit in the same frame was buffered BEFORE any tick ran
## and would be mis-claimed -- which is why [method tick_all] announces per condition,
## immediately, instead of once at the end of the turn.
func _on_status_ticked(unit = null, condition = null, _events = null) -> void:
	if condition == null or unit == null or not is_instance_valid(unit):
		return
	var unit_id: int = unit.get_instance_id()
	for entry in _pending:
		if entry.get("status", null) != null:
			continue
		var defender = entry.get("defender", null)
		if defender == null or not is_instance_valid(defender):
			continue
		if defender.get_instance_id() == unit_id:
			entry["status"] = condition


## A condition LANDED. Shout its name over the unit, above the tick number.
func _on_status_applied(unit = null, condition = null) -> void:
	_spawn_status_label(unit, condition, StatusVisuals.applied_label(condition), false)


## A condition ran out. Report it quietly -- faded colour, same place.
func _on_status_expired(unit = null, condition = null) -> void:
	_spawn_status_label(unit, condition, StatusVisuals.expired_label(condition), true)


## Shared body of the two lifecycle handlers: one small word label in the status' colour,
## lifted clear of the numbers. Guarded exactly like every other spawn path -- animations
## off, a freed unit, or a detached layer all produce nothing.
func _spawn_status_label(unit, condition, text: String, faded: bool) -> void:
	if condition == null or text == "":
		return
	if not _fx_enabled():
		return
	var pos = _anchor_of(unit)
	if pos == null:
		return
	var color: Color = StatusVisuals.info_for(condition).get("color", damage_color)
	if faded:
		color = color.lerp(Color(0.72, 0.68, 0.60), status_expired_desaturation)
	_spawn_popup(pos + Vector3(0.0, status_label_lift, 0.0), text, color, status_label_scale)


## The cast that produced this frame's hits, announced right after it resolved. Stored
## purely as crit context for [method _flush_pending], which clears it again.
func _on_move_performed(caster = null, move = null) -> void:
	_cast_move = move
	_cast_caster_id = caster.get_instance_id() if is_instance_valid(caster) else 0
	# Queue a flush even for a move that dealt no damage (a buff, a pure status). The flush
	# clears the cast context, so a non-damaging cast can never linger as crit context for
	# some later frame's hit.
	if not _flush_queued:
		_flush_queued = true
		call_deferred("_flush_pending")


# --- Deferred flush ----------------------------------------------------------

## Spawn every hit buffered this frame, deciding crit styling now that the cast is known.
## One camera kick per frame at most, however many targets crit.
func _flush_pending() -> void:
	_flush_queued = false
	var batch: Array[Dictionary] = _pending.duplicate()
	_pending.clear()

	var any_crit: bool = false
	for entry in batch:
		var pos: Vector3 = entry.get("pos", Vector3.ZERO)
		var amount: int = int(entry.get("amount", 0))
		var healed: bool = bool(entry.get("heal", false))
		var condition = entry.get("status", null)

		# SOAKED DAMAGE READS AS SOAKED. Without this a shielded unit took a plain white
		# "12" and lost no HP, which looks like the game dropped the hit. The absorbed part
		# spawns as its own SILVER "◊ 12" -- the same glyph and colour as the shield segment
		# on the bar it just came off -- and only the part that reached HP is drawn as
		# damage. A fully-absorbed hit is therefore silver and nothing else.
		var absorbed: int = int(entry.get("absorbed", 0))
		if absorbed > 0 and not healed:
			_spawn_popup(pos, ShieldVisuals.absorbed_popup_text(absorbed), shield_color, 1.0)
		var to_health: int = amount if healed else maxi(0, amount - absorbed)
		if not healed and to_health <= 0:
			continue

		# A status tick wins the styling: it is the ONE case where the player cannot see
		# where the damage came from, so it gets the status' colour and glyph. A status
		# tick is never a crit (crits belong to casts), so the inference is skipped.
		if condition != null:
			var status_text: String = StatusVisuals.tick_text(condition, to_health, healed)
			if status_text != "":
				var status_color: Color = StatusVisuals.info_for(condition).get(
					"color", heal_color if healed else damage_color)
				_spawn_popup(pos, status_text, status_color, 1.0)
			continue

		if healed:
			_spawn_popup(pos, "+%d" % to_health, heal_color, 1.0)
			continue

		# Crit is inferred from the FULL dealt number (that is what the previewer's
		# crit_damage is comparable with); only the printed value is the post-shield one.
		var crit: bool = _infer_crit(entry)
		any_crit = any_crit or crit
		var color: Color = crit_color if crit else damage_color
		var size_scale: float = crit_size_scale if crit else 1.0
		_spawn_popup(pos, str(to_health), color, size_scale)

	# Drop the cast context: it is only ever valid for the frame it was announced in.
	_cast_move = null
	_cast_caster_id = 0

	if any_crit:
		_kick_camera()


## Did [param entry] land as a critical hit? See the class doc for why this is an
## inference rather than a signal read. Fails CLOSED at every step.
func _infer_crit(entry: Dictionary) -> bool:
	if _cast_move == null:
		return false
	var attacker = entry.get("attacker", null)
	var defender = entry.get("defender", null)
	if attacker == null or defender == null:
		return false
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return false
	# Only the unit that actually cast this frame's move can have crit with it.
	if attacker.get_instance_id() != _cast_caster_id:
		return false

	var board = CombatServices.board() if CombatServices != null else null
	var preview: Dictionary = MoveExecutor.preview_vs(_cast_move, attacker, defender, board)
	var base: int = int(preview.get("damage", 0))
	var crit_damage: int = int(preview.get("crit_damage", 0))
	# A move whose crit damage does not exceed its base damage (no damage effect, or a
	# 1-HP floor) can never be told apart, so it is never called a crit.
	if base <= 0 or crit_damage <= base:
		return false
	return int(entry.get("amount", 0)) >= crit_damage


# --- Popup construction ------------------------------------------------------

## Build one floating [Label3D] at [param world_pos] and start its drift+fade. The label
## owns its tween and frees itself when the tween finishes, so nothing tracks it here.
func _spawn_popup(world_pos: Vector3, text: String, color: Color, size_scale: float) -> void:
	# A Tween cannot be created on a detached node, and this runs from signals that can
	# arrive while the battle scene is being torn down.
	if not is_inside_tree():
		return
	if get_child_count() >= max_live_popups:
		return
	# FOG: nothing floats out of the mist. A "-12" rising over an empty-looking tile is a
	# perfect marker for a unit you are not supposed to know is there -- worse than the model
	# itself, because it is drawn with no_depth_test and reads over everything. Gated on the
	# CELL rather than the unit so status ticks, tile damage and hazard chip-damage are all
	# covered by one check, and read live so a just-revealed attacker's numbers do show.
	if FogOfWarOverlay.world_hidden(world_pos):
		return

	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Drawn over the units it describes: a number hidden behind the model it belongs to
	# is worse than no number at all.
	label.no_depth_test = true
	label.shaded = false
	label.render_priority = 8
	label.outline_render_priority = 7
	label.pixel_size = pixel_size
	label.font_size = maxi(1, int(round(float(font_size) * size_scale)))
	label.outline_size = outline_size
	label.outline_modulate = outline_color
	label.modulate = color
	# DISABLED (not a discard/hash cut) so the alpha fade below actually renders.
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	add_child(label)

	var jitter := Vector3(
		_rng.randf_range(-spawn_jitter, spawn_jitter),
		0.0,
		_rng.randf_range(-spawn_jitter, spawn_jitter))
	label.global_position = world_pos + jitter

	var life: float = clampf(_scaled(float_time), _LIFETIME_MIN, _LIFETIME_MAX)
	var rise: Vector3 = label.position + Vector3(0.0, float_height, 0.0)

	# NOTE: deliberately NOT registered with UnitAnimator's busy registry. See the class doc.
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", rise, life) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, life) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "outline_modulate:a", 0.0, life) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		if is_instance_valid(label):
			label.queue_free())


## Free every live popup at once (scene reset / test teardown). Immediate, not deferred,
## so a caller can assert on the empty state in the same frame.
func clear_popups() -> void:
	for child in get_children():
		if is_instance_valid(child):
			remove_child(child)
			child.free()


# --- Helpers -----------------------------------------------------------------

## The world point a popup for [param unit] should spawn at, or null when the unit is
## not a live [Node3D]. Read ONCE, at signal time -- see property 2 in the class doc.
func _anchor_of(unit):
	if unit == null or not is_instance_valid(unit) or not (unit is Node3D):
		return null
	return (unit as Node3D).global_position + Vector3(0.0, spawn_height, 0.0)


## Coerce an untyped signal payload to a non-negative int. The bus params are untyped so
## headless harnesses can emit mocks, so a null / string / float all have to be tolerated.
func _as_amount(value) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return maxi(0, int(value))
		_:
			return 0


## Nudge the battle camera on a crit, when the live camera is our [CameraController]
## (duck-typed, so any other camera simply does not shake).
func _kick_camera() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	# Untyped on purpose: impulse_shake lives on the CameraController script, not on
	# Camera3D, and the duck-typed check is what keeps any other camera unaffected.
	var camera = viewport.get_camera_3d()
	if camera != null and is_instance_valid(camera) and camera.has_method("impulse_shake"):
		camera.impulse_shake(crit_shake_strength)


# --- GameSettings bridge -----------------------------------------------------
#
# Mirrors UnitAnimator's bridge exactly: the autoload is optional, and an absent one
# behaves as "animations ON at scale 1.0" so a minimal/headless scene is unaffected.

func _game_settings() -> Node:
	if _game_settings_cached != null and is_instance_valid(_game_settings_cached):
		return _game_settings_cached
	# An absolute lookup on an OFF-TREE node logs an engine error even though it
	# returns null (headless tests drive handlers on a bare instance) - guard first.
	if not is_inside_tree():
		return null
	_game_settings_cached = get_node_or_null("/root/GameSettings")
	return _game_settings_cached


## False when the player has turned animations off -- then NOTHING is spawned or queued.
func _fx_enabled() -> bool:
	var settings := _game_settings()
	if settings == null or not settings.has_method("animations_on"):
		return true
	return bool(settings.animations_on())


func _scaled(base_seconds: float) -> float:
	var settings := _game_settings()
	if settings == null or not settings.has_method("scaled_time"):
		return base_seconds
	return float(settings.scaled_time(base_seconds))
