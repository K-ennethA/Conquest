extends Node

## Autoload that plays lightweight, inspector-tunable unit animations in
## response to the existing GameEvents signal bus.
##
## Design goals:
##  - Additive & non-invasive: it never edits unit.gd or the turn systems; it
##    only listens to signals and drives each unit's own MeshInstance3D via
##    Tween. If a signal or mesh is missing, it silently no-ops.
##  - Inspector-editable: all timings/colors are @export params so a designer
##    can retune feel without touching code.
##  - Cheap: uses Tweens (no per-frame _process work, no per-frame allocation)
##    and reuses one temporary material per flash.

# --- Move glide -----------------------------------------------------------
@export_group("Move Glide")
## Seconds to visually glide a unit's mesh from its old tile to the new one.
## The unit's authoritative position is already at the destination when
## GameEvents.unit_moved fires, so we glide the MESH (a child offset) only --
## game logic, health bars, and targeting stay correct.
@export_range(0.0, 1.5, 0.01) var move_glide_time: float = 0.3
## Easing curve for the glide.
@export var move_glide_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var move_glide_ease: Tween.EaseType = Tween.EASE_OUT

# --- Hit flash ------------------------------------------------------------
@export_group("Hit Flash")
## Seconds the damage flash is held before restoring the original look.
@export_range(0.0, 1.0, 0.01) var hit_flash_time: float = 0.12
## Color the mesh flashes to when it takes damage.
@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25)
## Extra emission energy during the flash (makes it pop in 3D lighting).
@export_range(0.0, 8.0, 0.1) var hit_flash_emission: float = 2.0
## Squash-punch scale applied on hit (1.0 = no punch). Adds tactile feedback.
@export_range(1.0, 1.6, 0.01) var hit_punch_scale: float = 1.12

# --- Heal flash -----------------------------------------------------------
@export_group("Heal Flash")
## Seconds the heal flash is held before restoring the original look. Mirrors
## [member hit_flash_time] but reads as positive (a gentle green glow).
@export_range(0.0, 1.0, 0.01) var heal_flash_time: float = 0.22
## Color the mesh flashes to when it is healed (a positive green, not the red hit).
@export var heal_flash_color: Color = Color(0.3, 1.0, 0.4)
## Extra emission energy during the heal flash (makes the green pop in 3D lighting).
@export_range(0.0, 8.0, 0.1) var heal_flash_emission: float = 2.0
## Gentle upward hop (local +Y) on heal (0.0 = none). A small POSITIVE pop, the
## opposite of the damage squash -- it reads as "revived", not "struck".
@export_range(0.0, 0.6, 0.01) var heal_hop_height: float = 0.12

# --- Move shake -----------------------------------------------------------
@export_group("Move Shake")
## Default caster feedback for ANY move (attack, buff, heal, status) on a model
## with no authored "attack" clip: a punchy forward lunge-and-recoil of the model,
## so no move is ever silent and it reads as "I attacked". A model that ships an
## attack clip plays that instead.
@export_range(0.0, 0.6, 0.01) var move_shake_distance: float = 0.35
## Total seconds of the lunge-and-recoil. Kept snappy so it reads as a strike.
@export_range(0.0, 1.0, 0.01) var move_shake_time: float = 0.28

# --- Idle bob -------------------------------------------------------------
#
# A standing unit that is perfectly still reads as a prop. This is the cheapest fix:
# a slow, tiny breathe -- the model rises a few centimetres and squashes slightly,
# then settles -- looped forever on each unit's own model node.
#
# Four properties keep it from being a source of bugs:
#  * IT NEVER REGISTERS IN THE BUSY REGISTRY. It loops forever, so an entry would read
#    as "animating" permanently and the AI driver would wait for the heat death of the
#    universe. Nothing here calls _track / _anim_begin, and nothing ever should.
#  * IT PAUSES FOR EVERY REAL ANIMATION. Glide, lunge, hit flash, heal flash and death
#    all drive the same position/scale properties on the same nodes; two tweens fighting
#    over one property is exactly the drift bug that strands a model off its unit. Every
#    entry point stops the bob (which SNAPS the model back to its rest pose first, so the
#    animation captures a clean base) and the animation's own tween restarts it on finish.
#  * THE TWEEN IS OWNED BY THE MODEL NODE, so freeing the unit kills it -- a death can
#    never leave a bob ticking on a dead instance.
#  * IT IS PHASE-OFFSET PER UNIT (by instance id), so a line of eight units breathes as
#    eight individuals rather than one accordion.
@export_group("Idle Bob")
## Master switch for the idle breathe.
@export var idle_bob_enabled: bool = true
## Authored seconds of one full up-and-down cycle. Slow on purpose -- this should be
## noticed only when it is missing. Scaled by battle speed and jittered per unit.
@export_range(0.5, 6.0, 0.05) var idle_bob_period: float = 2.2
## Peak rise (local +Y) of the breathe, in metres. Tiny: a unit is ~1 metre tall.
@export_range(0.0, 0.3, 0.005) var idle_bob_height: float = 0.045
## Peak squash/stretch of the breathe as a fraction of the model's rest scale
## (0.02 = 2% wider and 2% shorter at the bottom of the cycle). 0.0 = pure bob.
@export_range(0.0, 0.2, 0.005) var idle_bob_scale: float = 0.02

# unit instance id -> the looping idle Tween. Present ONLY while a unit is bobbing;
# stopping erases the entry, so `has(id)` is the authoritative "is it bobbing?".
var _idle_tween: Dictionary = {}

# unit instance id -> the model's authored REST scale, captured the first time the bob
# starts (i.e. before anything has squashed it). The counterpart to _anim_base for
# position: every stop restores to THIS, never to a live reading taken mid-breathe.
var _idle_base_scale: Dictionary = {}

# --- Death ----------------------------------------------------------------
#
# A death is dramatic and unmissable, not a quiet 0.25s shrink: a bright colour
# FLASH, a small topple/POP up, THEN a slower SINK + shrink + fade. The colour flash
# and fade drive the visible mesh (material_override); the pop/sink/shrink drive the
# model root. Honors _anims_on() (off -> instant removal, no drama) and scales every
# duration by battle speed via _scaled(), so a slow battle lingers on the death.
@export_group("Death")
## Seconds of the final SINK + shrink + fade -- the theatrical body of the death.
## Raised well above the old quick 0.25s so the unit visibly sinks and fades away
## rather than just popping out of existence.
@export_range(0.0, 3.0, 0.01) var death_shrink_time: float = 0.7
## Colour the mesh flashes to at the instant of death (a bright emissive tell). A near-
## white/red default reads as a killing blow regardless of the unit's own colour.
@export var death_flash_color: Color = Color(1.0, 0.85, 0.8)
## Extra emission energy of the death flash, so it pops hard in 3D lighting.
@export_range(0.0, 12.0, 0.1) var death_flash_emission: float = 4.0
## Seconds to snap TO the death flash (the bright hit), before the sink begins.
@export_range(0.0, 1.0, 0.01) var death_flash_time: float = 0.1
## Height (local +Y) of the brief POP/rise the model does as it is struck, before it
## sinks. A small theatrical lurch upward; 0.0 disables the pop.
@export_range(0.0, 1.5, 0.01) var death_rise_height: float = 0.35
## Seconds of the upward pop. Kept short so it reads as a lurch, not a jump.
@export_range(0.0, 1.0, 0.01) var death_rise_time: float = 0.14
## Distance (local -Y) the model SINKS through the floor as it shrinks and fades out.
## Combined with the shrink it reads as the body dropping and dissolving.
@export_range(0.0, 3.0, 0.01) var death_sink_distance: float = 0.6

# --- Authored animation clips ---------------------------------------------
#
# When a character ships a model with an AnimationPlayer (a Blender export -- see
# tools/blender/README.md), these clip names are played in response to the same
# game events that drive the procedural tweens below. A model that has no clips,
# or is missing one, silently falls back to the tween, so placeholder capsules and
# half-rigged models keep animating exactly as before.
#
# This is the ONE piece of naming an artist has to honour.
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_ATTACK := "attack"
const CLIP_HIT := "hit"
const CLIP_DEATH := "death"

@export_group("Authored Clips")
## Play authored clips when a model provides them. Turn off to force the
## procedural tweens everywhere (useful for comparing feel).
@export var use_authored_clips: bool = true
## Seconds to blend between clips.
@export_range(0.0, 1.0, 0.01) var clip_blend_time: float = 0.12

# unit instance id -> AnimationPlayer, or null when that unit has none. Caching
# the MISS matters too: without it every event re-walks the unit's whole subtree.
var _anim_players: Dictionary = {}

# Tracks each unit's last known world position so we can compute a glide start
# even though unit_moved carries tile coords (not world coords) from some
# emitters. Keyed by instance id -> Vector3.
var _last_world_pos: Dictionary = {}

# The authored REST local-position of each unit's anim root (CharacterModel/mesh),
# captured once. Every motion tween settles back to THIS, never to a live reading
# of node.position -- otherwise a shake that starts mid-glide would capture the
# displaced position as its rest and leave the model stranded a full move-offset
# away (it looks like the unit vanished). Keyed by instance id -> Vector3.
var _anim_base: Dictionary = {}

# The unit's current motion tween (shake OR glide), keyed by instance id. A new
# motion kills the previous one so two tweens never fight over the same position
# property (which also stranded the model). Death/flash use their own tweens.
var _motion_tween: Dictionary = {}

# --- Global animation-busy registry (static, poll-based) -------------------
#
# Lets a consumer -- specifically the AI driver (BotTurnDriver) -- know whether
# any gameplay-visible animation this animator drives (move glide, attack shake,
# hit/heal flash, death, and authored clips) is still in flight, so it can wait
# for the screen to go QUIET before starting the next action. The reported bug is
# the enemy acting on top of the player's still-playing attack/hit/death; the turn
# SYSTEMS advancing instantly is by design, so the fix lives here on the visual
# side plus a matching wait in the driver.
#
# Statics can't emit signals, so this is a POLLED design and -- crucially -- it can
# never wedge the game: each started animation registers an entry with an EXPIRY
# timestamp; the getter treats ONLY unexpired entries as "playing". If a finish
# callback is ever lost (a killed tween emits no `finished`, or a unit frees mid-
# animation), the entry simply expires and the registry goes quiet on its own. In
# the common case entries are also erased promptly on the tween's `finished`.
#
# The registry is STATIC so the single UnitAnimator autoload's entries are visible
# to the driver via the same script class, with no autoload lookup and no counter
# that could drift negative (a Dictionary of live tokens can't).

# token -> expiry ms (from Time.get_ticks_msec). A monotonic token keys each in-
# flight animation so overlapping animations never clobber one another's entry.
static var _anim_entries: Dictionary = {}
static var _anim_token_seq: int = 0
## Absolute hard ceiling (ms) on how long ONE entry is ever considered active,
## regardless of the duration handed in -- the final backstop against a runaway
## clip length. ~4s per the design: a lost callback can wedge nothing past this.
const ANIM_MAX_AGE_MS: int = 4000
## Slack (ms) added to every entry's duration so an animation is still counted
## busy across scheduling jitter between its last frame and its finish callback.
const ANIM_MARGIN_MS: int = 120

## Register a started gameplay animation of ~[param duration_s] seconds and return
## its token. The entry expires on its own after the (clamped) duration even if
## [method _anim_end] is never called, so the registry can never get stuck busy.
static func _anim_begin(duration_s: float) -> int:
	_anim_token_seq += 1
	var token: int = _anim_token_seq
	var ms: int = int(ceil(maxf(0.0, duration_s) * 1000.0)) + ANIM_MARGIN_MS
	ms = clampi(ms, 0, ANIM_MAX_AGE_MS)
	_anim_entries[token] = Time.get_ticks_msec() + ms
	return token

## Mark a registered animation finished (its tween completed or was killed early).
## Idempotent and safe with an unknown/stale token.
static func _anim_end(token: int) -> void:
	_anim_entries.erase(token)

## Drop every entry whose expiry has passed. Keeps the registry bounded and makes
## a lost [method _anim_end] harmless.
static func _prune_anim_entries() -> void:
	if _anim_entries.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var dead: Array = []
	for token in _anim_entries:
		if int(_anim_entries[token]) <= now:
			dead.append(token)
	for token in dead:
		_anim_entries.erase(token)

## True when any gameplay-visible animation this animator drives is still in flight.
## Polled by the AI driver so it defers its next action until the screen is quiet.
## Prunes expired entries first, so a lost finish callback never wedges it. When
## animations are OFF nothing is ever registered (every play path early-outs on
## [method _anims_on]), so this is trivially false without special-casing here.
static func is_any_animation_playing() -> bool:
	_prune_anim_entries()
	return not _anim_entries.is_empty()

## Clear the registry outright. For tests / a hard scene reset -- production never
## needs it (entries expire), but a test asserting the empty state wants a clean slate.
static func _clear_anim_registry() -> void:
	_anim_entries.clear()

## Register [param tw] in the global busy registry for ~[param duration_s] seconds so
## the AI driver waits for it. The entry auto-expires even if the tween is killed (a
## killed tween never emits `finished`), so a leaked callback can never wedge the game;
## in the normal case the `finished` callback clears it as soon as the tween completes.
func _track(tw: Tween, duration_s: float) -> void:
	if tw == null or not tw.is_valid():
		return
	var token: int = _anim_begin(duration_s)
	tw.finished.connect(func() -> void: _anim_end(token))

func _ready() -> void:
	name = "UnitAnimator"
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe_connect(bus, &"unit_selected", _on_unit_selected)
	_safe_connect(bus, &"turn_started", _on_turn_started)
	_safe_connect(bus, &"unit_moved", _on_unit_moved)
	_safe_connect(bus, &"damage_dealt", _on_damage_dealt)
	_safe_connect(bus, &"unit_healed", _on_unit_healed)
	_safe_connect(bus, &"unit_eliminated", _on_unit_eliminated)
	_safe_connect(bus, &"move_performed", _on_move_performed)
	_safe_connect(bus, &"unit_spawned", _on_unit_spawned)

func _safe_connect(obj: Object, signal_name: StringName, callable: Callable) -> void:
	if obj != null and obj.has_signal(signal_name) and not obj.is_connected(signal_name, callable):
		obj.connect(signal_name, callable)

# --- Position tracking (feeds the glide start) ----------------------------

func _remember(unit) -> void:
	if unit is Node3D and is_instance_valid(unit):
		_last_world_pos[unit.get_instance_id()] = (unit as Node3D).global_position

func _on_unit_selected(unit = null, _position = null) -> void:
	_remember(unit)

func _on_turn_started(who = null) -> void:
	_remember(who)

## Every unit on the board announces itself here -- pre-placed ones at load and runtime
## reinforcements alike -- which makes this the one place that reaches ALL of them. The
## start is DEFERRED by a frame: a character unit builds its "CharacterModel" subtree in
## its own _ready, and _get_anim_root would otherwise find nothing to bob.
func _on_unit_spawned(unit = null, _runtime = null) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	call_deferred("_start_idle_bob", unit)

# --- Move glide -----------------------------------------------------------

func _on_unit_moved(unit = null, _from = null, _to = null) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var node := _get_anim_root(unit)
	# is_inside_tree as well as null: Node.create_tween() (in _begin_motion below) errors
	# with "Can't create Tween when not inside scene tree" on a detached node, and this
	# runs from a signal that can arrive while a unit is being torn down.
	if node == null or not node.is_inside_tree():
		_remember(unit)
		return

	# Glide relative to the model's fixed authored REST position (cached once), never
	# a live reading -- a live reading taken mid-animation would drift the model.
	var base: Vector3 = _base_pos(unit, node)

	# A walk clip animates the LEGS; the glide below still has to carry the model
	# across the tile, so these layer rather than replace each other. (play_clip
	# is itself a no-op when animations are off.)
	play_clip(unit, CLIP_WALK)

	var dest: Vector3 = (unit as Node3D).global_position
	var start: Vector3 = _last_world_pos.get(unit.get_instance_id(), dest)
	_last_world_pos[unit.get_instance_id()] = dest

	var offset := start - dest
	# Animations off, negligible move, or zero glide time -> snap to base instantly.
	if not _anims_on() or offset.length() < 0.001 or move_glide_time <= 0.0:
		_kill_motion(unit)
		node.position = base
		return
	var t: float = _scaled(move_glide_time)
	if t <= 0.0:
		_kill_motion(unit)
		node.position = base
		return

	# Place the model (visually) back at the old spot -- offset from its OWN base --
	# then slide it home. Only the child model moves; the unit node stays put.
	var tw := _begin_motion(unit, node)
	node.position = base + offset
	tw.set_trans(move_glide_trans).set_ease(move_glide_ease)
	tw.tween_property(node, "position", base, t)
	_track(tw, t)

# --- Hit flash ------------------------------------------------------------

func _on_damage_dealt(_attacker = null, defender = null, _damage = null) -> void:
	# Only the DEFENDER's reaction lives here now. The attacker's own cast animation
	# is driven by move_performed instead -- that fires for every move (including
	# non-damaging buffs/heals), so putting the caster animation there gives uniform
	# feedback and avoids animating the attacker twice on a damaging move.
	play_clip(defender, CLIP_HIT)
	_flash(defender)

# --- Move cast (every move) ------------------------------------------------

func _on_move_performed(caster = null, _move = null) -> void:
	# A model with an authored attack clip uses it; every other unit still gets
	# feedback via a procedural shake, so a buff/heal/status cast is never silent.
	if play_clip(caster, CLIP_ATTACK):
		return
	_shake(caster)

## Punchy lunge-and-recoil of the unit's model -- the universal "I attacked" tell.
## Drives the model root (CharacterModel/mesh) offset, so the unit's real position,
## health bars, and targeting are untouched. Animates relative to the model's OWN
## base position so an authored offset is preserved.
func _shake(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var node := _get_anim_root(unit)
	# See the glide path: a detached node cannot host a Tween.
	if node == null or not node.is_inside_tree():
		return
	var base: Vector3 = _base_pos(unit, node)
	# Animations off -> ensure the model sits at its base, no motion.
	if not _anims_on():
		_kill_motion(unit)
		node.position = base
		return
	var total: float = _scaled(move_shake_time)
	var d: float = move_shake_distance
	if total <= 0.0 or d <= 0.0:
		_kill_motion(unit)
		node.position = base
		return
	# Snap to the rest position FIRST. The AI almost always moves-then-attacks in one
	# action, so a move glide may have just displaced the model; without this reset the
	# lunge would start from the old cell and read as a slide-correction, not a strike.
	# Starting every lunge from base makes the attack a clean, always-visible tell.
	var seg: float = total / 4.0
	var tw := _begin_motion(unit, node)
	node.position = base
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position", base + Vector3(0.0, 0.0, -d), seg)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", base + Vector3(d * 0.5, 0.0, 0.0), seg)
	tw.tween_property(node, "position", base + Vector3(-d * 0.35, 0.0, 0.0), seg)
	tw.tween_property(node, "position", base, seg)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_track(tw, total)

func _flash(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	# is_inside_tree as well as null: mesh.create_tween() below errors on a detached node.
	if mesh == null or not mesh.is_inside_tree():
		return

	# Animations off -> no flash and no punch. We never touched material_override or
	# scale, so there is nothing to restore; the unit stays exactly as it is.
	if not _anims_on():
		return

	# Stop the idle breathe FIRST. On a placeholder capsule the bob and the punch below
	# drive the same node's `scale`, so the punch would otherwise capture a mid-breathe
	# scale as its base and leave the unit permanently stretched. Stopping snaps the model
	# back to rest, so base_scale below is always the authored one.
	_stop_idle_bob(unit)

	# A model with its own hit clip supplies the MOTION, so skip the squash punch
	# (two competing motions read as a glitch) but keep the colour flash, which
	# stays legible and reads as damage regardless of the animation.
	var has_hit_clip := _anim_player_for(unit) != null \
		and not _find_clip(_anim_player_for(unit), CLIP_HIT).is_empty()

	# Color flash via a temporary material_override; the prior override (usually
	# null) is captured and restored exactly, so the base look is untouched.
	var flash_dur: float = _scaled(hit_flash_time)
	if flash_dur > 0.0:
		var prev_override := mesh.material_override
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = hit_flash_color
		flash_mat.emission_enabled = true
		flash_mat.emission = hit_flash_color
		flash_mat.emission_energy_multiplier = hit_flash_emission
		mesh.material_override = flash_mat
		var ft := mesh.create_tween()
		ft.tween_interval(flash_dur)
		ft.tween_callback(func():
			if is_instance_valid(mesh):
				mesh.material_override = prev_override)
		_track(ft, flash_dur)
		_resume_idle_after(ft, unit)

	# Squash punch (always safe -- no material knowledge needed).
	var punch_dur: float = _scaled(hit_flash_time * 0.5)
	if hit_punch_scale > 1.0 and not has_hit_clip and punch_dur > 0.0:
		var base_scale := mesh.scale
		var pt := mesh.create_tween()
		pt.tween_property(mesh, "scale", base_scale * hit_punch_scale, punch_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_property(mesh, "scale", base_scale, punch_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_track(pt, punch_dur * 2.0)
		_resume_idle_after(pt, unit)

# --- Heal flash -----------------------------------------------------------

func _on_unit_healed(unit = null, _amount = null) -> void:
	# The healed unit's reaction: a positive green flash (+ a gentle hop), the
	# counterpart to the red hit flash. Fires for any restored HP; the emitter
	# already skips a 0-heal, so we always have something worth showing.
	_heal_flash(unit)

## Green emissive flash on the unit's mesh, the positive mirror of [method _flash].
## Restores the prior material_override exactly like the hit flash, and adds a small
## upward hop (NOT the damage squash) so the beat reads as "revived". Honors
## _anims_on() (no-op when animations are off) and feeds every duration through
## _scaled(). Self-contained: it drives the mesh via its OWN tweens and never touches
## the shared motion-tween / base-position caches.
func _heal_flash(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	# is_inside_tree as well as null: mesh.create_tween() below errors on a detached node.
	if mesh == null or not mesh.is_inside_tree():
		return

	# Animations off -> no flash and no hop. We never touched material_override or
	# position, so there is nothing to restore; the unit stays exactly as it is.
	if not _anims_on():
		return

	# Stop the idle breathe FIRST -- same reason as the hit flash, except here it is the
	# hop that would capture a mid-breathe `position` as its base and strand the model.
	_stop_idle_bob(unit)

	# Color flash via a temporary material_override; the prior override (usually
	# null) is captured and restored exactly, so the base look is untouched.
	var flash_dur: float = _scaled(heal_flash_time)
	if flash_dur > 0.0:
		var prev_override := mesh.material_override
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = heal_flash_color
		flash_mat.emission_enabled = true
		flash_mat.emission = heal_flash_color
		flash_mat.emission_energy_multiplier = heal_flash_emission
		mesh.material_override = flash_mat
		var ft := mesh.create_tween()
		ft.tween_interval(flash_dur)
		ft.tween_callback(func():
			if is_instance_valid(mesh):
				mesh.material_override = prev_override)
		_track(ft, flash_dur)
		_resume_idle_after(ft, unit)

	# Gentle upward hop (local +Y) and settle -- a small POSITIVE pop, restored to
	# the mesh's own current position so it leaves nothing displaced.
	var hop_dur: float = _scaled(heal_flash_time * 0.5)
	if heal_hop_height > 0.0 and hop_dur > 0.0:
		var base_mesh_pos := mesh.position
		var ht := mesh.create_tween()
		ht.tween_property(mesh, "position", base_mesh_pos + Vector3(0.0, heal_hop_height, 0.0), hop_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ht.tween_property(mesh, "position", base_mesh_pos, hop_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_track(ht, hop_dur * 2.0)
		_resume_idle_after(ht, unit)

# --- Death ----------------------------------------------------------------

func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	var id: int = unit.get_instance_id() if is_instance_valid(unit) else 0
	# Stop the idle breathe BEFORE anything else: it loops forever and drives the same
	# position/scale the death animation is about to take over, and stopping it snaps the
	# model to its rest pose so the death captures a clean base.
	_stop_idle_bob(unit)
	# An authored death clip replaces the shrink entirely -- shrinking a model
	# that is playing its own death animation just deletes the animation.
	var played_death: bool = play_clip(unit, CLIP_DEATH, false)
	# A lingering shake/glide tween would fight the death shrink; stop it and drop
	# the per-unit caches so a freed instance id can't leak or be reused stale.
	if is_instance_valid(unit):
		_kill_motion(unit)
	_last_world_pos.erase(id)
	_anim_players.erase(id)
	_anim_base.erase(id)
	_motion_tween.erase(id)
	_idle_tween.erase(id)
	_idle_base_scale.erase(id)
	if played_death:
		return
	# Animations off -> instant removal, no drama and no dead time; the emitter is
	# freeing the unit anyway, so there is no half-animated state to leave behind.
	if not _anims_on():
		return
	_procedural_death(unit)

## Dramatic, unmissable PROCEDURAL death (the fallback when a model ships no authored
## death clip): a bright colour FLASH + a brief POP up, THEN a slower SINK + shrink +
## fade. Best-effort and null-safe throughout -- the emitter may free the unit on the
## same frame, so every step re-guards is_instance_valid. Self-contained: it drives the
## model root and mesh via their OWN local tweens and never touches the shared motion-
## tween / base-position caches (those were already dropped for this id above). All
## durations pass through _scaled() so a slow battle lingers on the death.
func _procedural_death(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var node := _get_anim_root(unit)
	var mesh := _get_mesh(unit)

	# COLOUR FLASH + FADE on the visible mesh. A temporary emissive material_override is
	# installed and then faded to transparent -- no restore needed, the unit frees. We
	# enable transparency so the albedo alpha can carry the dissolve.
	var sink_t: float = _scaled(death_shrink_time)
	# is_inside_tree too: the death flash tweens are created ON the mesh, and this runs from
	# unit_eliminated -- the one moment the node is most likely to be leaving the tree.
	if mesh != null and mesh.is_inside_tree():
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = death_flash_color
		flash_mat.emission_enabled = true
		flash_mat.emission = death_flash_color
		flash_mat.emission_energy_multiplier = death_flash_emission
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = flash_mat
		var flash_dur: float = _scaled(death_flash_time)
		var mt := mesh.create_tween()
		# Snap bright, hold through the pop, then fade the emission and alpha out over
		# the sink so the body dissolves as it drops.
		if flash_dur > 0.0:
			mt.tween_interval(flash_dur)
		if sink_t > 0.0:
			mt.tween_property(flash_mat, "emission_energy_multiplier", 0.0, sink_t)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			mt.parallel().tween_property(flash_mat, "albedo_color",
				Color(death_flash_color.r, death_flash_color.g, death_flash_color.b, 0.0), sink_t)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_track(mt, flash_dur + sink_t)

	# MOTION on the model root: a brief POP up (the lurch of the killing blow), THEN a
	# slower SINK downward while shrinking to nothing. Uses the node's own local tween.
	if node != null and node.is_inside_tree():
		var base: Vector3 = node.position
		var rise_t: float = _scaled(death_rise_time)
		var dt := node.create_tween()
		if death_rise_height > 0.0 and rise_t > 0.0:
			dt.tween_property(node, "position",
				base + Vector3(0.0, death_rise_height, 0.0), rise_t)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if sink_t > 0.0:
			dt.tween_property(node, "position",
				base - Vector3(0.0, death_sink_distance, 0.0), sink_t)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			dt.parallel().tween_property(node, "scale", Vector3.ZERO, sink_t)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_track(dt, rise_t + sink_t)

# --- Idle bob ---------------------------------------------------------------

## Start (or restart) [param unit]'s looping idle breathe. Idempotent, and a no-op in
## every case where bobbing would be wrong: disabled, animations off, no model, a model
## not in the tree (a Tween cannot be created on one), or a REAL animation currently
## owning the model. Never registers in the busy registry -- see the section header.
func _start_idle_bob(unit) -> void:
	if not idle_bob_enabled or not _anims_on():
		return
	# is_instance_valid FIRST: this runs from a deferred call and from tween `finished`
	# callbacks, both of which can land after the unit has been freed.
	if unit == null or not is_instance_valid(unit) or not (unit is Node3D):
		return
	var id: int = unit.get_instance_id()
	var existing = _idle_tween.get(id, null)
	if existing is Tween and existing.is_valid():
		return
	# A glide / lunge owns `position` right now; that animation's finish restarts us.
	var motion = _motion_tween.get(id, null)
	if motion is Tween and motion.is_valid():
		return
	var node := _get_anim_root(unit)
	if node == null or not node.is_inside_tree():
		return

	var period: float = _scaled(idle_bob_period)
	if period <= 0.0:
		return

	# Rest pose. _base_pos caches the position on FIRST call, and the bob is normally the
	# first thing to touch the model, so the cache is seeded clean here; the scale gets the
	# same treatment through _idle_base_scale.
	var base: Vector3 = _base_pos(unit, node)
	if not _idle_base_scale.has(id):
		_idle_base_scale[id] = node.scale
	var base_scale: Vector3 = _idle_base_scale[id]
	node.position = base
	node.scale = base_scale

	# Per-unit desync: the instance id gives a stable 0..1 fraction, used BOTH to jitter
	# the cycle length (+/-15%) and to start the loop already part-way through.
	var fraction: float = float(id % 1000) / 1000.0
	var cycle: float = period * (0.85 + 0.3 * fraction)
	var half: float = cycle * 0.5
	# Top of the breathe: a touch TALLER and thinner (a chest filling), settling back to
	# the authored rest scale at the bottom. The loop therefore always ends on base_scale.
	var stretch := Vector3(
		base_scale.x * (1.0 - idle_bob_scale),
		base_scale.y * (1.0 + idle_bob_scale),
		base_scale.z * (1.0 - idle_bob_scale))

	var tween := node.create_tween()
	tween.set_loops()
	tween.tween_property(node, "position", base + Vector3(0.0, idle_bob_height, 0.0), half)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(node, "scale", stretch, half)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position", base, half)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(node, "scale", base_scale, half)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween[id] = tween
	# Advance into the loop so no two units are in step on their very first cycle.
	if tween.is_valid():
		tween.custom_step(fraction * cycle)


## Stop [param unit]'s idle breathe and SNAP the model back to its rest pose. Every real
## animation calls this first, so it never captures a mid-breathe position or scale as its
## own base -- that is what would otherwise strand the model off its unit.
func _stop_idle_bob(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var id: int = unit.get_instance_id()
	var tween = _idle_tween.get(id, null)
	if tween is Tween and tween.is_valid():
		tween.kill()
	if not _idle_tween.has(id):
		return
	_idle_tween.erase(id)
	if not (unit is Node3D):
		return
	var node := _get_anim_root(unit)
	if node == null:
		return
	node.position = _base_pos(unit, node)
	if _idle_base_scale.has(id):
		node.scale = _idle_base_scale[id]


## Restart [param unit]'s breathe once [param tween] (a real animation) finishes. The unit
## may be freed by then -- _start_idle_bob re-validates -- and a still-running motion tween
## makes it a no-op, so overlapping animations never double-start it.
func _resume_idle_after(tween: Tween, unit) -> void:
	if tween == null or not tween.is_valid():
		return
	tween.finished.connect(func() -> void:
		# A tween is STILL `is_valid()` at the instant it emits `finished` -- the engine
		# invalidates it a step later. So drop it from the motion registry here, or
		# _start_idle_bob would conclude a real animation still owns the model and
		# decline to restart, leaving the unit frozen for the rest of the battle.
		# A no-op for the flash/hop tweens, which were never registered as motion.
		if is_instance_valid(unit):
			var id: int = unit.get_instance_id()
			if _motion_tween.get(id, null) == tween:
				_motion_tween.erase(id)
		_start_idle_bob(unit))


# --- Helpers --------------------------------------------------------------

## Return a unit's primary MeshInstance3D, or null. Units in this project use a
## direct child named "MeshInstance3D"; we fall back to a recursive search so
## alternate rigs still animate.
func _get_mesh(unit) -> MeshInstance3D:
	if not is_instance_valid(unit) or not (unit is Node):
		return null
	var direct := (unit as Node).get_node_or_null("MeshInstance3D")
	if direct is MeshInstance3D:
		return direct
	return _find_mesh_recursive(unit as Node)

## Return the node to translate/scale for MOTION animations (shake, glide, death
## shrink), or null. Real character units nest their whole model under a direct
## child named "CharacterModel" (the instantiated .glb scene root); placeholder
## capsules use a direct "MeshInstance3D". We prefer those whole-model roots over
## the recursive first-MeshInstance3D search, which on a glb finds only a sub-part
## (one limb/cap) -- animating that shakes a fragment, not the unit. _get_mesh (the
## visible MeshInstance3D) stays the right target for the colour flash, which needs
## material_override on a mesh; this is only for motion.
func _get_anim_root(unit) -> Node3D:
	if not is_instance_valid(unit) or not (unit is Node):
		return null
	var model := (unit as Node).get_node_or_null("CharacterModel")
	if model is Node3D:
		return model as Node3D
	var direct := (unit as Node).get_node_or_null("MeshInstance3D")
	if direct is Node3D:
		return direct as Node3D
	# Fall back to the visible mesh (a Node3D) so alternate rigs still animate.
	return _find_mesh_recursive(unit as Node)

func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var found := _find_mesh_recursive(child)
		if found != null:
			return found
	return null

## The authored rest local-position of [param node], captured ONCE per unit. All
## motion animations settle back to this fixed value, so overlapping shakes/glides
## can never drift the model away from the unit.
func _base_pos(unit, node: Node3D) -> Vector3:
	var id: int = unit.get_instance_id()
	if not _anim_base.has(id):
		_anim_base[id] = node.position
	return _anim_base[id]

## Start a fresh motion tween on [param node], killing any in-flight motion tween
## for this unit first so the two never fight over `position`.
func _begin_motion(unit, node: Node3D) -> Tween:
	var id: int = unit.get_instance_id()
	var prev = _motion_tween.get(id, null)
	if prev is Tween and prev.is_valid():
		prev.kill()
	# The idle breathe drives the same `position` property -- stop it (which snaps the
	# model back to its rest pose) before the real animation takes over, and restart it
	# when that animation finishes. A killed tween never emits `finished`, but the
	# replacement motion tween created above will resume the bob in its place.
	_stop_idle_bob(unit)
	var tw := node.create_tween()
	_motion_tween[id] = tw
	_resume_idle_after(tw, unit)
	return tw

## Kill any in-flight motion tween for [param unit] (used before instant snaps).
func _kill_motion(unit) -> void:
	var id: int = unit.get_instance_id()
	var prev = _motion_tween.get(id, null)
	if prev is Tween and prev.is_valid():
		prev.kill()
	_motion_tween.erase(id)

# --- Authored clip bridge --------------------------------------------------

## The AnimationPlayer inside a unit's authored model, or null when it has none.
## Both the hit AND the miss are cached: re-walking the subtree on every signal
## for every capsule unit would be pure waste.
func _anim_player_for(unit) -> AnimationPlayer:
	if not use_authored_clips or not is_instance_valid(unit) or not (unit is Node):
		return null
	var key: int = unit.get_instance_id()
	if _anim_players.has(key):
		var cached = _anim_players[key]
		return cached if is_instance_valid(cached) else null
	var found: AnimationPlayer = _find_anim_player(unit as Node)
	_anim_players[key] = found
	return found


func _find_anim_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var deeper := _find_anim_player(child)
		if deeper != null:
			return deeper
	return null


## Resolve a logical clip name to a real animation on [param ap].
##
## Exporters rarely give you the bare name: glTF commonly emits "Armature|Idle",
## and casing varies. So match the exact name first, then the part after a "|",
## then any clip containing the base word -- all case-insensitively. Returns ""
## when the model has nothing suitable.
func _find_clip(ap: AnimationPlayer, base: String) -> String:
	if ap == null:
		return ""
	var want := base.to_lower()
	var names: PackedStringArray = ap.get_animation_list()
	for n in names:
		if String(n).to_lower() == want:
			return String(n)
	for n in names:
		var tail: String = String(n).get_slice("|", String(n).get_slice_count("|") - 1)
		if tail.to_lower() == want:
			return String(n)
	for n in names:
		if String(n).to_lower().contains(want):
			return String(n)
	return ""


## Play an authored clip on a unit. Returns true when one was actually found and
## started -- callers use that to decide whether the procedural fallback is still
## needed, so "no clip" degrades instead of leaving the unit with no feedback.
func play_clip(unit, base: String, loop_idle_after: bool = true) -> bool:
	# Authored clips are animation too: with animations off we skip them so the unit
	# holds its final state instead of playing an attack/walk in place. Callers treat
	# the false return as "no clip" and their procedural fallback is itself gated.
	if not _anims_on():
		return false
	var ap := _anim_player_for(unit)
	if ap == null:
		return false
	var clip := _find_clip(ap, base)
	if clip.is_empty():
		return false
	ap.play(clip, clip_blend_time)
	# Count a one-shot authored clip (walk/attack/hit/death) as busy for ~its length so
	# the AI driver waits for an authored death/attack the same way it waits for the
	# procedural tweens. IDLE is excluded -- it loops, so it must never register (it would
	# read as "forever busy"). No explicit end is wired: the entry's expiry (clamped to
	# ANIM_MAX_AGE_MS) clears it, which also caps a very long clip's hold.
	if base != CLIP_IDLE:
		var clip_anim := ap.get_animation(clip)
		if clip_anim != null:
			_anim_begin(clip_anim.length)
	if loop_idle_after and base != CLIP_IDLE and base != CLIP_DEATH:
		_queue_idle(ap)
	return true


## After a one-shot clip, fall back to idle when the model has one.
func _queue_idle(ap: AnimationPlayer) -> void:
	var idle := _find_clip(ap, CLIP_IDLE)
	if not idle.is_empty():
		ap.queue(idle)

# --- GameSettings bridge ---------------------------------------------------
#
# The optional GameSettings autoload governs presentation: whether animation runs
# at all, and how battle speed scales every authored duration. It is accessed
# null-safely -- when it is absent (e.g. headless tests) we behave as if animations
# are ON at scale 1.0, so nothing here changes for callers that never load it.

# Cached only on a HIT; a miss re-looks-up so late autoload registration is caught.
var _game_settings_cached: Node = null

func _game_settings() -> Node:
	if _game_settings_cached != null and is_instance_valid(_game_settings_cached):
		return _game_settings_cached
	_game_settings_cached = get_node_or_null("/root/GameSettings")
	return _game_settings_cached

## True unless GameSettings is present AND reports animations off. Absent settings
## default to ON so nothing that doesn't load the autoload is affected.
func _anims_on() -> bool:
	var gs := _game_settings()
	if gs == null or not gs.has_method("animations_on"):
		return true
	return bool(gs.animations_on())

## An authored duration scaled by battle speed. Absent settings pass the base value
## through unscaled; a returned 0.0 means "instant" and callers set the final state
## directly rather than tweening.
func _scaled(base_seconds: float) -> float:
	var gs := _game_settings()
	if gs == null or not gs.has_method("scaled_time"):
		return base_seconds
	return float(gs.scaled_time(base_seconds))
