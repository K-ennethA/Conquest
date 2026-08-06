extends Node3D

class_name FogOfWarOverlay

## FOG OF WAR -- the PRESENTATION half. Everything here is a look and a refusal; not one
## line of it decides what a unit may do. [VisionSystem] (game/combat/VisionSystem.gd) owns
## the truth -- who can see which cell, which unit -- and this layer is the only thing in
## the game allowed to turn that truth into pixels, hidden models and denied clicks.
##
## THE FOUR JOBS
##
##   1. WHOSE EYES.       [method local_perspective] is the ONE definition of "the player
##                        this screen belongs to". Every hook below asks it; nothing else
##                        in the codebase re-derives it.
##   2. CELL SHROUD.      A warm-dark translucent quad over every cell the perspective
##                        cannot see. ONE [MultiMeshInstance3D] -- one node, one draw call,
##                        one instance per hidden cell -- following [MapSurround]'s merged
##                        -mesh economy. Never per-cell nodes.
##   3. UNIT HIDING.      A unit the perspective cannot see has its WHOLE node hidden
##                        (model, world-space [HealthBar], status badges, terrain chips --
##                        they are all children of the unit, so one flag takes the lot).
##   4. INTERACTION       Hidden units cannot be hovered, cursor-selected, threat-mapped,
##      HONESTY.          named in the log/announcer, or identified in the turn queue; and
##                        no FX or damage float is drawn on a cell outside vision.
##
## FOG OFF COSTS NOTHING. [method fog_active] short-circuits on a cached vision handle, so
## with fog off (or no [VisionSystem] mounted at all, which is every battle today) every
## hook below is one static call returning `false`. This node then mounts with ZERO children
## -- no shroud geometry is ever built -- and no unit is ever touched, which is what makes a
## fog-off battle render byte-identically to one with this file deleted.
##
## VISIBILITY IS READ LIVE, NEVER SNAPSHOTTED. Every gate calls straight through to
## [VisionSystem] at the moment the event fires. That is what makes REVEAL-ON-ATTACK work:
## the vision core flips a hidden attacker visible BEFORE the damage announcement, so the
## same suppression that would have swallowed the hit renders it -- with no ordering
## contract beyond "the reveal lands first", which the core guarantees. A cached visible-set
## would have eaten the very attack that revealed the attacker.
##
## SPECTATORS ARE NOT PLAYERS. During [method ReplayPlayback.is_playing] the perspective is
## [constant SPECTATOR] and [method fog_active] is false: a replay viewer sees the whole
## board, because there is nothing left to hide from someone who is not making decisions.
##
## ZERO BOARD CELLS, ZERO BATTLE RNG. Nothing here registers with [CombatServices], carries
## a [Tile] script, or holds a collider; the shroud has no RNG at all (its layout is the
## hidden set). Pathing, spawns, AI, lockstep and replays cannot see this node.


# --- Perspective -------------------------------------------------------------

## The perspective of someone who is watching rather than playing (a replay viewer). Fog is
## OFF for this value -- see [method fog_active].
const SPECTATOR: int = -1


# --- Shroud look -------------------------------------------------------------

## WARM-DARK, not black, and translucent: "you know the ground, not what stands on it".
## The terrain has to stay readable underneath -- a player must still be able to plan a
## route through fog -- so this is a dim warm veil over the tiles, sitting with the amber
## HUD rather than punching a hole in the board.
const SHROUD_COLOR: Color = Color(0.11, 0.075, 0.055)
const SHROUD_ALPHA: float = 0.72

## Cell size in world units (one board cell is 2x2 -- see MapLoader._create_tile_at_position)
## and the height the veil floats at: just over LowPolyTileBuilder's 0.10 cap top, and under
## TileEffectOverlay's 0.55 pips, so effect pips still read through the fog.
const CELL: float = 2.0
const SHROUD_Y: float = 0.14

## How long the veil takes to settle in. Only ever used when animations are enabled;
## GameSettings.animations_on() == false snaps it (tests and the "instant" preset).
const FADE_TIME: float = 0.22

## Node name the batched veil always mounts under -- what the tests measure.
const SHROUD_NAME: StringName = &"Shroud"


# --- Static state (the seam) -------------------------------------------------

## The mounted overlay, or null. Not load-bearing for the gates below (they are all static
## and work with no instance at all); it exists so tests and [GameWorldManager] can find the
## one live veil.
static var _active: FogOfWarOverlay = null

## TEST SEAM. A stub implementing { fog_enabled, is_cell_visible, is_unit_visible,
## visible_cells } installed by [method set_vision_override], so the fog suites never
## depend on a real [VisionSystem] being mounted. Null in every real battle.
static var _vision_override = null

## Resolved [VisionSystem] handle and whether we have looked for it yet. Cached because
## these gates run on every damage event, every FX cell and every cursor move: with fog off
## the whole cost must be one null check, not a scene-tree scan.
static var _vision_cached: Node = null
static var _vision_scanned: bool = false

## The seat the HOTSEAT perspective last swapped to, latched on turn_started. -1 until the
## first human turn begins.
static var _hotseat_pid: int = -1


# --- Instance state ----------------------------------------------------------

## The batched veil. Built LAZILY -- it does not exist until a cell is actually hidden, so
## a fog-off battle leaves this node childless.
var _shroud: MultiMeshInstance3D = null
var _shroud_material: StandardMaterial3D = null
var _fade_tween: Tween = null

## Units this overlay currently has hidden, so a reveal (or teardown) can put back exactly
## what it took and nothing else.
var _hidden_units: Array = []

## The hidden set most recently painted, so an identical vision_changed repaints nothing.
var _hidden_cells: Array[Vector2i] = []

## One announcement per battle (see [method announce_fog_intro]), re-armed on board_ready.
var _announced: bool = false

## The turn system we are riding for hotseat swaps. Per CONQUEST.md rule 2 this is the
## ACTIVE turn system's turn_started, never PlayerManager's -- which does not fire on an
## AI turn, and would therefore freeze the perspective mid-battle.
var _turn_system: TurnSystemBase = null


# =============================================================================
# WHOSE EYES
# =============================================================================

## The player id whose vision THIS SCREEN shows. The single definition; every hook in this
## file and every gate in the HUD asks this and nothing else.
##
##   * REPLAY    -> [constant SPECTATOR]. A viewer is not playing, so there is nothing to
##                  hide from them; [method fog_active] is false for this value.
##   * NETWORKED -> [method NetSession.local_slot] -- the seat this machine is sitting in.
##   * HOTSEAT   -> the ACTIVE player's id, swapped on the active turn system's turn_started.
##                  Two humans share one screen, so each may only ever see their own vision
##                  on their own turn; keeping player 0's eyes through player 1's turn would
##                  be a wallhack with extra steps.
##   * SOLO      -> the human's id, held CONSTANT through the AI's turn. Watching the enemy
##                  move through your own fog is the tension the genre is built on; snapping
##                  to the bot's eyes on its turn would show you everything it can see.
static func local_perspective() -> int:
	if _is_spectating():
		return SPECTATOR
	if _is_networked():
		return int(NetSession.local_slot())
	if _is_hotseat():
		var live: Player = _live_active_player()
		# An AI or neutral seat never becomes the perspective: it has no player behind it,
		# so we hold the last human seat's eyes (which is also the solo rule).
		if live != null and not live.is_ai and not live.is_neutral:
			_hotseat_pid = int(live.player_id)
		if _hotseat_pid >= 0:
			return _hotseat_pid
	return _local_player_id()


## True while a recording is being watched. [ReplayPlayback] is a class_name with static
## state (not an autoload), so this is always answerable -- including from a bare unit-test
## tree with no battle mounted.
static func _is_spectating() -> bool:
	return ReplayPlayback.is_playing()


## True only for a LIVE, multi-participant networked match that has seated us -- exactly
## [method GameModeManager._netsession_is_live]'s test, restated here because this file must
## work with no GameModeManager at all.
static func _is_networked() -> bool:
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return false
	if not NetSession.has_method("is_networked_match") or not NetSession.is_networked_match():
		return false
	return int(NetSession.local_slot()) >= 0


## HOTSEAT is TWO HUMAN SEATS SHARING ONE SCREEN, and it is decided by counting seats rather
## than by trusting the mode enum: GameSettings.game_mode defaults to VERSUS, so a solo
## skirmish that never set the mode would otherwise be treated as hotseat and swap the
## player's eyes onto the bot every enemy turn. One human seat is solo by definition,
## whatever the enum says.
static func _is_hotseat() -> bool:
	if _is_networked():
		return false
	if GameSettings == null or not ("game_mode" in GameSettings):
		return false
	if GameSettings.game_mode != GameSettings.GameMode.VERSUS:
		return false
	return _human_seat_count() >= 2


static func _human_seat_count() -> int:
	if PlayerManager == null or not ("players" in PlayerManager):
		return 0
	var count: int = 0
	for player in PlayerManager.players:
		if player == null or not is_instance_valid(player):
			continue
		if not player.is_ai and not player.is_neutral:
			count += 1
	return count


## The player whose turn it currently is, or null.
static func _live_active_player() -> Player:
	if PlayerManager == null or not PlayerManager.has_method("get_current_player"):
		return null
	return PlayerManager.get_current_player()


## The local human's id: the real slot in multiplayer, 0 in solo / hotseat. Read through
## GameModeManager so friend/foe here agrees with [UnitVisualManager]'s outlines.
static func _local_player_id() -> int:
	if GameModeManager != null and GameModeManager.has_method("get_local_player_id"):
		return int(GameModeManager.get_local_player_id())
	return 0


# =============================================================================
# THE GATES (static; every hook in the HUD calls these and nothing else)
# =============================================================================

## True when fog is on AND this screen belongs to someone it should be hidden from.
## FALSE -- immediately, on one cached null check -- with no [VisionSystem] mounted, with
## fog authored off, and for a replay spectator. This is the function that makes the whole
## layer free when fog is off.
static func fog_active() -> bool:
	var vision = _vision()
	if vision == null:
		return false
	if not vision.has_method("fog_enabled") or not bool(vision.fog_enabled()):
		return false
	# A spectator is checked LAST: it is the rare branch, and putting it first would cost a
	# ReplayPlayback lookup on every one of the thousands of fog-off calls above.
	return not _is_spectating()


## True when [param cell] lies outside this screen's vision. Used by the FX / damage-float
## suppression: a blow landing in fog draws nothing, because you cannot see where it landed.
static func cell_hidden(cell: Vector2i) -> bool:
	if not fog_active():
		return false
	var vision = _vision()
	if vision == null or not vision.has_method("is_cell_visible"):
		return false
	return not bool(vision.is_cell_visible(local_perspective(), cell))


## True when [param unit] is invisible to this screen. Read LIVE on every call (see the
## class doc): a unit the vision core has just revealed by attacking answers false here even
## though it answered true one event earlier.
static func unit_hidden(unit) -> bool:
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return false
	if not fog_active():
		return false
	var vision = _vision()
	if vision == null or not vision.has_method("is_unit_visible"):
		return false
	return not bool(vision.is_unit_visible(local_perspective(), unit))


## True when the cell [param world] sits over is hidden. The world->cell fold every FX layer
## needs, kept here so there is one of it.
static func world_hidden(world: Vector3) -> bool:
	if not fog_active():
		return false
	return cell_hidden(Vector2i(int(floor(world.x / CELL)), int(floor(world.z / CELL))))


# --- Vision resolution -------------------------------------------------------

## Install a stub vision source (tests). Pass null to clear. Always invalidates the cache,
## so a suite can swap stubs between tests.
static func set_vision_override(vision) -> void:
	_vision_override = vision
	invalidate_vision()


## Drop the cached [VisionSystem] handle. Called on board_ready, because the vision core is
## mounted per battle and a stale handle from the previous board would answer for the wrong
## map.
static func invalidate_vision() -> void:
	_vision_cached = null
	_vision_scanned = false


## The live vision source, or null. Resolved ONCE and cached -- with no VisionSystem in the
## project (which is every battle until the core lands) this settles on "scanned, nothing
## there" and every later gate is a single boolean test.
static func _vision():
	if _vision_override != null:
		return _vision_override
	if _vision_cached != null and is_instance_valid(_vision_cached):
		return _vision_cached
	if _vision_scanned:
		return null
	_vision_scanned = true
	_vision_cached = _find_vision_node()
	return _vision_cached


## The vision core, wherever it is mounted.
##
## [method VisionSystem.active] is the canonical handle and answers null outside a battle,
## which is exactly the "fog off, cost nothing" case. The tree walks below it are a
## belt-and-braces fallback (group, autoload, scene-root child, GameWorldManager child) so
## this layer keeps working if the core is ever mounted somewhere else.
static func _find_vision_node() -> Node:
	var canonical = VisionSystem.active()
	if canonical != null and canonical is Node:
		return canonical as Node

	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree := loop as SceneTree

	var grouped: Array = tree.get_nodes_in_group(&"vision_system")
	for node in grouped:
		if node is Node and is_instance_valid(node):
			return node as Node

	if tree.root != null:
		var autoloaded: Node = tree.root.get_node_or_null("VisionSystem")
		if autoloaded != null:
			return autoloaded

	var scene: Node = tree.current_scene
	if scene != null:
		var child: Node = scene.get_node_or_null("VisionSystem")
		if child != null:
			return child

	for manager in tree.get_nodes_in_group(&"game_world_manager"):
		if manager is Node:
			var owned: Node = (manager as Node).get_node_or_null("VisionSystem")
			if owned != null:
				return owned

	return null


## Drop every piece of PROCESS-WIDE state this class holds: the injected stub, the cached
## vision handle and the latched hotseat seat. For test [code]before_each[/code] /
## [code]after_each[/code] -- all three outlive a scene, and a suite that left any of them
## set would fog the next suite's board (tests/README rule 3).
static func reset_for_tests() -> void:
	_vision_override = null
	_hotseat_pid = -1
	invalidate_vision()


## The mounted overlay, or null.
static func active() -> FogOfWarOverlay:
	if _active != null and is_instance_valid(_active):
		return _active
	return null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	name = "FogOfWarOverlay"
	_active = self

	# A fresh board means a fresh vision core and a fresh hidden set -- and a fresh chance
	# to announce the mists. board_ready fires after every map load (CONQUEST.md's
	# reactive-overlay pattern, shared with TileEffectOverlay).
	if CombatServices != null and not CombatServices.board_ready.is_connected(_on_board_ready):
		CombatServices.board_ready.connect(_on_board_ready)

	# Ride the ACTIVE turn system for hotseat swaps -- never PlayerManager's player_turn_*,
	# which do not fire on an AI turn (CONQUEST.md rule 2).
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())

	_connect_vision()
	refresh()


func _exit_tree() -> void:
	# Put every unit we hid back before we go: an overlay freed mid-battle (scene change,
	# rematch) must never leave an invisible unit on someone else's board.
	_reveal_all()
	if _active == self:
		_active = null


## Subscribe to the vision core's `vision_changed`. Re-runnable: called on mount and again
## on every board_ready, since the core is rebuilt with the board.
func _connect_vision() -> void:
	var vision = _vision()
	if vision == null or not (vision is Object):
		return
	if not vision.has_signal(&"vision_changed"):
		return
	if not (vision as Object).is_connected(&"vision_changed", _on_vision_changed):
		(vision as Object).connect(&"vision_changed", _on_vision_changed)


func _on_board_ready() -> void:
	# New board -> new vision core. Drop the cached handle before anything reads it.
	invalidate_vision()
	_hidden_cells.clear()
	_announced = false
	_connect_vision()
	refresh(true)
	if fog_active():
		# Deferred: board_ready can beat the HUD's own mount, and an announcement with no
		# announcer mounted is a line the player never sees.
		announce_fog_intro.call_deferred()


func _on_vision_changed(_a = null, _b = null, _c = null) -> void:
	# SYNCHRONOUS on purpose. A mid-enemy-turn reveal (an ambusher stepping into the light,
	# or the vision core's reveal-on-attack) must pop the model in on the same frame the
	# vision changed -- a deferred repaint would show the attack before the attacker.
	refresh()


func _on_turn_system_activated(system: TurnSystemBase) -> void:
	if _turn_system != null and is_instance_valid(_turn_system):
		if _turn_system.turn_started.is_connected(_on_turn_started):
			_turn_system.turn_started.disconnect(_on_turn_started)
	_turn_system = system
	if system == null:
		return
	if not system.turn_started.is_connected(_on_turn_started):
		system.turn_started.connect(_on_turn_started)


## The seat changed. In hotseat this is the perspective SWAP -- the whole board's fog flips
## to the incoming player's eyes. In solo it is a no-op for the perspective (the human keeps
## their own eyes through the AI's turn) but still a good moment to repaint, since units
## moved.
func _on_turn_started(_player = null) -> void:
	refresh(true)


# =============================================================================
# PAINTING
# =============================================================================

## Repaint the veil and the hidden units from the CURRENT perspective. [param fade] asks for
## the brief settle-in (perspective swaps and fresh boards get it; an incremental
## vision_changed does not, so a revealed cell simply opens).
##
## The fog-off path is the first two lines: reveal anything we were hiding, drop the veil,
## return. So switching fog off mid-battle -- or mounting into a battle that never had it --
## leaves the board exactly as it was.
func refresh(fade: bool = false) -> void:
	if not fog_active():
		_reveal_all()
		_clear_shroud()
		_hidden_cells.clear()
		return

	var perspective: int = local_perspective()
	var was_hidden: Array = _hidden_units.duplicate()
	_apply_unit_hiding(perspective)
	if was_hidden != _hidden_units:
		_repaint_masked_hud()

	var hidden: Array[Vector2i] = _compute_hidden_cells(perspective)
	if hidden == _hidden_cells and not fade:
		return  # identical set, nothing to redraw
	_hidden_cells = hidden
	_paint_shroud(hidden, fade)


## Every in-bounds cell the perspective cannot see, in a fixed scan order (so an unchanged
## set compares equal and repaints nothing).
##
## Prefers the core's own [code]visible_cells[/code] -- one call, then a set membership test
## per cell -- and falls back to per-cell [code]is_cell_visible[/code] when the core does not
## offer it.
func _compute_hidden_cells(perspective: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if CombatServices == null:
		return out
	var cols: int = int(CombatServices.GRID.size.x)
	var rows: int = int(CombatServices.GRID.size.z)
	if cols <= 0 or rows <= 0:
		return out

	var vision = _vision()
	if vision == null:
		return out

	# [method VisionSystem.visible_cells] hands back its LIVE cache as a { Vector2i: true }
	# set -- never copied, never mutated here. An Array is accepted too, so a stub (or a
	# future core) that returns a plain list works unchanged.
	var visible_set: Dictionary = {}
	var have_set: bool = false
	if vision.has_method("visible_cells"):
		var cells = vision.visible_cells(perspective)
		if cells is Dictionary:
			have_set = true
			visible_set = cells
		elif cells is Array:
			have_set = true
			for cell in cells:
				if cell is Vector2i:
					visible_set[cell] = true

	var can_probe: bool = vision.has_method("is_cell_visible")
	if not have_set and not can_probe:
		return out

	for col in range(cols):
		for row in range(rows):
			var cell := Vector2i(col, row)
			var seen: bool
			if have_set:
				seen = visible_set.has(cell)
			else:
				seen = bool(vision.is_cell_visible(perspective, cell))
			if not seen:
				out.append(cell)
	return out


# --- The batched veil --------------------------------------------------------

## Draw the veil over exactly [param cells]. ONE [MultiMeshInstance3D], one instance per
## hidden cell -- the node count is 1 for a fully-fogged 40x40 board and 0 for a board with
## nothing hidden, which is [MapSurround]'s economy applied to a set that changes every turn.
func _paint_shroud(cells: Array[Vector2i], fade: bool) -> void:
	if cells.is_empty():
		_clear_shroud()
		return

	_ensure_shroud()
	var mm: MultiMesh = _shroud.multimesh
	mm.instance_count = cells.size()
	# Flat: the quad's default +Z face rotated to look straight up at the camera-side sky.
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in range(cells.size()):
		var cell: Vector2i = cells[i]
		mm.set_instance_transform(i, Transform3D(flat, Vector3(
			float(cell.x) * CELL + CELL * 0.5,
			SHROUD_Y,
			float(cell.y) * CELL + CELL * 0.5)))
	_shroud.visible = true

	if fade:
		_fade_in()
	else:
		_kill_fade()
		_shroud_material.albedo_color.a = SHROUD_ALPHA


## Build the veil node the FIRST time a cell is actually hidden. Lazy on purpose: a fog-off
## battle must leave this overlay childless, which is what "renders byte-identically" means.
func _ensure_shroud() -> void:
	if _shroud != null and is_instance_valid(_shroud):
		return

	_shroud_material = StandardMaterial3D.new()
	_shroud_material.albedo_color = Color(
		SHROUD_COLOR.r, SHROUD_COLOR.g, SHROUD_COLOR.b, SHROUD_ALPHA)
	# Unshaded so the veil is the same warm dark wherever the sun is not, and transparent so
	# the terrain underneath keeps its shape.
	_shroud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shroud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shroud_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_shroud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Over the tiles, under the tile-effect pips (render_priority 3) so a known hazard is
	# still legible through the mist.
	_shroud_material.render_priority = 1

	var quad := QuadMesh.new()
	quad.size = Vector2(CELL, CELL)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad

	_shroud = MultiMeshInstance3D.new()
	_shroud.name = SHROUD_NAME
	_shroud.multimesh = mm
	_shroud.material_override = _shroud_material
	# A translucent veil casting shadows would darken the board it is only meant to dim.
	_shroud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shroud)


## Drop the veil entirely (fog off, or nothing hidden). Frees the node rather than emptying
## it, so "no cell is hidden" and "fog is off" look identical to a measuring test.
func _clear_shroud() -> void:
	_kill_fade()
	if _shroud != null and is_instance_valid(_shroud):
		remove_child(_shroud)
		_shroud.free()
	_shroud = null
	_shroud_material = null


## The mists settling in: alpha 0 -> SHROUD_ALPHA over FADE_TIME. Honours the player's
## animation setting -- with animations off it snaps, exactly like every other effect.
func _fade_in() -> void:
	_kill_fade()
	if _shroud_material == null:
		return
	if not _animations_on() or not is_inside_tree():
		_shroud_material.albedo_color.a = SHROUD_ALPHA
		return
	_shroud_material.albedo_color.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_shroud_material, "albedo_color:a", SHROUD_ALPHA, FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _animations_on() -> bool:
	if GameSettings == null or not GameSettings.has_method("animations_on"):
		return false
	return bool(GameSettings.animations_on())


# --- Unit hiding -------------------------------------------------------------

## Hide every unit the perspective cannot see, and put back every unit it can.
##
## Delegated to [method UnitVisualManager.set_fog_hidden], which owns the CHANNEL question:
## it toggles the UNIT NODE's `visible`, while [SubmergedStatus] toggles the MODEL ROOT's.
## Two different nodes on one parent chain, so scene-tree visibility composes them for free
## and neither can strand the other's flag -- see that method's doc.
func _apply_unit_hiding(perspective: int) -> void:
	var still_hidden: Array = []
	var vision = _vision()
	var can_ask: bool = vision != null and vision.has_method("is_unit_visible")

	for unit in _board_units():
		if unit == null or not is_instance_valid(unit):
			continue
		var hide: bool = can_ask and not bool(vision.is_unit_visible(perspective, unit))
		UnitVisualManager.set_fog_hidden(unit, hide)
		if hide:
			still_hidden.append(unit)

	# Anything we hid that is no longer on the board (died in the dark, was despawned) is
	# dropped here rather than left in the list forever.
	for unit in _hidden_units:
		if unit != null and is_instance_valid(unit) and not (unit in still_hidden):
			UnitVisualManager.set_fog_hidden(unit, false)
	_hidden_units = still_hidden


## Reveal everything this overlay hid. Idempotent; the teardown path.
func _reveal_all() -> void:
	for unit in _hidden_units:
		if unit != null and is_instance_valid(unit):
			UnitVisualManager.set_fog_hidden(unit, false)
	_hidden_units.clear()


## The cells the veil is currently drawn over, in scan order. The rendered [MultiMesh]
## carries exactly this set -- one instance per entry, which is why a test can pin the
## RENDERED count against [code]multimesh.instance_count[/code] and the RENDERED placement
## against this.
##
## It exists because [method MultiMesh.get_instance_transform] is backed by the
## RenderingServer: under the headless dummy renderer it reads back identity for every
## instance, so the transforms themselves cannot be measured on a CI runner.
func shrouded_cells() -> Array[Vector2i]:
	return _hidden_cells.duplicate()


## Ask the HUD surfaces that CACHE a unit's identity to rebuild themselves, because the set
## of hidden units just changed.
##
## The [TurnQueue] is the only one: its chips are built once per turn boundary and each one
## bakes in a name, a portrait and a speed, so a unit revealed (or lost) MID-TURN would keep
## a stale chip until the next turn started -- long enough for a "???" to stay masked over a
## unit standing in plain sight, or worse, for a named chip to survive its unit stepping into
## the mist. Every other gate in this file is read live at draw/event time and needs nothing.
##
## Pushed rather than subscribed: [TurnQueue] is mounted deep inside GameUILayout by
## [UILayoutManager] and has no handle on this layer, and a fog signal on the global bus
## would be a second source of truth for something already answered by
## [method unit_hidden].
func _repaint_masked_hud() -> void:
	var scene := _scene_or_root()
	if scene == null:
		return
	var queue: Node = scene.find_child("TurnQueue", true, false)
	if queue != null and queue.has_method("_update_display"):
		queue.call("_update_display")


## The node to search the HUD from: the current scene in a real battle, else the tree root.
## The fallback matters for any host that mounts the battle without setting `current_scene`
## (GUT's command-line runner does exactly that), where the HUD is still in the tree and
## still needs finding.
func _scene_or_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func _board_units() -> Array:
	if CombatServices == null:
		return []
	var board = CombatServices.board()
	if board == null or not board.has_method("all_units"):
		return []
	return board.all_units()


# =============================================================================
# TOGGLE COURTESY
# =============================================================================

## One line, once per battle, when the map is authored with fog on -- so a player who did
## not read the map card still learns the rule before their first blind move. Routed through
## the ordinary [method ActionAnnouncer.announce] queue, so it takes its turn behind nothing
## and is styled like every other battle beat. Silent (and harmless) with no announcer
## mounted, which is every headless boot.
func announce_fog_intro() -> void:
	if _announced:
		return
	if not fog_active():
		return
	var announcer := _find_announcer()
	if announcer == null:
		return
	_announced = true
	announcer.announce("The mists close in", "Fog of war")


func _find_announcer() -> ActionAnnouncer:
	var scene := _scene_or_root()
	if scene == null:
		return null
	var found: Node = scene.find_child("ActionAnnouncer", true, false)
	return found as ActionAnnouncer
