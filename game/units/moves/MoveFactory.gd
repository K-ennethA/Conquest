extends Node

class_name MoveFactory

# Factory for creating predefined moves with custom effects

static func create_basic_attack() -> Move:
	"""Basic melee attack"""
	var move = Move.new("Basic Attack", "A simple melee attack", 0)
	move.move_type = Move.MoveType.DAMAGE
	move.base_power = 25
	move.range = 1
	move.accuracy = 0.95
	move.critical_chance = 0.1
	return move

static func create_fireball() -> Move:
	"""Fireball spell with area damage"""
	var move = Move.new("Fireball", "Launches a fireball that explodes on impact", 3)
	move.move_type = Move.MoveType.DAMAGE
	move.base_power = 40
	move.range = 3
	move.area_of_effect = 1  # 3x3 area
	move.accuracy = 0.85
	move.critical_chance = 0.15
	
	# Custom effect for fireball
	move.set_effect(func(caster: Node, target: Node, target_pos: Vector3, move_data: Move) -> Dictionary:
		var result = {
			"success": true,
			"damage_dealt": 0,
			"message": "",
			"area_damage": []
		}
		
		# Get all positions in area of effect
		var affected_positions = move_data.get_affected_positions(target_pos)
		var total_damage = 0
		
		# Apply damage to all units in area
		for pos in affected_positions:
			var units_at_pos = _get_units_at_position(pos)
			for unit in units_at_pos:
				var damage = move_data.base_power
				
				# Add caster's magic power
				var caster_stats = caster.get_node_or_null("UnitStats")
				if caster_stats and caster_stats.has_method("get_magic"):
					damage += caster_stats.get_magic()
				
				# Apply damage
				var unit_stats = unit.get_node_or_null("UnitStats")
				if unit_stats and unit_stats.has_method("take_damage"):
					var actual_damage = unit_stats.take_damage(damage)
					total_damage += actual_damage
					result.area_damage.append({
						"unit": unit.name,
						"damage": actual_damage
					})
		
		result.damage_dealt = total_damage
		result.message = "Fireball exploded for %d total damage!" % total_damage
		return result
	)
	
	return move

static func create_heal() -> Move:
	"""Basic healing spell"""
	var move = Move.new("Heal", "Restores health to target ally", 2)
	move.move_type = Move.MoveType.HEAL
	move.base_power = 30
	move.range = 2
	move.accuracy = 1.0
	return move

static func create_shield_wall() -> Move:
	"""Creates a protective shield"""
	var move = Move.new("Shield Wall", "Creates a protective barrier", 4)
	move.move_type = Move.MoveType.SHIELD
	move.base_power = 50
	move.range = 0  # Self only
	move.effect_duration = 3
	move.accuracy = 1.0
	return move

static func create_power_strike() -> Move:
	"""Powerful attack with longer cooldown"""
	var move = Move.new("Power Strike", "A devastating melee attack", 2)
	move.move_type = Move.MoveType.DAMAGE
	move.base_power = 50
	move.range = 1
	move.accuracy = 0.90
	move.critical_chance = 0.25
	
	# Custom effect for extra damage
	move.set_effect(func(caster: Node, target: Node, target_pos: Vector3, move_data: Move) -> Dictionary:
		var result = {
			"success": true,
			"damage_dealt": 0,
			"message": ""
		}
		
		var damage = move_data.base_power
		
		# Add caster's attack stat with bonus
		var caster_stats = caster.get_node_or_null("UnitStats")
		if caster_stats and caster_stats.has_method("get_attack"):
			damage += int(caster_stats.get_attack() * 1.5)  # 50% bonus
		
		# Apply critical hit
		var is_critical = randf() < move_data.critical_chance
		if is_critical:
			damage = int(damage * 2.0)  # Double damage on crit
			result.message = "CRITICAL POWER STRIKE! "
		
		# Apply damage
		var target_stats = target.get_node_or_null("UnitStats")
		if target_stats and target_stats.has_method("take_damage"):
			var actual_damage = target_stats.take_damage(damage)
			result.damage_dealt = actual_damage
			result.message += "%s dealt %d damage with Power Strike!" % [caster.name, actual_damage]
		
		return result
	)
	
	return move

static func create_poison_dart() -> Move:
	"""Attack that applies poison debuff"""
	var move = Move.new("Poison Dart", "Shoots a poisoned dart that deals damage over time", 3)
	move.move_type = Move.MoveType.DEBUFF
	move.base_power = 15
	move.range = 4
	move.accuracy = 0.90
	move.effect_duration = 3
	
	# Custom poison effect
	move.set_effect(func(caster: Node, target: Node, target_pos: Vector3, move_data: Move) -> Dictionary:
		var result = {
			"success": true,
			"damage_dealt": 0,
			"effects_applied": ["poison"],
			"message": ""
		}
		
		# Initial damage
		var initial_damage = move_data.base_power
		var target_stats = target.get_node_or_null("UnitStats")
		if target_stats and target_stats.has_method("take_damage"):
			var actual_damage = target_stats.take_damage(initial_damage)
			result.damage_dealt = actual_damage
		
		# Apply poison effect
		if BattleEffectsManager:
			var poison_data = {
				"type": "poison",
				"name": "Poison",
				"duration": move_data.effect_duration,
				"damage_per_turn": 10
			}
			BattleEffectsManager.apply_effect(target, poison_data)
		
		result.message = "%s poisoned %s!" % [caster.name, target.name]
		return result
	)
	
	return move

static func create_earthquake() -> Move:
	"""Area effect that damages all units and affects tiles"""
	var move = Move.new("Earthquake", "Shakes the ground, damaging all units", 5)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 20
	move.range = 0  # Affects entire battlefield
	move.area_of_effect = 10  # Large area
	move.accuracy = 1.0
	
	# Custom earthquake effect
	move.set_effect(func(caster: Node, target: Node, target_pos: Vector3, move_data: Move) -> Dictionary:
		var result = {
			"success": true,
			"damage_dealt": 0,
			"message": "",
			"units_affected": 0
		}
		
		# Get all units on the battlefield
		var all_units = _get_all_units()
		var total_damage = 0
		
		for unit in all_units:
			if unit == caster:
				continue  # Caster is immune
			
			var damage = move_data.base_power
			var unit_stats = unit.get_node_or_null("UnitStats")
			if unit_stats and unit_stats.has_method("take_damage"):
				var actual_damage = unit_stats.take_damage(damage)
				total_damage += actual_damage
				result.units_affected += 1
		
		result.damage_dealt = total_damage
		result.message = "Earthquake shook the battlefield! %d units affected for %d total damage" % [result.units_affected, total_damage]
		
		# Could also affect tiles here (make them impassable, etc.)
		
		return result
	)
	
	return move

# Helper functions for move effects
static func _get_units_at_position(position: Vector3) -> Array[Node]:
	"""Get all units at a specific position"""
	var units: Array[Node] = []
	
	# This would need to be implemented based on your game's unit tracking system
	# For now, return empty array
	
	return units

static func _get_all_units() -> Array[Node]:
	"""Get all units on the battlefield"""
	var units: Array[Node] = []
	
	# Find all units in the scene
	var game_world = Engine.get_main_loop().current_scene
	if game_world:
		var map = game_world.get_node_or_null("Map")
		if map:
			# Look for units in player folders
			for player_folder in ["Player1", "Player2"]:
				var player_node = map.get_node_or_null(player_folder)
				if player_node:
					for child in player_node.get_children():
						if child.has_method("get_node") and child.get_node_or_null("UnitStats"):
							units.append(child)
	
	return units

# Preset move sets for different unit types
static func get_warrior_moves() -> Array[Move]:
	"""Get moves for warrior units"""
	return [
		create_basic_attack(),
		create_power_strike(),
		create_shield_wall()
	]

static func get_mage_moves() -> Array[Move]:
	"""Get moves for mage units"""
	return [
		create_basic_attack(),
		create_fireball(),
		create_heal(),
		create_earthquake()
	]

static func get_archer_moves() -> Array[Move]:
	"""Get moves for archer units"""
	return [
		create_basic_attack(),
		create_poison_dart(),
		create_power_strike()
	]

static func get_all_moves() -> Array[Move]:
	"""Get all available moves"""
	return [
		create_basic_attack(),
		create_fireball(),
		create_heal(),
		create_shield_wall(),
		create_power_strike(),
		create_poison_dart(),
		create_earthquake(),
		create_flame_wall(),
		create_ice_field(),
		create_healing_sanctuary(),
		create_poison_cloud(),
		create_lightning_storm(),
		create_trap_placement(),
		create_speed_zone(),
		create_weakness_field()
	]

# Tile Effect Moves
static func create_flame_wall() -> Move:
	"""Creates a wall of fire tiles"""
	var move = Move.new("Flame Wall", "Creates a line of burning tiles", 4)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 3
	move.area_of_effect = 0
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.FIRE_DAMAGE
	move.tile_effect_strength = 2
	move.tile_effect_duration = 5
	move.tile_pattern = Move.TilePattern.LINE
	
	return move

static func create_ice_field() -> Move:
	"""Creates an area of slippery ice"""
	var move = Move.new("Ice Field", "Freezes the ground in a large area", 3)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 2
	move.area_of_effect = 2
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.ICE_DAMAGE
	move.tile_effect_strength = 1
	move.tile_effect_duration = 4
	move.tile_pattern = Move.TilePattern.CIRCLE
	
	return move

static func create_healing_sanctuary() -> Move:
	"""Creates a healing area"""
	var move = Move.new("Healing Sanctuary", "Blesses the ground with healing energy", 5)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 2
	move.area_of_effect = 1
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.HEALING_SPRING
	move.tile_effect_strength = 2
	move.tile_effect_duration = 6
	move.tile_pattern = Move.TilePattern.SQUARE
	
	return move

static func create_poison_cloud() -> Move:
	"""Creates a toxic cloud that poisons the ground"""
	var move = Move.new("Poison Cloud", "Spreads toxic gas across the battlefield", 4)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 3
	move.area_of_effect = 1
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.POISON_DAMAGE
	move.tile_effect_strength = 1
	move.tile_effect_duration = 4
	move.tile_pattern = Move.TilePattern.CIRCLE
	
	return move

static func create_lightning_storm() -> Move:
	"""Creates electrified tiles that shock units"""
	var move = Move.new("Lightning Storm", "Electrifies the ground with crackling energy", 6)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 4
	move.area_of_effect = 1
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.LIGHTNING_DAMAGE
	move.tile_effect_strength = 3
	move.tile_effect_duration = 3
	move.tile_pattern = Move.TilePattern.CROSS
	
	return move

static func create_trap_placement() -> Move:
	"""Places hidden traps on tiles"""
	var move = Move.new("Set Trap", "Places a hidden trap that triggers when stepped on", 2)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 2
	move.area_of_effect = 0
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.TRAP
	move.tile_effect_strength = 3
	move.tile_effect_duration = 0  # Instant when triggered
	move.tile_pattern = Move.TilePattern.SINGLE
	
	return move

static func create_speed_zone() -> Move:
	"""Creates an area that boosts unit speed"""
	var move = Move.new("Speed Zone", "Creates an area that energizes units", 3)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 1
	move.area_of_effect = 1
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.SPEED_BOOST
	move.tile_effect_strength = 2
	move.tile_effect_duration = 4
	move.tile_pattern = Move.TilePattern.SQUARE
	
	return move

static func create_weakness_field() -> Move:
	"""Creates an area that weakens enemies"""
	var move = Move.new("Weakness Field", "Curses the ground to weaken enemies", 4)
	move.move_type = Move.MoveType.TILE_EFFECT
	move.base_power = 0
	move.range = 3
	move.area_of_effect = 1
	move.accuracy = 1.0
	move.tile_effect_type = TileEffect.EffectType.WEAKNESS
	move.tile_effect_strength = 2
	move.tile_effect_duration = 5
	move.tile_pattern = Move.TilePattern.CIRCLE
	
	return move

# Enhanced move sets with tile effects
static func get_enhanced_mage_moves() -> Array[Move]:
	"""Get enhanced moves for mage units with tile effects"""
	return [
		create_basic_attack(),
		create_fireball(),
		create_heal(),
		create_flame_wall(),
		create_ice_field(),
		create_healing_sanctuary(),
		create_lightning_storm()
	]

static func get_enhanced_archer_moves() -> Array[Move]:
	"""Get enhanced moves for archer units with traps"""
	return [
		create_basic_attack(),
		create_poison_dart(),
		create_power_strike(),
		create_trap_placement(),
		create_poison_cloud()
	]

static func get_support_moves() -> Array[Move]:
	"""Get support moves that affect the battlefield"""
	return [
		create_healing_sanctuary(),
		create_speed_zone(),
		create_weakness_field(),
		create_trap_placement()
	]

static func get_tile_effect_moves() -> Array[Move]:
	"""Get all tile effect moves"""
	return [
		create_flame_wall(),
		create_ice_field(),
		create_healing_sanctuary(),
		create_poison_cloud(),
		create_lightning_storm(),
		create_trap_placement(),
		create_speed_zone(),
		create_weakness_field()
	]