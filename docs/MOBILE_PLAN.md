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
| Renderer split | Done (this change) | `project.godot` now has a `[rendering]` section: desktop keeps Forward+, mobile exports use the Mobile renderer automatically via the `.mobile` feature-tag override. See section 6. |

None of the above needs rework to start a mobile export. The blockers below are
what's between "it boots on a phone" and "it's actually good on a phone."

## 2. Blockers remaining

| Blocker | Why it matters | Recommendation |
|---|---|---|
| Gesture input (pinch zoom, two-finger pan, long-press cancel) | Tap-as-click covers the command loop, but camera control and cancel actions still assume mouse/keyboard. | Needs an intent-layer refactor: an input-intent abstraction that both mouse+keyboard and touch feed into, rather than touch code bolted onto existing click handlers. Scope this as its own task before any camera-heavy mobile testing. |
| DPI / content-scale strategy | `canvas_items` + `expand` handles aspect ratio, not pixel density. Phone screens range ~300-500+ DPI; UI text/icons sized for 1280x720 desktop may render too small or too large. | Decide on a `content_scale_factor` strategy per device class, or a UI-scale setting exposed to the player. Needs on-device testing to tune, not guessable from desktop. |
| Safe-area insets | Notches, punch-hole cameras, and gesture-nav bars (Android) / home indicator (iOS) can overlap HUD elements. | Add safe-area-aware margins to the root HUD container before shipping a build to real devices. |
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
- [ ] Gesture intent-layer refactor landed (section 2)
- [ ] DPI/content-scale strategy decided and implemented
- [ ] Safe-area insets added to HUD root
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
