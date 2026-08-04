class_name StoryBeat
extends Resource

## ONE LINE of a Fire-Emblem-style story conversation: who is talking, which side of the
## screen they stand on, what they say, and any presentation cues that fire as the line
## opens. A [StoryScene] is an ordered list of these; [StorySequencer] walks the list and
## [StoryDialogue] renders it.
##
## Authored as [code].tres[/code] under [code]game/campaign/story/[/code]. These are LOCAL
## TRUSTED content shipped in the project (a chapter's script), not player-supplied data --
## which is why a plain [Resource] is the right shape here and the hardened-importer rule
## in CONQUEST.md (#8, "untrusted JSON goes through the strict importers") does not apply.
## If story scripts ever become downloadable, that rule starts applying and this format must
## be re-exported as inert JSON first.
##
## SCHEMA (every field optional except [member text]):
## [codeblock]
## speaker_id      StringName  roster character id, or NARRATOR for an unattributed line
## speaker_name    String      display-name override; empty -> resolved from the roster
## side            StringName  SIDE_LEFT / SIDE_RIGHT -- which portrait slot speaks
## text            String      the line itself (typewriter-revealed)
## emotion         StringName  free authoring tag ("calm", "angry"); presentation hint only
## tint            Color       portrait tint multiplied over the ACTIVE modulate
## music_cue       StringName  AudioManager event fired once as this beat opens
## clear_portraits bool        hide BOTH portraits for this beat (scene-setting narration)
## [/codeblock]
##
## NARRATOR beats ([member speaker_id] == [constant NARRATOR]) render with no portraits at
## all and no name plate -- see [method is_narrator]. [member clear_portraits] is the same
## effect for an ATTRIBUTED line that should still wipe the stage (e.g. a voice from
## offscreen), so the two are independent rather than one implying the other.

## Reserved speaker id: an unattributed line. Portraits are hidden and no name plate shows.
const NARRATOR: StringName = &"narrator"

const SIDE_LEFT: StringName = &"left"
const SIDE_RIGHT: StringName = &"right"

## Roster character id whose portrait speaks this line, or [constant NARRATOR].
@export var speaker_id: StringName = NARRATOR

## Display name shown on the plate. Empty means "resolve it from the roster" -- see
## [method resolved_speaker_name]. Authored only when a character should be introduced
## under a different name than their roster entry ("a voice in the roots").
@export var speaker_name: String = ""

## Which portrait slot this speaker occupies. Anything that is not [constant SIDE_RIGHT]
## is treated as LEFT, so a typo can never leave a beat with no stage position.
@export var side: StringName = SIDE_LEFT

## The line. Revealed one character at a time by [StorySequencer].
@export_multiline var text: String = ""

## Free authoring tag for the speaker's mood. Carried through to [StoryDialogue] as a
## presentation hint (and set as node meta so a later emotion->portrait-variant lookup can
## read it); it drives nothing mechanically today.
@export var emotion: StringName = &""

## Multiplied over the ACTIVE portrait modulate while this beat is up -- a cheap way to
## push a portrait cold/bloodied without a second art asset. WHITE is "no tint".
@export var tint: Color = Color.WHITE

## [AudioManager] event name fired ONCE as this beat opens (see
## [method AudioManager.play_sfx] -- an unmapped event no-ops inside the manager, so an
## authored-but-unassigned cue is safe). Empty means "no cue".
@export var music_cue: StringName = &""

## Hide BOTH portrait panels for this beat while still attributing the line. Independent of
## [method is_narrator], which hides them because there IS no speaker.
@export var clear_portraits: bool = false


## True when this line has no attributed speaker: no portraits, no name plate.
func is_narrator() -> bool:
	return speaker_id == NARRATOR or String(speaker_id).strip_edges().is_empty()


## True when the speaker stands in the RIGHT slot. Everything else is left (see [member side]).
func is_right_side() -> bool:
	return side == SIDE_RIGHT


## The stage slot this beat's speaker occupies, normalised to one of the two constants.
func resolved_side() -> StringName:
	return SIDE_RIGHT if is_right_side() else SIDE_LEFT


## True when the overlay should show no portrait panels at all for this beat.
func hides_portraits() -> bool:
	return clear_portraits or is_narrator()


## What to print on the name plate: the authored override, else the roster display name for
## [member speaker_id], else the raw id. Returns "" for a narrator beat (no plate at all).
##
## Roster lookup is has_method-guarded so this resolves in a bare harness with no
## [CharacterLibrary] available, rather than erroring -- a story resource must be readable
## by a pure unit test.
func resolved_speaker_name() -> String:
	if not speaker_name.strip_edges().is_empty():
		return speaker_name
	if is_narrator():
		return ""
	var character: CharacterResource = CharacterLibrary.get_character(speaker_id)
	if character != null and not String(character.display_name).strip_edges().is_empty():
		return String(character.display_name)
	return String(speaker_id)


## Number of characters the typewriter has to reveal.
func text_length() -> int:
	return text.length()


## Seconds this beat's full reveal takes at [param chars_per_second]. 0.0 for an empty line
## and for a non-positive rate (which means "no typewriter" -- the text is already whole).
func reveal_duration(chars_per_second: float) -> float:
	if chars_per_second <= 0.0 or text.is_empty():
		return 0.0
	return float(text.length()) / chars_per_second
