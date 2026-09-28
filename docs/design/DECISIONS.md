# Story / Evolution / Duel — decisions (2026-09-27)

Owner decisions on the three design docs (EVOLUTION.md, OVERWORLD.md, DUEL_BATTLE.md). Where a
doc's default differs from this file, THIS FILE WINS. Anything not listed: use the doc's default.

## Owner decisions
1. **Collecting:** BOTH story joins AND befriending wild units are in scope (not deferred to M3).
   Befriending = after WINNING a wild duel, the defeated wild unit may offer to join. No capture
   items, no mid-battle capture.
2. **Evolution in open modes:** evolving UNLOCKS the evolved form in open modes (Skirmish, Versus,
   Arena — both forms pickable); in STORY the party member actually becomes the evolved form.
3. **Duel party size:** flexible — build the doc default (lead + up to 2 bench, KO-replacement,
   switch costs the turn; wild encounters 1 foe) but keep party size a ruleset knob
   (CONQUEST.md rule 11: tuning on the mode's ruleset resource). First slice is strict 1v1.
4. **Overworld avatar:** a dedicated HUMAN HERO (the "Warden" idea) — separate from the party, not
   the lead unit. Until a Blender model exists, the hero uses an existing roster character model as
   a placeholder (configurable in ONE place, e.g. a HeroResource with model/scene + yaw), so
   swapping in the real model later is a data change.

## RNG / befriend fairness (lead's default, owner may revise)
- Every battle (tactical or duel) starts from FRESH entropy (NetSession.begin_solo_match_rng); the
  per-command seed is stamped into replays so playback reproduces. Retrying re-rolls. Resuming a
  battle save also re-rolls (no anti-save-scum lock).
- A crit KO never forfeits a befriend: the join offer is rolled on VICTORY whether the wild unit
  was KO'd or not.
- "Subdue" mechanic: a False-Swipe-style move effect that cannot reduce the target below 1 HP;
  a wild unit that is subdued (ended at 1 HP / KO'd by a subdue move) gets a higher join chance.
  Join chance + subdue bonus are data on the duel/story ruleset.
- Story-critical recruits are never missable: on loss/flee the encounter persists (re-triggers on
  return / after a wayshrine rest).
- The join-offer roll uses the battle's seeded stream (deterministic in replays), never randf().

## Shared contracts (all three features)
- Persistent party/roster member records: EVOLUTION's RosterLedger member (stable member_id) is
  THE record the story party stores (OVERWORLD §10) — one record type, not two.
- Battle launch/return: OVERWORLD's BattleRequest / BattleResult; StoryController.report_battle_result
  exactly once per battle. BattleResult gains `befriend_offer: {character_id, accepted}`.
- Duel combatants are real Units on a DuelBoard; damage only through DamageMath (rule 9).
- Evolution: Unit.apply_form / EvolveEffect / GrowthTracker as in EVOLUTION.md.

## Process
- Branches off `reconcile/cloud-merge` (the reconciled merge; PR into main pending):
  `feat/evolution`, `feat/duel`, `feat/overworld`, each in its own worktree.
- Milestone 1 of each feature first (the vertical slices). Keep GUT at 0 failures on your branch.
- Follow CONQUEST.md coding conventions and docs/UI_STYLE.md (grove look) strictly.
