extends Node

class_name PortraitCache

## Captures a head-and-shoulders portrait of a roster character FROM ITS REAL 3D MODEL
## (game/characters/CharacterResource.model_scene -- the same asset the mapmaker spawn
## preview instantiates) and hands back a Texture2D, so UI panels can show real art
## instead of the element-monogram placeholder.
##
## LIFECYCLE: this is deliberately NOT an autoload. [method get_portrait] / [method get_cached]
## find (or lazily create) a single GROUP-discoverable instance parented under the current
## scene root -- see [method _find_or_create_instance]. That keeps the capture SubViewport
## (and its own isolated World3D) alive only while a scene that wants portraits is running,
## and means a scene change naturally tears it down with the rest of that scene's tree.
##
## USAGE (async by callback -- a capture takes at least two frames, so this can never be a
## synchronous getter):
##   var cached: Texture2D = PortraitCache.get_cached(id)     # already-resolved, or null
##   PortraitCache.get_portrait(id, func(tex): ...)            # resolves (disk or capture),
##                                                              # then calls back exactly once
## Callers keep their monogram/placeholder visible until the callback fires, then swap it in
## -- see UnitInfoPanel / TurnQueue / CharacterSelect.
##
## CACHING, two layers:
##   1. In-memory, for the life of this instance -- every caller asking for the same id after
##      the first gets the same Texture2D with no disk hit.
##   2. On disk at user://cache/portraits/<CACHE_VERSION>_<id>.png, load-first -- a portrait
##      captured in a PAST run is loaded straight off disk instead of re-rendered. Bumping
##      [constant CACHE_VERSION] changes the filename every id resolves to, so old captures
##      (stale framing/lighting) are simply never read again; nothing needs to be deleted.
##
## CAPTURE: an offscreen 256x256 SubViewport with its own World3D (so it neither lights nor
## is lit by the live scene), transparent background, UPDATE_ONCE + two awaited frames so the
## just-placed model and camera are fully committed before the pixels are read. The model is
## instantiated and oriented exactly like [code]MapMakerScene._instantiate_character_model[/code]
## / [code]Unit._orient_character_model[/code] (authored model_yaw_deg + model_scale, feet at
## the origin), PLUS 180 degrees so the character faces the capture camera (see the facing_yaw
## convention documented on tile_objects/units/unit.gd -- the authored correction alone leaves
## a unit facing world -Z, away from the south-side camera) and a further +15 degrees so the
## portrait reads as a flattering three-quarter turn rather than a flat mugshot. The camera
## frames the UPPER ~35% of the model's world-space AABB (its head and shoulders) so that
## band fills ~80% of the frame height, computed from the camera's FOV rather than a fixed
## distance so it works for a mushroom and a boss alike.
##
## HEADLESS: [constant DisplayServer.get_name] == "headless" (this project's established
## headless check -- see game/items/ItemToast.gd, game/profile/PlayerProfile.gd) gates the
## SubViewport/Camera3D/DirectionalLight3D construction entirely. A miss there resolves to
## null through the ordinary callback path -- never an engine error -- so headless tests and
## CI runs are silent and callers' monogram fallbacks simply stay up.
##
## QUEUEING: captures run ONE AT A TIME (`_busy`), each holding the single shared SubViewport
## and model instance in turn. Concurrent requests for the SAME id are coalesced onto one
## in-flight resolution rather than launching a second capture.


# --- Identity / discovery ----------------------------------------------------
const GROUP_NAME: StringName = &"portrait_cache"

# --- Disk cache ---------------------------------------------------------------
const DISK_DIR: String = "user://cache/portraits/"
## Bump this to invalidate every previously-captured portrait without touching disk --
## the filename changes, so old files are simply never looked at again.
const CACHE_VERSION: String = "v1"

# --- Capture geometry -----------------------------------------------------------
const CAPTURE_SIZE: int = 256
## Fraction of the model's total world-space height treated as "head and shoulders".
const HEAD_REGION_FRACTION: float = 0.35
## That head region fills this fraction of the captured frame's height.
const FRAME_FILL_FRACTION: float = 0.80
## Narrow-ish FOV (a portrait-lens angle) so a head shot doesn't fisheye.
const CAPTURE_FOV_DEG: float = 30.0
## Extra yaw (degrees) on top of the character's authored front-facing correction, for a
## three-quarter look instead of a flat front mugshot.
const CAPTURE_YAW_DEG: float = 15.0

# --- In-memory state -----------------------------------------------------------
## character_id (StringName) -> resolved Texture2D. Never holds a null entry -- a failed
## resolution is simply absent, so a later request can retry it.
var _memory_cache: Dictionary = {}
## character_id (StringName) -> Array[Callable] still waiting on that id's resolution.
## Coalesces concurrent requests for the same id onto one capture.
var _pending_callbacks: Dictionary = {}
## FIFO of ids waiting their turn at the single shared SubViewport.
var _queue: Array[StringName] = []
## True while a disk-load or capture is in flight for the head of [member _queue].
var _busy: bool = false

# --- Capture rig (built lazily; null in headless / before the first capture) ---
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _key_light: DirectionalLight3D = null
var _rim_light: DirectionalLight3D = null
var _model_root: Node3D = null


func _ready() -> void:
	add_to_group(GROUP_NAME)


# =============================================================================
#  Public API (static -- see class doc for why this isn't an autoload)
# =============================================================================

## The portrait for [param character_id] if it is ALREADY resolved in memory this process --
## never touches disk, never triggers a capture. Null when nothing has resolved it yet (or
## there is no live instance at all); callers keep showing their fallback in that case.
static func get_cached(character_id) -> Texture2D:
	var inst: PortraitCache = _find_instance()
	if inst == null:
		return null
	var key: StringName = _key_of(character_id)
	if String(key).is_empty():
		return null
	return inst._memory_cache.get(key, null)


## Resolve the portrait for [param character_id] (memory -> disk -> live capture, in that
## order) and invoke [param cb] with the result EXACTLY once. [param cb] receives null when
## the id is empty, no live scene tree is reachable, rendering is unavailable (headless), the
## character has no model_scene, or the model failed to instantiate -- callers keep their
## monogram fallback in every one of those cases.
static func get_portrait(character_id, cb: Callable) -> void:
	if not cb.is_valid():
		return
	var key: StringName = _key_of(character_id)
	if String(key).is_empty():
		cb.call(null)
		return

	var inst: PortraitCache = _find_or_create_instance()
	if inst == null:
		cb.call(null)
		return

	if inst._memory_cache.has(key):
		cb.call(inst._memory_cache[key])
		return

	inst._enqueue(key, cb)


## Disk-cache path a resolved portrait for [param character_id] would live at, under the
## current [constant CACHE_VERSION]. Exposed so tests can pre-seed / inspect the exact file
## PortraitCache itself reads and writes, without duplicating the naming rule.
static func disk_path(character_id) -> String:
	return _disk_path_for_key(_key_of(character_id))


## Test/tooling hook: drop the live capture-service instance, if any -- frees its SubViewport
## and every in-memory portrait. Never touches the disk cache. A test that calls
## [method get_portrait] must call this from after_each, or the Node this creates under the
## scene root leaks into the next suite (see tests/README.md on orphans / global state).
static func reset() -> void:
	var inst: PortraitCache = _find_instance()
	if inst == null:
		return
	var parent: Node = inst.get_parent()
	if parent != null:
		parent.remove_child(inst)
	inst.free()


# =============================================================================
#  Instance discovery
# =============================================================================

static func _key_of(character_id) -> StringName:
	return StringName(character_id) if character_id != null else &""


static func _find_instance() -> PortraitCache:
	var loop: Object = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop as SceneTree
	var existing: Node = tree.get_first_node_in_group(GROUP_NAME)
	if existing != null and is_instance_valid(existing):
		return existing as PortraitCache
	return null


## Finds the group-registered instance, or creates one parented under the current scene
## (falling back to the tree root if there is no current scene yet). Null only when there is
## no SceneTree at all to attach to (e.g. a bare RefCounted-only test harness).
static func _find_or_create_instance() -> PortraitCache:
	var existing: PortraitCache = _find_instance()
	if existing != null:
		return existing

	var loop: Object = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop as SceneTree

	var parent: Node = tree.current_scene
	if parent == null:
		parent = tree.root
	if parent == null:
		return null

	var inst: PortraitCache = PortraitCache.new()
	inst.name = "PortraitCache"
	parent.add_child(inst)
	return inst


# =============================================================================
#  Queue
# =============================================================================

func _enqueue(key: StringName, cb: Callable) -> void:
	if _pending_callbacks.has(key):
		(_pending_callbacks[key] as Array).append(cb)
		return  # already queued or in-flight; that resolution will call every waiting cb
	_pending_callbacks[key] = [cb]
	_queue.append(key)
	_process_queue()


func _process_queue() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var key: StringName = _queue.pop_front()
	_resolve_one(key)


## One capture (or disk load) at a time -- see class doc's QUEUEING note. Contains `await`,
## so calling it without awaiting (as [method _process_queue] does) simply starts it; it
## resumes and calls [method _finish] on its own once the frames it awaits land.
func _resolve_one(key: StringName) -> void:
	var disk_tex: Texture2D = _load_from_disk(key)
	if disk_tex != null:
		_finish(key, disk_tex)
		return

	var tex: Texture2D = await _capture(key)
	if tex != null:
		_save_to_disk(key, tex)
	_finish(key, tex)


func _finish(key: StringName, tex: Texture2D) -> void:
	if tex != null:
		_memory_cache[key] = tex

	var callbacks: Array = _pending_callbacks.get(key, [])
	_pending_callbacks.erase(key)
	for cb in callbacks:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(tex)

	_busy = false
	_process_queue()


# =============================================================================
#  Disk cache
# =============================================================================

static func _disk_path_for_key(key: StringName) -> String:
	return "%s%s_%s.png" % [DISK_DIR, CACHE_VERSION, String(key)]


func _load_from_disk(key: StringName) -> Texture2D:
	var path: String = _disk_path_for_key(key)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _save_to_disk(key: StringName, tex: Texture2D) -> void:
	var img: Image = tex.get_image()
	if img == null:
		return
	if not DirAccess.dir_exists_absolute(DISK_DIR):
		DirAccess.make_dir_recursive_absolute(DISK_DIR)
	img.save_png(_disk_path_for_key(key))


# =============================================================================
#  Capture
# =============================================================================

## Renders one portrait. Returns null (never raises) when: rendering is unavailable
## (headless), the character/model can't be resolved, or the model_scene doesn't instance
## to a Node3D. Takes at least two engine frames -- callers reach this only through
## [method get_portrait]'s callback, never a synchronous return.
func _capture(key: StringName) -> Texture2D:
	var character: CharacterResource = CharacterLibrary.get_character(key)
	if character == null or character.model_scene == null:
		return null

	if not _ensure_rig():
		return null

	if not _spawn_model(character):
		return null

	# Let the just-added model's transform (and its children's global_transform) settle
	# before measuring bounds off it.
	await get_tree().process_frame

	_frame_camera(_measure_world_aabb(_model_root))

	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = _viewport.get_texture().get_image()
	_clear_model()

	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Builds the shared SubViewport + camera + two DirectionalLights once. Returns false (no
## error) when rendering is unavailable -- the established headless check in this codebase
## (see game/items/ItemToast.gd), so this never even TOUCHES viewport/texture APIs headless.
func _ensure_rig() -> bool:
	if _viewport != null and is_instance_valid(_viewport):
		return true
	if DisplayServer.get_name() == "headless":
		return false

	_viewport = SubViewport.new()
	_viewport.name = "CaptureViewport"
	_viewport.size = Vector2i(CAPTURE_SIZE, CAPTURE_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.58, 1.0)
	env.ambient_light_energy = 0.55

	_camera = Camera3D.new()
	_camera.name = "CaptureCamera"
	_camera.fov = CAPTURE_FOV_DEG
	_camera.near = 0.05
	_camera.far = 50.0
	_camera.environment = env
	_viewport.add_child(_camera)

	# Key: warm, upper-front. Rim: cool, from behind the (camera-facing) model, so its
	# silhouette edges pick up a highlight against the transparent backdrop.
	_key_light = DirectionalLight3D.new()
	_key_light.name = "KeyLight"
	_key_light.light_energy = 1.15
	_key_light.light_color = Color(1.0, 0.97, 0.9)
	_viewport.add_child(_key_light)
	_key_light.look_at_from_position(Vector3(1.6, 2.4, 2.0), Vector3.ZERO, Vector3.UP)

	_rim_light = DirectionalLight3D.new()
	_rim_light.name = "RimLight"
	_rim_light.light_energy = 0.65
	_rim_light.light_color = Color(0.75, 0.85, 1.0)
	_viewport.add_child(_rim_light)
	_rim_light.look_at_from_position(Vector3(-1.2, 1.8, -2.4), Vector3.ZERO, Vector3.UP)

	return true


## Instance + orient [param character]'s model exactly like the mapmaker spawn preview /
## live Unit (authored model_yaw_deg + model_scale, feet at the origin) -- see
## MapMakerScene._instantiate_character_model and Unit._orient_character_model. Adds 180
## degrees so the character faces the capture camera (the authored correction alone leaves
## it facing world -Z -- see the facing_yaw convention on tile_objects/units/unit.gd) plus
## CAPTURE_YAW_DEG for a three-quarter turn. Returns false when the scene doesn't instance
## to a Node3D (freeing the bad instance itself), never an engine error.
func _spawn_model(character: CharacterResource) -> bool:
	_clear_model()

	var instance: Node = character.model_scene.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return false

	_model_root = instance as Node3D
	_viewport.add_child(_model_root)

	var yaw: float = character.model_yaw_deg if "model_yaw_deg" in character else 0.0
	var model_scale: float = character.model_scale if "model_scale" in character else 1.0
	_model_root.position = Vector3.ZERO
	_model_root.rotation = Vector3(
		0.0,
		deg_to_rad(yaw) + PI + deg_to_rad(CAPTURE_YAW_DEG),
		0.0)
	_model_root.scale = Vector3.ONE * maxf(0.05, model_scale)
	return true


func _clear_model() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		if _viewport != null and is_instance_valid(_viewport):
			_viewport.remove_child(_model_root)
		_model_root.queue_free()
	_model_root = null


## Point the camera so the upper [constant HEAD_REGION_FRACTION] of [param aabb] (world
## space) fills [constant FRAME_FILL_FRACTION] of the frame height, distance derived from
## the camera's FOV so this works at any model scale.
func _frame_camera(aabb: AABB) -> void:
	if _camera == null:
		return

	var top_y: float = aabb.position.y + aabb.size.y
	var head_h: float = maxf(aabb.size.y * HEAD_REGION_FRACTION, 0.05)
	var target_y: float = top_y - head_h * 0.5
	var center_x: float = aabb.position.x + aabb.size.x * 0.5
	var center_z: float = aabb.position.z + aabb.size.z * 0.5

	var frame_h: float = head_h / FRAME_FILL_FRACTION
	var half_fov: float = deg_to_rad(CAPTURE_FOV_DEG) * 0.5
	var distance: float = maxf((frame_h * 0.5) / tan(half_fov), 0.3)

	var target := Vector3(center_x, target_y, center_z)
	var cam_pos := target + Vector3(0.0, 0.0, distance)
	_camera.look_at_from_position(cam_pos, target, Vector3.UP)


## Combined world-space AABB of every VisualInstance3D under [param root] (mesh bounds, not
## skin-deformed -- close enough to frame a static capture pose). Falls back to a generic
## humanoid-sized box when the model has no visual instances at all (an empty/placeholder
## scene), so framing never divides by a zero-size box.
func _measure_world_aabb(root: Node3D) -> AABB:
	var acc := {"aabb": AABB(), "found": false}
	_accumulate_aabb(root, acc)
	if not acc["found"]:
		return AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8))
	return acc["aabb"]


func _accumulate_aabb(node: Node, acc: Dictionary) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var local_aabb: AABB = vi.get_aabb()
		if local_aabb.size.length_squared() > 0.0:
			var world_aabb: AABB = vi.global_transform * local_aabb
			if acc["found"]:
				acc["aabb"] = (acc["aabb"] as AABB).merge(world_aabb)
			else:
				acc["aabb"] = world_aabb
				acc["found"] = true

	for child in node.get_children():
		_accumulate_aabb(child, acc)
