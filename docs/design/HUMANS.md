# Humans as battle units — as built

Owner decisions: DECISIONS.md #5–#8, #16, #54, #61, #63–#66. Those win where this file differs.
This file describes what the code does today, which numbers are knobs, and what is still a
placeholder.

## Data model

- **`CharacterResource.kind`**: `CREATURE` (the default) or `HUMAN` (#5). The Compendium shows a
  "Kind" row and the squad-select card shows a "Human" prefix. Humans in the roster today:
  `wren` (the hero), `varden`, `elias`, `lyra`, `cael`. `tests/unit/test_human_units.gd` checks
  the whole roster's kinds, so a new entry has to be added there on purpose.
  - **Mortis (`necromancer`) stays CREATURE.** His description calls him "a gravecaller", which
    could be a person, but nothing says he is one. Whether he joins the dark organisation is
    still open (#19). Change his `kind` when the owner decides.
- **A human's kit** (`CharacterResource.get_moveset()`): its **weapon attack** in slot 0, then
  whatever special moves its `moveset` lists, up to 4 in all. A creature's kit is its authored
  `moveset`, unchanged. Every system reads moves through `get_moveset()` / `get_move()`: board,
  AI, duel compiler, Compendium, party page, evolution screen and KnowsMove trigger.
- **"Enhanced" humans are design flavour, not a mechanic** (owner, 2026-10-08). There is no
  `enhanced` flag. An enhanced character is simply one whose `moveset` lists special moves. Chiefs
  are authored that way. The hero gains special moves through **promotion**: the promoted form's
  `moveset` lists them.
- **Human fields**: `weapon` (a `WeaponResource`), `weapon_proficiencies` (the weapon types it can
  wield; more than one means it can **swap** weapons, #63), and `weapon_tendency` (its natural
  type, #63; stored as data and not used by any rule yet). `validate()` flags a human with no
  weapon, a weapon outside its proficiencies, or more than 3 special moves, and flags a creature
  that has a weapon.

## Weapons (Fire Emblem style)

- **`WeaponResource`** (`game/characters/weapons/library/<id>.tres`, `WeaponLibrary`). Its knobs:
  `weapon_type`, `might`, `hit`, `crit`, `min_range` / `max_range` (0 = the type's default),
  `uses` (**-1 = unlimited, the default: durability is off**; when set, it is a per-battle charge
  count, i.e. the move's `max_uses`), `element`, `attack_name`, `stat_scale`, and `placeholder`.
- **`attack_move()`** compiles the weapon into an ordinary `MoveResource` (cached and shared, so
  rule 7 applies). It is single-target ENEMY at the weapon's reach, carries the weapon's hit, crit
  and uses, and its one effect is a `WeaponStrikeEffect`, which is a `DamageEffect` subclass.
  Power is might plus the wielder's attack or magic. The strike therefore runs the existing
  pipeline unchanged: MoveExecutor, the forecast, AI planning, the command and replay vocabulary
  (it is just slot 0), and the duel compiler.
- **Weapon types are data** (`WeaponTypeResource` entries on
  `game/characters/weapons/weapon_rules.tres`): sword, lance, axe and bow are physical and scale
  with attack; staff and tome are magical and scale with magic. Each type also has a default
  reach and a verb. `unarmed` has no type: it is the fallback for a human with no weapon and sits
  off the triangle.
- **Weapon triangle: default ON** (`WeaponRules.triangle_enabled`). Sword beats axe, axe beats
  lance, lance beats sword. Advantage is ×(1 + `triangle_damage_bonus` = 0.15) and disadvantage
  ×0.85. It is step 7 of `DamageMath.apply_scales`, so the forecast and the real hit agree. It
  applies only when a weapon strike hits a human who wields a related type. Every creature
  number in every mode is unchanged (×1.0), which is why ON is a safe default. It changes
  damage only, not hit chance.
- **Swapping**: `Unit.equip_weapon(w)` (battle, on a private character copy),
  `StoryState.equip_weapon(member_id, weapon_id)` (story, stored as the member's `weapon_id`
  override), and `CharacterResource.with_weapon(w)`. Weapon **ownership is not tracked yet**:
  a human may equip any library weapon of a type it wields.

### Placeholders

| Who | Weapon | Note |
|---|---|---|
| Wren (hero) | `pitchfork` (lance) | from his sheet; proficiency lance |
| Varden | `iron_sword` | sword + lance proficiency; no special moves |
| Elias | `oak_staff` | staff + tome |
| Lyra, Cael | `study_tome` | the books on their sheets; **model = `elias_forge.glb` placeholder** |

Every weapon's numbers are placeholders (`placeholder = true`). The stats of Wren, Lyra and Cael
are placeholders too. Talyn has no model or roster entry, so the first fight still uses the
`vineweave` stand-in for her.

## Tactical battles

A human unit acts like any other unit. Its weapon attack's reach comes from the weapon (a bow's
min range is 2), the AI plans with it, and `effective_attack_range()` feeds the unit's range
stat. Open modes (Skirmish, Versus, online, replays) are unchanged for creatures. Humans become
pickable there because they now have a duel-eligible kit.

## Duels

A human can lead, or sit on the bench beside creatures (#7). The duel compiler compiles the kit
once, and `DuelCharacter.get_moveset()` returns the compiled list as-is. A story member's weapon
override travels as `DuelCombatant.weapon_id`. That key is written **only when set** (like
`level`) and checked against `WeaponLibrary` and the human's proficiencies. Open-mode requests,
net configs and replay headers are therefore byte-identical, and **`PROTOCOL_VERSION` is
unchanged**.

## Story

- **The hero is a party member.** `HeroResource.battle_character_id` (`wren`) is used to create a
  record flagged `is_hero` at journey start, at the starter level
  (`StoryRuleset.hero_joins_party`, default on). An older save gets the hero on load, at the
  party's top level. The hero:
  - never counts toward `party_cap`;
  - can never leave (`remove_member` returns `hero_cannot_leave`) or FALL (`mark_fallen` refuses
    him);
  - is not the **lead**. `StoryState.lead()` is the first non-hero member, the partner creature.
- **Game over (#66).** The hero falling in any real (non-spar) battle is a game over, and the
  journey goes back to the pre-battle autosave. This reuses the existing flows: the tactical
  hero guard (`ProtectUnit`, meta `story_hero`), `StoryPermadeath.game_over_reason`, and the
  "Load Last Save" action.
- **Fights need a partner.** Wild contact and trainer challenges need a healthy NON-hero member
  (`StoryController.can_battle()`), so the opening still walks past them. Knob:
  `StoryRuleset.hero_alone_can_battle`, default off.
- **Duels are the creatures' by default.** `StoryRuleset.hero_joins_duels` is false. Because the
  hero's fall is a game over, putting him in every duel would turn every lost wild duel into a
  game over instead of a whiteout.
  - A duel whose spec has `hero_deploy = REQUIRED` (a self-defence duel, #7) puts him in the
    lineup.
  - Lineup order comes from `StoryState.duel_lineup(hero_slot, with_hero)`: the partner creature
    leads and the hero stands right behind (`hero_duel_slot` = 1; 0 = he leads; -1 = party
    order).
- **Temporary joins (#61).** `JoinPartyCommand.temporary` / `guest_until`. The guest shows as
  "Guest" and leaves when its flag is set, or through `LeavePartyCommand`. Its record moves to
  `StoryState.guests_away`, so the same guest returns later with its level, XP and growth.
  - Humans are unique (#6): a second join of a human already in the party returns
    `already_in_party`, and a fallen human never rejoins.
  - For the Deep Woods agent, Lyra is
    `JoinPartyCommand{character_id = &"lyra", temporary = true, guest_until = "<flag>"}`.
- **Humans are never wild.** `EncounterZone.validate` rejects a human in an encounter table.
- **Party UI.** Cards show Hero, Human and Guest badges plus the weapon. The detail page shows
  chips and a weapon line.
- **The first fight** (`_first_fight_spec`, `hero_deploy = REQUIRED`). The hero fights beside
  his starter, and General Varden fights as himself (`GENERAL_UNIT = "varden"`, which also
  covers the General's spar duel).
- **Bond XP is creature-only.** Humans earn no bond XP; it measures a creature's bond with the
  hero (#68).

### Deploying (the squad picker)

- **`BattleSpec.hero_deploy`**: OPTIONAL (the default) or REQUIRED.
- **`BattleSpec.offered_guests`**: non-party guests the battle offers. A guest deploys only when
  picked, fights at the party's top level, and carries no member record. Both knobs are written
  into the request only when they differ from the default.
- **Rules: `SquadPick` (pure).** The candidates are the fieldable party, with the hero first,
  then the offered guests. The no-UI default (`default_picks`) is the required units, then party
  order, members only, up to `squad_size`. That is the old "first N healthy members" with the
  hero moved to the front.
- **View: `SquadPickScreen`.** It opens before a story tactical battle when there is a real
  choice: more candidates than chairs, or an offered guest. It never opens when headless, when
  `StoryRuleset.squad_picker_enabled` is off, or for `begin_battle` called directly. The picks
  ride `request.rules["deploy"]`. There is no "back" button: a scripted fight cannot be skipped.

## Promotion and bonds

- **Promotion** uses the existing `EvolutionResource` machinery (#8, #16). Class promotion uses
  `kind_label = "Promote"`; the triggers (HeldItem, UseItem, Location, Growth, Level …) already
  exist, so no new trigger was needed.
  - `EvolutionGraph.validate` now flags three things:
    - a human edge that is not "Promote";
    - a human promotion with no item or location requirement (#16);
    - an edge that crosses kinds.
  - The promoted form is a new HUMAN roster entry. Its `moveset` lists the special moves, and
    that is all "the hero becomes enhanced through promotion" needs. No promoted forms are
    authored yet (no class names have been decided).
- **Bonds (#54, #65).** `StoryPartyMember.bond_partner` holds a human's bonded creature (one
  each way, set with `StoryState.set_bond_partner`).
  - **Activation hook:** `StoryBond` plus `StoryController.activate_bond(human_id)`. It is
    behind `StoryRuleset.bond_activation_enabled`, which is **OFF by default** because it changes
    balance.
  - The **placeholder bonus** is +`bond_bonus_per_level` (0.02) of the bonded creature's
    attack, defense, magic and magic_defense per bond level, for `bond_bonus_turns` (3) turns.
    A second activation refreshes the bonus rather than stacking it (rule 6).
  - **Not wired yet:** a player action or command, a per-battle limit, and the real bonuses
    (the owner will define them later).

## Knobs (defaults)

| Where | Knob | Default |
|---|---|---|
| `weapon_rules.tres` | `triangle_enabled` / `triangle_beats` / `triangle_damage_bonus` | on / sword>axe>lance>sword / 0.15 |
| `WeaponResource` | `might`, `hit`, `crit`, `min_range`/`max_range`, `uses`, `stat_scale` | per weapon; `uses` -1 |
| `HeroResource` | `battle_character_id` | `wren` |
| `StoryRuleset` | `hero_joins_party` | true |
| | `hero_alone_can_battle` | false |
| | `hero_joins_duels` / `hero_duel_slot` | false / 1 |
| | `squad_picker_enabled` | true |
| | `bond_activation_enabled` / `bond_bonus_per_level` / `bond_bonus_turns` | **false** / 0.02 / 3 |
| `BattleSpec` | `hero_deploy` / `offered_guests` | OPTIONAL / [] |
| `JoinPartyCommand` | `temporary` / `guest_until` | false / "" |

## Deferred / open

- A weapon inventory (owning weapons, shops, durability that persists).
- A UI for swapping weapons and setting a bond partner (the APIs exist).
- The bond activation action and its command.
- Promoted class forms.
- Real stats for the human placeholders.
- Real Lyra and Cael models.
- Talyn's roster entry.
- Duel UI kind badges.
