@tool
extends RefCounted
class_name TileMeshCache

## SHARED GEOMETRY CACHE for the procedural tile builders ([LowPolyTileBuilder],
## [PavedTileBuilder]). Their meshes are pure functions of (builder, style, world cell): the
## same cell of the same style always gets the same geometry, and every story area (and every
## replay of a battle board) starts at the world origin. So each distinct cell's meshes are
## built ONCE per process and shared by every later tile standing there -- rebuilding them was
## ~0.5 ms of GDScript per tile per load, most of an area's build time.
##
## Keys are [Vector4i] ([method key]). Three tiers per key:
##   * meshes  -- ready-to-use ArrayMeshes (part name -> ArrayMesh);
##   * ready   -- surface arrays a background [method prewarm] made, not yet uploaded (the mesh is
##                created when a tile first needs it, a few at a time as the board builds, rather
##                than hundreds in one gameplay frame);
##   * pending -- a WorkerThreadPool task still computing it (a tile that needs it waits for it
##                instead of computing it twice).

## Builder kinds (the key's first component is kind * 64 + style).
const KIND_LOWPOLY := 1
const KIND_PAVED := 2

## Soft cap on cached cells. A cell is ~900 flat-shaded vertices (~35 KB of GPU buffers); the
## four story areas together use ~1.35 k cells (~45 MB). The whole cache is dropped when full
## (then rebuilt on demand), which bounds it at ~90 MB even across many battle boards.
const MAX_CELLS := 2500

static var _meshes: Dictionary = {}
static var _ready: Dictionary = {}
static var _pending: Dictionary = {}
## task id -> the Dictionary its worker fills (key -> {part: arrays}).
static var _tasks: Dictionary = {}
## How many cells had to be computed ON THE MAIN THREAD (nothing cached, nothing prewarmed) --
## the perf regression test asserts a prewarmed area boots with none.
static var main_thread_computes: int = 0


static func key(kind: int, style: int, kx: int, kz: int, ky: int = 0) -> Vector4i:
	return Vector4i(kind * 64 + style, kx, kz, ky)


## True when [param k] is cached, waiting as arrays, or being computed.
static func has(k: Vector4i) -> bool:
	return _meshes.has(k) or _ready.has(k) or _pending.has(k)


## The meshes of [param k] (part -> ArrayMesh). [param compute] (main thread, no arguments,
## returning part -> surface arrays) runs only when nothing is cached or in flight.
static func meshes_for(k: Vector4i, compute: Callable) -> Dictionary:
	if _meshes.has(k):
		return _meshes[k]
	if _pending.has(k):
		_harvest(int(_pending[k]))
	var arrays: Dictionary = {}
	if _ready.has(k):
		arrays = _ready[k]
		_ready.erase(k)
	else:
		arrays = compute.call()
		main_thread_computes += 1
	var out: Dictionary = {}
	for part in arrays:
		out[part] = mesh_from_arrays(arrays[part])
	if _meshes.size() >= MAX_CELLS:
		_meshes.clear()
	_meshes[k] = out
	return out


## Compute the arrays of every key in [param keys] not already known, on the WorkerThreadPool.
## [param batch] is a STATIC, thread-safe function (keys: Array, result: Dictionary) that fills
## result[key] = {part: surface arrays}. Returns the task id, or -1 when nothing was left to do.
static func prewarm(keys: Array, batch: Callable) -> int:
	var todo: Array = []
	for k in keys:
		if not has(k):
			todo.append(k)
	if todo.is_empty():
		return -1
	var result: Dictionary = {}
	var id: int = WorkerThreadPool.add_task(batch.bind(todo, result), false, "TileMeshCache.prewarm")
	_tasks[id] = result
	for k in todo:
		_pending[k] = id
	return id


## Collect every finished prewarm task (main thread, once per frame). True while any runs.
static func poll() -> bool:
	for id in _tasks.keys():
		if WorkerThreadPool.is_task_completed(id):
			_harvest(id)
	return not _tasks.is_empty()


## Block until every prewarm task is done and collected (shutdown, tests).
static func finish_pending() -> void:
	for id in _tasks.keys():
		_harvest(id)


static func _harvest(id: int) -> void:
	if not _tasks.has(id):
		return
	WorkerThreadPool.wait_for_task_completion(id)
	var result: Dictionary = _tasks[id]
	_tasks.erase(id)
	if _ready.size() + result.size() > MAX_CELLS:
		_ready.clear()
	for k in result:
		if _pending.get(k, -1) == id:
			_pending.erase(k)
		if not _meshes.has(k):
			_ready[k] = result[k]


## An ArrayMesh from surface arrays (an empty mesh for []).
static func mesh_from_arrays(arrays: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	if arrays.is_empty():
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Cells with uploaded meshes / with arrays waiting (tests, perf tools).
static func cached_count() -> int:
	return _meshes.size()


static func ready_count() -> int:
	return _ready.size()


## Drop everything (tests / tools; never needed in play).
static func clear() -> void:
	finish_pending()
	_meshes.clear()
	_ready.clear()
