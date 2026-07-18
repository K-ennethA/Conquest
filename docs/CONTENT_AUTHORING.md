# Content Authoring & Extensibility (Developer Experience)

Goal: add units, moves, tiles, and abilities **in the Godot editor**, not in code, wherever
possible — and keep the code maintainable when code *is* needed.

## The four tiers

### Tier 1 — Compose in the Inspector (no code)
Everything gameplay is a `Resource` with `@export` fields, so it's editable in the Inspector.

- **Add a unit**: FileSystem → right-click → *New Resource* → `CharacterResource` → set stats,
  drag in up to 4 move `.tres`, a model scene, abilities → save to `game/characters/roster/`.
- **Add a move**: *New Resource* → `MoveResource` → set a `TargetingPattern` (range + AoE shape),
  then in `effects` click **Add Element** and pick `DamageEffect` / `HealEffect` /
  `StatModifierEffect` / `TileTransformEffect` / `KnockbackEffect` / `ApplyStatusEffect` — edit
  each inline. Set `cooldown` / `max_uses`. Save to `game/combat/moves/`.
- **Add a tile / ability** (Phase 2): `TileEffectResource` / `AbilityResource` the same way —
  a trigger + condition + a list of effect blocks.

Editor polish that makes this pleasant (implemented on the resource classes):
- `@export_group` / `@export_subgroup` to organize fields.
- `@export_range`, `@export_enum`, `@export_multiline`, hint strings for guardrails.
- `@tool` + `_validate_property()` to show/hide fields by context.
- `_to_string()` so effect-array rows read "Deal 24 physical", "Burn 3 turns" — not `DamageEffect`.
- Registered class icons so the *New Resource* dialog is scannable.

### Tier 2 — New reusable behavior = a small effect subclass (a little code)
When a behavior doesn't exist yet (e.g. "pull target toward caster"), add one `MoveEffect`
subclass (~10 lines) overriding `apply(ctx)`. It is:
- **first-class** — auto-appears in the Inspector `effects` dropdown for everyone,
- **testable** — unit-tested like `DamageEffect`,
- **reusable** — usable by moves, tiles, statuses, and abilities (one pipeline).

This is the intended home for "moves need code": reusable, named, tested — not per-move.

### Tier 3 — `ScriptedEffect` escape hatch (the maintainable "lambda")
For one-off or experimental logic without touching the core: a `MoveEffect` with
`@export var logic: Script`. Write a tiny `.gd` with `func apply(ctx): ...`, assign it in the
Inspector. No core edits, still composes like any other effect.
> Why not store a lambda in the `.tres`? Godot cannot serialize a `Callable`/lambda into a
> resource. A `Script` reference is the serializable, inspector-assignable equivalent.
> Rule of thumb: prototype with `ScriptedEffect`; once a behavior is reused, promote it to a
> Tier-2 subclass so it's named and tested.

### Tier 4 — Guided creator docks (onboarding)
Extend the existing `addons/unit_creator`, `addons/tile_creator`, `addons/map_creator` (and add a
move/ability creator) into form-based tools that write the `.tres` for you. The Inspector remains
the power-user path; docks are for speed and discoverability.

## Maintainability principles
- **Open/closed**: `MoveExecutor` and the pipeline never change; you only *add* effect types.
- **Data vs. logic**: designers edit `.tres`; programmers rarely add a new effect subclass.
- **Named over anonymous**: behaviors are classes with tests, not lambdas buried in data.
- **One pipeline**: moves, tiles, statuses, abilities all resolve through `MoveEffect`/`MoveContext`.

## Build order for the DX layer
1. Inspector polish pass on existing resources (groups, ranges, enums, `_to_string`, `@tool` validation).
2. `ScriptedEffect` (Tier-3 escape hatch) + a template `.gd` + a test.
3. Class icons + `_validate_property` contextual fields.
4. Unified "Content" creator dock (extend the existing addons) — move/ability creators.
