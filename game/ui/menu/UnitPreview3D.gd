class_name UnitPreview3D
extends SubViewportContainer

## Small turntable render of a [CharacterResource]'s model_scene, auto-framed from
## the model's mesh bounds so any model size fits. [method show_character] returns
## false (and shows nothing) when the character has no usable model, so callers can
## fall back to an emblem.

@export var spin_speed: float = 0.6
@export var background_color: Color = Color(0, 0, 0, 0)

var viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.transparent_bg = background_color.a < 1.0
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if viewport.transparent_bg else Environment.BG_COLOR
	env.background_color = background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_camera.environment = env
	viewport.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.2
	key.light_color = Color(1.0, 0.95, 0.85)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.55, 0.7, 1.0)
	viewport.add_child(rim)


## Show [param chr]'s model; returns false when there is none to show.
func show_character(chr: CharacterResource) -> bool:
	_ensure()
	clear()
	if chr == null or chr.model_scene == null:
		return false
	var inst = chr.model_scene.instantiate()
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return false
	_model = inst
	_pivot.add_child(_model)
	_model.rotation_degrees.y = chr.model_yaw_deg
	if chr.model_scale > 0.0:
		_model.scale = Vector3.ONE * chr.model_scale
	_frame()
	return true


func clear() -> void:
	if _model != null and is_instance_valid(_model):
		_model.get_parent().remove_child(_model)
		_model.queue_free()
	_model = null
	if _pivot != null:
		_pivot.rotation = Vector3.ZERO


func _frame() -> void:
	var box := _bounds(_model, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	# Centre the model on the pivot so it spins in place.
	var c := box.get_center()
	_model.position -= Vector3(c.x, box.position.y, c.z)
	var h: float = maxf(box.size.y, maxf(box.size.x, box.size.z) * 0.8)
	var dist: float = h / (2.0 * tan(deg_to_rad(_camera.fov * 0.5))) * 1.35
	var look := Vector3(0, box.size.y * 0.5, 0)
	_camera.look_at_from_position(look + Vector3(0, h * 0.25, dist), look, Vector3.UP)


func _bounds(node: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is VisualInstance3D and not (node is Light3D):
		var b: AABB = local * (node as VisualInstance3D).get_aabb()
		out = b
		first = false
	for child in node.get_children():
		var cb := _bounds(child, local)
		if cb.size == Vector3.ZERO:
			continue
		if first:
			out = cb
			first = false
		else:
			out = out.merge(cb)
	return out


func _process(delta: float) -> void:
	if _pivot != null and _model != null:
		_pivot.rotate_y(spin_speed * delta)
