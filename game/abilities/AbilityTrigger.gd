extends RefCounted
class_name AbilityTrigger

## Enumerates the moments at which an [AbilityResource] may fire.
##
## Neutral, game-agnostic vocabulary (no external-franchise terms), mirroring the
## style of [CombatTypes]. [code]PASSIVE[/code] abilities are not "fired" on a
## discrete event; instead their [member AbilityResource.rule_modifiers] are read
## on demand (and any effects re-evaluated while their condition holds). The rest
## are event triggers the turn / action system raises as gameplay happens.
enum Trigger {
	PASSIVE,        ## always-on while its condition holds (read via passive_modifiers)
	ON_TURN_START,  ## the unit's turn begins
	ON_TURN_END,    ## the unit's turn ends
	ON_MOVE,        ## the unit finishes a movement
	ON_TILE_ENTER,  ## the unit steps onto a new tile
	ON_ATTACK,      ## the unit resolves an attack
	ON_DAMAGED,     ## the unit takes damage
	ON_KILL,        ## the unit defeats another unit
	## the unit ITSELF dies -- the victim's side of ON_KILL. Raised by
	## [method Unit._on_unit_died] while the dying unit is still in the tree and
	## still standing on its cell, so a death burst has an origin to explode from.
	## New values MUST be appended here: the enum is serialized as an integer into
	## every authored ability .tres, so inserting one in the middle would silently
	## re-point existing content at a different trigger.
	ON_DEATH,
}
