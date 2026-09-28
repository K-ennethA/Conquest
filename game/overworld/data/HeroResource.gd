class_name HeroResource
extends Resource

## THE OVERWORLD AVATAR -- a dedicated human hero, separate from the party (DECISIONS.md owner
## decision 4: the "Warden"). No Blender model exists yet, so the shipped hero.tres points at an
## existing roster model as a PLACEHOLDER. This is the ONE place the avatar is configured:
## swapping in the real model is a data change (model_scene + yaw + scale), never a code change.
##
## Model convention (CONQUEST.md "Unit facing"): after [member model_yaw_deg] the model faces +Z
## (south); feet at the origin. Clips named "idle" / "walk" animate when present.

const DEFAULT_PATH := "res://game/overworld/content/hero.tres"

## The hero's name ({hero} in dialogue). Player naming is planned; "Wren" is the default.
@export var display_name: String = "Wren"
@export var model_scene: PackedScene
@export var model_yaw_deg: float = 0.0
@export var model_scale: float = 1.0
## Dialogue portrait id (a CharacterLibrary id renders a captured portrait; anything else shows
## the monogram crest).
@export var speaker_id: StringName = &"hero"


static func load_default() -> HeroResource:
	if ResourceLoader.exists(DEFAULT_PATH):
		var h := load(DEFAULT_PATH) as HeroResource
		if h != null:
			return h
	return HeroResource.new()
