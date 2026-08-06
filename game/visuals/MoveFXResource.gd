extends Resource
class_name MoveFXResource

## PER-MOVE FX OVERRIDE -- the inspector-editable hook on top of [MoveFXDispatcher]'s
## defaults. Authored as a `.tres` and referenced from [member MoveResource.fx]; a move
## that references NOTHING (the default, and every move authored before this existed)
## renders the dispatcher's derived default sequence, so this file only ever changes a
## move that deliberately opts in.
##
## THE RESOLUTION RULE IS OVERRIDE-ELSE-DEFAULT, FIELD BY FIELD. Every field below has a
## "not authored" value (an alpha-0 colour, an empty cue, a 1.0 multiplier, a null scene)
## and the dispatcher falls back to its own derivation for exactly those. So an override
## that only wants a bigger burst says so in one field and inherits the element tint, the
## ring, the cue and the (absent) shake unchanged -- there is no "you set one, you own them
## all" cliff.
##
## PURELY COSMETIC. Nothing here is read by the combat layer, nothing here is serialised
## into a command or a replay, and nothing here draws from a battle RNG stream. A different
## FX resource on the same move resolves the identical damage on every peer.

## Tint for the burst, the ring and the shards. ALPHA 0 (the default) means "not authored"
## -- the dispatcher then uses the move's own element through
## [method ConquestTheme.element_color], the single colour vocabulary every element chip in
## the UI already reads. Author an opaque colour to force one.
@export var color: Color = Color(0.0, 0.0, 0.0, 0.0)

## Multiplier on the impact burst (the particle spark AND the shards). 1.0 = the default
## size. Bigger reads as a heavier hit; this is the knob Abyssal Maw's eruption turns up.
@export_range(0.1, 4.0, 0.05) var burst_scale: float = 1.0

## Draw the flat ground ring on every affected cell. Off makes an impact read as a hit on
## the unit rather than as something happening to the GROUND.
@export var ring_enabled: bool = true

## Multiplier on the ground ring's radius, independent of [member burst_scale] so a wide
## shockwave and a small spark are separately authorable.
@export_range(0.1, 4.0, 0.05) var ring_scale: float = 1.0

## [AudioManager] event name played once when the cast starts. Empty = the dispatcher's
## default cast cue. Must be a slot [AudioLibrary] actually maps -- an unknown or unassigned
## event is a silent no-op, never an error.
@export var cast_cue: StringName = &""

## [AudioManager] event name played once on impact. Empty = the dispatcher's default.
## See [MoveFXDispatcher] for WHEN the impact cue plays (it fills silence rather than
## doubling the hit sound the audio layer already plays per victim).
@export var impact_cue: StringName = &""

## Camera kick on impact, handed to [method CameraController.impulse_shake]. 0.0 (the
## default) is no shake at all. Tiny values are the intended range -- the camera clamps
## anything above 0.5 and skips the kick entirely when animations are off.
@export_range(0.0, 0.5, 0.01) var shake_strength: float = 0.0

## OPTIONAL bespoke scene instanced once per affected cell, at that cell's centre, IN
## ADDITION to (not instead of) the default ring/shards -- so a hand-authored VFX can be
## dropped onto one move without also having to re-author the parts that already read.
## It is added as a child of the cell's self-freeing impact container, so it is freed with
## it: an instanced scene must not assume it lives longer than [member lifetime_scale] x the
## default impact life.
@export var impact_scene: PackedScene = null

## Multiplier on how long the impact lives. Bigger = it lingers. Still floored/capped by
## the dispatcher so a fast battle speed cannot compress it away and a slow one cannot
## leave it on the board into the next action.
@export_range(0.25, 4.0, 0.05) var lifetime_scale: float = 1.0


## True when [member color] was actually authored. Alpha 0 is the sentinel (see that
## member) -- a fully transparent tint would render nothing, so it can never be a
## legitimate authored value.
func has_color() -> bool:
	return color.a > 0.0
