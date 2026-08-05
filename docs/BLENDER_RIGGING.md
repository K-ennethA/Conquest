# Blender rigging + animation cheat sheet (Conquest pipeline)

Everything here is tuned to THIS project: Blender 5.x, chunky low-poly creatures,
the `tools/blender/prepare_unit.py` import pipeline, and the clip names the game's
`UnitAnimator` actually plays. Written 2026-08; shortcuts are the Blender defaults.

---

## 0. The one rule that makes everything else work

The game plays authored clips by name — **`idle`, `walk`, `attack`, `hit`, `death`** —
with forgiving matching (case-insensitive, and exporter prefixes like `Armature|Walk`
are fine). Name your Actions exactly those five words and the game wires itself.
Any clip you don't author falls back to the built-in procedural motion, so you can
ship a unit with only `idle` and `attack` and it still works.

---

## 1. Prep the sculpt (before any bones)

A sculpt fresh from sculpt mode is usually millions of polys and several loose
shells. Bones don't care, but **automatic weighting does**.

| Step | How | Why |
|---|---|---|
| Merge shells | Select all parts → `Ctrl+J` (Join) | One object to rig |
| Make it one volume | Modifier: **Remesh** (Voxel, size ~0.02–0.05) → Apply | Bone-heat weighting fails or spikes on disjoint/overlapping shells |
| Knock the polycount down | Modifier: **Decimate** (ratio till ~5–15k faces) → Apply | The pipeline decimates again anyway (`--target-faces`), but weighting a 2M-poly mesh is slow |
| Feet at world origin | `Tab` edit mode, select all, `G Z` to sit soles on Z=0; origin: Object → Set Origin → Origin to 3D Cursor (cursor at world 0) | The pipeline scales/fits assuming the model stands on its origin |
| Face the -Y axis | Look at the model in Front view (`Numpad 1`) — you should see its face | Consistent facing = consistent in-game rotation |
| Neutral pose | Limbs slightly away from the body (A-pose-ish), mouth/tentacles relaxed | Bones deform FROM this pose; limbs glued to the torso steal each other's weights |
| Apply transforms | `Ctrl+A` → All Transforms | Rot/scale of 1 before rigging saves you an hour of mystery later |

**Style note for our roster**: after Remesh+Decimate, hit Shade Flat (right-click →
Shade Flat). Faceted is the look; smooth-shaded blobs read as unfinished clay.

---

## 2. Add a skeleton (small is correct)

Our creatures need 4–8 bones. More bones = more weighting problems, and the game
camera is too far away to see finger curls.

1. `Shift+A` → **Armature**. In the armature's Object Data (green bone icon) tick
   **Viewport Display → In Front** so you can see bones through the mesh.
2. `Tab` into Edit Mode on the armature. You have one bone:
   - `G` move it into the pelvis/center of mass. Rename it `root` (F2).
3. Grow the chain with **`E` (extrude)** from a bone's tip:
   - `E` up → `spine` (or `cap` for a mushroom) → `E` up again → `head`.
4. Limbs: select the tip of `spine`, `E` out to the side → `arm.L`, and legs from
   `root` → `leg.L`. **Name left-side bones with `.L`** then use
   Armature menu → **Symmetrize** to mirror them as `.R` for free.
5. A tail/vine: `E` a 2–3 bone chain from `root` backwards (`tail.1`, `tail.2`).

Suggested skeletons per archetype:

| Archetype | Bones |
|---|---|
| Blob / mushroom (Blightcap) | `root`, `cap`, 2 side sway bones |
| Biped (Gem Knight) | `root`, `spine`, `head`, `arm.L/R`, `leg.L/R` |
| Quadruped / beast (Petalfang) | `root`, `spine`, `head`, 4 legs, `tail.1-2` |
| Tree / totem (Tree Grunt) | `root`, `trunk`, `head`, `arm.L/R` |

Don't chase anatomical joints — a bone through the *visual mass* you want to move
is right, wherever the "elbow" technically is.

---

## 3. Bind mesh to skeleton (the 10-second step)

1. Object Mode. Click the **mesh**, then `Shift`-click the **armature** (order matters —
   armature LAST so it's active).
2. `Ctrl+P` → **With Automatic Weights**.

That's it. Test immediately: select armature → `Ctrl+Tab` (Pose Mode) → grab a bone
(`R` to rotate). The mesh should follow smoothly.

**When it deforms badly** (the usual three):
- Whole mesh moves with one bone → mesh was several shells; go back to Remesh (§1).
- A limb drags belly polys with it → in Weight Paint mode (select mesh, then the
  armature bone), paint weight 0 on the stolen region (or in Edit Mode select those
  verts → Vertex Groups panel → remove from the wrong group).
- Error "Bone Heat Weighting: failed" → non-manifold mesh; Remesh fixes it 95% of
  the time.

`Alt+R` / `Alt+G` in Pose Mode resets a bone; use it constantly while testing.

---

## 4. Animate the five clips

Open the **Animation** workspace tab. Use the **Action Editor** (Dope Sheet mode
dropdown) — one Action per clip.

The loop for each clip:
1. In the Action Editor header press **New**, name it exactly `idle` (etc.).
   Click the **shield icon** (Fake User) so it can't vanish, and **Push Down /
   Stash** it into the NLA when done — *stashed actions are what the exporter ships*.
2. Pose Mode. Frame 1: pose the bones, select them, **`I` → Location & Rotation**
   to key.
3. Move the playhead, pose, `I` again. `Space` plays.
4. End frame: for loops (`idle`, `walk`) copy frame 1's pose to the last frame so it
   cycles — select bones at frame 1, `Ctrl+C`, go to end frame, `Ctrl+V`.

What each clip needs (durations at 24 fps — short reads better in a tactics game):

| Clip | Length | Recipe |
|---|---|---|
| `idle` | 40–60f loop | Root bobs down-up ~2% of height; head/cap sways 2–3°. Subtle. If it looks like breathing you're done |
| `walk` | 16–24f loop | Root bob ×2 per cycle, opposite arm/leg swing 15–25°, slight lean forward. Chunky units WADDLE (roll the root ±4°) — it's charming |
| `attack` | 12–20f, no loop | 3 frames anticipation (pull back), 2 frames strike (fast!), rest recover. The strike being FAST is 90% of feeling good |
| `hit` | 8–12f, no loop | Sharp recoil back + 5° twist, ease back to neutral |
| `death` | 20–30f, no loop | Topple sideways or crumple down; end held on the final pose |

Pro habit: turn on **Auto Keying** (the record dot next to the playhead) while
blocking a clip, and OFF the second you stop — stray keys from forgotten auto-key
are the #1 mess.

---

## 5. Export — actually, don't. The pipeline does it

Save the `.blend` (with actions stashed, §4.1) and run:

```bash
blender --background your_unit.blend --factory-startup --python tools/blender/prepare_unit.py -- --output game/characters/models/your_unit.glb --name YourUnit
```

It decimates, cell-fits the scale, applies transforms, converts Z-up → Y-up, and
exports the `.glb` with all stashed actions. Then wire the `.tres` per the
`blender-unit-import` skill / `tools/blender/README.md`.

If you ever export manually: File → Export → glTF 2.0, check **+Y Up** and under
Animation make sure your actions are included (stashed NLA tracks are, by default).

---

## 6. Sculpt guidelines for this game's look

- **Silhouette first**: at gameplay zoom a unit is ~100px tall. If the black
  silhouette doesn't say "mushroom" or "knight", no amount of detail will.
- **Exaggerate**: heads/weapons/claws ~20% bigger than feels right up close.
- **Facet, don't smooth**: hard normals, low poly, slight bevels. Detail through
  a few bold shapes, not surface noise.
- **Color via materials, not textures**: 2–5 flat material slots (bark, leaf,
  crystal). Matches the tile art and skins can retint slots.
- **One connected mass** wherever possible; floating accents (rocks orbiting,
  detached pauldrons) are fine but parent them to a bone explicitly (select
  accent, shift-select bone in Pose Mode, `Ctrl+P` → Bone) instead of relying
  on auto-weights.
- Model at any size — the pipeline rescales — but keep proportions; height is
  fitted to `--target-height`.

---

## 7. Fast diagnosis table

| Symptom | Cause | Fix |
|---|---|---|
| Mesh doesn't follow bones | Parented in wrong order | Redo §3, armature selected LAST |
| Clip plays in Blender, not in game | Action not stashed / wrong name | §4.1 — stash + name from the five |
| Unit tiny/huge in game | Origin not at feet | §1 origin row, re-run pipeline |
| Unit faces wrong way | Sculpt not facing -Y | §1 facing row |
| Limb tears polys off the body | Weight bleed | Weight-paint the bleed to 0 |
| Animation drifts sideways over the loop | Keys on `root` location X/Y | Delete X/Y location keys on root; loops should move in place |
