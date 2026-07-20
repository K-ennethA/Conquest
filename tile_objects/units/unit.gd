extends TileObject

class_name Unit

# Unit stats component integration
@export var stats_resource: UnitStatsResource
@onready var unit_stats: UnitStats = get_node_or_null("UnitStats")

# Optional custom-character data (identity + base stats + moveset). When present,
# this unit can perform data-authored moves via the combat model (MoveExecutor).
@export var character_resource: CharacterResource

@export var has_turn: bool = false

# Player ownership
var owner_player: Player = null
var has_acted_this_turn: bool = false
## Set once the unit has moved this turn. A unit may move only once per turn
## unless an ability or move effect grants extra movement (see [method grant_extra_move]).
var has_moved_this_turn: bool = false

# Signals
signal unit_died(unit: Unit)
signal unit_action_completed(unit: Unit, action_type: String)
signal owner_changed(unit: Unit, old_owner: Player, new_owner: Player)

# Inspector testing properties (for runtime testing)
@export_group("Runtime Testing")
@export var test_damage_amount: int = 10:
	set(value):
		if value > 0 and is_inside_tree():
			take_damage(value)
			test_damage_amount = 0  # Reset after use

@export var test_heal_amount: int = 10:
	set(value):
		if value > 0 and is_inside_tree():
			heal(value)
			test_heal_amount = 0  # Reset after use

@export var current_health_display: int:
	get:
		return current_health
	set(value):
		if unit_stats and value >= 0:
			unit_stats.set_stat("health", min(value, max_health))

# Visual management
var visual_manager: UnitVisualManager
var player_assignment: PlayerMaterials.PlayerTeam = PlayerMaterials.PlayerTeam.NEUTRAL

# Health management
var current_health: int:
	get:
		if unit_stats:
			return unit_stats.get_stat("health")
		return 0

var max_health: int:
	get:
		if unit_stats:
			return unit_stats.get_base_stat("health")
		return 0

# Visual feedback
var _mesh_instance: MeshInstance3D
var _original_material: Material

# Board footprint. Cells are 2 world units across (see Grid.cell_size); the mesh
# scale a large unit was built from is cached the first time apply_footprint_visual()
# runs so re-applying it never multiplies the scale again.
const CELL_SIZE: float = 2.0
var _footprint_base_scale: Vector3 = Vector3.ONE
var _has_footprint_base_scale: bool = false

# Death guard: death resolution (signals + despawn) must run exactly once, no
# matter how many code paths observe HP hitting 0 (take_damage, the health_changed
# signal, or a heal-then-lethal edge). Latches true on the first death.
var _is_dead: bool = false

func _ready() -> void:
	_setup_stats_component()
	_setup_visuals()
	_connect_events()
	_setup_visual_management()

func _setup_visual_management() -> void:
	"""Set up visual management for this unit"""
	# Find or create visual manager
	visual_manager = _find_visual_manager()
	if not visual_manager:
		# No visual manager (e.g. headless / test harness). Visuals are cosmetic; skip silently.
		return
	
	# Check if we have an owner player (new system)
	if owner_player:
		visual_manager.setup_unit_visuals_for_player(self, owner_player)
	else:
		# Fallback to old system - determine player assignment from scene tree
		player_assignment = _determine_player_from_scene_tree()
		visual_manager.setup_unit_visuals(self, player_assignment)

func _find_visual_manager() -> UnitVisualManager:
	"""Find UnitVisualManager in the scene tree"""
	# Look for it in the scene root or map
	var scene_root = get_tree().current_scene
	if scene_root:
		var manager = scene_root.find_child("UnitVisualManager", true, false)
		if manager:
			return manager

		# If not found, create one under the current scene
		var new_manager = UnitVisualManager.new()
		new_manager.name = "UnitVisualManager"
		scene_root.add_child(new_manager)
		return new_manager

	# No current scene (e.g. running headless / under a test harness). Skip
	# visual manager creation rather than dereferencing a null scene root.
	return null

func _determine_player_from_scene_tree() -> PlayerMaterials.PlayerTeam:
	"""Determine player assignment based on parent node names"""
	var parent = get_parent()
	while parent:
		if parent.name.to_lower().contains("player1"):
			return PlayerMaterials.PlayerTeam.PLAYER_1
		elif parent.name.to_lower().contains("player2"):
			return PlayerMaterials.PlayerTeam.PLAYER_2
		parent = parent.get_parent()
	
	return PlayerMaterials.PlayerTeam.NEUTRAL

func _setup_stats_component() -> void:
	"""Initialize the UnitStats component"""
	# Create UnitStats component if it doesn't exist
	if not unit_stats:
		unit_stats = UnitStats.new()
		unit_stats.name = "UnitStats"

		# Decide which UnitStatsResource drives the runtime stats. When a
		# CharacterResource is assigned it is the canonical authoring data
		# (D1): derive a UnitStatsResource from its base stats and feed the
		# existing UnitStats component. A character always wins over any
		# pre-assigned stats_resource. With no character, behaviour is
		# unchanged from the legacy stats_resource-only path.
		var effective_resource: UnitStatsResource = stats_resource
		if character_resource:
			effective_resource = _build_stats_resource_from_character(character_resource)

		# Set up stats resource BEFORE adding to tree
		if effective_resource:
			unit_stats.stats_resource = effective_resource
		else:
			push_error("Unit requires a UnitStatsResource! Please assign one in the inspector.")
			return

		# Now add to tree, _ready() will work properly
		add_child(unit_stats)

	# Connect to stats events
	if unit_stats:
		unit_stats.health_changed.connect(_on_health_changed)
		unit_stats.stat_changed.connect(_on_stat_changed)

	# A character-backed unit also gets its combat companion components
	# (moveset cooldown tracking + status conditions).
	if character_resource:
		_setup_character_components()


## Build a runtime [UnitStatsResource] from a [CharacterResource]'s authoring
## data. The character owns the base stat block (D1); the derived resource is
## what the [UnitStats] component consumes, so take_damage/heal/get_stat keep
## working unchanged. Note: CharacterResource.base_magic_defense has no
## counterpart on UnitStatsResource and is intentionally not mapped.
func _build_stats_resource_from_character(character: CharacterResource) -> UnitStatsResource:
	var derived := UnitStatsResource.new()
	derived.unit_name = character.display_name
	derived.unit_type = String(character.character_id)
	derived.max_health = character.base_health
	derived.base_attack = character.base_attack
	derived.base_defense = character.base_defense
	derived.base_magic = character.base_magic
	derived.base_speed = character.base_speed
	derived.movement_range = character.base_movement
	derived.attack_range = character.attack_range
	return derived


## Attach the combat companion components a character-backed unit needs, once.
## Both are guarded so repeated setup calls never duplicate them.
func _setup_character_components() -> void:
	# Moveset cooldown / uses tracker. The controller tracks state lazily by
	# move_id and needs no explicit seeding; if a sibling task adds a seeding
	# hook, feed it the character's moveset via duck-typing.
	if not has_node("MovesetController"):
		var moveset_controller := MovesetController.new()
		moveset_controller.name = "MovesetController"
		if moveset_controller.has_method("seed_from_moveset"):
			moveset_controller.call("seed_from_moveset", character_resource.moveset)
		add_child(moveset_controller)

	# Active status-condition tracker.
	if not has_node("StatusController"):
		var status_controller := StatusController.new()
		status_controller.name = "StatusController"
		status_controller.owner_unit = self
		add_child(status_controller)

	# Character abilities (always-on / triggered passives). Attached as a CHILD
	# so AbilitySystem._unit() resolves to this unit naturally, and only when the
	# character actually declares abilities -- a character with none keeps the
	# exact node layout it had before.
	if not has_node("AbilitySystem") and not character_resource.abilities.is_empty():
		var ability_system := AbilitySystem.new()
		ability_system.name = "AbilitySystem"
		ability_system.owner_unit = self
		for ability in character_resource.abilities:
			ability_system.add_ability(ability)
		add_child(ability_system)

func _setup_visuals() -> void:
	"""Initialize visual components"""
	# Only set up visuals if MeshInstance3D exists (for testing compatibility)
	if has_node("MeshInstance3D"):
		_mesh_instance = get_node("MeshInstance3D")
		if _mesh_instance and _mesh_instance.mesh and _mesh_instance.mesh.material:
			_original_material = _mesh_instance.mesh.material
		# Size the model to the unit's footprint even when no visual manager is
		# present (headless / test harness). No-op for normal 1x1 units.
		apply_footprint_visual()
	# Swap in the character's authored model, if it has one.
	_setup_character_model()


## Instantiate the character's authored model (a Blender export -- see
## tools/blender/prepare_unit.py) in place of the placeholder capsule.
##
## Models are exported origin-at-feet and already scaled to their real height, so
## they need no runtime correction: dropping one in at the unit's origin puts its
## feet on the tile. The capsule is HIDDEN rather than removed, because
## UnitVisualManager still drives team colour/selection through it and other code
## looks it up by name.
func _setup_character_model() -> void:
	if character_resource == null or character_resource.model_scene == null:
		return
	if get_node_or_null("CharacterModel") != null:
		return  # already built

	var model := character_resource.model_scene.instantiate()
	if model == null:
		push_warning("[Unit] model_scene failed to instantiate for %s" % name)
		return
	model.name = "CharacterModel"
	add_child(model)

	# Centre a multi-cell model over its whole footprint, exactly like the capsule.
	if model is Node3D:
		(model as Node3D).position = get_footprint_offset()

	if _mesh_instance:
		_mesh_instance.visible = false

func _connect_events() -> void:
	"""Connect to game events"""
	# Only connect if GameEvents exists (for testing compatibility)
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)

# Stat access methods (preferred interface)
func get_stat(stat_name: String) -> int:
	"""Get current stat value"""
	if unit_stats:
		return unit_stats.get_stat(stat_name)
	return 0

func get_base_stat(stat_name: String) -> int:
	"""Get base stat value (without modifiers)"""
	if unit_stats:
		return unit_stats.get_base_stat(stat_name)
	return 0

func modify_stat(stat_name: String, amount: int, is_permanent: bool = false) -> void:
	"""Modify a stat by amount"""
	if unit_stats:
		unit_stats.modify_stat(stat_name, amount, is_permanent)

func set_stat(stat_name: String, value: int, is_permanent: bool = false) -> void:
	"""Set a stat to specific value"""
	if unit_stats:
		unit_stats.set_stat(stat_name, value, is_permanent)

func add_stat_modifier(stat_name: String, amount: int, duration: int = -1) -> int:
	"""Add temporary stat modifier"""
	if unit_stats:
		return unit_stats.add_stat_modifier(stat_name, amount, duration)
	return -1

func remove_stat_modifier(modifier_id: int) -> bool:
	"""Remove specific stat modifier"""
	if unit_stats:
		return unit_stats.remove_stat_modifier(modifier_id)
	return false

# Health management
func take_damage(amount: int) -> void:
	"""Apply damage to the unit"""
	if unit_stats:
		var current_hp = unit_stats.get_stat("health")
		var new_hp = max(0, current_hp - amount)
		unit_stats.set_stat("health", new_hp)
		
		if new_hp <= 0:
			_on_unit_died()

func heal(amount: int) -> void:
	"""Heal the unit"""
	if unit_stats:
		var current_hp = unit_stats.get_stat("health")
		var max_hp = unit_stats.get_base_stat("health")
		var new_hp = min(max_hp, current_hp + amount)
		unit_stats.set_stat("health", new_hp)

func is_alive() -> bool:
	"""Check if unit is alive"""
	return not _is_dead and current_health > 0

func is_at_full_health() -> bool:
	"""Check if unit is at full health"""
	return current_health >= max_health

# Unit type and properties
func get_unit_type() -> String:
	"""Get the unit's type"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.unit_type
	return ""

func get_display_name() -> String:
	"""Get the unit's display name"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.unit_name
	return "Unknown Unit"

func is_ranged_unit() -> bool:
	"""Check if this is a ranged unit"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.is_ranged_unit()
	return false

# Player ownership methods
func set_owner_player(player: Player) -> void:
	"""Set the player who owns this unit"""
	var old_owner = owner_player
	owner_player = player
	
	# Update visual identification
	if player:
		player_assignment = _get_player_assignment_from_player(player)
		# Update visuals immediately if visual manager exists
		if visual_manager:
			visual_manager.setup_unit_visuals_for_player(self, player)
	else:
		player_assignment = PlayerMaterials.PlayerTeam.NEUTRAL
		# Update visuals to neutral
		if visual_manager:
			visual_manager.setup_unit_visuals(self, player_assignment)
	
	owner_changed.emit(self, old_owner, player)

func get_owner_player() -> Player:
	"""Get the player who owns this unit"""
	return owner_player

func _get_player_assignment_from_player(player: Player) -> PlayerMaterials.PlayerTeam:
	"""Convert Player to PlayerMaterials.PlayerTeam enum"""
	if not player:
		return PlayerMaterials.PlayerTeam.NEUTRAL
	
	match player.player_id:
		0:
			return PlayerMaterials.PlayerTeam.PLAYER_1
		1:
			return PlayerMaterials.PlayerTeam.PLAYER_2
		_:
			return PlayerMaterials.PlayerTeam.NEUTRAL

# Turn action management
func reset_turn_actions() -> void:
	"""Reset unit's actions for a new turn"""
	has_acted_this_turn = false
	has_moved_this_turn = false

func mark_action_completed(action_type: String) -> void:
	"""Mark that this unit has completed its action (ends its turn)"""
	has_acted_this_turn = true
	unit_action_completed.emit(self, action_type)

func mark_moved() -> void:
	"""Mark that this unit has used its move for the turn (does NOT end its turn;
	the unit can still take an action). Moving again is blocked until reset or an
	extra-move grant."""
	has_moved_this_turn = true

func grant_extra_move() -> void:
	"""Allow the unit to move again this turn (for abilities / move effects)."""
	has_moved_this_turn = false

func can_act() -> bool:
	"""Check if unit can still take its action this turn"""
	return not has_acted_this_turn and is_alive()

func can_move() -> bool:
	"""Check if unit can move this turn (once, unless granted extra movement)"""
	return is_alive() and not has_acted_this_turn and not has_moved_this_turn

# Validation methods
func can_be_selected_by_player(player: Player) -> bool:
	"""Check if a specific player can select this unit"""
	return owner_player == player

func can_be_controlled_by_player(player: Player) -> bool:
	"""Check if a specific player can control this unit"""
	return owner_player == player and can_act()

# Character / move system integration
func has_character() -> bool:
	"""True if this unit is backed by a CharacterResource (custom moveset)."""
	return character_resource != null

## Current health of the unit (0 when no stats component is present).
func get_hp() -> int:
	return current_health

## How many board cells this unit spans. Vector2i.ONE (a normal 1x1 unit) for
## anything without a character resource or with an invalid authored value; the
## unit's anchor cell (BoardAdapter.cell_of) is the minimum corner of that span.
## This is the ONE place other systems ask a unit about its size.
func get_footprint() -> Vector2i:
	if character_resource == null:
		return Vector2i.ONE
	if character_resource.has_method("get_footprint"):
		return character_resource.get_footprint()
	var fp = character_resource.get("footprint")
	if fp is Vector2i:
		return Vector2i(maxi(1, fp.x), maxi(1, fp.y))
	return Vector2i.ONE

## Offset from the anchor cell's center to the center of the whole footprint.
## Cells are CELL_SIZE world units across and the unit node sits at its anchor
## cell's center, so a (w,h) span reaches (w-1) cells along +X and (h-1) along +Z.
## Vector3.ZERO for a 1x1 unit.
func get_footprint_offset() -> Vector3:
	var fp := get_footprint()
	return Vector3(
		float(fp.x - 1) * CELL_SIZE * 0.5,
		0.0,
		float(fp.y - 1) * CELL_SIZE * 0.5)

## Scale the unit's MeshInstance3D to fill its footprint and slide it so the model
## centers over the whole covered block instead of sitting on the anchor cell.
##
## Applied to the VISUAL child only -- moving the unit node itself would change the
## world position BoardAdapter.cell_of() derives the anchor from. A 1x1 unit is a
## no-op, so normal units keep exactly the scale/offset the scene and the visual
## manager gave them. The pre-footprint scale is cached on first use so repeated
## calls (the visual manager re-applies materials + type scale on every refresh)
## never compound.
func apply_footprint_visual() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var fp := get_footprint()
	if fp == Vector2i.ONE:
		return
	if not _has_footprint_base_scale:
		_footprint_base_scale = mesh.scale
		_has_footprint_base_scale = true
	# Wide/deep by the span; height follows the larger axis so a 2x2 boss reads
	# as genuinely big rather than a flattened slab.
	var tall: float = float(maxi(fp.x, fp.y))
	mesh.scale = Vector3(
		_footprint_base_scale.x * float(fp.x),
		_footprint_base_scale.y * tall,
		_footprint_base_scale.z * float(fp.y))
	mesh.position = get_footprint_offset()

## True only for character-backed bosses; false for legacy / non-character units.
func is_boss() -> bool:
	if character_resource:
		return character_resource.is_boss
	return false

## The MovesetController child (cooldown / uses tracking), or null if absent.
func get_moveset_controller() -> Node:
	return get_node_or_null("MovesetController")

## The StatusController child (active status conditions), or null if absent.
func get_status_controller() -> Node:
	return get_node_or_null("StatusController")

## The AbilitySystem child (character abilities), or null when the character
## declares none / there is no character at all.
func get_ability_system() -> Node:
	return get_node_or_null("AbilitySystem")

## The character's movement profile once T6 adds get_movement_profile() to
## CharacterResource. Duck-typed so this compiles before that method exists;
## returns null when there is no character or the method is not yet available.
func get_movement_profile():
	if character_resource and character_resource.has_method("get_movement_profile"):
		return character_resource.get_movement_profile()
	return null

func get_moveset() -> Array[MoveResource]:
	"""The unit's moves, or an empty list when no character is assigned."""
	if character_resource:
		return character_resource.moveset
	var empty: Array[MoveResource] = []
	return empty

func get_move(slot: int) -> MoveResource:
	"""Move in the given slot (0..3), or null when empty/out of range."""
	if character_resource:
		return character_resource.get_move(slot)
	return null

func perform_move(slot: int, aim_cell: Vector2i, board_adapter) -> Dictionary:
	"""Resolve the move in [param slot] aimed at [param aim_cell] against the
	live board (a BoardAdapter). Delegates to MoveExecutor and returns its
	structured result dictionary (see MoveExecutor.execute)."""
	var move := get_move(slot)
	if move == null:
		return {
			"success": false,
			"reason": "no_move_in_slot",
			"events": [],
			"cells": [],
		}
	return MoveExecutor.execute(move, self, board_adapter, aim_cell)

# Movement methods
func get_movement_range() -> int:
	"""Get unit's movement range"""
	return get_stat("movement")

func can_move_to(position: Vector3) -> bool:
	"""Check if unit can move to position (override in derived classes)"""
	return true

# Turn management
func process_turn_start() -> void:
	"""Called when unit's turn starts"""
	if unit_stats:
		unit_stats.process_modifier_durations()

func process_turn_end() -> void:
	"""Called when unit's turn ends"""
	# Reset action points or other per-turn resources
	pass
func _on_health_changed(old_health: int, new_health: int) -> void:
	"""Handle health changes"""
	# Notify visual manager directly
	if visual_manager:
		visual_manager._on_unit_health_changed(self, old_health, new_health)
	
	# Update health bar UI, check for death, etc.
	if new_health <= 0 and old_health > 0:
		_on_unit_died()

func _on_stat_changed(stat_name: String, old_value: int, new_value: int) -> void:
	"""Handle stat changes"""
	# Update UI, trigger effects, etc.
	pass

func _on_unit_died() -> void:
	"""Handle unit death: fire the death signals ONCE, then remove the unit from
	the board and scene so it stops occupying a cell, blocking turns, or lingering
	visually. Idempotent via _is_dead -- multiple observers of HP == 0 (take_damage,
	the health_changed signal) all funnel here but death only resolves once."""
	if _is_dead:
		return
	_is_dead = true

	# 1. Notify listeners while the node is still valid:
	#    - the owning Player removes it from owned_units (and self-eliminates when
	#      its last unit dies, which PlayerManager turns into a win/lose result),
	#    - the active turn system unregisters it and re-checks turn completion so a
	#      side whose last actable unit just died doesn't stall the turn.
	unit_died.emit(self)
	GameEvents.unit_eliminated.emit(self, null)  # null = no killer specified

	# 2. Tear down this unit's floating health bar (erases it from the visual
	#    manager's registry so no dangling reference remains).
	if visual_manager and visual_manager.has_method("cleanup_unit_visuals"):
		visual_manager.cleanup_unit_visuals(self)

	# 3. Remove the unit from play. Hide immediately so it disappears this frame,
	#    then free the node deferred -- deferring lets the signal handlers above
	#    (and anything mid-iteration over the board/units this same frame) unwind
	#    before the node is actually gone.
	visible = false
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()

# Visual feedback (updated to use visual manager)
func _on_unit_selected(unit: Unit) -> void:
	if unit == self and visual_manager:
		visual_manager.apply_selection_visual(self, true)

func _on_unit_deselected(unit: Unit) -> void:
	if unit == self and visual_manager:
		visual_manager.apply_selection_visual(self, false)

func _apply_selection_visual(selected: bool) -> void:
	"""Legacy method - now delegates to visual manager"""
	if visual_manager:
		visual_manager.apply_selection_visual(self, selected)

# Debug helpers
func _to_string() -> String:
	if unit_stats:
		return str(unit_stats)
	return "Unit: No stats component"

func get_debug_info() -> Dictionary:
	"""Get debug information about the unit"""
	var info = {
		"name": get_display_name(),
		"alive": is_alive(),
		"has_turn": has_turn,
		"position": position,
		"stats_component": unit_stats != null
	}
	
	if unit_stats:
		info.merge(unit_stats.get_debug_info())
	
	return info
