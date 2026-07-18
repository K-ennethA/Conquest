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

# --- Death ----------------------------------------------------------------
@export_group("Death")
## Seconds to shrink a unit's mesh on elimination. Best-effort: if the emitter
## frees the unit on the same frame, there is nothing left to animate.
@export_range(0.0, 1.5, 0.01) var death_shrink_time: float = 0.25

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
	_flash(defender)

func _flash(unit) -> void:
	if not (unit is Node3D) or not is_instance_valid(unit):
		return
	var mesh := _get_mesh(unit)
	if mesh == null:
		return

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
	if hit_punch_scale > 1.0:
		var base_scale := mesh.scale
		var pt := mesh.create_tween()
		pt.tween_property(mesh, "scale", base_scale * hit_punch_scale, hit_flash_time * 0.5)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_property(mesh, "scale", base_scale, hit_flash_time * 0.5)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# --- Death ----------------------------------------------------------------

func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	_last_world_pos.erase(unit.get_instance_id() if is_instance_valid(unit) else 0)
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
