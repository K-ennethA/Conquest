extends Node

# GameWorldManager
# Manages the initialization and setup of the game world based on GameSettings
# Now supports both local and network multiplayer modes and dynamic map loading

## The animated end-of-battle overlay scene (VICTORY / DEFEAT). Preloaded so the
## PackedScene is validated at load time; instantiated once in
## _setup_game_over_screen() and added to the "UI" CanvasLayer.
const GAME_OVER_SCREEN_SCENE := preload("res://game/ui/screens/GameOverScreen.tscn")

## Battle-juice layers, preloaded as SCRIPTS rather than referenced by their global
## class_name. Both are brand-new files, and a fresh checkout resolves a global class
## only once the editor/engine has rescanned -- a preload by path never has that problem.
const DAMAGE_NUMBERS_SCRIPT := preload("res://game/visuals/DamageNumbers.gd")
const IMPACT_FX_SCRIPT := preload("res://game/visuals/ImpactFX.gd")

var map_loader: MapLoader
var current_map_path: String = ""

## Tile-effect runtime (T14): resolves terrain effects (fire ticks damage, water
## buffs matching units, fortify) as units move and at each turn start. Created
## once; reads per-cell effects from [code]CombatServices.tile_effects_at[/code]
## via the system's injected lookup. Null-safe: handlers no-op until it and the
## live board exist.
var _tile_effect_system: TileEffectSystem = null
# The turn system the tile-effect per-turn tick is currently bound to (re-wired on switch).
var _tile_fx_watched_ts = null

## Terrain / tile inspection HUD (Fire Emblem-style terrain window): shows the
## terrain name, movement cost, and active tile effects for the cell under the
## board cursor. Self-contained -- see [TerrainInfoPanel] -- this just
## instantiates it and places it in the "UI" CanvasLayer once.
var _terrain_info_panel: TerrainInfoPanel = null

## Unit inspection HUD (bottom-right): shows the name, HP, and active status
## conditions of whatever unit is under the board cursor, WITHOUT requiring
## selection. Self-contained -- see [UnitHoverPanel] -- this just instantiates it
## and places it in the "UI" CanvasLayer once, exactly like the terrain panel.
var _unit_hover_panel: UnitHoverPanel = null

## Tile-effect map overlay (Node3D): floats a row of colored, billboarded pips
## over every cell that has one or more tile effects, so stacking (e.g. tall
## grass + a fire ignited on top) is visible on the 3D battlefield. Self-contained
## -- see [TileEffectOverlay] -- this just instantiates it and adds it to the 3D
## scene root (NOT the "UI" CanvasLayer). Rebuilds itself reactively off
## CombatServices.board_ready / tile_effects_changed.
var _tile_effect_overlay: TileEffectOverlay = null

## Animated end screen (see [GameOverScreen]). Instantiated once during setup and
## kept hidden; revealed by _on_player_eliminated() when the battle is decided.
var _game_over_screen: GameOverScreen = null

## Full-screen ULTIMATE cut-in flash (see [UltimateCutIn]). Its own CanvasLayer, mounted
## once during setup and left idle; it self-triggers off GameEvents.ultimate_casting when a
## unit fires its signature move, and the cast sites await its `finished` so the flash plays
## BEFORE the move resolves. Null until _setup_ultimate_cutin runs.
var _ultimate_cutin: UltimateCutIn = null
## The current map's compiled win/lose objectives (built at map load from
## MapResource.victory_conditions). Null until a map is loaded; when set, it drives
## the single-player end check in _evaluate_game_end.
var _game_mode_rules: GameModeRules = null
## Human faction slot for win-condition scoring.
const HUMAN_FACTION: int = 0

## Runtime spawn scheduler (see [SpawnManager]): fires the authored spawn KINDS that
## MapLoader leaves inert -- staggered Reinforcements, Respawns after a unit dies, and
## endless waves. Created fresh per battle in _setup_spawn_manager() after the board is
## rebuilt, and freed + recreated on the next map load so its per-point state and turn
## counter reset cleanly between games. Null before the first map finishes loading.
var _spawn_manager: SpawnManager = null

## Runtime hazard runtime (see [HazardManager]): advances every live [TravelingHazard]
## (Forest Barrage's crawling vine) one band per player-turn. Created fresh per battle
## in _setup_hazard_manager() beside the spawn manager, and freed + recreated on the
## next map load so no in-flight vine leaks between battles. Null before the first map
## finishes loading.
var _hazard_manager: HazardManager = null

## Runtime item runtime (see [ItemSystem]): applies the player's PERSISTENT equipped items
## (per-character and team-wide) to their units at the first turn boundary, and rolls the
## post-battle drop that grows the collection. Created fresh per battle in
## _setup_item_system() beside the spawn/hazard managers, and freed + recreated on the next
## map load so its per-battle latches reset. The collection itself is process-wide static
## state in [ItemInventory] and outlives this node.
var _item_system: ItemSystem = null

## Floating combat numbers (see [DamageNumbers]) and code-built impact particles (see
## [ImpactFX]): two additive Node3D presentation layers mounted in the 3D scene root
## beside [TileEffectOverlay]. Created fresh per battle in _setup_damage_numbers() /
## _setup_impact_fx() -- the same free-then-recreate discipline as the spawn/hazard/item
## runtimes -- so no popup or particle burst can outlive the battle that produced it.
## Both self-wire to GameEvents in their own _ready; there is nothing to connect here.
var _damage_numbers: Node3D = null
var _impact_fx: Node3D = null

## Mid-battle SAVE & RESUME seam (see [BattleSaveManager]). Mounted once per battle as a
## child so the pause menu can find it through group &"battle_save_manager" and ask it
## can_save_now() / save_and_quit(). Battle-scoped like the runtimes above; the save FILE
## itself is process-wide static state and outlives this node.
var _battle_save_manager: BattleSaveManager = null

## The snapshot this battle is being RESTORED from, consumed in _maybe_restore_battle_snapshot
## and then replayed in stages across setup (see that method for the four phases). Empty for
## an ordinary battle, which is every code path below's "do nothing" case.
var _restore_snapshot: Dictionary = {}
## Units re-spawned from [member _restore_snapshot], positionally aligned with its "units"
## array (index N in the file is index N here). Empty outside a restore.
var _restored_units: Array = []

func _ready() -> void:
	# Discoverable by decoupled systems that need to spawn units mid-battle without a
	# hard reference (e.g. SummonEffect reaches summon_unit() via this group).
	add_to_group("game_world_manager")

	# Save & quit seam, mounted BEFORE the map load so the pause menu can always resolve it
	# (it answers can_save_now() == false until a battle is actually in progress).
	_setup_battle_save_manager()

	# Initialize map loader
	map_loader = MapLoader.new()
	add_child(map_loader)

	# Connect map loader signals
	map_loader.map_loaded.connect(_on_map_loaded)
	map_loader.map_load_failed.connect(_on_map_load_failed)

	# Stand up the tile-effect runtime and connect it to movement + turn events so
	# terrain affects combat. Done before any map load so the hooks are live for
	# the very first move/turn.
	_setup_tile_effects()

	# Wait a frame for all singletons to be ready. Backing out of the battle during boot
	# (Main Menu, a rematch, an Arena hand-off) frees this node mid-await; everything
	# below touches `self` and the live tree, so bail if we are no longer in it.
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Terrain inspection HUD: purely additive overlay, safe to add before the
	# map finishes loading -- it resolves the live board lazily on each cursor
	# move (via GameEvents.cursor_moved, wired in its own _ready) and simply
	# stays hidden until a board and registered terrain exist.
	_setup_terrain_info_panel()

	# Unit inspection HUD: same deal -- additive, resolves the live board lazily on
	# each cursor move, and stays hidden until the cursor is over an actual unit.
	_setup_unit_hover_panel()

	# End-of-battle overlay: additive, hidden until an elimination decides the
	# game. Added to the same "UI" CanvasLayer as the terrain panel and safe to
	# create now -- nobody is eliminated at boot, so it just sits hidden.
	_setup_game_over_screen()

	# Tile-effect 3D overlay: additive Node3D floating effect pips over affected
	# cells. Added to the 3D scene root (not the CanvasLayer) and, like the terrain
	# panel, safe to add before the map loads -- it rebuilds itself on
	# CombatServices.board_ready and stays empty until a board/effects exist.
	_setup_tile_effect_overlay()

	# Ultimate cut-in flash: its own high CanvasLayer overlay, additive and hidden until a
	# unit fires an ultimate. Safe to add now -- it stays idle until GameEvents.ultimate_casting.
	_setup_ultimate_cutin()

	# Battle REPLAY recorder: a headless listener that logs every committed command. Mounted
	# BEFORE the map/players load so it is subscribed in time for the very first turn (it
	# latches its header on the first turn_started, once the roster exists).
	_setup_replay_recorder()

	# Load the selected map or default map
	await _load_selected_map()
	if not is_inside_tree():
		return

	# RESUMED BATTLE: swap the map's authored units for the saved ones before players are
	# set up, so the ordinary ownership/turn-registration passes below adopt them unchanged.
	# A no-op for every ordinary battle.
	_maybe_restore_battle_snapshot()

	# Networked matches (GameMode.MULTIPLAYER) boot through the SAME deterministic setup
	# as solo/hotseat: both peers build an identical board locally, and the NetSession
	# command seam installed per map load (_install_command_seam) keeps them in lockstep.
	await _setup_local_game()


## Runtime-summon a unit MID-BATTLE (the Necromancer's Reanimate / Undying Legion).
##
## [method MapLoader.spawn_unit_now] alone yields a board-visible but OWNERLESS and
## TURN-LESS puppet, so this does the two load-bearing follow-ups it omits: it hands the
## unit an owner ([PlayerManager]) and registers it with the active turn system, then
## marks it as having already acted so it holds the summon turn and only acts next turn
## (the same "summoning sickness" [SpawnManager]'s runtime spawns use). Returns the new
## [Unit], or null if the summon could not be placed. Null-safe end to end.
func summon_unit(character_id: StringName, cell: Vector2i, player_id: int, stance: String = "aggressive", net_id: int = -1) -> Node:
	if map_loader == null:
		return null
	var unit = map_loader.spawn_unit_now({
		"position": cell,
		"player_id": player_id,
		"character_id": String(character_id),
		"spawn_kind": "Reinforcement",
		"ai_stance": stance,
	})
	if unit == null:
		return null
	# Networked command layer (CommandApplier) passes a deterministic net_id derived
	# from the summoning command's seq so every peer names the same body identically.
	# -1 (the default, single-player path) leaves the unit untagged exactly as before;
	# CommandApplier can still assign an id reactively from the resolved event log.
	if net_id >= 0:
		unit.set_meta("net_id", net_id)
	# spawn_unit_now does NOT assign an owner or turn-register -- do both explicitly, else
	# the summon is neither ally nor enemy to anyone and never takes a turn.
	if PlayerManager != null:
		PlayerManager.assign_unit_to_player(unit, player_id)
	if TurnSystemManager != null and TurnSystemManager.has_active_turn_system():
		var ts := TurnSystemManager.get_active_turn_system()
		if ts != null and ts.has_method("register_unit"):
			ts.register_unit(unit)
	# Hold the turn it was raised on; it becomes actable next turn.
	if unit.has_method("mark_action_completed"):
		unit.mark_action_completed("spawn")
	return unit

func _load_selected_map() -> void:
	"""Load the selected map or create a default one"""

	# Get selected map from GameSettings or use default
	var selected_map = GameSettings.get_selected_map() if GameSettings.has_method("get_selected_map") else ""
	
	if selected_map.is_empty():
		# Create and save default map if none exists
		var available_maps = MapLoader.get_available_maps()
		if available_maps.is_empty():
			var default_map = MapLoader.create_default_map()
			MapLoader.save_map(default_map, "default_skirmish")
			selected_map = "res://game/maps/resources/default_skirmish.tres"
		else:
			selected_map = available_maps[0]
	
	current_map_path = selected_map
	
	# Find the Map node in the scene. current_scene is NULL mid-transition (and this runs
	# after several awaits in _ready), so chaining straight off it is a null-instance
	# error waiting to happen.
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var map_node = scene_root.get_node_or_null("Map")
	if not map_node:
		return

	# Clear existing map content but keep the Map node structure
	_clear_existing_map_content(map_node)
	
	# Load the new map
	var success = map_loader.load_map_from_file(selected_map, map_node)
	if not success:
		var default_map = MapLoader.create_default_map()
		map_loader.load_map(default_map, map_node)

func _clear_existing_map_content(map_node: Node3D) -> void:
	"""Clear existing hardcoded map content while preserving structure"""
	# The old board's Unit nodes are about to be freed; drop the shared adapter
	# so nothing reads stale units before the next rebuild on map load.
	CombatServices.clear()

	# Remove existing tiles
	var tiles_node = map_node.get_node_or_null("Tiles")
	if tiles_node:
		for child in tiles_node.get_children():
			child.free()  # Immediate deletion
		tiles_node.free()  # Immediate deletion
	
	# Remove existing player containers
	var player1_node = map_node.get_node_or_null("Player1")
	if player1_node:
		for child in player1_node.get_children():
			child.free()  # Immediate deletion
		player1_node.free()  # Immediate deletion
	
	var player2_node = map_node.get_node_or_null("Player2")
	if player2_node:
		for child in player2_node.get_children():
			child.free()  # Immediate deletion
		player2_node.free()  # Immediate deletion

func _on_map_loaded(map_resource: MapResource) -> void:
	"""Handle successful map loading"""

	# Rebuild the shared live BoardAdapter against the freshly populated "Map"
	# node so movement/attacks/AI/tiles all read the new board. map_loader.map_root
	# is the target parent the loader just filled with units and tiles.
	if map_loader and map_loader.map_root:
		CombatServices.rebuild(map_loader.map_root)

	# Stand up the runtime spawn scheduler for THIS battle. Done after the rebuild so
	# it can adopt the load-time seed units off the fresh board (to time their deaths).
	_setup_spawn_manager()

	# Battle juice for THIS battle: floating damage/heal numbers and impact particles.
	# Recreated per load like the runtimes above, so a second battle in the same app run
	# never inherits a popup or a burst from the previous one.
	_setup_damage_numbers()
	_setup_impact_fx()

	# Stand up the per-battle hazard runtime alongside it, so crawling vines cast this
	# battle tick forward and none leak into the next one.
	_setup_hazard_manager()

	# Stand up the per-battle item runtime beside them: it stamps the player's equipped items
	# onto their units at the first turn boundary (see [ItemSystem] for why not here) and
	# rolls the post-battle drop that grows the collection.
	_setup_item_system()

	# Stand up the networked command seam for THIS battle: a fresh CommandApplier +
	# UnitRegistry bound to the units just spawned on the rebuilt board, handed to
	# NetSession. This is what lets resolved commands drive the ONE mutation point on
	# every peer. Rebuilt each map load so no stale applier outlives its board.
	_setup_command_seam()

	# Compile THIS map's authored win conditions into a live rule set. This is what
	# makes objectives per-map: a boss map ends on the boss's death, a skirmish on a
	# wipe -- same engine, different WinCondition list (see _evaluate_game_end).
	_game_mode_rules = WinConditionLibrary.build_rules(map_resource.victory_conditions)

	# Light the battle: a sun + sky ambient so the 3D map reads with depth and
	# shadow instead of flat ambient. The scene shipped with a WorldEnvironment but
	# NO key light, which is why everything looked washed out.
	_setup_lighting(map_resource)

	# Update GameSettings with map info if available
	if GameSettings.has_method("set_current_map"):
		GameSettings.set_current_map(map_resource)

func _on_map_load_failed(error_message: String) -> void:
	"""Handle map loading failure"""

	# Try to load default map as fallback. Same null-current_scene hazard as
	# _load_selected_map: a load failure can itself coincide with a transition.
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var default_map = MapLoader.create_default_map()
	var map_node = scene_root.get_node_or_null("Map")
	if map_node:
		map_loader.load_map(default_map, map_node)

# --- Terrain inspection HUD --------------------------------------------------
#
# NOTE on the _setup_* helpers below: each one mounts an OPTIONAL overlay and bails
# silently when there is no current_scene or no "UI" CanvasLayer to mount into. Those
# bails used to push_warning, but both are EXPECTED conditions -- they happen on every
# scene transition and in every scene that is not GameWorld.tscn -- so they filled the
# debugger with warnings for a HUD that is meant to be additive. The early return IS the
# report; a real missing-HUD bug shows up as a missing HUD.

func _setup_terrain_info_panel() -> void:
	"""Instantiate TerrainInfoPanel and add it to the "UI" CanvasLayer (sibling of
	this node in GameWorld.tscn -- see the "UI" CanvasLayer node there). The panel
	builds its own UI, themes itself, and connects GameEvents.cursor_moved itself
	in _ready, so there is nothing else to wire up here."""
	if _terrain_info_panel != null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var ui_layer := scene_root.get_node_or_null("UI")
	if ui_layer == null:
		return

	_terrain_info_panel = TerrainInfoPanel.new()
	ui_layer.add_child(_terrain_info_panel)

func _setup_unit_hover_panel() -> void:
	"""Instantiate UnitHoverPanel and add it to the "UI" CanvasLayer. Mirrors
	_setup_terrain_info_panel exactly, including its null guards: the panel builds
	its own UI, themes itself, and connects GameEvents.cursor_moved in its own
	_ready, so there is nothing else to wire up here. It anchors bottom-right, the
	one HUD corner the terrain panel / right sidebar / turn banner do not use."""
	if _unit_hover_panel != null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var ui_layer := scene_root.get_node_or_null("UI")
	if ui_layer == null:
		return

	_unit_hover_panel = UnitHoverPanel.new()
	ui_layer.add_child(_unit_hover_panel)

# --- End-of-battle screen ----------------------------------------------------

func _setup_lighting(map_resource: MapResource) -> void:
	"""Give the battle scene a proper key light + sky ambient so tiles and units read
	with form and shadow. Older GameWorld scenes carry a WorldEnvironment (sky +
	tonemap) but no DirectionalLight3D, so the map is lit by weak ambient alone and
	looks flat. This creates the sun once (reused across map loads) and tunes it +
	the ambient from the map's lighting_preset -- the field existed but nothing read
	it. Best-effort: no scene / no environment simply skips."""
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var sun := scene_root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		scene_root.add_child(sun)
	# Angled from above-front so faces catch light and cast readable shadows.
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.shadow_enabled = true

	var sun_color := Color(1.0, 0.96, 0.88)
	var sun_energy := 1.7
	var ambient_energy := 0.6
	match str(map_resource.lighting_preset):
		"Night":
			sun_color = Color(0.62, 0.70, 0.95)
			sun_energy = 0.55
			ambient_energy = 0.20
		"Dawn", "Dusk":
			sun_color = Color(1.0, 0.78, 0.62)
			sun_energy = 1.0
			ambient_energy = 0.30
		_:
			pass  # Day / Default: the warm values above
	sun.light_color = sun_color
	sun.light_energy = sun_energy

	# Sky-sourced ambient so shadowed sides aren't crushed to black.
	var we := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env: Environment = we.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = ambient_energy


func _setup_game_over_screen() -> void:
	"""Instantiate GameOverScreen and add it to the "UI" CanvasLayer (mirrors
	_setup_terrain_info_panel), then connect the elimination signals that drive it.
	The screen builds/themes itself and stays hidden until an outcome is decided.
	We connect BOTH PlayerManager.player_eliminated (the one that reliably fires,
	see player_manager.gd ~line 440) and GameEvents.player_eliminated (fallback);
	the handler + the screen's own _shown guard make a double-fire harmless."""
	if _game_over_screen != null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var ui_layer := scene_root.get_node_or_null("UI")
	if ui_layer == null:
		return

	_game_over_screen = GAME_OVER_SCREEN_SCENE.instantiate() as GameOverScreen
	ui_layer.add_child(_game_over_screen)

	if PlayerManager and not PlayerManager.player_eliminated.is_connected(_on_player_eliminated):
		PlayerManager.player_eliminated.connect(_on_player_eliminated)
	if GameEvents and not GameEvents.player_eliminated.is_connected(_on_player_eliminated):
		GameEvents.player_eliminated.connect(_on_player_eliminated)
	# Also re-check on any unit death: an objective like "Defeat Boss" is decided the
	# instant the BOSS dies, which does NOT eliminate a whole player while its grunts
	# still stand -- player_eliminated alone would miss that moment.
	if GameEvents and not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated):
		GameEvents.unit_eliminated.connect(_on_unit_eliminated)


func _setup_replay_recorder() -> void:
	"""Mount the battle REPLAY recorder once per battle. Like the overlays above it is
	entirely self-contained (see [ReplayRecorder]): it joins the "replay_recorder" group,
	subscribes to GameEvents.command_committed and the ACTIVE turn system's turn signals in
	_ready, latches its header on the first turn, and writes user://replays/<file> when the
	battle finalizes -- so there is nothing to wire here beyond adding it to the tree.

	Recording is ON by default for real battles (ReplayRecorder.recording_enabled); it costs
	one signal connection and a dictionary append per committed command, and the challenge
	base-defense flow needs the log. Added as a child of THIS node rather than the scene root
	so it is torn down with the battle, which is what triggers the save-on-quit path."""
	if get_node_or_null("ReplayRecorder") != null:
		return
	if not ReplayRecorder.recording_enabled:
		return
	var recorder := ReplayRecorder.new()
	recorder.name = "ReplayRecorder"
	add_child(recorder)


func _setup_ultimate_cutin() -> void:
	"""Mount the ULTIMATE cut-in overlay once. It is a self-contained CanvasLayer (see
	[UltimateCutIn]) that builds its own UI, joins the "ultimate_cutin" group, and connects to
	GameEvents.ultimate_casting itself in _ready -- so there is nothing to wire here beyond
	adding it to the tree. Added to the current scene root (its own layer index handles draw
	order above the HUD), mirroring how the other self-contained overlays are mounted."""
	if _ultimate_cutin != null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	_ultimate_cutin = UltimateCutIn.new()
	_ultimate_cutin.name = "UltimateCutIn"
	scene_root.add_child(_ultimate_cutin)


## Latch so an ARENA round resolves exactly once: the enemy-wipe fires BOTH unit_eliminated
## and player_eliminated, and after ArenaController finishes the run it is no longer active,
## so a second _evaluate_game_end would fall through to the normal game-over path (which
## paused/torn-down the tree). Reset naturally each round (fresh GameWorld scene).
var _arena_battle_resolved: bool = false

func _on_player_eliminated(_player) -> void:
	_evaluate_game_end(null)


func _on_unit_eliminated(unit, _eliminator) -> void:
	_evaluate_game_end(unit)


func _evaluate_game_end(just_removed) -> void:
	"""Decide win/lose and reveal the end screen once (idempotent).

	Single-player is MAP-DRIVEN: the map's compiled win/lose objectives
	(_game_mode_rules, built at load from MapResource.victory_conditions) are scored
	over the live board, so each map ends on its own terms -- kill the boss, clear
	the field, hold an objective. [param just_removed] is the unit that just died (or
	null for a player-elimination trigger); it is folded into the scored state so a
	boss death is visible on the very tick it happens, even after the board has
	dropped it. Versus/multiplayer keeps the neutral "last side standing wins"
	fallback."""
	if _game_over_screen == null or _game_over_screen.is_shown():
		return

	# Once an arena round has resolved this battle, ignore any further elimination signals
	# (see _arena_battle_resolved) so a trailing player_eliminated can't run the normal
	# game-over path after ArenaController has already handed off to the draft/results.
	if _arena_battle_resolved:
		return

	# ARENA rounds resolve into the Arena loop (draft / next round), NOT the normal end
	# screen. A round is won when the enemy wave is routed and lost when the player squad
	# is wiped. ArenaController owns what happens next; this is a no-op when not in a run.
	var arena = get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("is_active") and arena.is_active():
		var human_alive: bool = false
		var enemy_alive: bool = false
		for ap in PlayerManager.players:
			if ap == null or not ap.has_units_remaining():
				continue
			# NEUTRAL camps never count toward round win/loss -- a round is won when the
			# real enemy wave is routed even if a dormant neutral is still standing.
			if "is_neutral" in ap and bool(ap.is_neutral):
				continue
			if "is_ai" in ap and bool(ap.is_ai):
				enemy_alive = true
			else:
				human_alive = true
		# DEFER the hand-off: _evaluate_game_end runs deep inside the death -> combat ->
		# turn signal cascade. Changing scene (draft/results) from there means the round's
		# remaining signal handlers fire mid-teardown and crash on a null scene. call_deferred
		# lets this frame's cascade finish on the intact scene, then the transition runs clean.
		if not enemy_alive:
			_arena_battle_resolved = true
			arena.call_deferred("notify_round_ended", true)
		elif not human_alive:
			_arena_battle_resolved = true
			arena.call_deferred("notify_round_ended", false)
		return

	var single_player: bool = GameSettings != null and GameSettings.game_mode == GameSettings.GameMode.SINGLE_PLAYER

	if single_player and _game_mode_rules != null:
		var state: Dictionary = _build_win_state(just_removed)
		var outcome: int = _game_mode_rules.evaluate(state)
		if outcome == GameModeRules.Outcome.VICTORY:
			_game_over_screen.show_victory()
		elif outcome == GameModeRules.Outcome.DEFEAT:
			_game_over_screen.show_defeat()
		return

	# Versus / multiplayer (or single-player before a map's rules are built): end
	# when at most one side is still standing.
	var alive: Array[Player] = []
	for p in PlayerManager.players:
		if p != null and p.current_state != Player.PlayerState.ELIMINATED and p.has_units_remaining():
			alive.append(p)
	if alive.size() <= 1:
		var winner_name: String = alive[0].get_display_name() if alive.size() == 1 else "No one"
		_game_over_screen.show_result(
			GameOverScreen.OUTCOME_VICTORY,
			winner_name.to_upper() + " WINS",
			"The battle is decided."
		)


## Assemble the neutral state dict a [WinCondition] scores against: every living
## unit on the board, plus [param just_removed] (the unit that just died, which the
## board may already have dropped -- including it is how "the boss is dead" is seen
## on the death tick rather than a frame later). Schema: see WinCondition.gd.
func _build_win_state(just_removed) -> Dictionary:
	var units: Array = []
	var board = CombatServices.board() if CombatServices != null else null
	if board != null and board.has_method("all_units"):
		for u in board.all_units():
			units.append(u)
	if just_removed != null and just_removed not in units:
		units.append(just_removed)
	return { "units": units, "board": board, "turn": 0 }

func _setup_tile_effect_overlay() -> void:
	"""Instantiate TileEffectOverlay and add it to the 3D scene root (GameWorld
	scene root / get_tree().current_scene). Unlike TerrainInfoPanel this is a
	Node3D, so it goes in the 3D world -- NOT the "UI" CanvasLayer. The overlay
	builds its own pips and connects CombatServices.board_ready /
	tile_effects_changed itself in _ready, so there is nothing else to wire up."""
	if _tile_effect_overlay != null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_tile_effect_overlay = TileEffectOverlay.new()
	scene_root.add_child(_tile_effect_overlay)

# --- Runtime spawn scheduler ------------------------------------------------

func _setup_spawn_manager() -> void:
	"""Create (or recreate) the per-battle SpawnManager and hand it the freshly loaded
	map. Frees any prior instance first so a second+ battle in the same app run starts
	with a clean schedule and turn counter -- this node is deliberately battle-scoped,
	unlike the autoloads that survive scene changes. setup() wires it to the per-turn
	signal and adopts the load-time seed units from the board rebuilt just above."""
	if _spawn_manager != null and is_instance_valid(_spawn_manager):
		_spawn_manager.queue_free()
	_spawn_manager = null

	if map_loader == null or map_loader.current_map == null:
		return

	_spawn_manager = SpawnManager.new()
	_spawn_manager.name = "SpawnManager"
	add_child(_spawn_manager)
	_spawn_manager.setup(map_loader, map_loader.current_map)

# --- Battle juice (floating numbers + impact particles) ---------------------

func _setup_damage_numbers() -> void:
	"""Create (or recreate) the per-battle [DamageNumbers] layer, mirroring
	_setup_spawn_manager's free-then-recreate discipline. Unlike the spawn/hazard/item
	runtimes this is a Node3D, so it goes in the 3D scene root (like TileEffectOverlay),
	NOT the "UI" CanvasLayer. It subscribes to GameEvents in its own _ready -- there is
	nothing to wire here. Bails silently without a current_scene: that is an expected
	condition on every scene transition, and the missing numbers ARE the report."""
	if _damage_numbers != null and is_instance_valid(_damage_numbers):
		_damage_numbers.queue_free()
	_damage_numbers = null

	# Guard get_tree() too, not just current_scene: a map load can land on the same frame
	# as a scene hand-off (Rematch / Arena), which detaches this node mid-call.
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene_root: Node = tree.current_scene

	_damage_numbers = DAMAGE_NUMBERS_SCRIPT.new()
	scene_root.add_child(_damage_numbers)

func _setup_impact_fx() -> void:
	"""Create (or recreate) the per-battle [ImpactFX] layer, exactly as
	_setup_damage_numbers does -- same 3D scene-root mount, same per-battle lifetime,
	same self-wiring."""
	if _impact_fx != null and is_instance_valid(_impact_fx):
		_impact_fx.queue_free()
	_impact_fx = null

	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene_root: Node = tree.current_scene

	_impact_fx = IMPACT_FX_SCRIPT.new()
	scene_root.add_child(_impact_fx)

# --- Networked command seam (CommandApplier + registry per battle) ----------

func _setup_command_seam() -> void:
	"""Build the live command seam for this battle and hand it to NetSession.

	Constructs a fresh [CommandApplier] over a new [CommandApplier.UnitRegistry], assigns
	deterministic net_ids to the freshly spawned units in load order (board tree order,
	identical on every peer for identical match settings), and installs the applier plus a
	board provider on NetSession. In NON-networked play it also negotiates a solo match seed
	so per-command RNG is available (single-player is the degenerate local case of lockstep).

	Rebuilt per map load so the applier/registry never outlive the board they mutate; the
	stale seam is dropped in _exit_tree and replaced here on the next load."""
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return
	var board = CombatServices.board() if CombatServices != null else null
	if board == null:
		return

	var registry := CommandApplier.UnitRegistry.new()
	# Deterministic load order: BoardAdapter.all_units() follows the map's tree order,
	# which is identical across peers loading the same map + squads. Ids start at 1.
	var units: Array = []
	if board.has_method("all_units"):
		units = board.all_units()
	registry.assign_map_units(units)

	var applier := CommandApplier.new(registry, NetSession.match_rng)
	NetSession.install_command_seam(applier, _seam_board_provider)

	# Non-networked play (solo / hotseat / local versus): negotiate a solo match seed so
	# the applier's per-command RNG stream exists. Networked play already negotiated the
	# match seed via the lobby commit-reveal handshake, so we must not clobber it.
	if not NetSession.is_networked_match():
		NetSession.begin_solo_match_rng()
		applier.match_rng = NetSession.match_rng

func _seam_board_provider():
	"""Board provider handed to NetSession: resolves the CURRENT live board each apply,
	so the seam always mutates the board rebuilt for this battle (never a stale one)."""
	return CombatServices.board() if CombatServices != null else null

func _exit_tree() -> void:
	"""Battle scene is being torn down: drop the command seam so a stale applier never
	outlives the board it mutated. Null-safe -- a no-op if NetSession is absent."""
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null:
		NetSession.clear_command_seam()
	# The juice layers are parented to the SCENE ROOT, not to this node, so they are not
	# freed with us. The scene root normally takes them, but dropping them explicitly means
	# a hand-off that reuses the root (Rematch / Arena) can never inherit the old layers.
	if _damage_numbers != null and is_instance_valid(_damage_numbers):
		_damage_numbers.queue_free()
	_damage_numbers = null
	if _impact_fx != null and is_instance_valid(_impact_fx):
		_impact_fx.queue_free()
	_impact_fx = null

# --- Mid-battle save & resume ------------------------------------------------

func _setup_battle_save_manager() -> void:
	"""Mount the per-battle [BattleSaveManager]. It joins group &"battle_save_manager" in its
	own _ready, which is how the pause menu finds it -- nothing else is wired here. Created
	once per GameWorld scene (this node is battle-scoped), unlike the save FILE, which is
	process-wide static state in BattleSaveManager itself."""
	if _battle_save_manager != null and is_instance_valid(_battle_save_manager):
		return
	_battle_save_manager = BattleSaveManager.new()
	_battle_save_manager.name = "BattleSaveManager"
	add_child(_battle_save_manager)


## The per-battle spawn scheduler / hazard runtime, for the save layer. Read-only accessors:
## both are created and owned here (see _setup_spawn_manager / _setup_hazard_manager), and
## [BattleSaveManager] needs them to capture and restore their per-battle clocks.
func get_spawn_manager() -> SpawnManager:
	return _spawn_manager


func get_hazard_manager() -> HazardManager:
	return _hazard_manager


func _maybe_restore_battle_snapshot() -> void:
	"""RESUMED BATTLE, phase 1 -- the one entry point for restoring a saved battle.

	Runs immediately after the map has loaded (so the board, the spawn/hazard/item runtimes
	and the map's own authored units all exist) and BEFORE _setup_local_game, which is what
	registers players and assigns unit ownership by parent container. That ordering is the
	whole reason this is the insertion point: replacing the units HERE means the ordinary
	ownership + turn-registration passes adopt the restored board exactly as they would a
	fresh one, with no bespoke adoption code.

	The remaining phases are:
	  * phase 2 -- _setup_local_game, after the turn system is registered (tick suppression)
	  * phases 3 + 4 -- _finish_battle_restore, after _start_game (turn state, schedulers)

	A no-op unless a resume was staged from the main menu."""
	_restore_snapshot = {}
	_restored_units = []
	if not BattleSaveManager.has_pending_resume():
		return
	# Consuming DELETES the slot: a save is single-use, and a restore that fails part-way
	# must not leave a file that would be retried into the same failure on the next launch.
	var snapshot: Dictionary = BattleSaveManager.take_pending_resume()
	if snapshot.is_empty() or map_loader == null:
		return

	_restored_units = BattleSaveManager.restore_units(map_loader, snapshot)
	BattleSaveManager.restore_board(snapshot)
	_restore_snapshot = snapshot


func _finish_battle_restore() -> void:
	"""RESUMED BATTLE, phases 3 + 4. Split from _maybe_restore_battle_snapshot because both
	steps need the turn system to be ACTIVE, which only happens inside _start_game."""
	if _restore_snapshot.is_empty():
		return
	BattleSaveManager.restore_turn_state(_restore_snapshot, _restored_units)
	BattleSaveManager.restore_managers(_restore_snapshot, _spawn_manager, _hazard_manager, _restored_units)
	_restore_snapshot = {}


func _setup_item_system() -> void:
	"""Create (or recreate) the per-battle ItemSystem, mirroring _setup_hazard_manager. Frees
	any prior instance first so a second+ battle starts with a clean applied/drop-rolled latch
	-- this node is battle-scoped, while the player's collection itself lives in the
	process-wide static ItemInventory. setup() wires it to the ACTIVE turn system's per-turn
	signal (the only one that fires on AI turns too) and to the elimination signals that
	decide the post-battle drop."""
	if _item_system != null and is_instance_valid(_item_system):
		_item_system.queue_free()
	_item_system = null

	_item_system = ItemSystem.new()
	_item_system.name = "ItemSystem"
	add_child(_item_system)
	_item_system.setup()

func _setup_hazard_manager() -> void:
	"""Create (or recreate) the per-battle HazardManager, mirroring _setup_spawn_manager.
	Frees any prior instance first so a second+ battle starts with no leftover vines --
	this node is battle-scoped, unlike the autoloads that survive scene changes. setup()
	wires it to the per-turn tick and the GameEvents spawn-request seam."""
	if _hazard_manager != null and is_instance_valid(_hazard_manager):
		_hazard_manager.queue_free()
	_hazard_manager = null

	_hazard_manager = HazardManager.new()
	_hazard_manager.name = "HazardManager"
	add_child(_hazard_manager)
	_hazard_manager.setup()

# --- Tile effects (T14) -----------------------------------------------------

func _setup_tile_effects() -> void:
	"""Instantiate the TileEffectSystem and wire it to movement + turn events."""
	if _tile_effect_system == null:
		_tile_effect_system = TileEffectSystem.new()
		_tile_effect_system.name = "TileEffectSystem"
		add_child(_tile_effect_system)

	# Movement: run ON_EXIT on the tile a unit leaves, ON_ENTER on the tile it
	# steps onto. GameEvents.unit_moved carries Vector3(col, 0, row) grid coords
	# (the documented legacy contract), so we read cells straight off .x/.z.
	if GameEvents and not GameEvents.unit_moved.is_connected(_on_unit_moved_tile_effects):
		GameEvents.unit_moved.connect(_on_unit_moved_tile_effects)

	# Turn start: tick ON_TURN_START_WHILE_OCCUPYING for each unit the active player
	# owns. This rides the ACTIVE TURN SYSTEM's turn_started -- the signal that truly
	# fires every turn (human and AI). PlayerManager.player_turn_started only fires on
	# game start + the human's End-Turn button, so occupying-tile effects never ticked
	# during the AI phase. Mirrors SpawnManager / TurnIndicator wiring.
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated_tile_effects):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated_tile_effects)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated_tile_effects(TurnSystemManager.get_active_turn_system())


## (Re)wire the tile-effect turn tick to the active turn system's turn_started.
func _on_turn_system_activated_tile_effects(ts) -> void:
	if _tile_fx_watched_ts == ts:
		return
	if _tile_fx_watched_ts != null and is_instance_valid(_tile_fx_watched_ts) \
			and _tile_fx_watched_ts.turn_started.is_connected(_on_player_turn_started_tile_effects):
		_tile_fx_watched_ts.turn_started.disconnect(_on_player_turn_started_tile_effects)
	_tile_fx_watched_ts = ts
	if ts != null and not ts.turn_started.is_connected(_on_player_turn_started_tile_effects):
		ts.turn_started.connect(_on_player_turn_started_tile_effects)

func _prime_tile_effects(cell: Vector2i):
	"""Feed the system the effects on `cell` (base + runtime) through its injected
	lookup, recomputed each event so tile transforms and runtime ignite/douse are
	always reflected. Returns the live board, or null if it/the system is absent."""
	if _tile_effect_system == null:
		return null
	var board = CombatServices.board()
	if board == null:
		return null
	_tile_effect_system.tile_effects[cell] = CombatServices.tile_effects_at(cell)
	return board

func _on_unit_moved_tile_effects(unit, from_position, to_position) -> void:
	"""Terrain enter/exit hook. from/to are Vector3(col, 0, row) grid coords."""
	if unit == null or _tile_effect_system == null:
		return
	var from_cell := Vector2i(int(round(from_position.x)), int(round(from_position.z)))
	var to_cell := Vector2i(int(round(to_position.x)), int(round(to_position.z)))
	var board = _prime_tile_effects(from_cell)
	if board != null:
		_tile_effect_system.on_exit(unit, from_cell, board)
	board = _prime_tile_effects(to_cell)
	if board != null:
		_tile_effect_system.on_enter(unit, to_cell, board)

func _on_player_turn_started_tile_effects(player) -> void:
	"""At each player's turn start, tick occupying-tile effects for their units."""
	if player == null or _tile_effect_system == null:
		return
	var board = CombatServices.board()
	if board == null:
		return
	for unit in player.owned_units:
		if unit == null:
			continue
		var cell: Vector2i = board.cell_of(unit)
		_prime_tile_effects(cell)
		_tile_effect_system.on_turn_start(unit, board)

func _setup_local_game() -> void:
	"""Set up local single-player or local multiplayer game"""

	# Reset per-session autoload state FIRST. Autoloads survive scene changes, so on a
	# second+ game these still hold the previous session's players (with freed units)
	# and an active turn system -- which wedges turn advancement and leaves the game
	# state stuck off SETUP so start_game() never re-activates a turn system.
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()

	# ARENA: the arena maps ship unit-less, so fill the board with the run's squad (player
	# 0) + this round's escalating enemy wave (player 1) BEFORE players are assigned, so
	# the normal assign_units_by_parent pass below adopts them. No-op outside an arena run.
	var arena_ctrl = get_node_or_null("/root/ArenaController")
	if arena_ctrl != null and arena_ctrl.has_method("is_active") and arena_ctrl.is_active():
		ArenaRoundBuilder.build_round(map_loader, arena_ctrl.run(), arena_ctrl.ruleset())
		# (Run HUD removed -- the round is already in the turn banner and the squad is on
		# the board, so the overlay was redundant and collided with the SELECT MOVE popup.)

	# Initialize player management first
	_setup_players()
	
	# Wait another frame to ensure units are properly assigned
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Apply game settings (this will set up turn systems with units already assigned)
	if GameSettings:
		GameSettings.apply_settings_to_game()

	# RESUMED BATTLE, phase 2: the turn system now EXISTS but has not started. Stamp its
	# per-turn tick latch for every restored unit so the turn it opens with does not tick
	# statuses / cooldowns / abilities a second time (see BattleSaveManager).
	if not _restore_snapshot.is_empty():
		BattleSaveManager.suppress_turn_start_tick(_restored_units, 1)

	# Wait one more frame before starting the game
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Start the game
	_start_game()

	# RESUMED BATTLE, phases 3 + 4: rewind the live turn system to the saved turn/actor and
	# put the per-battle schedulers' clocks back. Must run AFTER _start_game, which is what
	# activates the turn system.
	_finish_battle_restore()

func _setup_players() -> void:
	"""Set up players and assign units"""
	# Ensure we have the right number of players
	if PlayerManager.players.is_empty():
		PlayerManager.setup_default_players()

	# Assign units to players based on scene structure
	PlayerManager.assign_units_by_parent()

	# Single-player: every player after the first is bot-controlled.
	if GameSettings and GameSettings.game_mode == GameSettings.GameMode.SINGLE_PLAYER:
		for i in range(1, PlayerManager.players.size()):
			PlayerManager.players[i].is_ai = true
		_ensure_bot_driver()

func _mount_arena_run_hud() -> void:
	"""Add the Arena in-round HUD overlay to the battle scene when a run is active.
	Runtime load (not preload) + fully guarded, so it is a harmless no-op if the scene
	is absent or already mounted, and never affects a normal (non-arena) battle."""
	var scene_root = get_tree().current_scene
	if scene_root == null or scene_root.get_node_or_null("ArenaRunHUD") != null:
		return
	var hud_scene = load("res://game/arena/ui/ArenaRunHUD.tscn")
	if hud_scene == null:
		return
	var hud = hud_scene.instantiate()
	if hud != null:
		hud.name = "ArenaRunHUD"
		scene_root.add_child(hud)


func _ensure_bot_driver() -> void:
	"""Add the bot turn driver to the scene if not already present"""
	var scene_root = get_tree().current_scene
	if not scene_root or scene_root.get_node_or_null("BotTurnDriver"):
		return
	var driver := BotTurnDriver.new()
	driver.name = "BotTurnDriver"
	scene_root.add_child(driver)

func _start_game() -> void:
	"""Start the game"""
	# Start the game in PlayerManager
	PlayerManager.start_game()

# Current UI Layout (1280x720, container-driven -- see game/ui/layout/GameUILayout.tscn
# + UILayoutManager, and UI_LAYOUT_GUIDE.md). Positions are laid out by containers,
# not hard-coded coordinates:
#
# TOP BAR:    TurnQueue (Speed First) OR TurnIndicator chip (Traditional), centered;
#             Settings gear button, top-right.
# LEFT COL:   UnitInfoPanel -- persistent selected-unit stat card, top-anchored.
# RIGHT COL:  UnitActionsPanel -- contextual command menu (shown when a unit acts).
# TOP-LEFT:   BattleLog (collapsible; auto-collapses while aiming) and, while aiming,
#             the CombatForecastPanel.
# BOTTOM-LEFT: TerrainInfoPanel -- hover terrain card (mounted on the UI CanvasLayer).
# OVERLAYS:   TurnTransition wipe + ActionAnnouncer banner, each on its own CanvasLayer.

# Debug input handling. Gated OFF by default: these raw single-key bindings collide
# with gameplay hotkeys (M = legacy move mode, T = enemy danger-zone toggle) and
# KEY_M would yank the player back to the main menu mid-battle. Flip on only for
# hands-on debugging sessions.
const DEBUG_HOTKEYS := false

func _input(event: InputEvent) -> void:
	if not DEBUG_HOTKEYS:
		return
	if not event.is_pressed():
		return

	if event is InputEventKey:
		match event.keycode:
			KEY_M:
				_return_to_main_menu()
			KEY_S:
				_print_game_status()
			KEY_V:
				_refresh_unit_visuals()
			KEY_T:
				_toggle_mouse_mode()
			KEY_U:
				_test_unit_action()
			KEY_O:
				_debug_unit_ownership()
			KEY_I:
				_test_ui_separation()
			KEY_L:
				_check_ui_layout()

func _test_unit_action() -> void:
	"""Test unit action for debugging"""
	if not TurnSystemManager.has_active_turn_system():
		return
	
	var turn_system = TurnSystemManager.get_active_turn_system()
	var units_that_can_act = []
	
	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		units_that_can_act = trad_system.get_units_that_can_act()
	
	if units_that_can_act.is_empty():
		return

	var test_unit = units_that_can_act[0]

	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		trad_system.mark_unit_acted(test_unit)

	# Update visuals
	var visual_manager = get_node_or_null("../UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()

func _debug_unit_ownership() -> void:
	"""Debug unit ownership issues"""
	pass

func _test_ui_separation() -> void:
	"""Debug (KEY_I): confirm the command surfaces resolve at their real container paths."""
	var layout: Node = get_tree().current_scene.get_node_or_null("UI/GameUILayout")
	if layout == null:
		return
	var actions: Node = layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
	var info: Node = layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/LeftSidebar/UnitInfoPanel")
	print("[GameWorldManager] UI check -- actions:%s info:%s" % [actions != null, info != null])

func _check_ui_layout() -> void:
	"""Debug (KEY_L): dump the live layout state from UILayoutManager, if present."""
	var layout: Node = get_tree().current_scene.get_node_or_null("UI/GameUILayout")
	if layout != null and layout.has_method("get_layout_info"):
		print("[GameWorldManager] Layout: ", layout.get_layout_info())

func _return_to_main_menu() -> void:
	"""Return to the main menu"""
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _print_game_status() -> void:
	"""Print current game status"""
	if GameSettings:
		GameSettings.print_settings()
	if PlayerManager:
		PlayerManager.print_game_status()
	if TurnSystemManager:
		TurnSystemManager.print_turn_system_status()

	# Print detailed turn system info
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()

		if turn_system is TraditionalTurnSystem:
			var trad_system = turn_system as TraditionalTurnSystem
			var progress = trad_system.get_current_turn_progress()

func _refresh_unit_visuals() -> void:
	"""Refresh unit visuals for testing"""
	var visual_manager = get_node_or_null("../UnitVisualManager")
	if visual_manager:
		visual_manager.refresh_unit_visuals()

func _toggle_mouse_mode() -> void:
	"""Toggle mouse cursor movement mode"""
	var cursor = get_tree().current_scene.get_node_or_null("Map/Cursor")
	if cursor:
		cursor.toggle_mouse_mode()