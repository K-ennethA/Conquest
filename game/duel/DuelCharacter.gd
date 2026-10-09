extends CharacterResource
class_name DuelCharacter

## The PRIVATE, duel-compiled copy of a roster [CharacterResource] (CONQUEST.md rule 7:
## never mutate the shared roster entry). Built only by [DuelMoveCompiler]; a duel [Unit]
## gets one as its [member Unit.character_resource] before it enters the tree.
##
## Beyond the ordinary character data it carries the duel's STRUGGLE move on a reserved
## slot ([constant STRUGGLE_SLOT], past the four real ones): [method get_move] answers it, so
## "Desperate Strike" is cast through the ordinary [method Unit.perform_move] /
## [CommandApplier] USE_MOVE path like every other move -- same command, same replay --
## while [method CharacterResource.move_count] (and so the HUD grid) still sees at most four.
## Slot 4 is never the ultimate slot (3), so the struggle can never trigger the cut-in.

## The reserved slot the struggle move answers on.
const STRUGGLE_SLOT: int = 4

## The roster id this copy was compiled from (the private copy keeps the same
## [member character_id]; this is kept separately so tooling never has to guess).
var source_id: StringName = &""
## The struggle move ([member DuelRuleset.struggle_move]); null = none offered.
var struggle_move: MoveResource = null
## move_id -> Array[String] of "no effect in duels" notes the compiler recorded.
var duel_notes: Dictionary = {}
## Roster move ids the compiler left out of the duel moveset (no variant).
var excluded_moves: Array[StringName] = []
## False when the compiled moveset cannot damage the foe at all (a pure self-guard kit).
var duel_eligible: bool = true


func get_move(slot: int) -> MoveResource:
	if slot == STRUGGLE_SLOT:
		return struggle_move
	return super(slot)


## The COMPILED moveset as-is. [DuelMoveCompiler] already built a human's kit (weapon attack +
## specials) into [member moveset], so the human kit must not be prepended a second time.
func get_moveset() -> Array[MoveResource]:
	return moveset
