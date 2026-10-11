# Mac App Store readiness (TodoCompanion / Max)

Direct download (Developer ID + notarization + Sparkle) is the **default**
channel and what [scripts/release-suite.sh](../scripts/release-suite.sh) builds.
The Mac App Store is a **second** channel: same product rules, different
packaging. Do not ship Sparkle inside an App Store build.

## What already aligns

- App sandbox + hand-written entitlements (Reminders **and** Calendars)
- App Store entitlements without Sparkle temporary exceptions
  (`TodoCompanion.AppStore.entitlements`)
- `LSUIElement` menu bar app
- Usage strings: Screen Capture, Microphone, Speech Recognition, Reminders,
  Calendars
- Privacy manifest (`PrivacyInfo.xcprivacy`)
- `ITSAppUsesNonExemptEncryption` / productivity category in generated Info.plist
- Apple Silicon–only Release (FluidAudio)
- Privacy posture: no analytics, no background capture, no cloud background work
- `APP_STORE` compile flag strips Sparkle menu/API, hides MCP Settings, forces
  MCP off

## Build the App Store package

```bash
CONFIRM=yes ./scripts/release-mas.sh 1.6.0
```

That archives with `APP_STORE`, swaps in App Store entitlements, clears Sparkle
Info.plist keys, strips `Sparkle.framework` from the archive, and exports with
`method: app-store`. Upload the result with Transporter or Xcode Organizer.

## Checklist before App Store Connect upload

1. **Run `scripts/release-mas.sh`** — not `release-suite.sh` / `release-companion.sh`
   (those hardcode `developer-id`).
2. **Calendars + Screen Capture usage strings** — present in the target build
   settings (`NSCalendarsFullAccessUsageDescription`,
   `NSScreenCaptureUsageDescription`).
3. **Screen Recording / Accessibility** — explain in App Review notes: capture
   is user-initiated on hotkey; Accessibility extras are opt-in.
4. **Two apps** — Electron “To-Do Notifier” is a separate listing or stays
   direct-only; the suite DMG is not an App Store package.
5. **Export compliance / encryption** — HTTPS to Ollama localhost and optional
   cloud APIs; `ITSAppUsesNonExemptEncryption` is set to `NO` for standard HTTPS.
6. **Demo account / video** — reviewers cannot grant Screen Recording easily;
   attach a short capture of summon → ask → save → library.
7. **Age rating / privacy nutrition labels** — data linked to user only if they
   opt into cloud Q&A; screenshots leave the device only then.
8. **Paid Apple Developer Program** — App Store distribution requires it
   (Developer ID notarization also does).

## Interview line

“We ship notarized Developer ID builds with Sparkle today. App Store is the same
companion binary with Apple’s updater instead of Sparkle — sandbox, privacy
strings, and a dedicated `release-mas.sh` path are in place; Connect upload is
export + review notes, not a product rewrite.”
