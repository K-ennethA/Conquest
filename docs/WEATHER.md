# Weather & environment

Battles have **weather**: a data-driven environment layer with real gameplay rules and a
visible world effect. Weathers are `WeatherResource` files in `game/weather/resources/`
(the file name is the id); every rule is composed from the existing effect pipeline
(`AbilityResource` + `AbilityCondition` + `MoveEffect`), so a new weather, a
weather-reactive ability or a map schedule needs **no code**.

Screenshots: `docs/screenshots/weather/`.

## 1. The weathers

| Weather | id | Damage | Hit | Turn start (each unit, its own turn) | Other |
|---|---|---|---|---|---|
| Clear | `clear` | — | — | — | — |
| Bright Sun | `bright_sun` | Fire ×1.3, Water ×0.8 | — | — | enables **Sunlit** |
| Rain | `rain` | Water ×1.3, Fire ×0.7 | — | — | **douses fire**: `fire` / `scorching_vent` tile effects are inert and runtime-lit fires are removed; enables **Rain Bath** |
| Desert Storm | `desert_storm` | — | ranged moves (targeting `max_range` ≥ 2) −15 | non-Earth units lose 1/16 max HP (min 1); Earth or `sand_proof`-tagged units are immune | Earth units +3 defense; enables **Sand Veil** |
| Overbloom | `overbloom` | Nature ×1.15 | non-Nature targets: pollen −5 evasion (i.e. +5 to hit them) | Nature units heal 1/10 max HP | summoned by **Verdant Call** |

All damage/hit modifiers apply identically in the resolved hit (`DamageEffect.apply`,
`MoveContext.hit_chance`) and in the forecast (`MoveExecutor.preview_vs`) through the
static hooks in `game/weather/Weather.gd`, so the combat forecast and every AI that scores
off it see the weather automatically. Order in the damage pipeline: … type matchup
(ElementChart) → **weather** → height → crit. The weather defense bonus is added in
`DamageEffect._mitigate_for` (shared by the forecast and hazards).

### Weather abilities on roster units

| Unit | Ability / move | Effect |
|---|---|---|
| Mycothrall | **Rain Bath** (`game/abilities/rain_bath.tres`) | ON_TURN_START, `WeatherCondition[rain]`: heal 1/8 max HP |
| Petalfang | **Sunlit** (`sunlit.tres`) | ON_TURN_START, `WeatherCondition[bright_sun]`: +4 speed, +1 movement (1 turn) |
| Geode | **Sand Veil** (`sand_veil.tres`) | ON_TURN_START, `WeatherCondition[desert_storm]`: +15 evasion (1 turn) |
| Barkling | **Verdant Call** (`game/combat/moves/verdant_call.tres`) | self move, cooldown 6: `SetWeatherEffect(overbloom, 3 rounds)` |

Nature units (Vineweave, Blightcap, Petalfang, Barkling, Mycothrall, Eldroot) all benefit
from Overbloom by element; Geode (earth) is sand-proof by element.

### Map weather

| Map | Mode | Weather |
|---|---|---|
| Forgotten Forest | dynamic, every 3 rounds | starts Overbloom; pool Overbloom 3 / Clear 2 / Rain 2 |
| River Crossing | dynamic, every 3 rounds | starts Rain; pool Rain 3 / Clear 2 / Bright Sun 1 |
| Skirmish Arena | dynamic, every 2 rounds | starts Bright Sun; pool Bright Sun 2 / Desert Storm 2 / Clear 1 |
| Elemental Crossroads | schedule (loops) | Clear 2 → Bright Sun 2 → Rain 2 → Desert Storm 2 → Overbloom 2 |
| Castle Siege | schedule (loops) | Clear 3 → Rain 3 |
| Proving Grounds | fixed | Bright Sun |
| others | fixed | Clear |

The build scripts (`game/maps/build_*.gd`) set the same settings so a rebuild keeps them.

## 2. Architecture

```
MapResource.weather_* ──► CombatServices.configure_weather(map, seed)   (GameWorldManager, map load)
                                   │
                           WeatherState (CombatServices.weather)
   TurnSystemBase._tick_unit_turn_start ──► advance_weather(round)  ──► changed ─► weather_changed
                                   │                                         ├─► WeatherFX (visuals)
   Weather.run_turn_start(unit) ◄──┘ (after status ticks,                    ├─► WeatherChip + banner
                                      before the unit's abilities)           └─► douse runtime fire
   Weather.damage_scale_for / hit_modifier_for / stat_bonus_for / suppresses_tile_effect
        ◄── DamageEffect, MoveContext, MoveExecutor.preview_vs, TileEffectSystem
```

* `game/weather/WeatherResource.gd` — the data (combat block + visual block).
* `game/weather/WeatherState.gd` — live state: current weather, round, summoned override;
  the **pure** schedule maths (`base_id_for_round`), `rounds_until_change`, `digest`.
* `game/weather/Weather.gd` — catalog (`get_weather`, `all_ids`) + combat hooks.
* `game/weather/WeatherCondition.gd`, `game/abilities/UnitElementCondition.gd` — conditions.
* `game/combat/effects/PercentHealthLossEffect.gd` — "lose X% max HP" (no roll/crit,
  ignores defense, respects invulnerable + shields, does not announce `damage_dealt`).
* `game/combat/effects/SetWeatherEffect.gd` — summon a weather for N rounds.
* Rounds are **derived**: `WinConditionLibrary.completed_rounds(turn_system) + 1`, evaluated
  in the shared per-unit turn-start tick (both turn systems), so the weather rolls over at
  the first unit tick of each new round.

## 3. Authoring

**A new weather** — *New Resource → WeatherResource*, save as
`game/weather/resources/<id>.tres` (id must equal the file name):
* `element_damage_scale` `{ &"wind": 1.2 }`.
* `ranged_hit_modifier` / `ranged_min_range`.
* `stat_rules`: PASSIVE `AbilityResource`s with `rule_modifiers` `{ "stat_defense": 2 }`,
  `"stat_evasion"`, `"stat_magic_defense"` (combat-time bonuses, like terrain avoid), gated
  by their `condition` (e.g. `UnitElementCondition`, wrap in `NotCondition` for "everyone
  except").
* `turn_start_rules`: ON_TURN_START `AbilityResource`s with any effects (`HealEffect`
  percent, `PercentHealthLossEffect`, `StatModifierEffect`, `ApplyStatusEffect` …).
* `suppressed_tile_effects`: tile effect ids that are inert (and removed if runtime-applied).
* Visuals: `fx_kind` picks a particle rig (`clear`/`sun`/`rain`/`sand`/`bloom`; a new look =
  a builder in `WeatherRigs.gd` + a term in `weather_overlay.gdshader`), plus light/fog/
  colour-grade values and the `shader_*` uniforms. It appears in the Map Maker dropdown
  automatically.

**A weather-reactive ability** — any `AbilityResource` with `condition =
WeatherCondition{ weathers = [&"rain"] }` (combine with `AllCondition` for "on water *and*
raining"). ON_TURN_START stat buffs should use `StatModifierEffect(duration = 1)`: modifiers
expire before abilities fire each turn start, so it holds exactly while the weather does.

**A weather-summoning move** — add `SetWeatherEffect { weather, rounds }` to a move's effects.

**A map schedule** — Map Maker ▸ *Weather* dropdown (fixed weathers + the presets
"Dynamic (all)" (every weather, equal weights, changes every 3 rounds; a loaded schedule/dynamic map shows as "Custom" and is kept)), or in the Inspector / a build script:
```gdscript
map.set_weather_settings({"mode": "schedule",
    "schedule": [{"weather": "clear", "rounds": 2}, {"weather": "rain", "rounds": 2}]})
map.set_weather_settings({"mode": "dynamic", "weather": "rain",
    "pool": {"rain": 3, "clear": 2}, "change_every": 3})
```
Schedules loop. Dynamic: round 1..N uses `weather`, then each `change_every`-round period
rolls a weighted pick from `pool`. JSON export/import carries a `"weather"` block (absent =
fixed Clear).

## 4. Network determinism

* The weather is never sent; every peer derives it. `base_id_for_round(settings, seed, r)`
  is pure: dynamic picks seed a private `RandomNumberGenerator` with
  `hash([seed, period, 7919])` — it **never draws from the combat RNG stream**
  (`CombatServices.match_rng`), so adding weather cannot shift any roll.
* The seed is the match's public setup seed (`NetSession.get_match_config().seed`,
  identical on every peer, see `systems/net/README.md`); single-player uses `randi()`.
  The setup seed is known before play: dynamic weather is *forecastable*, which is fine
  (the HUD shows "changes in N rounds" anyway) and it cannot be biased mid-match.
* Weather advances inside the turn-start tick that every peer runs identically; chip
  damage / healing are deterministic (no rolls). `SetWeatherEffect` is deterministic.
* `NetGameRules.state_digest()` folds in `WeatherState.digest()` (id, round, override), so
  a diverging weather is caught as a desync like any other state.
* Checked with `dev_scripts/net_multiprocess_check.sh`: `skirmish_arena.tres` (dynamic,
  every 2 rounds) traditional 40 — dedicated PASS (all three `seq=29`, weather Bright Sun →
  Clear at round 3) and `HOSTED=1` PASS (`seq=28`, Bright Sun → Desert Storm with chip
  damage); `elemental_crossroads.tres` (schedule) speed_first 40 PASS (`seq=37`, Clear →
  Bright Sun → Rain). Headless processes log `[Weather] round N -> id` on every change.
  `tests/integration/test_net_match.gd::test_dynamic_weather_stays_in_lockstep_across_peers`
  covers the in-process path.

## 5. Visuals

`game/visuals/weather/WeatherFX.gd` (spawned by `GameWorldManager`, skipped on a headless
server) listens to `CombatServices.weather_changed` and cross-fades over 1.5 s:

* **Particles** (`WeatherRigs.gd`): `CPUParticles3D` + unshaded materials + generated
  gradient textures (Compatibility and Forward+ alike), world-space, re-centred every frame
  on the camera's ground focus and re-sized to the view, so coverage is right at any zoom.
  Rain: ~3000 streaks, splash droplets, ripple rings pinned to water tiles. Sun: golden
  motes + ground glints. Desert Storm: horizontal grit, large rolling dust sheets, ground
  drift. Overbloom: pollen, tumbling petals, twinkling flower specks.
* **Screen overlay** (`weather_overlay.gdshader`, canvas layer 0 under the HUD): sun glare +
  god rays, rain vignette + gust sheets, billowing sand haze, pastel bloom edges.
* **Light / environment** (`WeatherEnvAdapter.gd`): captures the map's base look and applies
  relative changes — key light colour/energy, ambient, depth fog, glow, colour adjustments,
  sky tint — and writes the global shader uniforms `weather_wetness`, `weather_dust`,
  `weather_bloom`, `weather_sun`, `wind_strength_global` (declared in `project.godot`
  `[shader_globals]`) for the world-art shaders. When a world-look node exists in group
  `world_look` with `apply_weather_look(params)`, the adapter hands it the params instead
  of editing the environment itself.
* **Settings ▸ Weather Effects**: Full / Reduced (~40 % particles) / Off (no particles or
  overlay; the light mood stays). Visual only — gameplay is unaffected.

HUD: `WeatherChip` under the objective chip (icon, name, "changes in N rounds" /
"N rounds left", rules tooltip) and an `ActionAnnouncer` banner on every change. The combat
forecast shows a weather chip (`▲ Bright Sun ×1.3`, `▼ Desert Storm -15 hit`).

## 6. Tests

`tests/unit/test_weather.gd` (damage per element per weather, forecast == hit, ranged
penalty, sand chip + immunity, Overbloom heal + pollen, rain douse, weather-conditioned
abilities, SetWeatherEffect duration, schedule / dynamic determinism, digest, MapResource
JSON round trip, Map Maker model, forecast chip, HUD countdown) and
`tests/integration/test_weather_battle.gd` (real roster units ticked by a real turn system).
