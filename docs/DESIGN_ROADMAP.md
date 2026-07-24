# Conquest — Design & Architecture Roadmap

This is the living plan for building Conquest into the game described below. It maps
the **vision** to concrete **systems**, records **what exists today**, and lays out a
**phased build-out**. The guiding rule: everything gameplay-affecting is *data*, resolved
through *one shared effect pipeline*, so new content is authored (a `.tres`), not coded.

---

## 1. The Vision

- **Maps** — grids of **custom tiles** with effects: fire burns units standing on it,
  water empowers certain characters, fortify tiles boost defense, stealth tiles hide
  occupants, etc. Adding a new tile type must be easy.
- **Units** — distinct stats, **movement patterns**, moves, and abilities.
- **Moves** — deal damage (to one or many units, across many tiles), transform terrain,
  apply effects **over multiple turns**, buff/debuff, and have **cooldowns**. Very flexible,
  easy to add.
- **Abilities** — unique passive/triggered powers that change how a unit plays (empowered
  on water, move twice, …). Flexible, easy to add.
- **Solo** — bots that attack the enemy; **one map per boss**, where a boss is an empowered
  unit with extra strength.
- **Multiplayer** — players easily battle: pick **which** units, **how many**, **which map**,
  and the **rules**. Players can **build their own maps** from the tiles and units we ship.

---

## 2. Core architectural principle — the Effect Pipeline

There is one vocabulary for "something happens to a unit or tile": **`MoveEffect`**, resolved
against a **`MoveContext`** (caster/board/targets). It already powers moves. We extend the
*same* pipeline to be driven by **tiles**, **status conditions**, and **abilities**:

```
            ┌───────────── triggers ─────────────┐
  Move  ──▶ │                                     │
  Tile  ──▶ │   Effect(s): Damage / Heal /        │ ──▶ MoveContext ──▶ board + units mutate
  Status──▶ │   StatModifier / TileTransform /    │        (results log → UI / net / AI)
  Ability▶  │   Knockback / ApplyStatus / …       │
            └─────────────────────────────────────┘
```

Consequences:
- Add a new *behaviour* once (a small `MoveEffect` subclass) → reuse it in moves, tiles,
  statuses, and abilities.
- Add new *content* (a fire tile, a poison move, a "regen on water" ability) with zero code —
  just compose existing effects in a `.tres`.
- One resolution path → consistent rules, and it stays deterministic for networked replay.

---

## 3. System design

### 3.1 Tiles & Tile Effects
- `TileResource` — static data (name, texture, move cost, passable, tags).
- **NEW `TileEffectResource`** — `{ trigger, condition, effects: Array[MoveEffect] }`.
  - `trigger`: `ON_ENTER`, `ON_TURN_START_WHILE_OCCUPYING`, `ON_EXIT`, `PASSIVE_WHILE_OCCUPYING`.
  - `condition`: optional filter (faction, character tag) → e.g. water empowers only
    `aquatic`-tagged units; fire burns everyone.
  - Examples: **fire** = `ON_TURN_START` → `DamageEffect`; **water** = `PASSIVE` +
    condition `aquatic` → `StatModifierEffect(+attack)`; **fortify** = `PASSIVE` →
    `StatModifierEffect(+defense)`; **stealth** = `PASSIVE` → `UntargetableEffect`.
- **NEW `TileEffectSystem`** — listens to unit enter/exit/turn events and runs a tile's
  effects through the effect pipeline. (Reconcile/replace the older `TileEffect.gd` /
  `TileEffectManager.gd`.)

> **Migration status: DONE** (live gameplay path) — `CombatServices` wires cell → terrain →
> `TileEffectResource` (`game/tiles/effects/resources/*.tres`) through `TileEffectSystem`;
> movement, attacks, and enemy AI all resolve tile effects through this data-driven pipeline.
> **Not yet retired**: `game/tiles/TileEffect.gd` / `TileEffectManager.gd` (the old classes)
> are still hard-referenced by live code — `tile_objects/tiles/tile.gd` (the tile scene used
> by every map) and `game/tiles/resources/TileResource.gd` both type against `TileEffect` and
> constructs it directly, and `game/tiles/resources/molten_lava.tres` embeds a `TileEffect`
> sub-resource. Deleting the old scripts today is a hard load error; see T19 sweep notes for
> the rewiring needed before they can be removed.

### 3.2 Status / over-time conditions
- **NEW `StatusCondition`** (Resource) — `{ id, duration_turns, tick_effects: Array[MoveEffect],
  on_apply, on_expire, stacking }`. Burn = damage tick; regen = heal tick; timed buff = stat mod.
- **NEW `ApplyStatusEffect`** (a `MoveEffect`) — inflicts a `StatusCondition` on targets, so any
  move/tile/ability can cause multi-turn effects.
- **NEW `StatusController`** (unit component) — holds active conditions, ticks them on turn
  start/end, expires them, exposes them to UI.

### 3.3 Moves (extend existing)
Built: `MoveResource` = targeting + effect list (damage, AoE, terrain, buff/debuff). **Add:**
- `cooldown: int` on `MoveResource`.
- **NEW `MovesetController`** (unit component) — per-move cooldown/uses tracking, `can_use`,
  `on_used`, tick-down each turn.
- Multi-turn moves come free via `ApplyStatusEffect` (3.2).

### 3.4 Abilities
- **NEW `AbilityResource`** — `{ trigger, condition, effects | rule_modifiers }`.
  - `trigger`: `PASSIVE`, `ON_TURN_START`, `ON_MOVE`, `ON_TILE_ENTER`, `ON_ATTACK`,
    `ON_DAMAGED`, `ON_KILL`.
  - Effects reuse the pipeline; **rule modifiers** touch the action economy
    (e.g. `extra_actions: +1` = "move twice", `ignore_terrain_cost`).
- **NEW `AbilitySystem`** (unit component) — evaluates abilities on the relevant events.
- `CharacterResource.abilities: Array[AbilityResource]`.

### 3.5 Movement patterns
- **NEW `MovementProfile`** (Resource) — `{ kind (ground/fly/phase), range, shape
  (orthogonal/diagonal/knight/teleport), terrain_cost_overrides }`. Pathfinding consults it +
  tile move-cost. Wire into the existing grid + `MovementVisualizer`.

### 3.6 Solo — bots & bosses
Built: `BotController`, `BossController`, `WinCondition` framework. **Add:**
- **NEW `AITurnController`** — the solo turn loop: on an AI faction's turn, iterate its units,
  ask the controller for a decision, execute via `MoveExecutor` + `BoardAdapter`.
- **NEW `EncounterResource`** — "one map per boss": `{ map, roster, boss, win/lose conditions,
  reward }`.
- **Boss empowerment** — a modifier (stat multipliers + bonus abilities) layered onto a
  `CharacterResource`.
- Reconcile the bot↔board interface gap (bot expects `all_units()`, `hp`, `is_boss`;
  extend `BoardAdapter`/`Unit`).

### 3.7 Multiplayer match setup
Built: `NetSession` (server-authoritative, N-player), `GameModeRules`, map maker. **Add:**
- **NEW `MatchSettings`** (Resource/dict) — `{ map, mode/rules, per-player unit picks + count
  caps }`, synced over `NetSession`.
- **Lobby wiring** — pick map/units/count/rules → sync → start. Use built-in **and**
  user-created maps via a `MapRegistry` (scans `game/maps/resources/` + a user dir).

---

## 4. What exists today (foundation already built)

| Area | Modules |
|---|---|
| Effect pipeline / moves | `game/combat/`: `CombatTypes`, `TargetingPattern`, `MoveContext`, `MoveEffect` + `DamageEffect`/`HealEffect`/`StatModifierEffect`/`TileTransformEffect`/`KnockbackEffect`, `MoveResource`, `MoveExecutor`, `MoveLibrary`, `BoardAdapter` |
| Characters | `game/characters/`: `CharacterResource` (unique stats + 4 moves), `SampleRoster` (test units) |
| Modes / win conditions | `game/modes/`: `WinCondition`, `DefeatAllEnemies`, `CaptureThrone`, `SurviveTurns`, `ProtectUnit`, `GameModeRules` |
| Bots / bosses | `game/ai/`: `BotController`, `BossController` |
| Maps | `game/maps/` + `game/mapmaker/`: `MapResource`, `MapLoader`, `MapMakerModel`, `TileTextureImporter`, `skirmish_arena.tres` |
| Tiles | `game/tiles/`: `TileResource`; data-driven effects **DONE** via `game/tiles/effects/`: `TileEffectResource`/`TileEffectSystem`/`TileEffectLibrary`, wired through `CombatServices`. `TileEffect`/`TileEffectManager` (old) still present — still referenced by `tile_objects/tiles/tile.gd` and `TileResource.gd`; not yet retirable (see §3.1 note) |
| Networking | `systems/net/`: `NetSession`, `NetProtocol` (server-authoritative, N-player) |
| Turns / board | `board/`, `turns/`, `systems/` turn systems, `PlayerManager` |

Test coverage: ~158 passing unit tests across combat, characters, modes, AI, map maker, board adapter.

> **Migration status: DONE** — movement, attacks, and enemy AI all run on the data-driven
> stack above (`MoveResource`/`MoveExecutor`/`BoardAdapter` + `BotController`/`BossController`);
> the old move/unit systems they replaced have been retired. Tiles are DONE for gameplay
> resolution (see the Tiles row); the old `TileEffect`/`TileEffectManager` scripts remain only
> as an unretired residual dependency, tracked in §3.1.

---

## 5. Phased roadmap

### Phase 1 — Rules core (unblocks everything)
1. Generalize the effect pipeline so tiles/statuses/abilities can drive it (a shared
   `EffectContext`; effects independent of "a move").
2. `StatusCondition` + `ApplyStatusEffect` + `StatusController` → multi-turn effects (burn,
   poison, regen, timed buffs).
3. Move `cooldown` + `MovesetController` (per-unit cooldown/uses).
> Outcome: moves can burn-over-time and have cooldowns; the machinery for tiles/abilities exists.

### Phase 2 — Tiles, Abilities, Movement (the "easy to add" content systems)
4. `TileEffectResource` + `TileEffectSystem` (fire/water/fortify/stealth as data); reconcile old tile code.
   **Migration status: DONE** for gameplay (live via `CombatServices`); old-script retirement
   still blocked — see §3.1 / §4 notes.
5. `AbilityResource` + `AbilitySystem` + `CharacterResource.abilities` (passive/triggered, rule modifiers).
6. `MovementProfile` + pathfinding integration.
> Outcome: custom tiles, unit abilities, and movement patterns — all data-driven.

### Phase 3 — Game loops
7. Solo: `AITurnController` loop + `EncounterResource` (map-per-boss) + boss empowerment.
8. Multiplayer: `MatchSettings` + lobby wiring to `NetSession` + `MapRegistry` (built-in + user maps).
> Outcome: playable solo encounters vs. bots/bosses, and configurable MP matches.

### Phase 4 — Authoring & UX
9. In-game authoring: tile creator, ability/move authoring, roster/army builder.
10. End-to-end user-generated maps flow; content polish; more units/moves/tiles.

---

## 6. "How to add X" (the litmus test for the architecture)

- **A tile** (e.g. *ice*, slows movement): new `TileResource` + a `TileEffectResource`
  (`PASSIVE` → movement-cost modifier). No code.
- **A move** (e.g. *poison dart*): new `MoveResource` = targeting + `ApplyStatusEffect(poison)`.
  Poison is a `StatusCondition` with a damage tick. No code.
- **An ability** (e.g. *amphibious*: +move on water): new `AbilityResource`
  (`PASSIVE`, condition `on_water`, `StatModifierEffect(+movement)`). No code.
- **A unit**: new `CharacterResource` (stats + 4 moves + abilities + model). No code.
- **A map**: author in the map maker → `MapResource .tres`. No code.
- **A behaviour that doesn't exist yet** (e.g. *pull toward caster*): one small `MoveEffect`
  subclass — then reusable everywhere.

If any of these ever requires more than the above, the pipeline has sprung a leak — fix the
pipeline, not the content.
