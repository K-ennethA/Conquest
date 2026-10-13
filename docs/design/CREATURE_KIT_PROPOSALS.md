# Creature kit proposals (moves + abilities)

**Status: PROPOSAL ONLY. Nothing here is built yet, and nothing here is a decision until the owner
approves it.** The lore is limited to one concept line per creature, taken from its name, its
reference sheet and the owner's notes.

---

## 1. How to read this

**For the owner.** Each creature gets a short concept line, a **role** (the job it does on a team)
and a table of moves and abilities. Every move has two columns:
- **Duel**: what it does in the Pokémon-style 1v1/party battle.
- **Tactics**: what it does on the Fire Emblem-style grid.

"Same in both" means the move works identically in both modes.

**Kit sizes.** Base forms and small common creatures get **3 moves and no ultimate**. Evolved forms
and the bigger creatures get **4 moves**, and the 4th one is the **ULT** (ultimate). The engine
already treats every 4th move as an ultimate with the full-screen cut-in. Keeping ultimates off
small creatures is how they stay rare, and it means evolving is what unlocks one ("one new trick").

**Number columns** (`Power · Acc · En · CD`):
- **Power**: written `12 + 0.7×Atk`, meaning raw damage = 12 + 70% of the user's Attack.
  - **Phys** (physical) moves are then reduced by the target's Defense.
  - **Mag** (magical) moves are reduced by the target's Magic Defense.
  - **True** damage ignores both defences.
  - **Status** moves deal no damage.
- **Acc**: hit chance before the target's evasion.
- **En**: energy cost. It is **0 everywhere**, because current content paces moves with cooldowns
  and energy is only used by three legacy moves. See open question 4.
- **CD**: cooldown, i.e. how many of the user's own turns pass before the move can be used again.
  0 means it can be used every turn.
- Typical ranges in the existing moves:
  - light hits: 6–10 power, ×0.5–0.7
  - standard hits: 11–18 power, ×0.6–1.0
  - heavy hits and ultimates: 22–30 power, ×0.8–1.0, CD 3–5

**Build column** (for the implementer):
- **Existing**: buildable today from current effect scripts and `.tres` data.
- **data:** needs only a new `.tres` (status, tile effect or weather) made from existing classes.
- **NEW:** needs engine code. Every NEW item is listed in section 3.

**Types** use the new 15-type system (basic, martial, fire, water, plant, bug, electric, ice, wind,
earth, metal, poison, radiant, grim, dragon). The working tree already has the moves retyped
(nature→plant, dark→grim, neutral→basic) and `element2` / dual-type steps in `ElementChart`.

### Roster at a glance

| Creature | Types | Role | Moves |
|---|---|---|---|
| Aquaoct → **Supaoctto** | water → water/martial | grappler-controller → grappler bruiser | 3 → 4 |
| Oculith → **Pyroculus** | fire → fire/radiant | sentinel sniper → artillery | 3 → 4 |
| Magmodo → **Magmoo** | fire → fire | bruiser-zoner → juggernaut / area denial | 3 → 4 |
| Seedant → **Vineweave** | plant → plant | budding fighter → vine warrior (existing) | 3 → 4 |
| **Barkling** → Cinderbark | plant → fire | sturdy grunt (existing) → glass bruiser | 3 → 4 |
| Lintuft → **Murkbun** | grim → grim | pest-debuffer → ambush bruiser | 3 → 4 |
| Pangoknight | basic | frontline soldier (branches later) | 3 |
| Armouse | basic/metal | tank / protector | 4 |
| Blightcap | plant/poison | kamikaze bruiser (existing) | 2 (+1 suggested) |
| Eldroot | plant/earth | legend boss (existing) | 4 |
| Petalfang | plant/poison | trapper-sniper (existing) | 4 |
| Cobloom | plant/poison | venom duelist | 4 |
| Leafinch | plant/wind | scout, hit-and-run | 3 |
| Bombee | bug/metal | bomber (glass cannon / kamikaze) | 4 |
| Incendrone | bug/fire | arsonist, area denial | 4 |
| Mycothrall | bug/poison | parasite (existing) | 2 (+1 suggested) |
| Vampito | bug/grim | harasser, stat thief | 3 |
| Firesprite | fire/grim | glass-cannon caster | 4 |
| Pyrochick | fire/wind | support / survivor | 3 |
| Calderapin | fire/water | siege tank | 4 |
| Snolly | ice/plant | support-controller | 4 |
| Hushveil | ice/grim | silencer / freezer | 4 |
| Treasnare | earth/grim | ambusher / trapper | 4 |
| Prismutt | earth/radiant | guard-dog support | 4 |
| Geode | earth/electric | reprisal tank (existing) | 4 |
| Gloomole | grim/earth | tunneler / backline diver | 4 |
| Stormphora | metal/electric | battery / artillery | 4 |
| Oozegis | poison/earth | attrition tank | 4 |
| Halodin | radiant | warden / healer | 4 |
| Nocturrier | grim | scout / harasser | 3 |
| Fleecefang | grim | assassin / lone duelist | 4 |
| Fogeist | grim/water | evasive controller | 4 |
| Duskmaw | grim | void sniper (existing) | 4 |
| Corvogue | grim/wind | thief / skirmisher | 4 |
| Spectormn | grim | binder (chains) | 4 |
| Vampwarrior | grim | sustain bruiser | 4 |
| Carrionix | grim/wind | finisher / scavenger | 4 |
| Familurr | grim/wind | hexer / enabler | 4 |
| Rotwight | grim | Mortis's minion (enemy only) | 2 |
| Gemwyrm | dragon/radiant | powerhouse (legend-tier) | 4 |

The grim creatures are given deliberately different jobs (scout, assassin, controller, binder,
sustain, finisher, hexer, minion), as are the fire creatures (sniper, zoner, arsonist, caster,
survivor, tank).

---

## 2. Duel vs Tactics: what the engine already does

A duel is a tactical battle on a two-cell board: each side has one "station", 4 cells apart.
`DuelMoveCompiler` adapts every move with the policy table in `DuelRuleset`. This is the general
rule set, so each creature table below only notes where a move behaves interestingly.

| Thing | In a **Duel** | On the **Tactics** grid |
|---|---|---|
| Range, min-range dead zone, line of sight, height | Ignored: every move reaches the foe | All apply. High ground gives +1 range (ranged moves), ×1.15 damage, +10 hit. Low ground gives ×0.85 damage, −10 hit |
| Area shapes (3×3, line, arc, cross…) | Hit the one foe once. A self-centred burst is aimed at the foe, so it still hits | Hit every valid unit in the shape |
| Ally-targeted moves (heals, buffs) | Become **self**-targeted | Target allies (include the caster only if authored to) |
| Knockback / pull, leaps, terrain changes | **Dropped**: the rest of the move still works | Work |
| Dashes through enemies | Become a plain hit with the same numbers | Travel a lane, hit each enemy passed, land beyond |
| Teleport anchors, crawling hazards, **summons** | **Move removed** from the duel moveset (needs a `duel_variant`) | Work |
| Tile effects placed by a move | Kept only if they act on a unit **standing still** (turn-start or passive). A **step-on trap removes the whole move** from the duel moveset unless it has a `duel_variant` | Work. Traps spring on whoever steps in |
| Delayed bursts ("hits next turn"), weather, stat changes, statuses, shields, lifesteal | Same | Same |
| Movement-only debuffs (slow, root) | No effect, except the target still counts as "restricted" for bonuses like Thornlust | Real movement penalties |
| Stun, invulnerability, damage reduction, poison | Same | Same |
| Mind control | Acts as a stun (no ally to turn on) | The unit attacks its own side |
| Abilities on moving / entering tiles | Never fire | Fire |
| On-death area bursts (e.g. Deathbloom) | Hit nothing: the foe is 4 cells away | Hit adjacent units |
| On-kill spawners (Reanimate) | Disabled (a KO ends or switches the duel) | Work |
| Terrain conditions ("while on forest") | Read the **stage** biome | Read the unit's own cell |
| Turn order | **Speed** decides who acts first each round, so speed buffs and debuffs matter a lot | Depends on the mode: Traditional (whole side moves) or Speed First (per unit, by speed) |
| Cooldowns | Tick at the unit's own turn start (same) | Same |
| Tile type bonus | Stage tile only | A move whose type matches the target's tile element deals ×1.25. A unit on its own element's tile takes ×0.9 and gets ×1.25 of that tile's benefits |

**Design consequence used throughout:** every move below that places a step-on trap, needs an ally,
or only moves units carries an explicit **duel_variant** or a note saying what is left of it in a
duel.

---

## 3. New effects, triggers and statuses needed

### 3a. Engine work (code)

Effort is a rough guide: **S** is about one small class or one hook, **M** touches targeting/AI or
several systems, **L** is a new rule the AI, UI and vision all need to know about.

| # | Name (kind) | Effort | What it does | Duel | Tactics | Used by |
|---|---|---|---|---|---|---|
| N1 | **Pull** (`KnockbackEffect.pull` flag) | S | Moves the target toward the caster instead of away; stops at walls and units | Dropped (like knockback) | Drag foes off high ground, out of cover, into your team | Aquaoct, Supaoctto, Treasnare, Spectormn |
| N2 | **Recoil / HP cost** (`RecoilEffect`) | S | Caster loses a share of the damage it dealt, or a % of its max HP (100% = self-KO). Nobody gets kill credit | Same | Same | Bombee, Magmoo, Vampwarrior |
| N3 | **On death → killer** (ON_DEATH passes the last attacker as the triggering unit) | S | Lets a death ability target whoever landed the killing blow (`targets_triggering_unit`). The unit already records its last attacker for kill rewards | Death bursts finally do something in duels: they hit the foe that KO'd you | Optional; area bursts keep working as now | Bombee (also fixes Blightcap's Deathbloom in duels) |
| N4 | **Endure once** (rule modifier `endure_once`) | M | Once per battle, a blow that would KO leaves the unit at 1 HP. Optional follow-up heal | Same | Same | Pyrochick, Familurr |
| N5 | **Taunted** (status) | M | Tactics: a taunted unit's damaging moves must target the taunter if it can reach it (UI and AI both obey). Duel: the taunted unit can only use damaging moves (Pokémon "Taunt") | Status moves locked out for its duration | Forces enemies to hit the tank | Armouse, Oozegis |
| N6 | **Silenced** (honour the existing `"silenced"` flag in move legality) | S–M | Can only use its first move (slot 0, a human's weapon attack). The UI label already exists; nothing enforces it yet | Same | Same | Hushveil, Spectormn (Bound) |
| N7 | **Blinded** (read a caster `accuracy` stat in hit chance) | S | Hit chance today = move accuracy − target evasion. Add the attacker's `accuracy` stat (default 0), so a status can lower it. Blinded = −15 accuracy | Same | Same | Aquaoct, Supaoctto, Lintuft, Murkbun, Prismutt, Fogeist, Corvogue, Familurr |
| N8 | **StackPromoteEffect** (generalised `InfestEffect`) | S | Adds a stack of status A. At N stacks, clears A and applies status B. InfestEffect does this today but is hard-wired to mind control | Same | Same | Hushveil (Chilled→Frozen), Spectormn (Shackled→Bound) |
| N9 | **Element vulnerability on statuses** (`StatusCondition.element_damage_taken`) | S–M | A status can make its unit take more from specific types. **Soaked**: Electric and Ice ×1.25. **Doused**: Fire ×1.25. Folded into DamageMath next to the defender scale, so the forecast agrees | Same. Sets up a benched partner | Same. Rewards combos across a team | Soaked: Aquaoct, Supaoctto, Calderapin, Fogeist (exploited by Stormphora, Snolly, Hushveil). Doused: Incendrone (exploited by all fire) |
| N10 | **DispelEffect** (`cleanse` / `strip` / `steal`) | M | **Cleanse** removes debuffs from allies. **Strip** removes buffs and shields from enemies. **Steal** strips and gives them to the caster | Cleanse becomes self-cleanse | As written | Halodin, Cobloom, Corvogue, Familurr |
| N11 | **Tile filter** (`TileTransformEffect.only_on` tags) | S | Changes terrain only on matching cells (freeze only water, scorch only grass) | Dropped (terrain changes always are) | Freeze rivers into bridges, burn away grass cover | Snolly, Cinderbark |
| N12 | **On nearby death** (trigger `ON_NEARBY_DEATH`, radius) | S | Fires when any unit falls within N cells | Fires when any combatant on the field faints | Fires for deaths within N | Carrionix, Mortis |
| N13 | **Hits the wounded harder** (rule modifier `damage_vs_wounded`) | S | +X% damage to targets under 50% HP. A new step in the existing bonus chain, next to `damage_vs_restricted` | Same | Same | Carrionix, Vampito, Shadow Assassin |
| N14 | **Hits a status harder** (rule modifier `damage_vs_status_<id>`) | S | Like the existing `damage_vs_element_<type>` key, but keyed on a status the target has | Same | Same | Murkbun (Blinded), Cobloom (Poisoned) |
| N15 | **Overwatch** (status + reaction hook) | L | Until the unit's next turn, the first enemy that ends a move within range eats a free shot | Becomes a counter: the first time the foe damages it before its next turn, it fires back once | Zone control; enemies must path around its sight | Oculith, Pyroculus |
| N16 | **Disguised** (status) | L | AI ignores the unit as a target and threat. It breaks when the unit acts, takes damage, or an enemy ends a turn adjacent. The first attack out of disguise deals +50% and cannot miss | Its first damaging move deals +50% and can't miss | Ambush piece (the chest really looks like loot) | Treasnare, Fleecefang |
| N17 | **Cover** (status) | M–L | Attacks aimed at the covered ally hit the coverer instead while they stay adjacent | No allies on the field: uses a `duel_variant` | Bodyguard play | Armouse |
| N18 | **True sight** (rule modifier `true_sight`, radius) | S | Concealed enemies (tall grass, smoke, fog) within N cells are visible to this unit's side | No effect (duels have no fog) | Counters ambushers | Oculith, Pyroculus, Nocturrier, Gloomole |
| N19 | **Status immunity** (rule modifier `immune_to_<status id>`) | S | That status never lands on the unit | Same | Same | Incendrone (Burned), General Varden (Flinched) |
| N20 | **Ally adjacent** (condition `AllyAdjacentCondition`, optional kind filter) | S | Ability gate: "an ally (or a creature ally) is next to me". With `NotCondition`, means "no ally next to me" | Never true (no allies on the field). See open question 2 | As written | Prismutt, Fleecefang, Wren |
| opt | Wire the dormant **"Entering a tile"** trigger per step | M | Abilities fire on every cell walked through. `AbilitySystem` notes it is deliberately unwired | Never fires | Lets Magmodo leave a full lava path instead of a dot where it stops | Magmodo, Magmoo (optional upgrade) |

### 3b. Data-only additions (new `.tres`, no code)

**Statuses:** all are `StatusCondition` or `StatModifierStatus` with existing fields. A second stat
uses a tick `StatModifierEffect`, the same pattern Entangled uses.

| Status | Rule | Used by |
|---|---|---|
| **Burned** | 3 turns, refresh (no stacking). 5 true damage at turn start and −4 Attack while active. Fire's answer to Poison, which stacks but does not cut attack | Oculith, Pyroculus, Magmodo, Magmoo, Cinderbark, Incendrone, Firesprite, Pyrochick |
| **Chilled** | 2 turns, refresh. −4 Speed, −1 movement. In duels the speed loss can flip turn order | Snolly, Hushveil |
| **Frozen** | Stunned 1 turn (a copy of Flinched with its own name and icon) | Hushveil (via N8) |
| **Mesmerized** | 2 turns. −6 Attack, −4 Speed | Cobloom |
| **Hexed** | 3 turns. −6 Defense, −6 Magic Defense | Firesprite |
| **Formation** | 1 turn. Takes ×0.85 damage (aggregates as "strongest wins" with Braced etc.) | Pangoknight |
| **Shelled** | 1 turn. Takes ×0.5 damage | Armouse |
| **Withdrawn** | 2 turns. Takes ×0.5 damage and `immobilized` | Calderapin |
| **Fuse** | Stacking to 3, lasts the whole battle. Counter only | Bombee |
| **Charge** | Stacking to 3, 4 turns. Counter only (like `reprisal_charge`) | Stormphora |
| **Blood Rush** | 2 turns, refresh. +3 Attack | Vampito |
| **Glide** | A `CantoStatus` (like Void Surge) with −1 movement: "you may move once more after acting" | Leafinch, Murkbun, Corvogue, Vampito, Shadow Assassin |
| **Shackled** / **Bound** | Shackled: −2 movement, stacks to 2. Bound: `immobilized` + `silenced` for 1 turn (needs N6 and N8) | Spectormn |
| **Soaked**, **Doused**, **Blinded**, **Taunted**, **Silenced**, **Disguised**, **Overwatch**, **Covered** | Status files are data, but their rules need N5–N17 | see section 3a |

**Tile effects:** each needs an entry in `element_chart.tres` → `tile_elements`.

| Tile effect | Rule | Element | Used by |
|---|---|---|---|
| **Embers** | Enemies only. 8 fire damage at turn start while standing on it. Lasts 2 rounds | fire | Pyroculus, Magmoo, Incendrone |
| **Lava Trail** | Enemies only. When an enemy stops on it: 8 fire damage, 30% Burned. Lasts 2 rounds | fire | Magmodo, Magmoo |
| **Fog Bank** | Conceals occupants under fog of war (as `smoke_veil`). Placer's allies get +15 evasion while inside. Lasts 3 rounds | water | Fogeist, Supaoctto |
| **Dust Cloud** | Enemies standing in it get −15 accuracy (passive, so it also works in duels). Lasts 2 rounds. Needs N7 | grim | Lintuft, Murkbun |
| **Bait Chest** | A trap copied from Vine Trap: springs on pass, halts, used once. 12 damage + Ensnared | earth | Treasnare |
| **Sticky Ooze** | Enemies only. +2 movement cost to cross; Poisoned at each turn start spent inside. Lasts 3 rounds | poison | Oozegis |
| **Sanctum** | Allies only. Heal 10 at turn start (an allies-only Sacred Meadow). Lasts 3 rounds | radiant | Halodin |
| **Crystal Spikes** | Enemies only. 10 damage at turn start while standing on it. Lasts 3 rounds | earth | Gemwyrm |
| **Frost Patch** | A copy of Slippery Ice with a 3-round lifetime (−10 evasion to anyone standing on it) | ice | Snolly |

**Weather:**
- **Blizzard** exists but has no combat rules. Proposal: Ice moves ×1.3, Fire ×0.8, and non-Ice
  units lose 1/16 max HP at turn start (a copy of Desert Storm's chip rule). Used by Snolly; read
  by Snow Cloak and Misty Form.
- `tile_elements`: add `slippery_ice` → `ice` (it is `water` today; ice now exists).

---

## 4. Evolution lines

The evolved form keeps the same move family in stronger versions (matched by position) plus one
new trick, which is its ULT.

### 4.1 Aquaoct → Supaoctto

#### Aquaoct (`aquaoct`), water: **Grappler / controller**
*Concept:* a small, goggle-masked octopus whose tentacles are edged like leaves. Wants Attack and
Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Tentacle Tug | Water · Phys | 9 + 0.6×Atk · 95% · 0 · 1 | Grabs a foe and drags it 2 cells toward Aquaoct | Plain hit (the pull is dropped) | Range 1–3, single. Drag a foe off a ledge, out of cover or into your team | NEW N1 |
| Ink Cloud | Water · Status | — · 100% · 0 · 3 | Squirts ink: enemies in the area are Blinded (−15 accuracy) for 2 turns | Blinds the foe | Range 1–2, diamond (5 cells), enemies only | NEW N7 |
| Splash Soak | Water · Mag | 10 + 0.6×Mag · 100% · 0 · 2 | Water blast that leaves targets Soaked for 2 turns (take +25% from Electric and Ice) | Same; sets up an Electric or Ice partner on the bench | Range 1–3, plus-shape (5 cells) | NEW N9 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Slippery Skin | Turn start | +15 evasion this turn while standing on water or in Rain | Active on a water stage or in Rain | Rewards fighting from the shallows | Existing (AnyCondition: OnTerrainTag water / WeatherCondition rain) |

#### Supaoctto (`supaoctto`), water/martial: **Grappler bruiser**
*Concept:* Aquaoct grown into a masked octopus hero with a visor and a utility belt. Wants Attack
and HP.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Grapple Line *(Tug+)* | Water · Phys | 12 + 0.7×Atk · 95% · 0 · 1 | Drags a foe 3 cells and Entangles it (−2 movement) for 1 turn | Hit + Entangled (counts as "restricted" for Hold Fast) | Range 1–4, single, pull 3 | NEW N1 |
| Smoke Bomb *(Ink+)* | Water · Status | — · 100% · 0 · 3 | Bursts ink around itself: adjacent enemies Blinded 2 turns; leaves a Fog Bank on the 3×3 for 2 rounds | Blinds the foe (the fog has no effect) | 3×3 around self. Supaoctto and allies inside are hidden and get +15 evasion | NEW N7; data: Fog Bank |
| Tidal Suplex *(Soak+)* | Water · Phys | 18 + 0.8×Atk · 90% · 0 · 2 | Grabs and slams: Soaked 2 turns, thrown 2 cells back | Hit + Soaked | Melee, single. Throw into hazards or water | Existing knockback + NEW N9 |
| **ULT** Eight-Arm Barrage | Martial · Phys | 3 hits × (8 + 0.45×Atk) · 90% · 0 · 4 | Three rapid strikes on one foe. One accuracy roll; three separate hits, so it breaks shields and triggers on-hit effects three times | Same | Melee, single | Existing (three DamageEffects) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Slippery Skin | Turn start | Kept from Aquaoct | As Aquaoct | As Aquaoct | Existing |
| Hold Fast | Passive | +30% damage to foes that are slowed or rooted | Works: Entangled still counts as restricted in duels | Same | Existing (`damage_vs_restricted` 0.3) |

### 4.2 Oculith → Pyroculus

#### Oculith (`eye_totem`), fire: **Sentinel / sniper**
*Concept:* a floating black spike-totem with one ringed eye and a faint red glow. Wants Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Ember Gaze | Fire · Mag | 12 + 0.6×Mag · 95% · 0 · 1 | A searing stare through a line; 25% Burned | Single hit, 25% Burned | Line of 3 starting next to Oculith (pierces) | Existing; data: Burned |
| Unblinking Watch | Fire · Status (self) | — · — · 0 · 3 | Keeps watch until its next turn. The first enemy that ends a move within range 2–4 takes a free Ember Gaze (10 + 0.5×Mag) | Counter: if the foe damages Oculith first, it fires back once | Area denial; enemies path around its sight | NEW N15 |
| Evil Eye | Fire · Status | — · 100% · 0 · 2 | Marks a foe (Branded): the next hit it takes deals ×1.3. Ignores line of sight | Same; sets up its own next hit | Range 1–5, single, LOS ignored | Existing (DreadBrandEffect + `branded`) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| All-Seeing | Passive | Concealed enemies within 4 cells are visible to its side | No effect | Hard counter to stealth and ambush units | NEW N18 |

#### Pyroculus (`ember_eye`), fire/radiant: **Artillery / zone controller**
*Concept:* Oculith's eye opened into a blossom of flame petals with a flame-shaped pupil. Wants
Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Pyre Gaze *(Gaze+)* | Fire · Mag | 15 + 0.7×Mag · 95% · 0 · 1 | Longer line; 35% Burned | Single hit, 35% Burned | Line of 4 | Existing; data: Burned |
| Sentinel Flame *(Watch+)* | Fire · Status (self) | — · — · 0 · 3 | Overwatch at range 2–5. The shot is 12 + 0.6×Mag with 50% Burned | Counter, as Oculith | As Oculith, wider | NEW N15 |
| Radiant Brand *(Evil Eye+)* | Radiant · Status | — · 100% · 0 · 2 | Branded (×1.3 next hit) and −5 Magic Defense for 2 turns. Ignores LOS | Same | Range 1–6, single | Existing |
| **ULT** Solar Iris | Radiant · Mag | 28 + 1.0×Mag · 100% · 0 · 4 | Marks a large diamond. Embers cover it at once (the warning); on Pyroculus's next turn the sun erupts there | A telegraphed "next turn" hit on the foe, plus Embers under it (8/turn) | Range 3–6, diamond 2 (13 cells). Enemies get one turn to leave; staying burns | Existing (DelayedBurstEffect + ApplyTileEffect); data: Embers |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| All-Seeing | Passive | Kept from Oculith | No effect | As Oculith | NEW N18 |
| Sunward | Turn start | +6 Magic this turn in Bright Sun | Same | Same (pairs with Cinderbark's Wildfire Call) | Existing (WeatherCondition) |

### 4.3 Magmodo → Magmoo

#### Magmodo (`lava_komodo`), fire: **Bruiser / zoner**
*Concept:* a komodo of cracked stone plates whose legs melt into pooling magma. Wants Attack and HP.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Magma Bite | Fire · Phys | 12 + 0.7×Atk · 95% · 0 · 0 | Bite; 25% Burned | Same | Melee, single | Existing; data: Burned |
| Lava Ram | Fire · Phys | 12 + 0.6×Atk · 100% · 0 · 2 | Charges down a straight lane through up to 2 enemies, hitting each, and stops beyond them | Plain hit | Lane up to 4. Can't pass allies; can't stop without a free cell beyond | Existing (DashThroughEffect, physical) |
| Bask | Fire · Status (self) | — · — · 0 · 3 | Soaks up heat: heals 12% max HP, +4 Attack for 3 turns | Same | Same | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Lava Trail | After moving | The cell where it ends a move becomes Lava Trail for 2 rounds | Never fires | Leaves hot cells behind (a full path needs the optional per-step trigger) | Existing (ON_MOVE + ApplyTileEffect); data: Lava Trail |

#### Magmoo (`magmoo`), fire: **Juggernaut / area denial**
*Concept:* an 8-ft lava serpent bursting out of its own little volcano, dripping molten globs.
Flies. Wants Attack and HP.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Magma Maw *(Bite+)* | Fire · Phys | 16 + 0.8×Atk · 95% · 0 · 0 | Sweeping bite; 35% Burned | Single hit | 3-cell arc | Existing; data: Burned |
| Lava Surge *(Ram+)* | Fire · Phys | 16 + 0.8×Atk · 100% · 0 · 2 | Surges through up to 3 enemies; takes 10% of damage dealt as recoil | Plain hit; recoil applies | Lane up to 5 | Existing dash + NEW N2 |
| Volcanic Bask *(Bask+)* | Fire · Status (self) | — · — · 0 · 3 | Heals 15%, +6 Attack for 3 turns | Same | Same | Existing |
| **ULT** Eruption | Fire · Phys | 28 + 1.0×Atk · 90% · 0 · 5 | Erupts under a 3×3: damage, 50% Burned, Embers for 2 rounds | Big hit, 50% Burned, Embers under the foe | Range 1–3, 3×3, lobbed (ignores LOS) | Existing; data: Embers, Burned |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Lava Trail | After moving | Kept from Magmodo | Never fires | As Magmodo | Existing |
| Scalding Presence | Turn start | Adjacent enemies take 5 true fire damage | No effect (the foe is never adjacent) | Punishes surrounding it | Existing (ON_TURN_START, enemy 3×3 around self) |

### 4.4 Seedant → Vineweave

#### Seedant (`seedant`), plant: **Budding fighter**
*Concept:* a cheerful seedling peeking out of a clay pot, with red leaf ears and curled leaf arms.
Wants Attack.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Leaf Slap | Plant · Phys | 8 + 0.5×Atk · 95% · 0 · 0 | Slaps across one face (grows into Bramble Cleave) | Single hit | 3-cell arc | Existing |
| Pot Shell | Plant · Status (self) | — · — · 0 · 3 | Ducks into its pot: Braced (−40% damage) 1 turn (grows into Thornward) | Same | Same | Existing (`braced`) |
| Seed Shot | Plant · Phys | 9 + 0.6×Atk · 95% · 0 · 1 | Spits a seed; 30% Entangled (grows into Splinter Volley) | Hit; Entangle only marks "restricted" | Range 1–3, single | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Sun Sipper | Turn start | Heals 10% max HP in Bright Sun or Overbloom | Same | Same | Existing (WeatherCondition + HealEffect) |

#### Vineweave (`vineweave`), plant: **Vine warrior (existing kit, keep)**
Keep Bramble Cleave, Thornward, Splinter Volley, Strangling Roots (ULT) and Grass Cutter.
Suggestions:
- **Add Sun Sipper** as its second ability, inherited from Seedant.
- **Grass Cutter** already reads `damage_vs_element_plant`. Confirm it applies when Plant is a
  foe's *second* type too (it reads `get_element()` only).
- Family check, for the evolution screen:
  - Leaf Slap → Bramble Cleave
  - Pot Shell → Thornward
  - Seed Shot → Splinter Volley
  - New trick: Strangling Roots
- Duel notes: Splinter Volley's escalating crit only rolls its base crit (one target).
  Strangling Roots' root is inert in duels except as "restricted".

### 4.5 Barkling → Cinderbark

#### Barkling (`tree_grunt`), plant: **Sturdy grunt (existing kit, keep)**
Keep Tree Bash, Rooted, Verdant Call and Nature's Blessing.
- The Oakheart edge is gone. A `tree_grunt__ember_stump` edge with a `sunstone` use-item trigger
  is already in the working tree; this matches "fire stone".
- No kit changes.

#### Cinderbark (`ember_stump`), fire: **Glass bruiser**
*Concept:* a charred stump with a soot-plume crest and a jagged mask, breathing fire. Owner: "like
Scyther to Scizor". The stats are Barkling's redistributed (more Attack and Speed, less Defense),
and so is the kit: each Barkling move has a fire twin.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Char Bash *(Tree Bash)* | Fire · Phys | 14 + 1.0×Atk · 90% · 0 · 0 | Tree Bash's numbers plus 20% Burned | Same | Melee, single | Existing; data: Burned |
| Smolder *(Rooted)* | Fire · Status (self) | — · — · 0 · 3 | +8 Attack and heals 10%, but −4 Defense, all for 3 turns (burns hotter, not harder) | Same | Same | Existing |
| Wildfire Call *(Verdant Call)* | Fire · Status | — · — · 0 · 6 | Bright Sun for 3 rounds (Fire ×1.3, Water ×0.8) | Same (weather is global) | Map-wide; also powers enemy fire and weakens allied water | Existing (SetWeatherEffect `bright_sun`) |
| **ULT** Fire Breath | Fire · Phys | 22 + 0.9×Atk · 90% · 0 · 3 | Breathes flame down a line; 50% Burned; grass in the line burns to ash | Hit + 50% Burned (the scorch is dropped) | Line of 3 from the adjacent cell. Burning grass removes enemy evasion cover | Existing + NEW N11 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Ember Heart *(Nature's Blessing)* | Turn start | Heals 8% max HP (trades 2% of Barkling's heal for offence) | Same | Same | Existing |
| Charred Bark | When damaged | 30% chance the attacker is Burned (Thornskin's heir, now on fire) | Same | Same (ranged attackers too) | Existing (ON_DAMAGED + chance) |

### 4.6 Lintuft → Murkbun

#### Lintuft (`soot_puff`), grim: **Pest / debuffer**
*Concept:* a floating ball of black dust and lint with two dangling fuzzy arms. Wants Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Dust Puff | Grim · Status | — · 100% · 0 · 2 | Blinds enemies in a small diamond for 2 turns | Blinds the foe | Range 1–2, diamond (5 cells) | NEW N7 |
| Static Cling | Electric · Mag | 8 + 0.5×Mag · 100% · 0 · 1 | Static-charged lint sticks to the foe: Entangled 1 turn | Hit; "restricted" only | Melee, single | Existing |
| Fluff Up | Grim · Status (self) | — · — · 0 · 3 | +20 evasion for 2 turns | Same | Same | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Featherweight | Passive | Floats over rubble, snow and mud: ignores terrain movement cost | No effect | Mobility | Existing rule key `ignore_terrain_cost` (check the movement resolver reads it) |
| Puff Out | On death | Leaves a Dust Cloud on its cell and the 4 around it for 2 rounds | No effect | Punishes whoever finishes it from close up | Existing (ON_DEATH + ApplyTileEffect); data: Dust Cloud |

#### Murkbun (`shadowbun`), grim: **Ambush bruiser**
*Concept:* a hulking, grinning dark dust-bunny with a cloud of a tail; what the lint ball grows
into. Switches to Attack.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Dust Storm *(Puff+)* | Grim · Status | — · 100% · 0 · 3 | Blinds enemies in a 3×3 for 2 turns and leaves Dust Cloud there for 2 rounds | Blinds the foe; the cloud under it keeps −15 accuracy | Range 1–3, 3×3 | NEW N7; data: Dust Cloud |
| Static Maul *(Cling+)* | Electric · Phys | 16 + 0.8×Atk · 95% · 0 · 1 | A heavy, crackling swipe; Entangled 1 turn | Hit; "restricted" | Melee, single | Existing |
| Lurk *(Fluff Up+)* | Grim · Status (self) | — · — · 0 · 3 | +20 evasion for 2 turns and a smoke veil on its own cell | Evasion only | Hidden under fog of war until it attacks | Existing (`smoke_veil` + StatModifier) |
| **ULT** Dust Devil | Grim · Phys | 22 + 0.9×Atk · 90% · 0 · 4 | Spins into a dust tornado: hits every adjacent enemy, Blinds them, then may move again | Hit + Blind | 3×3 around self, then Glide (move again, −1) | Existing + NEW N7; data: Glide |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Lurker in the Dust | Passive | +30% damage to Blinded foes | Same | Same | NEW N14 |
| Puff Out | On death | Kept, now a 3×3 cloud | No effect | As Lintuft | Existing |

---

## 5. Standalone creatures, by primary type

### 5.1 Basic

#### Pangoknight (`pangolin_knight`), basic: **Frontline soldier**
*Concept:* a young pangolin in overlapping scale armour with gauntlet claws; a basic army soldier.
The owner is designing its three specialist branches, so this is a plain soldier kit. Each branch
should keep Claw Strike and Roll Up as the family and add its own trick.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Claw Strike | Basic · Phys | 12 + 0.7×Atk · 95% · 0 · 0 | Gauntlet-claw strike | Same | Melee, single | Existing |
| Roll Up | Basic · Status (self) | — · — · 0 · 2 | Curls into a scale ball: Braced 1 turn and +6 Defense for 2 turns | Same | Same | Existing |
| Rolling Charge | Basic · Phys | 12 + 0.6×Atk · 100% · 0 · 2 | Rolls through one enemy and comes out beyond it | Plain hit | Lane up to 4, pierces 1 | Existing (DashThroughEffect) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Shield Formation | Turn start | Adjacent allies take 15% less damage until their next turn | No effect (no allies) | Rewards holding formation | Existing (ON_TURN_START, ally 3×3); data: Formation |

#### Armouse (`shield_rodent`), basic/metal: **Tank / protector**
*Concept:* a little mouse whose back is a riveted steel round-shield, with a spear-tip tail. Wants
HP and Defense.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Tail Spike | Metal · Phys | 11 + 0.6×Atk · 95% · 0 · 0 | Stabs with its spear tail | Same | Range 1–2, single (reach) | Existing |
| Shell Up | Metal · Status | — · 100% · 0 · 2 | Hides under its shield: Shelled (takes ×0.5) for 1 turn, and Taunts adjacent enemies for 1 turn | Half-damage guard; the Taunted foe can only use damaging moves next turn | 3×3 around self | NEW N5; data: Shelled |
| Bodyguard | Metal · Status (ally) | — · — · 0 · 3 | Covers an adjacent ally until Armouse's next turn: attacks aimed at that ally hit Armouse instead | **duel_variant "Brace":** Braced 1 turn | Adjacent ally | NEW N17 |
| **ULT** Spiked Rampart | Metal · Phys | 20 + 0.8×Atk · 95% · 0 · 4 | Spins its shield: hits all adjacent enemies, Taunts them 1 turn; Armouse is Braced 1 turn | Hit + Taunt + Braced | 3×3 around self | Existing + NEW N5 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Iron Bulwark | Passive | Takes 15% less damage while above half HP | Same | Same | Existing (`damage_taken_scale` 0.85 + Not(HealthBelow 0.5)) |

### 5.2 Plant

#### Blightcap (`blightcap`), plant/poison: **Kamikaze bruiser (existing kit, keep)**
Keep Blight Burst, Spore Leap and Deathbloom. Suggestions:
- **Blight Burst → Poison type.** It is the move that poisons, and it uses the new second type.
- **Deathbloom**: add 50% Poisoned to the burst.
  - Duels: it currently hits nothing at the 4-cell gap. With N3 it can target the killer.
- **Add a 3rd move:**

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Rot Spores | Poison · Status | — · 100% · 0 · 3 | Puff of spores: 60% Poisoned on each enemy hit | 60% Poisoned on the foe | Range 1–2, diamond (5 cells) | Existing |

#### Eldroot (`eldroot`), plant/earth: **Legend boss (existing kit, keep)**
Keep Bough Sweep, Heartwood Guard, Timberfall, Forest Barrage (ULT) and Grovebound. Suggestions:
- **Timberfall → Earth type**, so the second type has a move.
- **Forest Barrage has no duel form** (crawling hazard). It only matters if Eldroot is ever dueled;
  if so, give it a duel_variant: "Root Volley", plant Phys, 20 + 0.6×Atk, Entangled.
- **Optional ability "Hollow Crown"** (turn start): drains 4 HP from every enemy within 2 and heals
  that much. This is the "drank the wood hollow" fantasy, built from existing parts (DamageEffect
  with lifesteal, enemy diamond 2). It is inert in duels because of the gap.

#### Petalfang (`petalfang`), plant/poison: **Trapper-sniper (existing kit, keep)**
Keep Thorn Spit, Vine Trap, Gathering Vines, Ingrained (ULT), Thornlust and Sunlit. Suggestions:
- **Vine Trap** also applies Poisoned when it springs, so the poison type shows.
- **Ingrained** does almost nothing in duels: rooting is inert and there is no range to gain. Give
  it a duel_variant "Deep Roots": +6 Defense and +6 Magic Defense for 3 turns, heals 10%.

#### Cobloom (`petal_cobra`), plant/poison: **Venom duelist**
*Concept:* a pale serpent whose hood is two great green petals. It differs from Petalfang (trapper)
and Blightcap (kamikaze) by stacking poison up close, then cashing it in. Wants Attack and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Bloom Bite | Poison · Phys | 11 + 0.6×Atk · 95% · 0 · 0 | Bite; always adds 1 Poison stack | Same | Melee, single | Existing |
| Hypnotic Hood | Plant · Status | — · 100% · 0 · 3 | Flares its hood: Mesmerized (−6 Attack, −4 Speed) for 2 turns | The speed drop can flip who acts first next round | Range 1–2, single. In Speed First battles it pushes the foe later | data: Mesmerized |
| Coil Lunge | Plant · Phys | 10 + 0.6×Atk · 100% · 0 · 2 | Springs beside a foe and strikes | Plain hit | Leap up to 3 to an empty cell next to the target | Existing (as Spore Leap) |
| **ULT** Venom Bloom | Poison · Phys | 24 + 0.9×Atk · 95% · 0 · 4 | A deep strike that adds 2 Poison stacks | Same | Melee, single | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Venom Hunter | Passive | +30% damage to Poisoned foes | Same | Same | NEW N14 |
| Shed Skin | Turn start, below 40% HP, once per battle | Removes all its debuffs and heals 15% | Same | Same | NEW N10 + existing HealthBelow, `max_activations` 1 |

#### Leafinch (`leaf_bird`), plant/wind: **Scout / hit-and-run**
*Concept:* a little bird-fish made of leaves that glides on vein-ribbed fins. Flies. Wants Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Leaf Dart | Plant · Phys | 9 + 0.6×Atk · 95% · 0 · 0 | A sharp leaf; 10% crit | Same | Range 1–3, single | Existing |
| Swoop | Wind · Phys | 10 + 0.6×Atk · 95% · 0 · 1 | Strikes, then may move again this turn (−1 movement) | Plain hit | Melee, then Glide away | Existing; data: Glide |
| Tailwind | Wind · Status | — · — · 0 · 3 | Allies in the area get +1 movement and +3 Speed for 2 turns | Self only: +3 Speed, which can steal the first move | Range 0–2, diamond (5 cells), includes self | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Canopy Hider | Turn start | +15 evasion this turn on a forest tile | Works on a forest stage | Same | Existing (OnTerrainTag `forest`) |

### 5.3 Bug

#### Bombee (`bombee`), bug/metal: **Bomber (glass cannon / kamikaze)**
*Concept:* a round, smiling bumblebee studded with metal spikes, a walking bomb. Floats. Owner: "on
death it can explode and do more damage". Wants Attack and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Stinger Jab | Bug · Phys | 10 + 0.6×Atk · 95% · 0 · 0 | Jabs with a spike | Same | Melee, single | Existing |
| Light the Fuse | Metal · Status (self) | — · — · 0 · 1 | +1 Fuse (max 3, lasts the whole battle) and +3 Speed for 2 turns. Each Fuse makes Blast Radius and Kamikaze bigger | Same | Same | data: Fuse |
| Pollen Bomb | Bug · Phys | 12 + 0.6×Atk · 90% · 0 · 2 | Lobs a pollen bomb | Same | Range 2–4, 3×3, lobbed (ignores LOS), enemies only | Existing |
| **ULT** Kamikaze | Metal · Phys | 30 + 10 per Fuse + 1.0×Atk · 100% · 0 · once per battle | Flies in and detonates: hits every enemy around the landing cell, then Bombee is knocked out. Spends its Fuse | A huge hit, then Bombee faints (counts as a KO; in a party duel you pick a replacement) | Leap up to 3 to an empty cell, then a 3×3 blast | Existing (Leap + StackConsumeDamageEffect on Fuse) + NEW N2 (100% max-HP cost) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Blast Radius | On death | Explodes: every enemy within 1 cell takes 18 + 8 per Fuse (physical). It also fires after Kamikaze, at base power, because the Fuse is spent: a double blast is the payoff | Hits the foe that knocked it out. **Needs N3**; without it, nothing in duels | 3×3 around its cell, enemies only by default (open question 1: hit allies too?) | Existing (ON_DEATH like Deathbloom + StackConsume) + NEW N3 |

#### Incendrone (`firefly`), bug/fire: **Arsonist / area denial**
*Concept:* a jet-propelled firefly in a firefighter's gas mask, who starts fires instead of putting
them out. Flies. Wants Magic and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Jet Strike | Fire · Mag | 11 + 0.6×Mag · 100% · 0 · 1 | Jets through up to 2 enemies in a line | Plain hit | Lane up to 4, pierce 2, lands beyond | Existing (DashThroughEffect) |
| Fuel Spray | Fire · Status | — · 100% · 0 · 2 | Sprays accelerant: Doused for 3 turns (takes +25% from Fire) | Douses the foe | Range 1–2, plus-shape | NEW N9 |
| Torch | Fire · Mag | 10 + 0.5×Mag · 95% · 0 · 2 | Sets an area alight; 20% Burned; Embers for 2 rounds | Hit + Embers under the foe | Range 1–3, 3×3 | Existing; data: Embers, Burned |
| **ULT** Scorched Earth | Fire · Status | — · — · 0 · 5 | Sets a big area ablaze for 3 rounds with real Fire (burns anyone who starts a turn there, allies too) and Douses everyone inside | The foe is Doused and takes 15 fire damage ×1.25 at each turn start for 3 rounds | Range 2–4, diamond 2 (13 cells). Walls off a region; friendly fire | Existing (ApplyTileEffect `fire` with a lifetime) + NEW N9 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Firefighter's Mask | Passive | Immune to Burned. It still takes reduced damage from fire tiles (Fire resists Fire) | Same | Lets it work inside its own fires | NEW N19 |

#### Mycothrall (`mycothrall`), bug/poison: **Parasite (existing kit, keep)**
Keep Infesting Lunge, Siphon Bite, Parasitic Hold and Rain Bath. Suggestions:
- **Infesting Lunge and Siphon Bite → Bug type** (they are plant today), so its own types show up.
- **Add a 3rd move:**

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Toxic Spores | Poison · Mag | 6 + 0.4×Mag · 100% · 0 · 3 | Spore cloud; 50% Poisoned | Hit + 50% Poisoned | Range 1–2, diamond (5 cells) | Existing |

#### Vampito (`vampito`), bug/grim: **Harasser / stat thief**
*Concept:* a pale mosquito with red eyes and a long striped proboscis. Flies. Wants Speed and
Attack.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Blood Sip | Bug · Phys | 8 + 0.5×Atk · 95% · 0 · 0 | Drinks strength: target −3 Attack for 2 turns; Vampito gets Blood Rush (+3 Attack, 2 turns, refreshes, no stacking) | Same | Melee, single | Existing (StatModifier + ApplyStatus `to_caster`); data: Blood Rush |
| Needle Dive | Bug · Phys | 10 + 0.6×Atk · 100% · 0 · 2 | Dives beside a foe and stabs; heals 30% of damage dealt | Plain hit + drain | Leap up to 3 next to the target | Existing |
| Buzz Off | Bug · Status (self) | — · — · 0 · 3 | +15 evasion for 2 turns, then may move again | Evasion only | Use after attacking to flit away | Existing; data: Glide |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Bloodscent | Passive | +25% damage to foes below half HP | Same | Same | NEW N13 |

### 5.4 Fire

#### Firesprite (`firesprite`), fire/grim: **Glass-cannon caster**
*Concept:* a little demon of living flame in a horned charcoal crown, carrying a fire wand. Wants
Magic and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Hellfire Bolt | Fire · Mag | 14 + 0.8×Mag · 95% · 0 · 0 | Wand bolt; 20% Burned | Same | Range 1–4, single | Existing; data: Burned |
| Brimstone Hex | Grim · Status | — · 100% · 0 · 2 | Hexed: −6 Defense and −6 Magic Defense for 3 turns | Same | Range 1–3, single | data: Hexed |
| Flicker | Fire · Status (self) | — · — · 0 · 3 | Vanishes in a puff of flame and reappears on an empty cell within 3; +10 evasion 1 turn | Evasion only (the teleport is dropped) | Escape or reposition | Existing (Leap, empty-cell aim) |
| **ULT** Soulfire | Grim · Mag | 28 + 1.0×Mag · 95% · 0 · 4 | Burns the soul: heals Firesprite 40% of damage dealt; 50% Burned | Same | Range 1–4, single | Existing (lifesteal) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Kindling Soul | On a defeat | +6 Magic for 2 turns | Same (party duels) | Same | Existing |

#### Pyrochick (`phoenix_hatchling`), fire/wind: **Support / survivor**
*Concept:* a round little phoenix chick with a smoking collar and an ember jewel on its chest.
Wants Magic and HP.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Ember Peck | Fire · Phys | 9 + 0.6×Atk · 95% · 0 · 0 | Peck; 20% Burned | Same | Melee, single | Existing; data: Burned |
| Warming Glow | Fire · Status | — · — · 0 · 3 | Allies in the area (and itself) heal 8 + 8% max HP | Heals itself | Range 0–2, diamond (5 cells) | Existing (HealEffect, `affects_caster_tile`) |
| Cinder Gust | Wind · Mag | 10 + 0.6×Mag · 95% · 0 · 1 | A flap of hot wind; knocks back 1 | Plain hit | Range 1–2, single | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Rekindle | Passive, once per battle | A blow that would KO it leaves it at 1 HP; at its next turn start it heals 25% | Same | Same | NEW N4 |

#### Calderapin (`volcano_turtle`), fire/water: **Siege tank**
*Concept:* a stocky stone turtle with a lava-cracked shell and a burning crater for a head. Wants
HP, Defense and Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Crater Punch | Fire · Phys | 14 + 0.8×Atk · 90% · 0 · 0 | Rock-fist punch | Same | Melee, single | Existing |
| Steam Vent | Water · Mag | 10 + 0.6×Mag · 100% · 0 · 2 | Scalding steam around itself; enemies hit are Soaked 2 turns | Hit + Soaked | 3×3 around self | Existing + NEW N9 |
| Withdraw | Water · Status (self) | — · — · 0 · 4 | Pulls into its shell: takes ×0.5 damage for 2 turns but cannot move | A pure 2-turn half-damage guard (no movement to lose) | A real trade-off: it holds ground | data: Withdrawn |
| **ULT** Steam Geyser | Water · Mag | 26 + 1.0×Mag · 95% · 0 · 5 | A geyser erupts under one foe: big damage, Soaked, and Rain for 3 rounds. Rain boosts Water ×1.3 but cuts Fire ×0.7, Calderapin's own fire included | Same | Range 1–4, single. Rain also douses burning tiles map-wide | Existing (SetWeatherEffect `rain`) + NEW N9 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Hot Spring Body | Turn start | Heals 8% in Rain, or while standing on water or lava | Rain or a water/volcano stage | Same | Existing (AnyCondition) |

### 5.5 Ice

#### Snolly (`holly_snowman`), ice/plant: **Support-controller**
*Concept:* a fluffy, round snowman with holly-leaf ears and berry-laden leafy arms. Wants Magic
Defense and a mix of Attack and Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Snowball | Ice · Phys | 10 + 0.6×Atk · 95% · 0 · 0 | Snowball; 40% Chilled | Same; the speed drop matters for turn order | Range 1–3, single | Existing; data: Chilled |
| Holly Berry | Plant · Status (ally) | — · — · 0 · 2 | Tosses a berry: heals 12 + 10% max HP | Heals itself | Ally within 3 | Existing |
| Frost Patch | Ice · Status | — · — · 0 · 3 | Ices an area for 3 rounds (−10 evasion to anyone on it, allies too). Water cells in the area freeze into walkable ice for the rest of the battle | The foe stands on ice: −10 evasion while it lasts (the freeze is dropped) | Range 1–3, 3×3. Freeze a river into a bridge | Existing (ApplyTileEffect) + NEW N11 (only water → `ice_sheet`); data: Frost Patch |
| **ULT** Winter Wreath | Ice · Status | — · — · 0 · 6 | Calls a Blizzard for 3 rounds; allies within 2 (and itself) get a 15 HP shield | Blizzard + self shield | Map-wide weather + team shield | Existing (SetWeather + ShieldEffect); data: Blizzard rules |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Snow Cloak | Turn start | +15 evasion this turn during a Blizzard | Same | Same | Existing (WeatherCondition) |

#### Hushveil (`mystic_snow_spirit`), ice/grim: **Silencer / freezer**
*Concept:* a hushed snow spirit with twig antlers, ringed by snowballs burning with blue-violet
flame. Wants Magic and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Wisp Snowball | Ice · Mag | 12 + 0.7×Mag · 95% · 0 · 0 | Flaming snowball; 30% Chilled | Same | Range 1–4, single | Existing; data: Chilled |
| Hush | Grim · Status | — · 100% · 0 · 3 | Silenced for 1 turn: the foe can only use its first move | Same | Range 1–3, single | NEW N6 |
| Deep Freeze | Ice · Mag | 14 + 0.7×Mag · 95% · 0 · 2 | Chills the target; a target that is already Chilled is Frozen instead (stunned 1 turn) | Same | Range 1–3, single | NEW N8; data: Chilled, Frozen |
| **ULT** Whiteout | Ice · Mag | 18 + 0.7×Mag · 95% · 0 · 5 | A squall: damage and Chilled to all; already-Chilled enemies Freeze | Hit + Chill or Freeze on the foe | Range 2–4, 5×5 | Existing + NEW N8 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Frost Orbit | When damaged | 30% chance the attacker is Chilled | Same | Same | Existing |

### 5.6 Earth

#### Treasnare (`chest_monster`), earth/grim: **Ambusher / trapper**
*Concept:* a mimic: a living treasure chest with crystals sprouting from the lid, one eye-lock and
tiny clawed feet. Wants Attack and Defense.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Lid Chomp | Grim · Phys | 16 + 0.8×Atk · 90% · 0 · 0 | Slams its lid; 15% crit | Same | Melee, single | Existing |
| Glittering Bait | Earth · Status | — · — · 0 · 3 | Plants a fake treasure. The first enemy to step on or across it takes 12 earth damage and is Ensnared 1 turn | **duel_variant "Coin Toss":** earth Phys 10 + 0.4×Atk, 30% Flinched (a dazzling distraction) | Empty cell within 3 | data: Bait Chest |
| Gem Shards | Earth · Phys | 10 + 0.5×Atk · 95% · 0 · 2 | Spits crystal shards: damage and −4 Defense for 2 turns | Same | Range 1–3, plus-shape | Existing |
| **ULT** Gaping Maw | Grim · Phys | 24 + 1.0×Atk · 95% · 0 · 4 | Opens wide, drags a foe right up to it, and chomps | Big hit (the pull is dropped) | Range 1–3, single, pull to adjacent | Existing + NEW N1 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Mimic | Battle start | Starts Disguised as a chest. The first attack out of disguise deals +50% and cannot miss | First damaging move +50%, can't miss | AI ignores it until it acts, is hit, or an enemy ends a turn next to it | NEW N16 |
| Snap Shut | When damaged | 30% chance the attacker is Ensnared 1 turn | Same ("restricted" only) | Holds melee attackers in place | Existing |

#### Prismutt (`crystal_canine`), earth/radiant: **Guard-dog support**
*Concept:* a white fox-like dog with a mane of rose-quartz crystal plates and a gem on its brow.
Wants Defense and Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Crystal Fang | Earth · Phys | 12 + 0.7×Atk · 95% · 0 · 0 | Crystal-edged bite | Same | Melee, single | Existing |
| Prism Howl | Radiant · Status | — · — · 0 · 3 | Allies within 2 (and itself) gain a 12 HP crystal shield | Self shield | Range 0, diamond 2 around self | Existing (ShieldEffect) |
| Dazzle | Radiant · Status | — · 100% · 0 · 2 | Flashes its mane: Blinded 2 turns | Same | Range 1–3, single | NEW N7 |
| **ULT** Gem Beacon | Radiant · Mag | 24 + 0.9×Mag · 95% · 0 · 4 | Its brow gem fires a beam (Radiant beats Martial, Grim and Dragon) | Single hit | Line of 4 (pierces) | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Pack Bond | Turn start | +6 Attack and +6 Magic this turn while an ally is adjacent | Never active (see open question 2) | Rewards sticking with the team | NEW N20 |

#### Geode (`gem_knight`), earth/electric: **Reprisal tank (existing kit, keep)**
Keep all four moves and four abilities. One suggestion: **Refraction Lance → Electric type**. It
reads as a charged crystal beam and gives Geode's new second type a move. Duels are already covered
(Scree Trap has its Scree Shower variant).

#### Gloomole (`shadow_mole`), grim/earth: **Tunneler / backline diver**
*Concept:* a near-black mole surfacing from a pool of shadow, with bright pink digging claws and
flower-tipped stalks. Wants Attack and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Dig Claw | Earth · Phys | 13 + 0.7×Atk · 95% · 0 · 0 | Pink-claw rake; 10% crit | Same | Melee, single | Existing |
| Burrow | Earth · Status (self) | — · — · 0 · 3 | Dives underground and surfaces on an empty cell within 4 (under walls and units); Braced 1 turn on arrival | Braced only | Reposition behind lines | Existing (Leap + `braced`) |
| Cave-In | Earth · Phys | 12 + 0.6×Atk · 90% · 0 · 3 | Collapses the ground: damage, 20% Flinched, cells become rubble | Hit + 20% Flinched | Range 1–3, 3×3. Rubble slows crossing | Existing (TileTransform `rubble`, like Crushing Quake) |
| **ULT** Tunnel Strike | Grim · Phys | 20 + 0.9×Atk · 100% · 0 · 4 | Shoots through the earth along a line, bursting up under every enemy in it, and surfaces beyond | Single big hit | Lane up to 6, pierce 3 | Existing (DashThroughEffect, physical) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Tremor Sense | Passive | Feels footsteps: concealed enemies within 3 are visible to its side | No effect | Anti-ambush | NEW N18 |

### 5.7 Metal

#### Stormphora (`storm_vessel`), metal/electric: **Battery / artillery**
*Concept:* a round storm-jar with a glowing core, a floating lidded head and hands, and a
lightning-bolt tail. Wants Magic and Defense.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Arc Lash | Electric · Mag | 12 + 0.7×Mag · 95% · 0 · 0 | Lightning lash; 10% Flinched | Same | Range 1–3, single | Existing |
| Capacitor | Metal · Status (self) | — · — · 0 · 1 | +1 Charge (max 3) and +4 Defense for 2 turns | Same | Same | data: Charge |
| Chain Lightning | Electric · Mag | 12 + 0.6×Mag · 95% · 0 · 2 | Strikes a foe and arcs to every enemy next to it. Soaked foes take +25% | Single hit | Range 1–3, 3×3 | Existing (+ N9 synergy) |
| **ULT** Overload | Electric · Mag | 16 + 10 per Charge + 0.8×Mag · 100% · 0 · 4 | Dumps every Charge into a blast; 30% Flinched | Same | Range 1–4, 3×3 | Existing (StackConsumeDamageEffect) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Lightning Rod | When damaged | +1 Charge (max 3) | Same | Same | Existing (like Geode's Reprisal) |

### 5.8 Poison

#### Oozegis (`goo_shield`), poison/earth: **Attrition tank**
*Concept:* a green slime wearing a rough black rock as a helmet and another as a shell. Wants HP and
Defense.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Acid Smear | Poison · Phys | 11 + 0.6×Atk · 95% · 0 · 0 | Corrosive slap: −4 Defense for 2 turns | Same | Melee, single | Existing |
| Rock Shell | Earth · Status (self) | — · — · 0 · 2 | Braced 1 turn and +8 Defense for 2 turns | Same | Same | Existing |
| Slime Pool | Poison · Status | — · — · 0 · 3 | Oozes a slick for 3 rounds: enemies pay +2 movement to cross and are Poisoned at each turn start inside | The foe is Poisoned every turn (the turn-start tile is kept) | Range 0–2, 3×3 | data: Sticky Ooze |
| **ULT** Engulf | Poison · Phys | 20 + 0.8×Atk · 95% · 0 · 4 | Swallows an adjacent foe: 2 Poison stacks, Ensnared 1 turn, Taunted 1 turn | Hit + 2 Poison + Taunt (no status moves next turn) | Melee, single | Existing + NEW N5 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Corrosive Body | When damaged | The attacker loses 3 Defense for 2 turns | Same | Same | Existing |

### 5.9 Radiant

#### Halodin (`halo_sentinel`), radiant: **Warden / healer**
*Concept:* a one-eyed crimson sentinel with wing-like arms, a crystalline jelly skirt and a spinning
orange halo. Wants Magic Defense and Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Halo Toss | Radiant · Mag | 12 + 0.7×Mag · 95% · 0 · 0 | Throws its halo | Same | Range 1–3, single | Existing |
| Purify | Radiant · Status | — · — · 0 · 2 | Allies in the area each lose 1 debuff and heal 8% max HP | Cleanses and heals itself | Range 0–2, diamond (5 cells), includes self | NEW N10 + existing HealEffect |
| Sanctuary | Radiant · Status | — · — · 0 · 4 | Blesses an area for 3 rounds: allies standing there heal 10 at each turn start | **duel_variant "Sanctum Glow":** heals 12% and Braced 1 turn | Range 0–2, 3×3 | data: Sanctum |
| **ULT** Judgment | Radiant · Mag | 28 + 1.0×Mag · 100% · 0 · 4 | Marks an area; next turn a pillar of light strikes it | A telegraphed "next turn" hit | Range 2–5, diamond (5 cells) | Existing (DelayedBurstEffect) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Halo Light | Turn start | Adjacent allies heal 5% max HP | No effect | Steady sustain for the front line | Existing (ally 3×3) |

### 5.10 Grim

#### Nocturrier (`canine_bat`), grim: **Scout / harasser**
*Concept:* a cuddly canine-bat with huge veined ears, a bat's nose and little fangs. Flies. Wants
Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Nip | Grim · Phys | 10 + 0.6×Atk · 95% · 0 · 0 | Nip; heals 25% of damage dealt | Same | Melee, single | Existing (lifesteal) |
| Screech | Grim · Status | — · 100% · 0 · 3 | 30% Flinched on every adjacent enemy | 30% Flinched on the foe | 3×3 around self | Existing |
| Sonic Ping | Grim · Mag | 6 + 0.4×Mag · 100% · 0 · 2 | Pinpoints a foe: −10 evasion for 2 turns. Ignores line of sight | Same | Range 1–5, single, LOS ignored | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Echolocation | Passive | Concealed enemies within 4 are visible to its side | No effect | Scout role | NEW N18 |

#### Fleecefang (`eclipse_wolf`), grim: **Assassin / lone duelist**
*Concept:* the owner's MYTHICAL of nightmares (2026-10-12): a wolf in sheep's clothing that chases the
dream sheep (who brings good sleep; not made yet). A grinning black wolf in a woolly fleece with glowing
crescent horns and leg rings. Wants Attack and Speed. (Kit below predates the mythical call -- revisit
once the owner designs the sheep.)

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Crescent Rend | Grim · Phys | 13 + 0.7×Atk · 95% · 0 · 0 | Raking swipe | Single hit | 3-cell arc | Existing |
| Wolf's Howl | Grim · Status (self) | — · — · 0 · 4 | Empowered: +8 Attack for 3 turns | Same | Same | Existing (`empowered`) |
| Pull the Wool | Basic · Status (self) | — · — · 0 · 4 | Pulls the fleece back over: Disguised again | Re-arms the +50% first strike | Re-enter stealth mid-battle | NEW N16 |
| **ULT** Total Eclipse | Grim · Phys | 24 + 1.0×Atk · 95% · 30% crit · 0 · 5 | Darkness swallows the cells around it for 2 rounds; it rends every adjacent enemy | Hit with 30% crit chance | 3×3 around self. The 9 cells conceal units under fog | Existing (+ `smoke_veil` tiles) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Sheep's Clothing | Battle start | Starts Disguised (see Treasnare's Mimic) | First damaging move +50% | Ambush piece | NEW N16 |
| Lone Wolf | Turn start | +6 Attack this turn when no ally is adjacent | **Always on** (no allies in duels), so Fleecefang is a natural duelist | Rewards flanking alone | NEW N20 (with NotCondition) |

#### Fogeist (`fogeist`), grim/water: **Evasive controller**
*Concept:* a low, reclining ghost made of layered fog, with two simple eyes and a trailing tail of
mist. Wants Magic and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Chill Mist | Water · Mag | 11 + 0.6×Mag · 95% · 0 · 0 | Cold mist; 50% Soaked | Same | Range 1–3, single | Existing + NEW N9 |
| Fog Bank | Water · Status | — · — · 0 · 3 | Rolls fog over an area for 3 rounds: units inside are hidden under fog of war; Fogeist's allies inside get +15 evasion | **duel_variant "Haze":** +20 evasion to itself for 2 turns | Range 0–3, 3×3 | data: Fog Bank |
| Haunting Drift | Grim · Mag | 10 + 0.6×Mag · 100% · 0 · 2 | Drifts through up to 3 enemies in a line | Plain hit | Lane up to 4, pierce 3 | Existing (DashThroughEffect, magical) |
| **ULT** Drowning Fog | Grim · Mag | 22 + 0.9×Mag · 95% · 0 · 4 | Heavy fog: damage, Blinded and Soaked for 2 turns | Same | Range 1–4, 3×3 | Existing + NEW N7, N9 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Misty Form | Turn start | +15 evasion this turn in Rain or a Blizzard | Same | Same | Existing (WeatherCondition) |

#### Duskmaw (`monster`), grim: **Void sniper (existing kit, keep)**
Keep Abyssal Maw, Umbral Claw, Voidwalk, Voidstep and Dread Brand. One suggestion: **Voidstep is
removed from duels** (teleport anchors), so Duskmaw duels with only 3 moves. Give it a
duel_variant: "Void Rend", grim Mag 16 + 0.8×Mag, applies Branded.

#### Corvogue (`raven_rogue`), grim/wind: **Thief / skirmisher**
*Concept:* a scarred, heavy-lidded raven with a cape of ragged purple feathers. Flies. Wants Attack
and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Beak Jab | Grim · Phys | 12 + 0.7×Atk · 95% · 0 · 0 | Beak jab; 15% crit | Same | Melee, single | Existing |
| Snatch | Grim · Phys | 8 + 0.4×Atk · 100% · 0 · 2 | Steals one buff or shield from the target | Same | Melee, single | NEW N10 (steal) |
| Gale Shove | Wind · Phys | 10 + 0.5×Atk · 100% · 0 · 0 | The existing move: knocks a foe back 2 | Light plain hit | Melee, knockback 2 | Existing (`gale_shove`; retype basic → wind) |
| **ULT** Murder of Crows | Grim · Phys | 14 + 0.6×Atk · 95% · 0 · 4 | A flock tears down a line; crit chance climbs +25% per extra enemy hit; 30% Blinded | Single hit, base crit | Line of 4 (pierces) | Existing (Splinter Volley pattern) + NEW N7 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Hit and Fly | On attack (cooldown 2) | After hitting, may move again (−1 movement) | No effect | Hit-and-run | Existing (ON_ATTACK + CantoStatus); data: Glide |

#### Spectormn (`spectormn`), grim: **Binder (chains)**
*Concept:* a white sheet-like wraith with red slit eyes, glowing red chain shackles on both wrists,
fading into violet mist. Wants Magic.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Chain Lash | Grim · Mag | 12 + 0.7×Mag · 95% · 0 · 0 | Chain whip; pulls 1 | Plain hit | Range 1–3, single | Existing + NEW N1 |
| Shackle | Grim · Status | — · 100% · 0 · 1 | Adds a Shackle (−2 movement, 2 turns). At 2 Shackles the foe is Bound: can't move and is Silenced for 1 turn | Bound = Silenced 1 turn | Range 1–3, single | NEW N8 + N6; data: Shackled, Bound |
| Phantom Wail | Grim · Mag | 12 + 0.6×Mag · 95% · 0 · 2 | Wails: damage and −4 Attack for 2 turns to every adjacent enemy | Same | 3×3 around self | Existing |
| **ULT** Chains of the Damned | Grim · Mag | 22 + 0.9×Mag · 95% · 0 · 5 | Chains burst from the ground: damage and a Shackle on each (a second Shackle Binds) | Same | Range 1–4, plus-shape | Existing + NEW N8 |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Restless Chains | On attack | 25% chance to add a Shackle to whoever it hits | Same | Same | Existing (ON_ATTACK) + NEW N8 |

#### Vampwarrior (`vampwarrior`), grim: **Sustain bruiser**
*Concept:* a pale, white-haired vampire knight in black armour and a crimson-lined cape. Wants
Attack and HP.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Crimson Slash | Grim · Phys | 13 + 0.7×Atk · 95% · 0 · 0 | Sweeping slash; heals 25% of damage dealt | Single hit | 3-cell arc | Existing (lifesteal) |
| Blood Pact | Grim · Status (self) | — · — · 0 · 4 | Pays 15% max HP: Empowered (+8 Attack, 3 turns) and +15 crit for 3 turns | Same | Same | Existing + NEW N2 |
| Dark Mantle | Grim · Status (self) | — · — · 0 · 3 | Wraps in its cape: Braced 1 turn, heals 10% | Same | Same | Existing |
| **ULT** Sanguine Feast | Grim · Phys | 26 + 1.0×Atk · 90% · 0 · 4 | Heavy strike that heals 75% of damage dealt | Same | Melee, single | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Vampiric | On a defeat | Heals 20% max HP | Same (party duels) | Same | Existing |
| Sun-Scorned | Passive | Takes 15% more damage in Bright Sun (a real weakness against its sustain) | Same | Same | Existing (`damage_taken_scale` 1.15 + WeatherCondition) |

#### Carrionix (`vulture_creature`), grim/wind: **Finisher / scavenger**
*Concept:* a hunched black vulture wearing a bird's skull as a helmet and a skull pendant, wreathed
in green spirit-smoke. Flies. Wants Attack.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Bone Beak | Grim · Phys | 13 + 0.7×Atk · 95% · 0 · 0 | Beak strike | Same | Melee, single | Existing |
| Carrion Dive | Wind · Phys | 14 + 0.7×Atk · 95% · 0 · 2 | Swoops onto a foe from up to 5 cells | Plain hit | Leap next to the target | Existing |
| Grave Miasma | Grim · Status | — · 100% · 0 · 3 | Spirit-smoke: enemies −6 Defense for 2 turns | Same | Range 1–3, 3×3 | Existing |
| **ULT** Last Rites | Grim · Phys | 24 + 0.9×Atk · 95% · 0 · 4 | A finishing strike (with Pick the Bones: +50% under half HP) | Same | Melee, single | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Pick the Bones | Passive | +50% damage to foes below half HP | Same | Same | NEW N13 |
| Scavenger | When any unit within 3 falls | Heals 15% and +4 Attack for 2 turns | Fires when any combatant on the field faints | Snowballs in big fights | NEW N12 |

#### Familurr (`winged_cat`), grim/wind: **Hexer / enabler**
*Concept:* a grinning green cat with leaf-shaped wings, a red fur collar and a witch's-broom tail; a
witch's familiar. Flies. Wants Magic and Speed.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Broom Swipe | Wind · Phys | 10 + 0.6×Atk · 95% · 0 · 0 | Sweeps with its broom tail; knocks back 1 | Single hit | 3-cell arc | Existing |
| Jinx | Grim · Status | — · 100% · 0 · 2 | Blinded and −4 Speed for 2 turns (bad luck) | Same; the speed loss can flip turn order | Range 1–4, single | NEW N7 |
| Familiar's Boon | Grim · Status (ally) | — · — · 0 · 3 | An ally gets +6 Attack and +6 Magic for 3 turns | Buffs itself | Ally within 3 | Existing |
| **ULT** Witching Hour | Grim · Mag | 14 + 0.6×Mag · 100% · 0 · 5 | Every enemy near Familurr takes damage and loses all its buffs and shields | Hit + strip | Diamond 3 around self | NEW N10 (strip) |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Nine Lives | Passive, once per battle | Survives a KO blow at 1 HP | Same | Same | NEW N4 |
| Bad Omen | When damaged | 25% chance the attacker is Blinded 1 turn | Same | Same | Existing (ON_DAMAGED) + NEW N7 |

#### Rotwight (`undead`), grim: **Minion (enemy only, raised by Mortis)**
*Concept:* a husk dragged back from death. It only exists when Mortis raises it.
- It never appears in duels: summons are excluded and Reanimate is disabled there.
- Keep it simple, so a horde reads clearly.

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Undead Strike | Grim · Phys | 14 + 1.0×Atk · 95% · 0 · 0 | The existing claw | n/a | Melee, single | Existing |
| Grave Clutch | Grim · Phys | 6 + 0.4×Atk · 100% · 0 · 2 | Grabs at a foe: Entangled 1 turn, so the horde can pin targets for Mortis | n/a | Melee, single | Existing |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Crumble | On death | Collapses into bone dust: adjacent enemies Entangled 1 turn | n/a | A small parting gift | Existing (ON_DEATH, enemy 3×3) |

### 5.11 Dragon

#### Gemwyrm (`gemwing_dragon`), dragon/radiant: **Powerhouse (legend-tier)**
*Concept:* a dragon grown entirely of prismatic gemstone, with blade-crystal wings and a crystal
crown. Flies. Wants Attack and Magic (mixed).

| Move | Type · Kind | Power · Acc · En · CD | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| Gem Claw | Dragon · Phys | 16 + 0.8×Atk · 95% · 0 · 0 | Crystal-claw sweep | Single hit | 3-cell arc | Existing |
| Prism Breath | Radiant · Mag | 18 + 0.8×Mag · 95% · 0 · 2 | A prismatic beam; crit chance +25% per extra enemy pierced | Single hit, base crit | Line of 4 | Existing (Splinter Volley pattern) |
| Crystal Wings | Dragon · Status (self) | — · — · 0 · 3 | Folds its wings: 20 HP shield and +8 Magic Defense for 2 turns | Same | Same | Existing |
| **ULT** Prismatic Cataclysm | Dragon · Mag | 28 + 1.0×Mag · 90% · 0 · once per battle | Crystal storm over a wide area; leaves Crystal Spikes for 3 rounds (enemies standing in them take 10 at turn start) | Big hit + spikes under the foe | Range 2–5, 5×5 | Existing; data: Crystal Spikes |

| Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|
| Shard Scales | When damaged | The attacker takes 6 true damage | Same | Same | Existing (Thornskin pattern) |

---

## 6. Humans (abilities only)

Humans fight with their **weapon attack** (slot 0, `WeaponResource`). These are signature
**abilities**, not creature moves. In duels only one unit per side is on the field, so any ability
that needs an adjacent ally is inactive there.

| Human | Ability | Trigger | What it does | Duel | Tactics | Build |
|---|---|---|---|---|---|---|
| **Wren** (pitchfork / lance) | Farmhand's Grit | Turn start, below 35% HP | +6 Attack and +4 Defense this turn | Same | Same | Existing (HealthBelow) |
| | Side by Side | Turn start | +3 Attack and +3 Defense this turn while a creature ally is adjacent | Inactive | Rewards fighting beside his creatures | NEW N20 (kind filter) |
| **Elias** (staff / tome) | Mending Staff | Turn end | Adjacent allies heal 8% max HP | Inactive | Field medic | Existing (ON_TURN_END, ally 3×3) |
| | Calm Mind | Turn start, untouched last turn | +4 Magic and +4 Magic Defense this turn | Same | Same | Existing (UndamagedForTurns 1) |
| **Cael** (tome) | Ward Glyph | Turn start | Adjacent allies gain a 6 HP shield (refreshes, never stacks) | Inactive | Support caster | Existing (ShieldEffect, ally 3×3) |
| | Second Wind | Turn start, below 30% HP, once per battle | Heals 20% max HP | Same | Same | Existing (`max_activations` 1) |
| **Lyra** (tome) | Rival's Spark | On a defeat | +6 Magic for 2 turns | Same | Same | Existing |
| | Showstopper | Turn start, at full HP | +15 crit this turn | Same | Same | Existing (Not(HealthBelow 1.0)) |
| **General Varden** (sword / lance) | Commander's Presence | Turn start | Allies within 2 get +3 Defense this turn | Inactive | Holds a line together | Existing (ally diamond 2) |
| | Iron Discipline | Passive | Cannot be Flinched | Same | Same | NEW N19 |
| **Mortis** (now human, grim) | Reanimate | On a defeat | Raises a Rotwight on the fallen foe (kept as-is) | Disabled (already) | His signature | Existing |
| | Grave Communion | When any unit within 3 falls | +4 Magic for 2 turns and heals 8% | Fires on any faint on the field | The longer the fight, the stronger he gets | NEW N12 |
| **Shadow Assassin** | Assassinate | Passive | +30% damage to foes below half HP | Same | Same | NEW N13 |
| | Vanish | On a defeat | May move again (Glide) and veils its cell in smoke for 1 round | Inactive | Kill, then disappear | Existing (CantoStatus + `smoke_veil`); data: Glide |

**Mortis's existing spell moves.** Settled when the roster edits were applied (2026-10-12): a human
lists at most 3 specials after the weapon attack, so Wither Bolt left (his staff strike covers a
basic bolt). He keeps Grave Grasp, Soul Drain and Undying Legion, plus Reanimate.

---

## 7. Open questions for the owner

1. **Friendly fire.** Should Bombee's death blast hit **allies** next to it too (a riskier, funnier
   bomb)? Incendrone's Scorched Earth already burns everyone on purpose.
2. **Duels and teammates.** Abilities that need an adjacent ally (Pack Bond, Side by Side, auras)
   never work in duels. Should a duel count "a healthy partner on the bench" as an adjacent ally?
3. ~~Mortis as a human.~~ Settled: Grave Grasp, Soul Drain, Undying Legion (Wither Bolt dropped).
   Undying Legion only works in tactics.
4. **Energy.** Every kit uses energy 0 and paces moves with cooldowns, which matches current
   content. Is energy staying unused, or should ultimates cost energy?
5. **Ultimate count.** Base forms and small commons get 3 moves and no ultimate; evolving unlocks
   one. Is that the rarity the owner wants?
