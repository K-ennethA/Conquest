class_name AreaPrewarmer
extends RefCounted

## NEIGHBOUR PREWARM for story area travel (docs/STORY_MODE.md "Area travel & loading").
##
## Walking out of an area used to build the next one from scratch in one frame: ~0.9-1.6 s of
## GDScript (per-tile procedural geometry, the world skirt) with the screen frozen. Now, once an
## area is up, every area its present warps lead to is prepared in the BACKGROUND while you walk:
##
##   1. AREA   -- its area.tres (+ terrain) via [method ResourceLoader.load_threaded_request],
##                handed to StoryController's area cache.
##   2. SCENES -- the tile scenes it uses that are not loaded yet, the same way.
##   3. BUILD  -- its tiles' procedural geometry ([method MapLoader.prewarm_tile_geometry]) and its
##                world skirt ([method WorldSkirt.prewarm]) on the WorkerThreadPool.
##
## Results land in caches keyed by CONTENT, so the arrival build just picks them up (waiting for
## a task still running rather than redoing it); a wrong guess only wastes background work.
## Nothing here changes WHAT gets built -- areas, entities, encounter rolls and saves are
## untouched. Driven once per frame by StoryController ([method poll]): one short step per frame.
##
## It also keeps the BATTLE SCENES loaded for the session ([constant BATTLE_SCENES]): a trainer or
## the grass can start a fight on any step, and GameWorld.tscn alone took ~1.7 s to load
## synchronously on the first battle (the duel stage ~0.2 s). They are requested once the
## neighbours are ready and held until the session ends ([method release_held]).

enum Stage { AREA, SCENES, BUILD }

## Scenes a story battle changes to (StoryController.GAME_WORLD_SCENE, DuelController.STAGE_SCENE).
const BATTLE_SCENES: Array[String] = ["res://game/world/GameWorld.tscn", "res://game/duel/DuelStage.tscn"]

## Master switch (tests that count work, tools).
var enabled: bool = true

## Preload + hold [constant BATTLE_SCENES]. Off on the headless renderer (tests / CI boot their
## battles directly; a 1.7 s background load per suite would only slow them down).
var preload_battle_scenes: bool = DisplayServer.get_name() != "headless"

## area id -> {"stage": Stage, "scenes": Array (threaded scene loads in flight), "listed": bool}.
var _jobs: Dictionary = {}
## Battle scenes wanted / being loaded in the background / held (path -> PackedScene).
var _want_battle_scenes: bool = false
var _battle_loads: Array = []
var _held: Dictionary = {}
## False after [method release_held]: loads still in flight are collected and dropped.
var _holding: bool = false


## Queue every area [param area]'s present warps lead to (not [param area] itself).
func request_neighbours(area: OverworldAreaResource, state: StoryState) -> void:
	if not enabled or area == null:
		return
	_want_battle_scenes = preload_battle_scenes
	var ents: Array = area.present_entities(state) if state != null else area.entity_list()
	for e in ents:
		if e is WarpEntity:
			var target := String((e as WarpEntity).target_area)
			if not target.is_empty() and target != String(area.area_id):
				request(target)


## Queue area [param area_id] for prewarming (no-op when already queued).
func request(area_id: String) -> void:
	if not enabled or area_id.is_empty() or _jobs.has(area_id):
		return
	_jobs[area_id] = {"stage": Stage.AREA, "scenes": [], "listed": false}


## True while any area is still queued (its BUILD tasks may run on after this turns false).
func is_busy() -> bool:
	return not _jobs.is_empty()


## The area ids still queued (tests).
func pending_areas() -> Array:
	return _jobs.keys()


## One step of the oldest job, then collect finished worker tasks. Call once per frame.
func poll(story) -> void:
	TileMeshCache.poll()
	WorldSkirt.poll()
	_poll_battle_scenes()
	if _jobs.is_empty():
		return
	var area_id: String = _jobs.keys()[0]
	var job: Dictionary = _jobs[area_id]
	match int(job["stage"]):
		Stage.AREA:
			_step_area(story, area_id, job)
		Stage.SCENES:
			_step_scenes(story, area_id, job)
		Stage.BUILD:
			var area: OverworldAreaResource = story.load_area(area_id)
			if area != null and area.terrain != null:
				MapLoader.prewarm_tile_geometry(area.terrain)
				WorldSkirt.prewarm(area.terrain)
			_jobs.erase(area_id)


## Run every remaining step now and wait for the workers (shutdown, tests).
func finish(story) -> void:
	var guard := 0
	while not _jobs.is_empty() and guard < 10000:
		poll(story)
		guard += 1
	for p in _battle_loads:
		var ps := ResourceLoader.load_threaded_get(p) as PackedScene
		if ps != null and _holding:
			_held[p] = ps
	_battle_loads.clear()
	TileMeshCache.finish_pending()
	WorldSkirt.finish_pending()


## Let go of the held battle scenes (the session ended: back to the title).
func release_held() -> void:
	_want_battle_scenes = false
	_holding = false
	_held.clear()


## True when [param path] is loaded and held (tests / perf tools).
func is_held(path: String) -> bool:
	return _held.has(path)


func _poll_battle_scenes() -> void:
	if _want_battle_scenes and _jobs.is_empty() and enabled:
		_want_battle_scenes = false
		_holding = true
		for p in BATTLE_SCENES:
			if _held.has(p) or _battle_loads.has(p) or not ResourceLoader.exists(p):
				continue
			if ResourceLoader.load_threaded_request(p) == OK:
				_battle_loads.append(p)
	if _battle_loads.is_empty():
		return
	var still: Array = []
	for p in _battle_loads:
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(p)
		elif st == ResourceLoader.THREAD_LOAD_LOADED:
			var ps := ResourceLoader.load_threaded_get(p) as PackedScene
			if ps != null and _holding:
				_held[p] = ps
	_battle_loads = still


func _step_area(story, area_id: String, job: Dictionary) -> void:
	var path := OverworldAreaResource.path_for(area_id)
	var status := ResourceLoader.load_threaded_get_status(path)
	if story.has_area_cached(area_id):
		# Already loaded (or loaded synchronously by a warp meanwhile): release our request.
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		job["stage"] = Stage.SCENES
		return
	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			if not ResourceLoader.exists(path) or ResourceLoader.load_threaded_request(path) != OK:
				_jobs.erase(area_id)
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass
		ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(path) as OverworldAreaResource
			if res == null:
				_jobs.erase(area_id)
				return
			story.adopt_area(area_id, res)
			job["stage"] = Stage.SCENES
		_:
			_jobs.erase(area_id)


func _step_scenes(story, area_id: String, job: Dictionary) -> void:
	if not bool(job["listed"]):
		# First visit: request the tile scenes the area needs that nothing has loaded yet.
		job["listed"] = true
		var area: OverworldAreaResource = story.load_area(area_id)
		var wanted: Array = []
		var paths: Dictionary = {}   # path -> true (deduped)
		if area != null and area.terrain != null:
			for p in MapLoader.model_paths_for(area.terrain):
				if not MapLoader.is_tile_scene_resolved(p):
					paths[p] = true
			# NPCs drawn with a roster model: their CharacterResource pulls the .glb in.
			for e in area.entity_list():
				var cid := String(e.visual_character)
				if not cid.is_empty():
					paths[CharacterLibrary.ROSTER_DIR + cid + ".tres"] = true
			# Visible wild creatures stand on the map from the first frame: their species too.
			for z in area.zones():
				if not z.is_visible_mode():
					continue
				for entry in z.entries():
					var wid := String(entry.character_id)
					if not wid.is_empty():
						paths[CharacterLibrary.ROSTER_DIR + wid + ".tres"] = true
		for p in paths:
			if ResourceLoader.has_cached(p) or not ResourceLoader.exists(p):
				continue
			if ResourceLoader.load_threaded_request(p) == OK:
				wanted.append(p)
		job["scenes"] = wanted
	var still: Array = []
	for p in job["scenes"]:
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(p)
		elif st == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(p)
	job["scenes"] = still
	if still.is_empty():
		job["stage"] = Stage.BUILD
