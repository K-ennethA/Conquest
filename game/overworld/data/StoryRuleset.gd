class_name StoryRuleset
extends Resource

## STORY MODE'S TUNING SURFACE (CONQUEST.md rule 11: a mode's knobs live on its ruleset
## resource). Retuning the overworld pace, the encounter rate or befriending odds is an edit to
## game/overworld/content/story_ruleset.tres.

const DEFAULT_PATH := "res://game/overworld/content/story_ruleset.tres"

@export_group("Journey start")
@export var start_area: StringName = &"oakvale"
@export var start_entry: StringName = &"start"
## Members a new journey starts with. EMPTY in the shipped story: the hero is a villager with no
## creature until the shard ceremony in Crownhaven (docs/design/DECISIONS.md #14).
@export var starting_party: Array[StringName] = []
@export var starting_gold: int = 100
@export_range(1, 12) var party_cap: int = 6

@export_group("Walking")
## Seconds per cell walking / running (run = hold fast_forward: Shift / R3).
@export var walk_step_seconds: float = 0.22
@export var run_step_seconds: float = 0.12
## A tap on a new direction only TURNS; holding longer than this walks.
@export var turn_hold_seconds: float = 0.09

@export_group("Encounters")
## Steps after an area entry / a battle before grass may roll again.
@export var grace_steps: int = 3

@export_group("Befriending")
## Base chance a defeated wild unit offers to join (rolled on VICTORY off the battle's seed).
@export_range(0.0, 1.0) var befriend_join_chance: float = 0.35
## Added when the wild unit was subdued (left at 1 HP / KO'd by a subdue move -- DUEL M2).
@export_range(0.0, 1.0) var subdue_join_bonus: float = 0.35

@export_group("Stakes")
## Gold lost on a whiteout (0 = Q2 default: lose nothing but position).
@export var whiteout_gold_penalty: int = 0


static func load_default() -> StoryRuleset:
	if ResourceLoader.exists(DEFAULT_PATH):
		var r := load(DEFAULT_PATH) as StoryRuleset
		if r != null:
			return r
	return StoryRuleset.new()
