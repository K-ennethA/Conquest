extends Node

class_name MoveManager

# Manages moves for a unit, including cooldowns and execution

signal move_used(move: Move, result: Dictionary)
signal move_cooldown_updated(move_index: int, remaining_turns: int)

@export var moves: Array[Move] = []
var move_cooldowns: Dictionary = {}  # move_name -> remaining_turns
var unit_owner: Node

func _ready() -> void:
	name = "MoveManager"
	unit_owner = get_parent()
	
	# Initialize cooldowns
	for move in moves:
		if move:
			move_cooldowns[move.name] = 0

func add_move(move: Move) -> bool:
	"""Add a move to the unit (max 5 moves)"""
	if moves.size() >= 5:
		print("Cannot add move: Unit already has maximum of 5 moves")
		return false
	
	moves.append(move)
	move_cooldowns[move.name] = 0
	print("Added move '%s' to %s" % [move.name, unit_owner.name])
	return true

func remove_move(move_index: int) -> bool:
	"""Remove a move by index"""
	if move_index < 0 or move_index >= moves.size():
		return false
	
	var move = moves[move_index]
	moves.remove_at(move_index)
	move_cooldowns.erase(move.name)
	print("Removed move '%s' from %s" % [move.name, unit_owner.name])
	return true

func can_use_move(move_index: int) -> bool:
	"""Check if a move can be used (not on cooldown)"""
	if move_index < 0 or move_index >= moves.size():
		return false
	
	var move = moves[move_index]
	if not move:
		return false
	
	return move_cooldowns.get(move.name, 0) <= 0

func get_move_cooldown(move_index: int) -> int:
	"""Get remaining cooldown turns for a move"""
	if move_index < 0 or move_index >= moves.size():
		return 0
	
	var move = moves[move_index]
	if not move:
		return 0
	
	return move_cooldowns.get(move.name, 0)

func use_move(move_index: int, target: Node, target_position: Vector3 = Vector3.ZERO) -> Dictionary:
	"""Execute a move"""
	var result = {
		"success": false,
		"message": "Invalid move",
		"move_name": ""
	}
	
	# Validate move index
	if move_index < 0 or move_index >= moves.size():
		result.message = "Invalid move index"
		return result
	
	var move = moves[move_index]
	if not move:
		result.message = "Move not found"
		return result
	
	result.move_name = move.name
	
	# Check cooldown
	if not can_use_move(move_index):
		var remaining = get_move_cooldown(move_index)
		result.message = "%s is on cooldown (%d turns remaining)" % [move.name, remaining]
		return result
	
	# Check range if target is specified
	if target and unit_owner:
		var caster_pos = unit_owner.global_position
		var target_pos = target.global_position
		if not move.can_target(caster_pos, target_pos):
			result.message = "%s is out of range" % move.name
			return result
	
	# Execute the move
	result = move.execute(unit_owner, target, target_position)
	result.move_name = move.name
	
	if result.success:
		# Apply cooldown
		move_cooldowns[move.name] = move.cooldown_turns
		print("Move '%s' used by %s. Cooldown: %d turns" % [move.name, unit_owner.name, move.cooldown_turns])
		
		# Emit signal
		move_used.emit(move, result)
	
	return result

func advance_cooldowns() -> void:
	"""Reduce all move cooldowns by 1 (called at start of unit's turn)"""
	for move_name in move_cooldowns.keys():
		if move_cooldowns[move_name] > 0:
			move_cooldowns[move_name] -= 1
			
			# Find move index for signal
			var move_index = -1
			for i in range(moves.size()):
				if moves[i] and moves[i].name == move_name:
					move_index = i
					break
			
			if move_index >= 0:
				move_cooldown_updated.emit(move_index, move_cooldowns[move_name])
				
				if move_cooldowns[move_name] == 0:
					print("Move '%s' is now available for %s" % [move_name, unit_owner.name])

func get_available_moves() -> Array[int]:
	"""Get indices of moves that are not on cooldown"""
	var available: Array[int] = []
	
	for i in range(moves.size()):
		if can_use_move(i):
			available.append(i)
	
	return available

func get_moves_info() -> Array[Dictionary]:
	"""Get display information for all moves"""
	var moves_info: Array[Dictionary] = []
	
	for i in range(moves.size()):
		var move = moves[i]
		if move:
			var info = move.get_display_info()
			info["index"] = i
			info["cooldown_remaining"] = get_move_cooldown(i)
			info["available"] = can_use_move(i)
			moves_info.append(info)
	
	return moves_info

func get_move_by_name(move_name: String) -> Move:
	"""Get a move by its name"""
	for move in moves:
		if move and move.name == move_name:
			return move
	return null

func get_move_index_by_name(move_name: String) -> int:
	"""Get move index by name"""
	for i in range(moves.size()):
		if moves[i] and moves[i].name == move_name:
			return i
	return -1

func reset_all_cooldowns() -> void:
	"""Reset all move cooldowns (for testing or special abilities)"""
	for move_name in move_cooldowns.keys():
		move_cooldowns[move_name] = 0
	print("All move cooldowns reset for %s" % unit_owner.name)

func get_moves_on_cooldown() -> Array[Dictionary]:
	"""Get info about moves currently on cooldown"""
	var cooldown_moves: Array[Dictionary] = []
	
	for i in range(moves.size()):
		var move = moves[i]
		if move and not can_use_move(i):
			cooldown_moves.append({
				"name": move.name,
				"index": i,
				"remaining_turns": get_move_cooldown(i)
			})
	
	return cooldown_moves