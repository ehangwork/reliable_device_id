# Changelog

All notable changes to this project are documented here.
Versions before 0.4.0 were never published and exist to record the design evolution.

## 0.4.0

### Added

- `getAndroidId()`: direct raw ANDROID_ID (SSAID) accessor for risk-control and
  statistics — Android only, returns null on iOS or ROM failure, never throws.
  Plays no role in deriving the primary ID.

## 0.3.1

### Fixed

- Under a persistent platform failure the degraded value now stays
  session-stable instead of being re-randomized on every retrying `get()`.
- Android executor thread is shut down on engine detach (safe for add-to-app
  re-attach); calls arriving after shutdown reply with `engine-detached`.

### Docs

- Known limitations now spell out that debug/release signing keys (Android)
  and per-flavor bundle ids (iOS) yield different IDs on the same device.

## 0.3.0

### Breaking

- API reduced to `get()` — removed `refresh()` (a re-read always yields the
  same deterministic result within a session) and `reset()` (a local reset
  cannot survive uninstall; persistent unbinding belongs on the server side).

### Changed

- Degraded results are no longer pinned for the whole session: the next
  `get()` automatically retries the platform, so transient storage failures
  (e.g. iOS Keychain unreadable before first unlock) self-heal.
- Android internals simplified: salt storage and the reset code path removed;
  pure deterministic derivation remains. The derivation input format differs
  from 0.2.0, so upgrading from an installed 0.2.0 rotates the ID once —
  irrelevant if 0.2.0 never shipped to users.

## 0.2.0

### Breaking (Android semantics)

- The primary ID is now deterministically derived (SHA-256 name-based UUID)
  from a device seed — `ANDROID_ID` first, MediaDRM (Widevine) device ID as
  fallback, random as last resort — so uninstall/reinstall on the same device
  restores the **same** ID (the previous random-UUID implementation changed
  on reinstall).

### Changed

- Clearing app data (without uninstall) also restores the same ID on Android.
  Witness-based clone-tool migration detection unchanged.

### Added

- Signals: `mediaDrmId` (namespaced SHA-256 hash) and `seedSource`
  (`ssaid` | `mediaDrm` | `random`).

## 0.1.0

- Initial release.
- Device-level stable unique ID: persisted UUID v4 with iOS Keychain
  (`ThisDeviceOnly`) / Android SharedPreferences + ANDROID_ID witness
  (detects vendor clone-tool migration and regenerates).
- Auxiliary signals for risk control / analytics: `androidId`, `idfv`,
  `isPhysicalDevice`, manufacturer, model, os version, sdkInt, `migrated`.
- Explicit-call-only collection (privacy consent gating), no permissions,
  never throws — platform failures degrade to a session-only UUID.
