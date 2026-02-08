# Example of how to integrate the new unified game system with existing code
# This shows how UnitActionsPanel and other systems can work with both single-player and multiplayer

extends Node

"""
Example modifications to UnitActionsPanel.gd for unified game system:

1. Replace multiplayer-specific checks with unified game checks:

func _on_move_pressed() -> void:
    if not selected_unit:
        return
    
    # NEW: Unified check that works for all game modes
    if not Game.can_i_act():
        print("Cannot move: not your turn or game not active")
        return
    
    # Existing validation code...
    if TurnSystemManager.has_active_turn_system():
        var turn_system = TurnSystemManager.get_active_turn_system()
        if turn_system.validate_turn_action(selected_unit, "move"):
            # NEW: Submit action through unified system
            var action_data = {
                "unit_id": selected_unit.get_id(),
                "player_id": Game.get_status().get("current_player", -1)
            }
            
            if Game.submit_action("unit_move_start", action_data):
                print("Move action submitted successfully")
            else:
                print("Failed to submit move action")
                # Fallback to local movement for single-player
                if not Game.is_multiplayer_active():
                    _enter_movement_mode()

2. Modify movement execution to work with unified system:

func _execute_movement_to_destination(destination: Vector3) -> void:
    if not selected_unit:
        return
    
    # Get movement data
    var old_world_pos = selected_unit.global_position
    var old_grid_pos = grid.calculate_grid_coordinates(old_world_pos)
    
    # NEW: Submit through unified game system
    var action_data = {
        "unit_id": selected_unit.get_id(),
        "from_position": old_grid_pos,
        "to_position": destination,
        "player_id": Game.get_status().get("current_player", -1)
    }
    
    if Game.submit_action("unit_move", action_data):
        print("Movement submitted successfully")
        # Clear UI state
        _clear_movement_range()
        _update_actions()
    else:
        print("Failed to submit movement, executing locally")
        # Fallback to local execution
        _execute_local_movement(old_world_pos, destination)

func _execute_local_movement(old_world_pos: Vector3, destination: Vector3) -> void:
    # Existing single-player movement code
    var new_world_pos = grid.calculate_map_position(destination)
    new_world_pos.y = selected_unit.global_position.y
    
    _clear_movement_range()
    _animate_unit_movement(selected_unit, old_world_pos, new_world_pos)
    GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)
    _complete_movement_action()
    _update_actions()

3. Update action availability checks:

func _update_actions() -> void:
    if not selected_unit:
        return
    
    # NEW: Use unified game system for all checks
    var game_status = Game.get_status()
    var is_game_active = game_status.get("is_active", false)
    var can_act = Game.can_i_act()
    var is_my_turn = Game.is_my_turn()
    
    # Update buttons based on unified state
    if move_button:
        move_button.disabled = not (is_game_active and can_act and is_my_turn)
        
        if not is_game_active:
            move_button.text = "Move (M)\n[No Game]"
        elif not is_my_turn:
            move_button.text = "Move (M)\n[Not Your Turn]"
        elif not can_act:
            move_button.text = "Move (M)\n[Cannot Act]"
        else:
            move_button.text = "Move (M)"

4. Add unified game event handlers:

func _ready() -> void:
    # Existing code...
    
    # NEW: Connect to unified game events
    if Game:
        Game.game_started.connect(_on_game_started)
        Game.game_ended.connect(_on_game_ended)
        Game.mode_changed.connect(_on_game_mode_changed)

func _on_game_started(mode) -> void:
    print("Game started in mode: %s" % str(mode))
    _update_actions()

func _on_game_ended(winner_id: int) -> void:
    print("Game ended, winner: %d" % winner_id)
    _update_actions()

func _on_game_mode_changed(new_mode) -> void:
    print("Game mode changed to: %s" % str(new_mode))
    _update_actions()
"""

# Example of a unified game menu system
class UnifiedGameMenu:
    
    static func show_game_mode_selection() -> void:
        """Show game mode selection menu"""
        print("=== Game Mode Selection ===")
        print("1. Single Player")
        print("2. Local Multiplayer (Hot-seat)")
        print("3. Network Multiplayer (Host)")
        print("4. Network Multiplayer (Join)")
    
    static func start_single_player_game() -> void:
        """Start single player game"""
        var success = Game.start_single_player("Player", 1)
        if success:
            print("Single player game started!")
        else:
            print("Failed to start single player game")
    
    static func start_local_multiplayer_game() -> void:
        """Start local multiplayer game"""
        var player_names = ["Player 1", "Player 2"]
        var success = Game.start_local_multiplayer(player_names)
        if success:
            print("Local multiplayer game started!")
        else:
            print("Failed to start local multiplayer game")
    
    static func start_network_host() -> void:
        """Start network multiplayer as host"""
        var success = await Game.start_network_host("Host Player", "local")
        if success:
            print("Network host started!")
            var status = Game.get_status()
            print("Connection info: %s" % str(status.get("connection_info", {})))
        else:
            print("Failed to start network host")
    
    static func join_network_game() -> void:
        """Join network multiplayer game"""
        var success = await Game.join_network_game("127.0.0.1", 8910, "Client Player", "local")
        if success:
            print("Joined network game!")
        else:
            print("Failed to join network game")

# Example of unified action handling
class UnifiedActionHandler:
    
    static func handle_unit_selection(unit: Unit, position: Vector3) -> void:
        """Handle unit selection in any game mode"""
        if not Game.is_active():
            print("Cannot select unit: no active game")
            return
        
        if not Game.can_i_act():
            print("Cannot select unit: not your turn")
            return
        
        # Submit selection action
        var action_data = {
            "unit_id": unit.get_id() if unit.has_method("get_id") else unit.name,
            "position": position
        }
        
        Game.submit_action("unit_select", action_data)
    
    static func handle_unit_movement(unit: Unit, from_pos: Vector3, to_pos: Vector3) -> void:
        """Handle unit movement in any game mode"""
        if not Game.can_i_act():
            print("Cannot move unit: not your turn")
            return
        
        var action_data = {
            "unit_id": unit.get_id() if unit.has_method("get_id") else unit.name,
            "from_position": from_pos,
            "to_position": to_pos
        }
        
        Game.submit_action("unit_move", action_data)
    
    static func handle_end_turn() -> void:
        """Handle end turn in any game mode"""
        if not Game.can_i_act():
            print("Cannot end turn: not your turn")
            return
        
        var status = Game.get_status()
        var action_data = {
            "player_id": status.get("current_player", -1)
        }
        
        Game.submit_action("end_turn", action_data)

# Example of how to integrate with existing GameEvents
func integrate_with_existing_systems() -> void:
    """Show how to integrate with existing GameEvents system"""
    
    # The GameManager already forwards actions to GameEvents
    # So existing systems continue to work without modification
    
    if GameEvents:
        # These will still work as before
        GameEvents.unit_moved.connect(_on_unit_moved)
        GameEvents.unit_selected.connect(_on_unit_selected)
        GameEvents.unit_action_completed.connect(_on_unit_action_completed)

func _on_unit_moved(unit: Unit, from_pos: Vector3, to_pos: Vector3) -> void:
    """Handle unit moved event (works for all game modes)"""
    print("Unit moved: %s from %s to %s" % [unit.name, from_pos, to_pos])

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
    """Handle unit selected event (works for all game modes)"""
    print("Unit selected: %s at %s" % [unit.name, position])

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
    """Handle unit action completed (works for all game modes)"""
    print("Unit action completed: %s performed %s" % [unit.name, action_type])

# Example of game status monitoring
func monitor_game_status() -> void:
    """Example of monitoring game status"""
    var status = Game.get_status()
    
    print("=== Game Status ===")
    print("Mode: %s" % status.get("game_mode", "None"))
    print("Active: %s" % status.get("is_active", false))
    print("Current Player: %s" % status.get("current_player", -1))
    print("Can I Act: %s" % Game.can_i_act())
    print("Is My Turn: %s" % Game.is_my_turn())
    
    # Network-specific info (only if in network mode)
    if status.has("network_status"):
        print("Network Status: %s" % status.get("network_status", "unknown"))
        print("Network Stats: %s" % str(status.get("network_stats", {})))

# Example of migration from old multiplayer system
func migrate_from_old_system() -> void:
    """Example of how to migrate from the old multiplayer system"""
    
    # OLD WAY:
    # if Multiplayer.is_active() and Multiplayer.is_my_turn():
    #     Multiplayer.submit_action("unit_move", data)
    
    # NEW WAY (works for all game modes):
    if Game.is_active() and Game.can_i_act():
        Game.submit_action("unit_move", data)
    
    # OLD WAY:
    # var status = Multiplayer.get_multiplayer_status()
    
    # NEW WAY:
    var status = Game.get_status()  # Works for all modes
    
    # For compatibility, you can still use:
    var mp_status = Game.get_multiplayer_status()  # Returns compatible format