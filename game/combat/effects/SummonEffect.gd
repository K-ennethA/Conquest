extends MoveEffect
class_name SummonEffect

## Raises [member count] units of [member character_id] onto free cells near the aim,
## owned by the CASTER's player. The Necromancer's identity: Reanimate (an ON_KILL
## ability that raises one undead on the slain foe's cell) and Undying Legion (a move
## that raises a small horde beside the caster) both use this.
##
## The actual spawn + ownership + turn-registration is delegated to
## [method GameWorldManager.summon_unit] (found via the "game_world_manager" group), so
## this effect stays a thin, headless-safe describer: with no live GameWorldManager
## (unit tests, mock harnesses) it simply summons nothing rather than erroring.
##
## NOTE: summons belong to the caster's player and are PLAYER-CONTROLLED. The turn/AI
## architecture drives whole AI players, not individual units on a human's side, so a
## truly autonomous "charge the enemy on its own" ally is not expressible yet -- the
## stance is carried through for the day that becomes possible. See the survey notes.

## How many bodies to raise.
@export var count: int = 1
## The roster id of the unit to raise (a melee-only "undead" character by default).
@export var character_id: StringName = &"undead"
## AI stance stamped on each summon (forward-looking; player-owned summons are commanded
## by the player today).
@export var stance: String = "aggressive"


func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.caster == null:
		return
	if not ctx.caster.has_method("get_owner_player"):
		return
	var owner = ctx.caster.get_owner_player()
	if owner == null:
		return
	var pid: int = int(owner.player_id)

	var gwm = _game_world_manager()
	if gwm == null or not gwm.has_method("summon_unit"):
		return  # no live world (headless/tests) -> nothing to raise

	var origin: Vector2i = ctx.aim_cell
	var cells: Array = _summon_cells(ctx, origin, count)
	for cell in cells:
		var unit = gwm.summon_unit(character_id, cell, pid, stance)
		if unit != null:
			ctx.log_event({
				"effect": "summon",
				"target": unit,
				"cell": cell,
				"character_id": String(character_id),
			})


## The active [GameWorldManager], or null when there is no live scene (headless tests).
func _game_world_manager():
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return loop.get_first_node_in_group("game_world_manager")
	return null


## Up to [param n] free cells spiralling out from [param origin] (the aim / victim cell),
## skipping out-of-bounds and occupied cells so summons never stack on a corpse or a
## standing unit. The origin itself is included only if free -- at an ON_KILL raise the
## victim still occupies it this frame, so the raise lands on an adjacent cell.
func _summon_cells(ctx: MoveContext, origin: Vector2i, n: int) -> Array:
	var out: Array = []
	var board = ctx.board
	var ring: int = 0
	while out.size() < n and ring <= 6:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if out.size() >= n:
					break
				# Only the current ring's PERIMETER, so cells fill nearest-first.
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if cell in out:
					continue
				if not _cell_is_free(board, cell):
					continue
				out.append(cell)
		ring += 1
	return out


## True when [param cell] is a legal, empty landing spot. Duck-typed / null-safe so a
## bare mock board (or none) never blocks the spiral.
func _cell_is_free(board, cell: Vector2i) -> bool:
	if board == null:
		return true
	if board.has_method("in_bounds") and not board.in_bounds(cell):
		return false
	if board.has_method("is_occupied") and board.is_occupied(cell):
		return false
	if board.has_method("is_blocked") and board.is_blocked(cell):
		return false
	return true


func describe() -> String:
	if description_override != "":
		return description_override
	if count == 1:
		return "Raise an undead servant"
	return "Raise %d undead servants" % count
