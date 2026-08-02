# Mobile / App Store Port Plan

Status: planning document. No mobile export has shipped yet. This is the honest
state of readiness plus the concrete path to Android and iOS.

## 1. What already works

| Area | Status | Notes |
|---|---|---|
| Aspect handling | Done | `window/stretch/mode="canvas_items"` + `aspect="expand"` verified fine at 20:9 phone aspect ratios. |
| Input model | Done | Tap == click for the command loop (selection, move, ability targeting all route through the same input path as mouse clicks). |
| Hit targets | Done | 44px minimum hit-target pass completed across HUD/menu controls. |
| Info panels | Done | Sticky info panels already work without hover (no hover-only UI blocking mobile). |
| Save data | Done | `user://` JSON saves are portable as-is; no path/permission changes needed for Android or iOS. |
| Renderer split | Done | `project.godot` now has a `[rendering]` section: desktop keeps Forward+, mobile exports use the Mobile renderer automatically via the `.mobile` feature-tag override. See section 6. |
| Gesture intent layer | Done (this change) | Tap / one-finger pan / pinch zoom / long-press inspect, classified by a pure state machine and routed to the existing camera + cursor APIs. See section 7. |
| DPI / content scale | Done (this change) | `MobileDisplay` autoload picks a clamped `content_scale_factor` from DPI + resolution on mobile only. **Still needs on-device tuning** — the model is derived, not measured. See section 7. |
| Safe-area insets | Done (this change) | Battle HUD and every menu scene root are inset from notches / gesture bars on mobile only. See section 7. |

None of the above needs rework to start a mobile export. The blockers below are
what's between "it boots on a phone" and "it's actually good on a phone."

## 2. Blockers remaining

| Blocker | Why it matters | Recommendation |
|---|---|---|
| Content-scale tuning on hardware | The factor is derived from a viewing-distance model, not measured. It is clamped to 1.00–1.75 so it cannot go badly wrong, but the right number for this HUD is an empirical question. | Tune `MobileDisplay.VIEW_DISTANCE_RATIO` / `SCALE_MIN` / `SCALE_MAX` on a real phone. Consider exposing a UI-scale slider once a baseline is known. |
| Mouse emulation double-fire on pan start | With `emulate_mouse_from_touch` left on (see section 7), the synthetic mouse-down at touch-down selects the tile a camera pan starts from. Harmless (the next tap replaces it) but wrong. | Fix on-device by having `board/cursor/cursor.gd` ignore events with `device == InputEvent.DEVICE_ID_EMULATION` once the adapter owns taps. Do not do this blind — it touches the shared click path. |
| Map creator touch story | The map/tile/unit creator addons are precision editing tools built for mouse+keyboard. | Recommend desktop-only v1. Do not attempt touch support for the creator tools in the first mobile release; revisit only if player demand shows up post-launch. |
| Always-on SubViewports on mobile GPUs | Galleries (unit/tile gallery) and the creator tools appear to keep SubViewports live continuously, which is fine on desktop GPUs but can be a real battery/thermal/perf cost on phone SoCs. | Needs a test pass: measure GPU/battery cost of each always-on SubViewport on a mid-range Android device, and gate/pause the ones not actively visible. Test list: unit gallery, tile gallery, augment creator preview, any battle-effects preview viewports. |
| First on-device profiling checklist | Nothing has been profiled on real mobile hardware yet. | Before any beta: frame time on a mid-range Android device, cold-start time, memory footprint, thermal throttling under a full battle, battery drain per session. |

## 3. Android path

| Step | Detail |
|---|---|
| Export templates | Install Godot 4.6 Android export templates (Editor > Manage Export Templates), plus Android SDK/build-tools via Godot's Android export settings (or use the built-in Gradle build). |
| Keystore signing | Generate a release keystore (`keytool`), configure it in the Android export preset. Debug builds use Godot's auto-generated debug keystore; release builds need your own, kept safe — losing it means you can never update the app under the same listing. |
| Play Console | One-time $25 registration fee. Internal testing track is free and fast to set up — use it for the first beta before any public track. |
| Target API level | Google Play requires targeting a recent Android API level (moves forward roughly yearly); check current requirement at submission time, not now — it changes. Godot's Android export exposes `target_sdk`/`min_sdk`. |
| ETC2/ASTC import flag | Now set in `project.godot` (`textures/vram_compression/import_etc2_astc=true`), required for Android GPU texture compression. This forces a one-time texture re-import next time the project is opened in the editor — expect that re-import to take a while on first run after this change. |
| Testing | USB deploy via Godot's one-click export/deploy to a device with USB debugging enabled. Cheapest and fastest iteration loop of the two mobile platforms — no Mac required. |

## 4. iOS / App Store path

| Step | Detail |
|---|---|
| Hardware requirement | Requires a Mac with Xcode — Godot's iOS export still needs Xcode installed locally to build/sign/archive the `.ipa`. No way around this from Windows. |
| Apple Developer Program | $99/year, required for any device testing beyond simulator and for App Store submission. |
| Export + signing | Godot iOS export preset generates an Xcode project; signing (provisioning profiles, certificates) happens through Xcode/Apple Developer portal as usual for any iOS app. |
| Monetization / App Review | The gacha system currently uses **earned currency only** — no real-money purchase path exists. Apple's loot-box disclosure requirement (odds disclosure) applies only once a real-money purchase path is added. **If IAP is added later**, that triggers: App Store Review Guideline 3.1.1 (In-App Purchase) — must use Apple's IAP for any purchasable virtual currency/items — plus regional loot-box disclosure laws (e.g., China, South Korea, Belgium precedent) that require published drop-rate odds. Flag this for design review before any IAP work starts, not after. |
| Privacy manifest / nutrition label | We collect no user data (no analytics, no accounts, no ad SDKs as of this writing) — the privacy manifest and App Store "nutrition label" should both state "Data Not Collected." Re-verify this is still true at submission time if any telemetry/analytics gets added later. |
| LAN multiplayer | Fine as-is under App Review — local network multiplayer is a normal, accepted pattern. iOS 14+ requires a `NSLocalNetworkUsageDescription` Info.plist entry and, depending on discovery method, Bonjour service declarations — Godot's iOS export needs these added to the generated Xcode project's Info.plist. |
| Community/UGC moderation | If the community content-browsing service (`game/community/CommunityClient.gd`) goes live before iOS launch, Apple's UGC guideline (1.2) requires report and block tooling to exist *before* the app can ship with community content browsing enabled. Do not submit with live community browsing until report/block is built. |

## 5. Sequence recommendation

1. **Windows / Steam first.** Ship and stabilize on the platform with the fastest iteration loop and no store-review gate.
2. **Android beta next.** Cheap ($25 one-time), no Mac needed, fast USB-deploy iteration. Use this to do the first real on-device profiling pass (section 2) and shake out gesture/DPI/safe-area issues before iOS is even in scope.
3. **iOS last.** Requires the Mac+Xcode+$99/yr investment and has the strictest review gate (UGC moderation, IAP rules if added). Only start once Android has proven the mobile input/UI work is solid — porting fixes from Android to iOS is cheap; discovering them fresh on iOS is not.

### Per-step prerequisite checklist

**Before Android beta:**
- [x] Gesture intent-layer refactor landed (section 7)
- [x] DPI/content-scale strategy decided and implemented (section 7) — still needs on-device tuning
- [x] Safe-area insets added to HUD root and menu roots (section 7)
- [ ] SubViewport battery/perf test pass done, always-on viewports gated where needed
- [ ] Release keystore generated and stored securely
- [ ] Play Console account created ($25)

**Before iOS beta:**
- [ ] Android beta feedback incorporated (input/UI fixes proven on real hardware)
- [ ] Mac + Xcode available
- [ ] Apple Developer Program enrolled ($99/yr)
- [ ] `NSLocalNetworkUsageDescription` / Bonjour Info.plist entries added for LAN multiplayer
- [ ] Community browsing kept OFF for iOS build unless report/block tooling exists

**Before either store's public release (not just beta):**
- [ ] Map/tile/unit creator tools confirmed desktop-only and hidden/disabled on mobile builds
- [ ] Full on-device profiling checklist completed on target min-spec device
- [ ] IAP guideline review re-checked if monetization plans changed since this doc was written

## 6. Rendering configuration (implemented)

`project.godot` now has:

```
[rendering]

textures/vram_compression/import_etc2_astc=true
renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
```

- `renderer/rendering_method` = `"forward_plus"` keeps desktop/Steam on Forward+ (unchanged behavior).
- `renderer/rendering_method.mobile` = `"mobile"` uses Godot's `.mobile` platform-feature-tag override so Android/iOS exports automatically switch to the Mobile renderer without any desktop config change.
- `textures/vram_compression/import_etc2_astc=true` is set unconditionally (not feature-tagged) because it's required for Android texture export regardless of renderer, and Godot needs it enabled before textures are imported for mobile-compatible compression. This will trigger a one-time texture re-import next time the project is opened in the Godot editor.

## 7. Touch input, content scale and safe area (implemented)

All three are runtime-branched on `OS.has_feature("mobile")`, not feature-tagged in
`project.godot`. One build behaves correctly wherever it lands, and **desktop is a
guaranteed no-op** — every path returns before touching anything on a non-mobile host.

### 7.1 Gesture intent layer

| File | Role |
|---|---|
| `game/input/GestureClassifier.gd` | Pure `RefCounted` state machine. Pointer events + an injected clock in, gesture intents out. No scene dependencies, so the 0.5s long-press is testable synchronously. |
| `game/input/TouchInputAdapter.gd` | Thin adapter node. Subscribes to `InputEventScreenTouch` / `ScreenDrag` / `MagnifyGesture` and calls existing APIs. Mounted once as a child of the `MobileDisplay` autoload. |

Intent → existing API:

| Gesture | Intent | Routed to |
|---|---|---|
| Tap (press + release inside 16px slop, under 0.5s) | select / confirm | `cursor.gd::_handle_mouse_click(pos)` — the same method a left click drives |
| One-finger drag past 16px, not starting on HUD | camera pan | `CameraController.pan_by_screen_delta(delta)` |
| Two-finger pinch | camera zoom | `CameraController.zoom_by(1.0 / factor, center)` (finger-distance ratio → camera-distance multiplier; they are reciprocals) |
| Long press ≥ 0.5s inside slop | inspect | `cursor.gd::_handle_mouse_movement(pos)` — moves the board cursor, which emits `GameEvents.cursor_moved`, which is what `TerrainInfoPanel` / `UnitHoverPanel` already listen to for mouse hover |
| Trackpad `InputEventMagnifyGesture` | camera zoom | same as pinch — works on desktop too, and is the one behaviour this adds off-mobile |

The classifier resolves **one intent per touch sequence**: once a gesture is decided (or
disqualified by a third finger) nothing more is emitted until every finger lifts. The
adapter only ever reads touch/gesture events, never mouse events, so mouse behaviour is
untouched.

`CameraController` gained exactly two additive public methods — `pan_by_screen_delta()`
and `zoom_by()` — and its existing middle-drag / wheel handlers now call through them, so
mouse and touch share one implementation rather than two that drift.

### 7.2 The `emulate_mouse_from_touch` decision

**Left at Godot's default (`true`). The setting is deliberately NOT written to
`project.godot`.**

Turning it off would make the adapter the single owner of touch and remove all
double-fire risk — but Godot's `BaseButton` handles only `InputEventMouseButton` in
`_gui_input`, not `InputEventScreenTouch`. Disabling emulation would stop every HUD and
menu button in the game responding to a tap. That is a far larger regression than the one
it fixes, and it cannot be validated without a device.

Consequence: a tap already reaches `cursor.gd` as a synthetic left click (the "Tap ==
click" row in section 1). So `TouchInputAdapter` **auto-detects** the setting in `_ready()`
and routes its own tap intent only when emulation is off. The classifier still classifies
taps either way — the adapter simply declines to double-fire them. The residual issue
(pan start also selects the origin tile) is logged as a blocker in section 2.

`emulate_touch_from_mouse` is likewise **not** enabled. It would let gestures be driven
with a desktop mouse for testing, but it does exactly what this work is forbidden from
doing: it changes what a mouse drag means. Gesture behaviour is covered by unit tests
instead.

### 7.3 Content scale

`game/mobile/MobileDisplay.gd` (autoload `MobileDisplay`) sets
`Window.content_scale_factor` on mobile from:

```
factor = (dpi / 96) / stretch_scale * 0.5,  snapped to 0.05, clamped to [1.00, 1.75]
```

- `96` is the desktop reference density the HUD was authored at.
- `stretch_scale` is what `canvas_items` + `expand` already applies (`min(w/1280, h/720)`).
- `0.5` targets equal *angular* size rather than equal physical size, because a phone is
  held at roughly half a monitor's viewing distance.
- Any unusable input (DPI ≤ 0, which is what a platform that cannot report density
  returns) yields exactly `1.0` — the authored desktop look.

Worked examples: 2400×1080 @ 440 DPI → **1.55**; 1280×720 @ 300 DPI → **1.55**;
3200×1440 @ 700 DPI → **1.75** (clamped); 2560×1600 tablet @ 264 DPI → **1.00** (its 2×
stretch already covers the density).

### 7.4 Safe area

`MobileDisplay.apply_safe_area(control)` is the one reusable helper. It converts
`DisplayServer.get_display_safe_area()` against the window rect into per-edge margins,
divides by the content scale (physical pixels → UI pixels), rounds **up** so no pixel
hides under a notch, and is idempotent so an orientation change replaces rather than
accumulates insets. It handles a `MarginContainer` by adding to its margin constants
(preserving the authored values) and any other `Control` by shifting its anchor offsets.

Two application points, no per-screen copy-paste:

- **Battle HUD** — `UILayoutManager._apply_safe_area()` calls it on the single outermost
  `MarginContainer` that every HUD panel already lives inside. Runs *after* `_apply_theme()`
  so the theme sweep cannot clobber the margin constants.
- **Menus** — no menu scene needed editing. On mobile only, the autoload watches for
  `Control` scene roots being added under `/root` and insets them deferred (after their
  own `_ready`, so a `set_anchors_preset()` call cannot overwrite the offsets).

### 7.5 Coverage

| Suite | What it pins |
|---|---|
| `tests/unit/test_gesture_classifier.gd` | 22 tests — tap vs. drag slop, long-press timing on an injected clock, pinch ratios, one-intent-per-sequence, teardown |
| `tests/unit/test_mobile_content_scale.gd` | 13 tests — the pure DPI→factor function, clamps, snapping, monotonicity |
| `tests/unit/test_safe_area_margins.gd` | 12 tests — the pure inset function, scale conversion, no negative margins, empty-safe-rect = desktop no-op |
| `tests/unit/test_touch_adapter_contract.gd` | 4 tests — the by-name method contract with `CameraController` and `cursor.gd`, which `Object.call()` would otherwise let a rename break silently |

**Not covered, deliberately:** on-device profiling and tuning. No hardware was available.
