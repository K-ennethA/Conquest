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
	## THE BATTLE BEGINS -- raised exactly ONCE per unit, for every unit already on
	## the board when the first turn opens (see
	## [method TurnSystemBase._dispatch_battle_start_once], called from the top of
	## Traditional's `_start_player_turn` and Speed First's `_start_unit_turn`). It
	## therefore lands AFTER spawn, loadout and adoption have all finished, which is
	## what lets a battle-start effect read a fully built unit.
	##
	## Deliberately NOT spawn semantics: a unit that arrives LATER -- a summon, a
	## reinforcement wave, an Arena round's second batch -- does not get it. "Every
	## unit that is here when the fight starts" is one moment in a battle; "every unit
	## the moment it exists" is a different trigger (ON_SPAWN), and conflating them
	## would hand a mid-battle summon a free opening buff. ON_SPAWN is not authored
	## yet; add it as its own appended value if content ever needs it.
	##
	## A RESUMED battle re-boots the turn system, so this pass runs again -- restored
	## units are pre-latched out of it by
	## [method BattleSaveManager.suppress_turn_start_tick], for the same reason it
	## suppresses the opening turn tick: a resume is not a battle starting.
	ON_BATTLE_START,
}
