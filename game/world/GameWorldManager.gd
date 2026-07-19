extends Node

# GameWorldManager
# Manages the initialization and setup of the game world based on GameSettings
# Now supports both local and network multiplayer modes and dynamic map loading

var map_loader: MapLoader
var current_map_path: String = ""

## Tile-effect runtime (T14): resolves terrain effects (fire ticks damage, water
## buffs matching units, fortify) as units move and at each turn start. Created
## once; reads per-cell effects from [code]CombatServices.tile_effects_at[/code]
## via the system's injected lookup. Null-safe: handlers no-op until it and the
## live board exist.
var _tile_effect_system: TileEffectSystem = null

## Terrain / tile inspection HUD (Fire Emblem-style terrain window): shows the
## terrain name, movement cost, and active tile effects for the cell under the
## board cursor. Self-contained -- see [TerrainInfoPanel] -- this just
## instantiates it and places it in the "UI" CanvasLayer once.
var _terrain_info_panel: TerrainInfoPanel = null

## Tile-effect map overlay (Node3D): floats a row of colored, billboarded pips
## over every cell that has one or more tile effects, so stacking (e.g. tall
## grass + a fire ignited on top) is visible on the 3D battlefield. Self-contained
## -- see [TileEffectOverlay] -- this just instantiates it and adds it to the 3D
## scene root (NOT the "UI" CanvasLayer). Rebuilds itself reactively off
## CombatServices.board_ready / tile_effects_changed.
var _tile_effect_overlay: TileEffectOverlay = null

func _ready() -> void:
	print("=== GameWorld Initializing ===")

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

	# Wait a frame for all singletons to be ready
	await get_tree().process_frame

	# Terrain inspection HUD: purely additive overlay, safe to add before the
	# map finishes loading -- it resolves the live board lazily on each cursor
	# move (via GameEvents.cursor_moved, wired in its own _ready) and simply
	# stays hidden until a board and registered terrain exist.
	_setup_terrain_info_panel()

	# Tile-effect 3D overlay: additive Node3D floating effect pips over affected
	# cells. Added to the 3D scene root (not the CanvasLayer) and, like the terrain
	# panel, safe to add before the map loads -- it rebuilds itself on
	# CombatServices.board_ready and stays empty until a board/effects exist.
	_setup_tile_effect_overlay()

	# Load the selected map or default map
	await _load_selected_map()
	
	# Check if this is a network multiplayer game
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		print("Network multiplayer mode detected")
		await _setup_network_multiplayer()
	else:
		print("Local game mode detected")
		await _setup_local_game()
	
	print("=== GameWorld Initialization Complete ===")

func _load_selected_map() -> void:
	"""Load the selected map or create a default one"""
	print("Loading selected map...")
	
	# Get selected map from GameSettings or use default
	var selected_map = GameSettings.get_selected_map() if GameSettings.has_method("get_selected_map") else ""
	
	if selected_map.is_empty():
		print("No map selected, using default map")
		# Create and save default map if none exists
		var available_maps = MapLoader.get_available_maps()
		if available_maps.is_empty():
			var default_map = MapLoader.create_default_map()
			MapLoader.save_map(default_map, "default_skirmish")
			selected_map = "res://game/maps/resources/default_skirmish.tres"
		else:
			selected_map = available_maps[0]
	
	current_map_path = selected_map
	
	# Find the Map node in the scene
	var map_node = get_tree().current_scene.get_node_or_null("Map")
	if not map_node:
		print("ERROR: Map node not found in scene")
		return
	
	# Clear existing map content but keep the Map node structure
	_clear_existing_map_content(map_node)
	
	# Load the new map
	var success = map_loader.load_map_from_file(selected_map, map_node)
	if not success:
		print("Failed to load map, creating default")
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
	
	print("Cleared existing map content")

func _on_map_loaded(map_resource: MapResource) -> void:
	"""Handle successful map loading"""
	print("Map loaded successfully: " + map_resource.map_name)

	# Rebuild the shared live BoardAdapter against the freshly populated "Map"
	# node so movement/attacks/AI/tiles all read the new board. map_loader.map_root
	# is the target parent the loader just filled with units and tiles.
	if map_loader and map_loader.map_root:
		CombatServices.rebuild(map_loader.map_root)

	# Update GameSettings with map info if available
	if GameSettings.has_method("set_current_map"):
		GameSettings.set_current_map(map_resource)

func _on_map_load_failed(error_message: String) -> void:
	"""Handle map loading failure"""
	print("Map loading failed: " + error_message)
	
	# Try to load default map as fallback
	var default_map = MapLoader.create_default_map()
	var map_node = get_tree().current_scene.get_node_or_null("Map")
	if map_node:
		map_loader.load_map(default_map, map_node)

# --- Terrain inspection HUD --------------------------------------------------

func _setup_terrain_info_panel() -> void:
	"""Instantiate TerrainInfoPanel and add it to the "UI" CanvasLayer (sibling of
	this node in GameWorld.tscn -- see the "UI" CanvasLayer node there). The panel
	builds its own UI, themes itself, and connects GameEvents.cursor_moved itself
	in _ready, so there is nothing else to wire up here."""
	if _terrain_info_panel != null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		push_warning("[GameWorldManager] No current_scene yet; TerrainInfoPanel not added.")
		return

	var ui_layer := scene_root.get_node_or_null("UI")
	if ui_layer == null:
		push_warning("[GameWorldManager] 'UI' CanvasLayer not found; TerrainInfoPanel not added.")
		return

	_terrain_info_panel = TerrainInfoPanel.new()
	ui_layer.add_child(_terrain_info_panel)

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
		push_warning("[GameWorldManager] No current_scene yet; TileEffectOverlay not added.")
		return

	_tile_effect_overlay = TileEffectOverlay.new()
	scene_root.add_child(_tile_effect_overlay)

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

	# Turn start: tick ON_TURN_START_WHILE_OCCUPYING for each unit the active
	# player owns. PlayerManager.player_turn_started is the signal that reliably
	# fires per turn in the live loop.
	if PlayerManager and not PlayerManager.player_turn_started.is_connected(_on_player_turn_started_tile_effects):
		PlayerManager.player_turn_started.connect(_on_player_turn_started_tile_effects)

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

func _setup_network_multiplayer() -> void:
	"""Set up network multiplayer game"""
	print("Setting up network multiplayer...")
	
	# Check if GameModeManager is already handling multiplayer
	if GameModeManager and GameModeManager.is_multiplayer_active():
		print("Network multiplayer already active via GameModeManager")
		
		# Connect to GameModeManager signals
		if not GameModeManager.game_ended.is_connected(_on_multiplayer_game_ended):
			GameModeManager.game_ended.connect(_on_multiplayer_game_ended)
		
		# Set up players for network multiplayer
		await _setup_multiplayer_players()
		
		# Apply settings but don't start game (GameModeManager handles this)
		if GameSettings:
			GameSettings.apply_settings_to_game()
		
		# Wait one more frame before starting the game
		await get_tree().process_frame
		
		# Start the game for multiplayer
		_start_game()
		
		print("Network multiplayer setup complete")
	else:
		print("No active network multiplayer found, falling back to local mode")
		await _setup_local_game()

func _setup_local_game() -> void:
	"""Set up local single-player or local multiplayer game"""
	print("Setting up local game...")

	# Reset per-session autoload state FIRST. Autoloads survive scene changes, so on a
	# second+ game these still hold the previous session's players (with freed units)
	# and an active turn system -- which wedges turn advancement and leaves the game
	# state stuck off SETUP so start_game() never re-activates a turn system.
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()

	# Initialize player management first
	_setup_players()
	
	# Wait another frame to ensure units are properly assigned
	await get_tree().process_frame
	
	# Apply game settings (this will set up turn systems with units already assigned)
	if GameSettings:
		GameSettings.apply_settings_to_game()
	
	# Wait one more frame before starting the game
	await get_tree().process_frame
	
	# Start the game
	_start_game()

func _setup_multiplayer_players() -> void:
	"""Set up players for network multiplayer"""
	print("Setting up multiplayer players...")
	
	# Get player info from GameModeManager
	var multiplayer_status = GameModeManager.get_multiplayer_status()
	var network_players = multiplayer_status.get("players", {})
	var local_player_id = GameModeManager.get_local_player_id()
	
	print("Network players found: " + str(network_players.size()))
	print("Local player ID: " + str(local_player_id))
	
	# Reset per-session autoload state before registering players. Replaces the old
	# ad-hoc players.clear(): also resets game state back to SETUP and tears down any
	# turn system left over from a prior session (freed units). This runs BEFORE the
	# Player 1/2 registration below so the registration order is preserved.
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()

	# Set up multiplayer players with proper IDs
	# Always create 2 players for multiplayer
	var player1 = PlayerManager.register_player("Player 1")
	var player2 = PlayerManager.register_player("Player 2")
	
	print("Registered multiplayer players: Player 1 (ID: 0), Player 2 (ID: 1)")
	var local_player_id_int = int(local_player_id) if local_player_id is String else local_player_id
	print("This client is Player " + str(local_player_id_int + 1) + " (ID: " + str(local_player_id_int) + ")")
	
	# Assign units to players based on scene structure
	PlayerManager.assign_units_by_parent()
	
	print("Multiplayer players set up: " + str(PlayerManager.players.size()) + " players")
	
	# Debug: Print player unit assignments
	for i in range(PlayerManager.players.size()):
		var player = PlayerManager.players[i]
		var is_local = (i == local_player_id_int)
		var local_indicator = " (LOCAL)" if is_local else " (REMOTE)"
		print("Player " + str(i) + " (" + player.player_name + ")" + local_indicator + " has " + str(player.owned_units.size()) + " units")
		for unit in player.owned_units:
			print("  - " + unit.get_display_name())

func _setup_players() -> void:
	"""Set up players and assign units"""
	print("Setting up players...")
	
	# Ensure we have the right number of players
	if PlayerManager.players.is_empty():
		PlayerManager.setup_default_players()

	# Assign units to players based on scene structure
	PlayerManager.assign_units_by_parent()

	# Single-player: every player after the first is bot-controlled.
	if GameSettings and GameSettings.game_mode == GameSettings.GameMode.SINGLE_PLAYER:
		for i in range(1, PlayerManager.players.size()):
			PlayerManager.players[i].is_ai = true
			print("Player " + str(i) + " set to AI control")
		_ensure_bot_driver()

	print("Players set up: " + str(PlayerManager.players.size()) + " players")

func _ensure_bot_driver() -> void:
	"""Add the bot turn driver to the scene if not already present"""
	var scene_root = get_tree().current_scene
	if not scene_root or scene_root.get_node_or_null("BotTurnDriver"):
		return
	var driver := BotTurnDriver.new()
	driver.name = "BotTurnDriver"
	scene_root.add_child(driver)
	print("BotTurnDriver added for single-player AI")

func _start_game() -> void:
	"""Start the game"""
	print("Starting game...")
	
	# Start the game in PlayerManager
	PlayerManager.start_game()
	
	print("Game started successfully!")

func _on_multiplayer_game_ended(winner_id: int) -> void:
	"""Handle multiplayer game ended"""
	print("Multiplayer game ended, winner: " + str(winner_id))
	
	# Show game over screen or return to menu
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

# Current UI Layout (1920x1080 reference):
# 
# TOP ROW:
# - UnitInfoPanel: (20, 20) to (320, 360) - 300x340
# - TurnIndicator: (1670, 20) to (1900, 100) - 230x80
#
# MIDDLE ROW:  
# - UnitActionsPanel: (1700, 120) to (1900, 340) - 200x220
#
# BOTTOM ROW:
# - TurnSystemIndicator: (20, 960) to (320, 1060) - 300x100
# - PlayerTurnPanel: (340, 960) to (620, 1060) - 280x100

# Debug input handling
func _input(event: InputEvent) -> void:
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
	print("\n=== Testing Unit Action ===")
	
	if not TurnSystemManager.has_active_turn_system():
		print("No active turn system")
		return
	
	var turn_system = TurnSystemManager.get_active_turn_system()
	var units_that_can_act = []
	
	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		units_that_can_act = trad_system.get_units_that_can_act()
	
	if units_that_can_act.is_empty():
		print("No units can act")
		return
	
	var test_unit = units_that_can_act[0]
	print("Testing action with unit: " + test_unit.get_display_name())
	
	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		trad_system.mark_unit_acted(test_unit)
		print("Marked unit as acted")
	
	# Update visuals
	var visual_manager = get_node_or_null("../UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()
		print("Updated unit visuals")
	
	print("=== Unit Action Test Complete ===")

func _debug_unit_ownership() -> void:
	"""Debug unit ownership issues"""
	print("\n=== DEBUGGING UNIT OWNERSHIP ===")
	
	# Check PlayerManager
	if PlayerManager:
		print("PlayerManager players: " + str(PlayerManager.players.size()))
		for i in range(PlayerManager.players.size()):
			var player = PlayerManager.players[i]
			print("Player " + str(i) + ": " + player.get_display_name())
			print("  Owned units: " + str(player.owned_units.size()))
			for unit in player.owned_units:
				print("    - " + unit.get_display_name() + " (owner: " + (unit.get_owner_player().get_display_name() if unit.get_owner_player() else "None") + ")")
	
	# Check TurnSystem
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Turn system registered units: " + str(turn_system.registered_units.size()))
		for unit in turn_system.registered_units:
			var owner = unit.get_owner_player()
			print("  - " + unit.get_display_name() + " (owner: " + (owner.get_display_name() if owner else "None") + ")")
	
	print("=== UNIT OWNERSHIP DEBUG COMPLETE ===")

func _test_ui_separation() -> void:
	"""Test the separation between unit actions and player turn actions"""
	print("\n=== TESTING UI SEPARATION ===")
	
	# Find UI panels
	var unit_panel = get_tree().current_scene.get_node_or_null("UI/UnitActionsPanel")
	var player_panel = get_tree().current_scene.get_node_or_null("UI/PlayerTurnPanel")
	
	if unit_panel:
		print("UnitActionsPanel found: " + str(unit_panel.visible))
	else:
		print("UnitActionsPanel NOT found")
	
	if player_panel:
		print("PlayerTurnPanel found: " + str(player_panel.visible))
	else:
		print("PlayerTurnPanel NOT found")
	
	print("=== UI SEPARATION TEST COMPLETE ===")

func _check_ui_layout() -> void:
	"""Check UI layout for overlaps"""
	print("\n=== CHECKING UI LAYOUT ===")
	
	var ui_manager = get_node_or_null("UILayoutManager")
	if ui_manager:
		ui_manager.print_layout_status()
	else:
		print("UILayoutManager not found - checking manually")
		
		var ui_layer = get_tree().current_scene.get_node_or_null("UI")
		if ui_layer:
			print("UI Elements found:")
			for child in ui_layer.get_children():
				if child is Control:
					print("  " + child.name + ": Pos " + str(child.position) + " Size " + str(child.size) + " Visible: " + str(child.visible))
		else:
			print("No UI layer found")
	
	print("=== UI LAYOUT CHECK COMPLETE ===")

func _return_to_main_menu() -> void:
	"""Return to the main menu"""
	print("Returning to main menu...")
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _print_game_status() -> void:
	"""Print current game status"""
	print("\n=== Game Status ===")
	if GameSettings:
		GameSettings.print_settings()
	if PlayerManager:
		PlayerManager.print_game_status()
	if TurnSystemManager:
		TurnSystemManager.print_turn_system_status()
	
	# Print detailed turn system info
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("\n=== Turn System Details ===")
		print("System: " + turn_system.system_name)
		print("Registered units: " + str(turn_system.registered_units.size()))
		print("Registered players: " + str(turn_system.registered_players.size()))
		
		if turn_system is TraditionalTurnSystem:
			var trad_system = turn_system as TraditionalTurnSystem
			var progress = trad_system.get_current_turn_progress()
			print("Current player: " + str(progress.get("current_player", "None")))
			print("Total units: " + str(progress.get("total_units", 0)))
			print("Units acted: " + str(progress.get("units_acted", 0)))
			print("Units can act: " + str(progress.get("units_can_act", 0)))
			print("Turn complete: " + str(progress.get("turn_complete", false)))
			
			print("Units that acted this turn:")
			for unit in trad_system.get_units_that_acted():
				print("  - " + unit.get_display_name())
			
			print("Units that can still act:")
			for unit in trad_system.get_units_that_can_act():
				print("  - " + unit.get_display_name())

func _refresh_unit_visuals() -> void:
	"""Refresh unit visuals for testing"""
	var visual_manager = get_node_or_null("../UnitVisualManager")
	if visual_manager:
		visual_manager.refresh_unit_visuals()
	else:
		print("UnitVisualManager not found")

func _toggle_mouse_mode() -> void:
	"""Toggle mouse cursor movement mode"""
	var cursor = get_tree().current_scene.get_node_or_null("Map/Cursor")
	if cursor:
		cursor.toggle_mouse_mode()
	else:
		print("Cursor not found")