class_name OverworldController
extends Node3D

## THE WALKABLE SCENE (docs/design/OVERWORLD.md §4.3) -- root script of OverworldScene.tscn, and
## the live story-script HOST ([StoryScriptHost]'s method set).
##
## Boot: ask StoryController for the area + arrival -> MapLoader builds the terrain exactly as a
## battle board (tiles, WorldSkirt, TerrainMask) -> WorldLook lights it -> [OverworldGrid] from
## the terrain + present entities -> actors (hero, NPCs, props) -> HUD -> hand the controller
## this host (a script paused on a battle resumes here) -> on_enter scripts, trainer sight.
##
## Per frame (no script running, no overlay up): the held direction (cursor_* or camera_pan_*:
## arrows, WASD, d-pad, both sticks) steps the hero ONE CELL at a time -- a tap on a new
## direction turns in place, a hold walks, fast_forward (Shift / R3) runs. Each step costs its
## walk / run seconds even with animations off (the hero then snaps a cell per step instead of
## gliding) -- never a cell per frame. On arrival:
## warps -> trigger zones -> trainer sight -> the grass roll (only if nothing above fired).
## Confirm uses what the hero faces; a tap / click walks there (A*), and a tap on an NPC walks
## next to it and talks. map_menu / cancel opens the Journey menu.

const STEP_SOUND_EVENT := &"sfx_footstep"

var story = null
var area: OverworldAreaResource = null
var grid: OverworldGrid = null
var player: OverworldActor = null
var camera: OverworldCamera = null
var hud: OverworldHUD = null
var journey: JourneyMenu = null
var map_loader: MapLoader = null

var _state: StoryState = null
var _ruleset: StoryRuleset = null
## entity id -> OverworldActor (only entities that have an actor).
var _actors: Dictionary = {}
var _dialogue: StoryDialogue = null
var _cursor: Node3D = null
var _moving: bool = false
var _held_dir: Vector2i = Vector2i.ZERO
var _held_time: float = 0.0
var _turned_this_press: bool = false
var _walk_streak: bool = false
var _tap_path: Array[Vector3i] = []
var _tap_interact_cell: Vector3i = Cells.INVALID
## Seconds before the next INPUT-driven step (held direction / tap path) may start. Every step
## costs its walk / run time even with animations off, where the actor snaps instead of gliding:
## without this pace a held key stepped once per FRAME and the hero shot across the map.
var _step_cooldown: float = 0.0
## A host-side dialogue (the whiteout line) holds input like a script does.
var _busy: bool = false
var _booted: bool = false


func _ready() -> void:
	story = get_node_or_null("/root/StoryController")
	if story == null:
		return
	if not story.has_session():
		# Running the scene on its own (editor F6, screenshot tools): an in-memory journey.
		story.new_journey(0)
	_state = story.state()
	_ruleset = story.ruleset()
	area = story.current_area()
	if area == null or area.terrain == null:
		return
	_build_world()
	_booted = true
	# Method callable: the connection dies with this node, while the runner lives on.
	if not story.runner().finished.is_connected(_on_script_finished):
		story.runner().finished.connect(_on_script_finished)
	var msg: String = story.overworld_ready(self)
	hud.show_area_name(area.display_name)
	if not msg.is_empty():
		_show_system_message(msg)
	elif not story.is_script_running():
		call_deferred("_on_area_entered")


func _exit_tree() -> void:
	if story != null:
		story.detach_host(self)
	# Leave no stale board for menus / the next scene (MapLoader registered the tiles).
	var cs := get_node_or_null("/root/CombatServices")
	if cs != null and cs.has_method("clear"):
		cs.clear()


# =====================================================================================
#  Boot
# =====================================================================================

func _build_world() -> void:
	var map_root := Node3D.new()
	map_root.name = "Map"
	add_child(map_root)
	_cursor = Node3D.new()
	_cursor.name = "Cursor"
	map_root.add_child(_cursor)

	map_loader = MapLoader.new()
	map_loader.name = "MapLoader"
	map_loader.objective_markers_enabled = false
	add_child(map_loader)
	map_loader.load_map(area.terrain, map_root)

	var look := get_node_or_null("WorldLook") as WorldLook
	if look == null:
		look = WorldLook.new()
		look.name = "WorldLook"
		add_child(look)
	look.setup(self)
	look.apply_preset(area.lighting_preset())

	grid = OverworldGrid.build(area, _state)

	var entities_root := Node3D.new()
	entities_root.name = "Entities"
	add_child(entities_root)
	for e in area.entity_list():
		if not e.has_actor():
			continue
		var actor := _make_entity_actor(e)
		entities_root.add_child(actor)
		_actors[String(e.id)] = actor
	_refresh_actor_states()

	player = OverworldActor.new()
	player.name = "Player"
	player.entity_id = "player"
	var hero: HeroResource = story.hero()
	if hero != null and hero.model_scene != null:
		var inst := hero.model_scene.instantiate() as Node3D
		player.set_model(inst, hero.model_yaw_deg, hero.model_scale)
	else:
		player.set_model(OverworldProps.figure(Color(0.3, 0.42, 0.6), "trainer"))
	add_child(player)
	player.place(_state.location_cell())
	player.set_facing(OverworldEntity.facing_vector(_state.location_facing()))
	_state.mark_visited(String(area.area_id))

	camera = OverworldCamera.new()
	camera.name = "OverworldCamera"
	camera.target = player
	var w: float = area.width() * Cells.CELL_SIZE
	var h: float = area.height() * Cells.CELL_SIZE
	# Keep the look-at point a few cells inside the edge so the skirt frames the area.
	camera.bounds = Rect2(Vector2(minf(6.0, w * 0.5), minf(4.0, h * 0.5)),
		Vector2(maxf(0.0, w - 12.0), maxf(0.0, h - 8.0)))
	add_child(camera)
	camera.snap()

	hud = OverworldHUD.new()
	hud.name = "OverworldHUD"
	add_child(hud)
	hud.touch_confirm_pressed.connect(interact)
	hud.touch_menu_pressed.connect(open_journey_menu)

	journey = JourneyMenu.new()
	journey.name = "JourneyMenu"
	add_child(journey)
	journey.save_requested.connect(_on_journey_save)
	journey.title_requested.connect(_on_journey_title)

	_dialogue = StoryDialogue.new()
	add_child(_dialogue)
	_dialogue.name = "OverworldDialogue"
	_update_prompt()


func _make_entity_actor(e: OverworldEntity) -> OverworldActor:
	var actor := OverworldActor.new()
	actor.name = "Actor_" + String(e.id)
	actor.entity_id = String(e.id)
	var body: Node3D = null
	var used_character: bool = false
	if not String(e.visual_character).is_empty():
		used_character = actor.set_character_model(CharacterLibrary.get_character(e.visual_character))
	if not used_character:
		match e.kind():
			&"sign":
				if (e as SignEntity).look == "stone":
					body = OverworldProps.standing_stone(e.tint)
				else:
					body = OverworldProps.signpost(e.tint)
			&"chest":
				body = OverworldProps.chest(e.tint)
			&"wayshrine":
				body = OverworldProps.wayshrine(e.tint)
			&"prop":
				var p := e as PropEntity
				body = OverworldProps.prop(p.prop, p.footprint, e.tint, _prop_seed(p))
			&"trainer":
				var tf: String = (e as NpcEntity).figure
				body = OverworldProps.figure(e.tint, tf if not tf.is_empty() else "trainer")
			_:
				body = OverworldProps.figure(e.tint, _figure_kind(e))
		actor.set_model(body)
	var ov: Dictionary = _state.actor_override(String(area.area_id), String(e.id))
	var c: Vector3i = ov.get("cell", e.cell) if not ov.is_empty() else e.cell
	var f: String = String(ov.get("facing", e.facing)) if not ov.is_empty() else e.facing
	actor.place(c)
	actor.set_facing(OverworldEntity.facing_vector(f))
	return actor


## Deterministic per-prop variation seed (flame placement, barrel spread).
static func _prop_seed(p: PropEntity) -> int:
	return p.cell.x * 131 + p.cell.y * 977 + absi(String(p.id).hash()) % 1000


## Procedural figure silhouette: the NPC's authored [member NpcEntity.figure], else by id
## convention (elder / guard / villager).
static func _figure_kind(e: OverworldEntity) -> String:
	if e is NpcEntity and not (e as NpcEntity).figure.is_empty():
		return (e as NpcEntity).figure
	var sid: String = String(e.id)
	if sid.contains("elder"):
		return "elder"
	if sid.contains("guard"):
		return "guard"
	return "villager"


## Show/hide actors by visible_if, open chest lids, light shrines.
func _refresh_actor_states() -> void:
	for e in area.entity_list():
		var actor: OverworldActor = _actors.get(String(e.id), null)
		if actor == null:
			continue
		actor.visible = e.is_present(_state)
		if e is ChestEntity:
			OverworldProps.set_chest_open(actor.model(), (e as ChestEntity).is_opened(String(area.area_id), _state))


func _on_script_finished(_stopped: bool, _reason: String) -> void:
	if not is_inside_tree():
		return
	_refresh_actor_states()
	_update_prompt()
	# A trainer who was blocked by a cutscene can still spot you once it ends.
	_check_trainers.call_deferred()


func _on_area_entered() -> void:
	if not _booted:
		return
	var scripts: Array = []
	for c in area.on_enter:
		scripts.append(c)
	if not scripts.is_empty() and story.run_script(scripts, ""):
		return
	_check_trainers()


# =====================================================================================
#  Per-frame input + walking
# =====================================================================================

func is_input_blocked() -> bool:
	if not _booted or _busy:
		return true
	if story != null and story.is_script_running():
		return true
	if journey != null and journey.is_open():
		return true
	return InputActions.gameplay_input_blocked(get_tree())


func _process(delta: float) -> void:
	if not _booted:
		return
	if _cursor != null and player != null:
		_cursor.global_position = player.global_position
	_step_cooldown = maxf(0.0, _step_cooldown - delta)
	if _moving or is_input_blocked():
		_held_dir = Vector2i.ZERO
		return
	var dir: Vector2i = _held_direction()
	if dir == Vector2i.ZERO:
		_held_dir = Vector2i.ZERO
		if not _tap_path.is_empty():
			if _step_ready():
				_follow_tap_path()
		elif _walk_streak:
			_walk_streak = false
			player.settle()
		return
	_tap_path.clear()
	_tap_interact_cell = Cells.INVALID
	if dir != _held_dir:
		_held_dir = dir
		_held_time = 0.0
		_turned_this_press = false
	else:
		_held_time += delta
	if dir != player.facing:
		player.turn_to(dir)
		_turned_this_press = true
		_update_prompt()
		if not _walk_streak:
			return
	if _turned_this_press and not _walk_streak and _held_time < _ruleset.turn_hold_seconds:
		return
	if not _step_ready():
		return
	try_step(dir)


## True once the last step's walk / run time has passed (a hair of float slack so a glide that
## ends on this frame chains straight into the next step with no idle frame).
func _step_ready() -> bool:
	return _step_cooldown <= 0.0001


func _held_direction() -> Vector2i:
	var pairs := [
		[InputActions.CURSOR_UP, InputActions.CAMERA_PAN_UP, Vector2i(0, -1)],
		[InputActions.CURSOR_DOWN, InputActions.CAMERA_PAN_DOWN, Vector2i(0, 1)],
		[InputActions.CURSOR_LEFT, InputActions.CAMERA_PAN_LEFT, Vector2i(-1, 0)],
		[InputActions.CURSOR_RIGHT, InputActions.CAMERA_PAN_RIGHT, Vector2i(1, 0)],
	]
	# Keep walking the way we already face when two directions are held.
	for p in pairs:
		if p[2] == player.facing and (Input.is_action_pressed(p[0]) or Input.is_action_pressed(p[1])):
			return p[2]
	for p in pairs:
		if Input.is_action_pressed(p[0]) or Input.is_action_pressed(p[1]):
			return p[2]
	return Vector2i.ZERO


func _step_seconds() -> float:
	var running: bool = InputMap.has_action(InputActions.FAST_FORWARD) \
		and Input.is_action_pressed(InputActions.FAST_FORWARD)
	return _ruleset.run_step_seconds if running else _ruleset.walk_step_seconds


## Step the hero one cell in [param dir]. Returns false (a bump: turn only) when blocked or
## busy. Public so tests / tools can walk without synthesising input (it is not paced; the
## per-frame input path waits out [member _step_cooldown] before calling it).
func try_step(dir: Vector2i) -> bool:
	if _moving or dir == Vector2i.ZERO or player == null:
		return false
	player.turn_to(dir)
	var to := Vector3i(player.cell.x + dir.x, player.cell.y + dir.y, player.cell.z)
	if not grid.is_walkable(to):
		_walk_streak = false
		_update_prompt()
		return false
	_moving = true
	_walk_streak = true
	var seconds: float = _step_seconds()
	_step_cooldown = seconds
	player.walk_to(to, seconds)
	_await_arrival(to)
	return true


func _await_arrival(to: Vector3i) -> void:
	await player.walk_finished
	_moving = false
	_on_arrived(to)


## True while the hero is mid-step.
func is_moving() -> bool:
	return _moving


func _on_arrived(cell: Vector3i) -> void:
	story.note_player_position(cell, OverworldEntity.facing_name(player.facing))
	_state.steps += 1
	_update_prompt()
	# 1. Warps.
	for e in area.present_entities(_state):
		if e is WarpEntity and e.occupies(cell):
			var w := e as WarpEntity
			if w.is_open(_state):
				_tap_path.clear()
				story.warp_to(String(w.target_area), String(w.target_entry), cell, w)
				return
			if w.locked_scene != null:
				_tap_path.clear()
				story.run_script([SayCommand.from_scene(w.locked_scene)], String(w.id))
				return
	# 2. Trigger zones.
	for e in area.present_entities(_state):
		if e is TriggerZone and e.occupies(cell):
			var t := e as TriggerZone
			if t.can_fire(String(area.area_id), _state):
				_tap_path.clear()
				story.run_script(t.step_script(String(area.area_id)), String(t.id))
				return
	# 3. Trainers.
	if _check_trainers():
		_tap_path.clear()
		return
	# 4. The grass.
	if _roll_encounter(cell):
		_tap_path.clear()


## Any undefeated, present trainer whose line of sight holds the hero challenges him. True when
## one did.
func _check_trainers() -> bool:
	if story.is_script_running():
		return false
	# No creature to fight with (the opening, before the shard ceremony): trainers let you pass.
	if _state.healthy_members().is_empty():
		return false
	var aid: String = String(area.area_id)
	for e in area.present_entities(_state):
		if not (e is TrainerEntity):
			continue
		var t := e as TrainerEntity
		if t.is_defeated(aid, _state) or t.battle == null:
			continue
		var actor: OverworldActor = _actors.get(String(t.id), null)
		var tcell: Vector3i = actor.cell if actor != null else t.cell
		var tdir: Vector2i = actor.facing if actor != null else OverworldEntity.facing_vector(t.facing)
		if TrainerSight.spots(grid, tcell, tdir, t.sight_range, player.cell):
			var approach: Vector3i = TrainerSight.approach_cell(tcell, tdir, player.cell)
			story.run_script(t.encounter_script(aid, approach, approach != tcell), String(t.id),
				String(t.speaker_id), t.speaker_label())
			return true
	return false


## Roll the grass for the step onto [param cell]. True when a wild encounter started.
func _roll_encounter(cell: Vector3i) -> bool:
	if not DuelLauncher.has_launcher():
		return false
	# Wild creatures leave a traveller with no partner alone (the opening walks the Mossway before
	# the shard ceremony) -- and a duel with no one to field could not start anyway.
	if _state.healthy_members().is_empty():
		return false
	if _state.grace_steps > 0:
		_state.grace_steps -= 1
		return false
	var tid: StringName = grid.tile_id_at(cell)
	for z in area.zones():
		if not z.contains(cell, tid):
			continue
		var r: Dictionary = EncounterRoller.roll(_state.rng_seed, String(area.area_id), _state.steps, z, _state)
		if not bool(r.get("hit", false)):
			continue
		var entry: EncounterEntry = r["entry"]
		var duel := StartDuelCommand.new()
		duel.entry = entry
		duel.area_id = String(area.area_id)
		var prompt := BefriendPromptCommand.new()
		_state.grace_steps = z.grace_steps
		return story.run_script([duel, prompt], "")
	return false


func _follow_tap_path() -> void:
	if _tap_path.is_empty():
		return
	var next: Vector3i = _tap_path[0]
	var dir := Vector2i(next.x - player.cell.x, next.y - player.cell.y)
	if absi(dir.x) + absi(dir.y) != 1 or not grid.is_walkable(next):
		_tap_path.clear()
		return
	_tap_path.remove_at(0)
	if not try_step(dir):
		_tap_path.clear()
		return
	if _tap_path.is_empty() and _tap_interact_cell != Cells.INVALID:
		_finish_tap_interact.call_deferred()


func _finish_tap_interact() -> void:
	while _moving:
		await get_tree().process_frame
	if _tap_interact_cell == Cells.INVALID or is_input_blocked():
		return
	player.face_cell(_tap_interact_cell)
	_tap_interact_cell = Cells.INVALID
	interact()


# =====================================================================================
#  Interaction
# =====================================================================================

## The cell the hero faces.
func faced_cell() -> Vector3i:
	return Vector3i(player.cell.x + player.facing.x, player.cell.y + player.facing.y, player.cell.z)


## The present, interactable entity standing on [param cell] (moved actors where they stand
## now), or null.
func entity_at(cell: Vector3i) -> OverworldEntity:
	for e in area.present_entities(_state):
		if not e.is_interactable():
			continue
		var actor: OverworldActor = _actors.get(String(e.id), null)
		if actor != null:
			if actor.cell == cell:
				return e
		elif e.occupies(cell):
			return e
	return null


## Use what the hero faces (Confirm / the touch A button). True when something ran.
func interact() -> bool:
	if is_input_blocked() or _moving:
		return false
	var e: OverworldEntity = entity_at(faced_cell())
	if e == null:
		return false
	var actor: OverworldActor = _actors.get(String(e.id), null)
	if actor != null and (e is NpcEntity):
		actor.face_cell(player.cell)
	var speaker_id: String = ""
	var speaker_name: String = e.display_name
	if e is NpcEntity:
		speaker_id = String((e as NpcEntity).speaker_id)
		speaker_name = (e as NpcEntity).speaker_label()
	var ok: bool = story.run_script(e.interact_script(String(area.area_id), _state), String(e.id),
		speaker_id, speaker_name)
	_update_prompt()
	return ok


func _update_prompt() -> void:
	if hud == null or player == null:
		return
	if is_input_blocked():
		hud.set_prompt("")
		return
	var e: OverworldEntity = entity_at(faced_cell())
	hud.set_prompt(e.prompt_verb() if e != null else "")


func _unhandled_input(event: InputEvent) -> void:
	if not _booted:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom_by(1.1)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_by(1.0 / 1.1)
			return
	if is_input_blocked():
		return
	if event.is_action_pressed(InputActions.CONFIRM) or event.is_action_pressed(&"ui_accept"):
		if interact():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.MAP_MENU) or event.is_action_pressed(InputActions.CANCEL):
		get_viewport().set_input_as_handled()
		open_journey_menu()
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		tap_at_screen((event as InputEventMouseButton).position)


## Tap / click: walk to the cell (or next to the NPC / object there, then use it).
func tap_at_screen(screen_pos: Vector2) -> void:
	if camera == null or _moving:
		return
	var p = camera.ground_point(screen_pos, OverworldActor.GROUND_Y)
	if p == null:
		return
	var cell: Vector3i = Cells.world_to_cell(Vector3(p.x, 0.0, p.z))
	tap_cell(cell)


func tap_cell(cell: Vector3i) -> void:
	if not grid.in_bounds(cell):
		return
	var target: OverworldEntity = entity_at(cell)
	if target != null:
		var plan: Dictionary = TapPathfinder.path_to_adjacent(grid, player.cell, cell)
		if plan.is_empty():
			return
		_tap_path = plan["path"]
		_tap_interact_cell = cell
		if _tap_path.is_empty():
			player.face_cell(cell)
			_tap_interact_cell = Cells.INVALID
			interact()
		return
	_tap_interact_cell = Cells.INVALID
	_tap_path = TapPathfinder.find_path(grid, player.cell, cell)


# =====================================================================================
#  Journey menu
# =====================================================================================

func open_journey_menu() -> void:
	if journey == null or is_input_blocked():
		return
	hud.set_prompt("")
	journey.open(_state)


func _on_journey_save() -> void:
	var r: Dictionary = story.save_game()
	if bool(r.get("success", false)):
		journey.set_status("Journey saved.")
	elif String(r.get("reason", "")) == "no_slot":
		journey.set_status("Practice journey -- not saved.")
	else:
		journey.set_status("Could not save.")


func _on_journey_title() -> void:
	journey.close()
	story.return_to_title()


# =====================================================================================
#  THE SCRIPT HOST (see StoryScriptHost for the contract)
# =====================================================================================

func show_dialogue(scene: StoryScene) -> void:
	if _dialogue == null or scene == null:
		return
	hud.set_prompt("")
	if not _dialogue.play(scene):
		return
	await _dialogue.finished
	_update_prompt.call_deferred()


func show_choice(prompt: StoryBeat, options: PackedStringArray, cancel_index: int = -1) -> int:
	if _dialogue == null:
		return maxi(0, cancel_index)
	hud.set_prompt("")
	if not _dialogue.play_choice(prompt, options, cancel_index):
		return maxi(0, cancel_index)
	var picked: int = await _dialogue.choice_made
	return picked


func dialogue() -> StoryDialogue:
	return _dialogue


func move_actor(actor_id: String, to: Vector3i, _persist: bool = false) -> void:
	var actor: OverworldActor = player if actor_id == "player" else _actors.get(actor_id, null)
	if actor == null or actor.cell == to:
		return
	var ignore: String = "" if actor_id == "player" else actor_id
	# Path over the grid, ignoring the actor's own blocker; fall back to a straight line.
	var path: Array[Vector3i] = _path_for(actor.cell, to, ignore)
	for c in path:
		actor.walk_to(c, _ruleset.walk_step_seconds)
		await actor.walk_finished
		if actor_id != "player":
			grid.move_blocker(actor_id, c)
	if actor_id == "player":
		story.note_player_position(actor.cell, OverworldEntity.facing_name(actor.facing))
	else:
		_state.set_actor_position(String(area.area_id), actor_id, actor.cell,
			OverworldEntity.facing_name(actor.facing), _persist)
	_update_prompt()


func _path_for(from: Vector3i, to: Vector3i, ignore: String) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if ignore != "":
		grid.clear_blocker(from)
	var p: Array[Vector3i] = TapPathfinder.find_path(grid, from, to)
	if ignore != "":
		grid.set_blocker(from, ignore)
	if not p.is_empty():
		return p
	# Straight-line fallback (cutscene staging through a crowd).
	var c: Vector3i = from
	while c != to:
		if c.x != to.x:
			c.x += signi(to.x - c.x)
		else:
			c.y += signi(to.y - c.y)
		out.append(c)
	return out


func face_actor(actor_id: String, facing: String) -> void:
	var actor: OverworldActor = player if actor_id == "player" else _actors.get(actor_id, null)
	if actor == null:
		return
	if facing.begins_with("toward:"):
		var other_id: String = facing.substr(7)
		var other: OverworldActor = player if other_id == "player" else _actors.get(other_id, null)
		if other != null:
			actor.face_cell(other.cell)
	else:
		actor.turn_to(OverworldEntity.facing_vector(facing))
	if actor == player:
		story.note_player_position(player.cell, OverworldEntity.facing_name(player.facing))


func emote(actor_id: String, glyph: String) -> void:
	var actor: OverworldActor = player if actor_id == "player" else _actors.get(actor_id, null)
	if actor == null:
		return
	await actor.emote(glyph)


func wait(seconds: float) -> void:
	if seconds <= 0.0 or not _anims_on():
		return
	await get_tree().create_timer(seconds).timeout


func toast(text: String, kind: String = "") -> void:
	if hud != null:
		hud.toast(text, kind)


## The trainer VS clash, played over the overworld before the hand-off (the same VersusIntro
## the versus battles use; no GameWorld edit needed).
func play_clash(request) -> void:
	if not _anims_on() or DisplayServer.get_name() == "headless":
		return
	var intro := VersusIntro.new()
	intro.name = "StoryClash"
	add_child(intro)
	var lead_id: String = ""
	if not _state.party.is_empty():
		lead_id = _state.party[0].character_id
	var team = request.opponent.get("team", [])
	var foe_id: String = ""
	if team is Array and not team.is_empty():
		foe_id = String(team[0].get("character_id", ""))
	intro.play({
		"networked": false,
		"local_slot": 0,
		"local_name": story.hero_name(),
		"local_character_id": lead_id,
		"opponent_name": request.opponent_name(),
		"opponent_character_id": foe_id,
	})
	await intro.finished
	if is_instance_valid(intro):
		intro.queue_free()


func refresh_world() -> void:
	if grid == null:
		return
	grid.rebuild_blockers(area, _state)
	# Actors that moved stand where they are now, not where the data put them.
	for id in _actors:
		var actor: OverworldActor = _actors[id]
		var e: OverworldEntity = area.entity(id)
		if e == null:
			continue
		if not e.is_present(_state) or not e.blocking:
			grid.clear_blocker(actor.cell)
	_refresh_actor_states()
	_update_prompt()


func tile_under_player() -> String:
	return String(grid.tile_id_at(player.cell)) if grid != null and player != null else ""


# --- helpers ----------------------------------------------------------------------------

## A one-off line from the host itself (the whiteout message), holding input while it shows.
func _show_system_message(text: String) -> void:
	_busy = true
	var scene := StoryScene.new()
	scene.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR, "", text)])
	await show_dialogue(scene)
	_busy = false
	_update_prompt()


## The actor node for [param entity_id] ("player" = the hero), or null.
func actor(entity_id: String) -> OverworldActor:
	if entity_id == "player":
		return player
	return _actors.get(entity_id, null)


func _anims_on() -> bool:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null or not gs.has_method("animations_on"):
		return true
	return bool(gs.animations_on())
