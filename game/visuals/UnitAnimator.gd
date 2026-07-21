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
	var node := _get_anim_root(unit)
	if node == null:
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
	if node == null:
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

func _flash(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	if mesh == null:
		return

	# Animations off -> no flash and no punch. We never touched material_override or
	# scale, so there is nothing to restore; the unit stays exactly as it is.
	if not _anims_on():
		return

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

	# Squash punch (always safe -- no material knowledge needed).
	var punch_dur: float = _scaled(hit_flash_time * 0.5)
	if hit_punch_scale > 1.0 and not has_hit_clip and punch_dur > 0.0:
		var base_scale := mesh.scale
		var pt := mesh.create_tween()
		pt.tween_property(mesh, "scale", base_scale * hit_punch_scale, punch_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_property(mesh, "scale", base_scale, punch_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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
	if mesh == null:
		return

	# Animations off -> no flash and no hop. We never touched material_override or
	# position, so there is nothing to restore; the unit stays exactly as it is.
	if not _anims_on():
		return

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

# --- Death ----------------------------------------------------------------

func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	var id: int = unit.get_instance_id() if is_instance_valid(unit) else 0
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
	if played_death:
		return
	if not (unit is Node3D) or not is_instance_valid(unit) or death_shrink_time <= 0.0:
		return
	var node := _get_anim_root(unit)
	if node == null:
		return
	# Animations off -> skip the shrink; the unit is being removed anyway, so there
	# is no half-animated state to worry about.
	if not _anims_on():
		return
	var t: float = _scaled(death_shrink_time)
	if t <= 0.0:
		return
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ZERO, t)\
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
	var tw := node.create_tween()
	_motion_tween[id] = tw
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
