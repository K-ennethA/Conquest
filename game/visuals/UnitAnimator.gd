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
@export_range(0.0, 1.5, 0.01) var move_glide_time: float = 0.18
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

# --- Move shake -----------------------------------------------------------
@export_group("Move Shake")
## Default caster feedback for ANY move (attack, buff, heal, status) on a model
## with no authored "attack" clip: a quick side-to-side jitter of the mesh, so no
## move is ever silent. A model that ships an attack clip plays that instead.
@export_range(0.0, 0.6, 0.01) var move_shake_distance: float = 0.14
## Total seconds of the shake.
@export_range(0.0, 1.0, 0.01) var move_shake_time: float = 0.26

# --- Death ----------------------------------------------------------------
@export_group("Death")
## Seconds to shrink a unit's mesh on elimination. Best-effort: if the emitter
## frees the unit on the same frame, there is nothing left to animate.
@export_range(0.0, 1.5, 0.01) var death_shrink_time: float = 0.25

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

func _ready() -> void:
	name = "UnitAnimator"
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe_connect(bus, &"unit_selected", _on_unit_selected)
	_safe_connect(bus, &"turn_started", _on_turn_started)
	_safe_connect(bus, &"unit_moved", _on_unit_moved)
	_safe_connect(bus, &"damage_dealt", _on_damage_dealt)
	_safe_connect(bus, &"unit_eliminated", _on_unit_eliminated)
	_safe_connect(bus, &"move_performed", _on_move_performed)

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

# --- Move glide -----------------------------------------------------------

func _on_unit_moved(unit = null, _from = null, _to = null) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	if mesh == null:
		_remember(unit)
		return

	# A walk clip animates the LEGS; the glide below still has to carry the model
	# across the tile, so these layer rather than replace each other.
	play_clip(unit, CLIP_WALK)

	var dest: Vector3 = (unit as Node3D).global_position
	var start: Vector3 = _last_world_pos.get(unit.get_instance_id(), dest)
	_last_world_pos[unit.get_instance_id()] = dest

	var offset := start - dest
	if offset.length() < 0.001 or move_glide_time <= 0.0:
		mesh.position = Vector3.ZERO
		return

	# Place the mesh (visually) back at the old spot, then slide it home to the
	# unit's real position. Only the child mesh moves; the unit node stays put.
	mesh.position = offset
	var tw := mesh.create_tween()
	tw.set_trans(move_glide_trans).set_ease(move_glide_ease)
	tw.tween_property(mesh, "position", Vector3.ZERO, move_glide_time)

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

## Quick side-to-side jitter of the unit's mesh -- the universal "I did something"
## tell. Uses the mesh child offset (like the glide), so the unit's real position,
## health bars, and targeting are untouched.
func _shake(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	if mesh == null or move_shake_time <= 0.0 or move_shake_distance <= 0.0:
		return
	var base: Vector3 = mesh.position
	var d: float = move_shake_distance
	var seg: float = move_shake_time / 4.0
	var tw := mesh.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(mesh, "position", base + Vector3(d, 0.0, 0.0), seg)
	tw.tween_property(mesh, "position", base + Vector3(-d, 0.0, 0.0), seg)
	tw.tween_property(mesh, "position", base + Vector3(d * 0.5, 0.0, 0.0), seg)
	tw.tween_property(mesh, "position", base, seg)

func _flash(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	if mesh == null:
		return

	# A model with its own hit clip supplies the MOTION, so skip the squash punch
	# (two competing motions read as a glitch) but keep the colour flash, which
	# stays legible and reads as damage regardless of the animation.
	var has_hit_clip := _anim_player_for(unit) != null \
		and not _find_clip(_anim_player_for(unit), CLIP_HIT).is_empty()

	# Color flash via a temporary material_override; the prior override (usually
	# null) is captured and restored exactly, so the base look is untouched.
	if hit_flash_time > 0.0:
		var prev_override := mesh.material_override
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = hit_flash_color
		flash_mat.emission_enabled = true
		flash_mat.emission = hit_flash_color
		flash_mat.emission_energy_multiplier = hit_flash_emission
		mesh.material_override = flash_mat
		var ft := mesh.create_tween()
		ft.tween_interval(hit_flash_time)
		ft.tween_callback(func():
			if is_instance_valid(mesh):
				mesh.material_override = prev_override)

	# Squash punch (always safe -- no material knowledge needed).
	if hit_punch_scale > 1.0 and not has_hit_clip:
		var base_scale := mesh.scale
		var pt := mesh.create_tween()
		pt.tween_property(mesh, "scale", base_scale * hit_punch_scale, hit_flash_time * 0.5)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_property(mesh, "scale", base_scale, hit_flash_time * 0.5)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# --- Death ----------------------------------------------------------------

func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	var id: int = unit.get_instance_id() if is_instance_valid(unit) else 0
	# An authored death clip replaces the shrink entirely -- shrinking a model
	# that is playing its own death animation just deletes the animation.
	var played_death: bool = play_clip(unit, CLIP_DEATH, false)
	_last_world_pos.erase(id)
	_anim_players.erase(id)
	if played_death:
		return
	if not (unit is Node3D) or not is_instance_valid(unit) or death_shrink_time <= 0.0:
		return
	var mesh := _get_mesh(unit)
	if mesh == null:
		return
	var t := mesh.create_tween()
	t.tween_property(mesh, "scale", Vector3.ZERO, death_shrink_time)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

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

func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var found := _find_mesh_recursive(child)
		if found != null:
			return found
	return null

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
	var ap := _anim_player_for(unit)
	if ap == null:
		return false
	var clip := _find_clip(ap, base)
	if clip.is_empty():
		return false
	ap.play(clip, clip_blend_time)
	if loop_idle_after and base != CLIP_IDLE and base != CLIP_DEATH:
		_queue_idle(ap)
	return true


## After a one-shot clip, fall back to idle when the model has one.
func _queue_idle(ap: AnimationPlayer) -> void:
	var idle := _find_clip(ap, CLIP_IDLE)
	if not idle.is_empty():
		ap.queue(idle)
