# Battle names — a PROPOSAL (not a decision)

The owner asked for names for the different battle types "so communication can be clear"
(2026-10-12). This is a researched proposal; nothing here is decided until the owner picks.
Owner decisions live in `DECISIONS.md`.

## The rule

"Battle" is the umbrella word for both formats. Always name the format; never say "battle" on its
own.

## The two formats — options

| Option | 1v1, Pokémon-style | Grid, Fire Emblem-style | Notes |
|---|---|---|---|
| **A (recommended)** | **Duel** | **Tactics** | The code already says `Kind.DUEL` / `Kind.TACTICAL`, so nothing needs renaming. Plain and unambiguous. |
| B | Duel | Fray | Shorter and more fantasy-flavoured, but "fray" is vague to a new player. |
| C | Duel | Muster | Suggests picking a squad, but it's an uncommon word and doesn't say "battle". |

Avoid these words for a format, because they already mean something else:

| Word | Already used for |
|---|---|
| Clash | the VS intro |
| Skirmish | a menu mode, and the default map type |
| Arena | three things already |
| Field | field moves |
| Siege, Campaign | menu modes |

## Sub-types

Say them as "`<Sub>` Duel" or "`<Sub>` Tactics" (for example "Chief Duel", "Legend Tactics").

**Duel**

| Sub-type | What it is | Example |
|---|---|---|
| Wild | a wild creature | any wild encounter |
| Recruit | a creature that may join | the Lone Petalfang |
| Trainer | an ordinary trainer | trainers on routes |
| Ambush | foes back to back | the Mossway bridge, the hideout guards |
| Rival | a friendly rival | Lyra, Cael |
| Sparring | a sparring partner | the barracks roster |
| Chief | a town chief | Nyra, Eloi, Saevi |
| Cup | a tournament bout | the Crown Cup |
| Encounter | a legend fought as a duel | the volcano legend (#105) |
| Mini-boss | a guard creature | the crypt's wardens (#104) |
| Versus | another player | online or same device |

**Tactics**

| Sub-type | What it is | Example |
|---|---|---|
| Story | story fight, guests on your side | the Oakvale fight, the hideout's last fight |
| Trainer | a trainer on the grid | Bram |
| Legend | a legend | Eldroot, the glacier legend, the sea legend |
| Mythical | the mythical pair | Frostpeak's dream |
| Boss | a dungeon boss | the crypt, the Hidden Depths |
| Skirmish, Campaign, Arena Run, Challenge, Siege, Versus | the menu modes | — |

## Two separate tags

**Stakes**

| Tag | What happens if you lose |
|---|---|
| Real | Whiteout. Permadeath applies in Classic. |
| Must-win | Try Again. |
| Friendly | Nothing — a spar: no permadeath, no whiteout. |

**Objective** (Tactics only)

| Tag | Meaning |
|---|---|
| Rout | defeat every enemy |
| Boss | defeat the boss |
| Escort | protect a unit |
| Gem | defend or destroy the base — the owner's "gem" |
| Throne | seize the throne |
| Hold | survive N turns |

Example: *"Legend Tactics, Must-win, Rout."*

## Glossary (paste-ready)

```
BATTLE  -- any fight; always name the format.
DUEL    -- 1v1, Pokemon-style, no grid. Wild, Recruit, Trainer, Ambush, Rival, Sparring, Chief,
           Cup, Encounter, Mini-boss, Versus.
TACTICS -- Fire Emblem-style grid battle with a squad. Story, Trainer, Legend, Mythical, Boss,
           Skirmish, Campaign, Arena Run, Challenge, Siege, Versus.
STAKES  -- Real (lose = whiteout; Classic permadeath) | Must-win (lose = Try Again) |
           Friendly (spar: no permadeath, no whiteout)
OBJECTIVE (Tactics) -- Rout | Boss | Escort | Gem | Throne | Hold
GUEST   -- an ally who fights in one Tactics battle (Lyra, Varden); never in Duels.
```

## Naming inconsistencies found today

1. **"Battle" is used for both formats.** For example "battle (duel) style" (#96) and "regular
   Pokémon-style battles" (#50).
2. **"Arena" means three things:** Arena Run, the Crown Arena / Crown Cup, and Online Arena.
3. **`BattleSpec.make_chief` also scales non-chiefs** (Lyra, Cael, the hideout). A name like
   `make_scaled` would be clearer.
4. **"Boss" is overloaded.** The `boss_battle` XP flag is separate from the `DefeatBoss` objective.
5. **"Legend battle" also covers the mythical pair.**
6. **Spar terms vary.** Also, the Lone Petalfang's no-loss duel is not marked `spar`.
7. **"Trainer" doesn't imply duel.** Bram is a Tactics trainer.
8. **The owner's "gem" is Base / Control Point in code.**
9. **The defeat-all objective has three names:** "Eliminate All Enemies", "Defeat every enemy unit"
   and "Rout the enemy".
10. **`DUEL_BATTLE.md` line 4** still lists Duel in the Solo menu, which #31 superseded.
