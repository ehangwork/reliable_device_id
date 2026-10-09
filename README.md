# device_unique_id

[![pub package](https://img.shields.io/badge/pub-0.4.0-blue.svg)](https://pub.dev/packages/device_unique_id)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-green.svg)

A Flutter plugin that provides a **stable per-device unique ID** for Android and iOS — built for apps distributed in mainland China (no Google services required) and for use cases like device binding / passwordless login, analytics, and risk-control signal collection.

Modern mobile platforms no longer expose a reliable hardware identifier (IMEI is unreadable for regular apps since Android 10; UDID is private API on iOS; IDFV rotates on reinstall). This plugin works around those limits with a layered design instead of a single magic value.

## Features

- **Survives uninstall/reinstall** — the ID is deterministically derived (Android) or Keychain-persisted (iOS), not merely stored in app-local storage.
- **One device, one ID** — device-to-device migration (vendor clone tools like HUAWEI Phone Clone / Mi Mover, encrypted backups, iOS Quick Start) is detected and does *not* carry the ID over.
- **Rich auxiliary signals** for risk control: raw `androidId`, hashed MediaDRM device ID, `idfv`, emulator heuristic, model/OS info, and which seed the ID was derived from.
- **Zero permissions, zero GMS dependency** — nothing to declare in the merged manifest.
- **Consent-friendly** — the plugin performs *no* collection at registration; the first native read happens only when your code calls `get()`, so you can gate it behind your privacy-policy dialog (PIPL requirement).
- **Never throws** — platform failures degrade to a session-stable random UUID with a `degraded` flag and self-heal on retry.

## Platform support

| Android | iOS |
|:---:|:---:|
| ✅ (minSdk 24) | ✅ (iOS 13+) |

## Installation

```yaml
dependencies:
  device_unique_id: ^0.4.0
```

## Usage

```dart
import 'package:device_unique_id/device_unique_id.dart';

// Call only after the user has consented to your privacy policy.
final result = await DeviceUniqueId.instance.get();

result.deviceId;                  // the stable device ID (UUID-shaped)
result.firstSeenAt;               // epoch ms when this ID was first derived
result.degraded;                  // true → session-only random value
result.signals.androidId;         // ANDROID_ID (Android)
result.signals.idfv;              // identifierForVendor (iOS)
result.signals.mediaDrmId;        // MediaDRM device ID, namespaced SHA-256 (Android)
result.signals.seedSource;        // 'ssaid' | 'mediaDrm' | 'random' (Android)
result.signals.isPhysicalDevice;  // emulator heuristic
result.signals.toMap();           // flat map for your reporting pipeline

// Direct raw ANDROID_ID accessor (Android only; null on iOS, never throws).
final androidId = await DeviceUniqueId.instance.getAndroidId();
```

### ID stability semantics

| Scenario | Result | Why |
|---|---|---|
| App restart / process kill | unchanged | in-memory cache + persisted record |
| **Uninstall → reinstall (same device)** | **unchanged** | Android: seed (`ANDROID_ID` / MediaDRM) outlives the app, the ID is re-derived; iOS: Keychain survives uninstall |
| Factory reset / Erase All Content | new ID | SSAID rotates; Keychain wiped — "new device identity" by design |
| **Android vendor clone tools** (Phone Clone / Mi Mover …) | **new ID** | the stored SSAID *witness* no longer matches → data was carried to another device → re-derive from this device's seed |
| iOS device-to-device migration | new ID | Keychain item is `ThisDeviceOnly` |
| Android multi-user / work profile / app cloning | independent IDs per profile | SSAID is user-scoped |
| Android "clear data" (without uninstall) | **unchanged** | re-derived from the seed |
| Persistent storage failure | session-stable random value, `degraded: true`, auto-retried | never throws, self-heals |

### How it works

**Android** — `deviceId = SHA-256(namespace \| seed)` formatted as a name-based UUID, with seed priority `ANDROID_ID (SSAID) > MediaDRM (Widevine) device ID > random`:

- SSAID is scoped to (device, user, **signing key**) on Android 8.0+, so it survives uninstall, rotates on factory reset, and is invisible to apps signed with other keys — making it both stable and privacy-scoped;
- MediaDRM is device-wide and survives everything, used as a fallback for ROMs where SSAID is unreadable, and exposed (hashed with a namespace) as a strong risk-control signal;
- the persisted record stores the SSAID observed at creation as a *witness*: vendor clone tools copy app data wholesale (ignoring `allowBackup`), and a witness mismatch on read means "this data now lives on a different device" — the ID is re-derived from the current device's seed there;
- apps signed with the **same key** derive the *same* deviceId on the same device — multi-app alignment comes free with a unified keystore.

**iOS** — a UUID v4 minted on first use, stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:

- survives uninstall (the Keychain lives outside the app sandbox);
- `ThisDeviceOnly` keeps it out of backups and device-to-device migration, preserving "one device, one ID";
- a transient Keychain failure (e.g. protected data unavailable before first unlock) never mints a new persistent ID — the plugin returns a session-only degraded value and retries later.

### Privacy & compliance

- The device ID and signals are **personal information** under PIPL/GDPR-style regimes. Gate the first `get()` behind privacy-policy consent — the plugin deliberately does nothing at registration time, which is exactly what regulators check ("collecting device identifiers before consent" is a top-reported violation in MIIT app inspections);
- list "device identifiers" and their purpose in your privacy policy;
- no permissions, no GMS, no third-party SDKs;
- fill in your App Store privacy label ("identifiers" category) and Google Play Data safety form if you distribute there.

### Security positioning

A device ID is a **weak credential**, not authentication: forging a UUID is trivial and rooted devices can tamper with local state. Treat `deviceId` as one risk signal server-side; combine it with sessions, IP and behavior for auto-login decisions. Real anti-fraud needs server-side device fingerprinting — this plugin supplies signals, not verdicts.

### Known limitations

- Keychain persistence across uninstall is an Apple **implementation detail**, not a contract (confirmed by Apple engineers) — "Erase All Content and Settings" or system repair loses it. Build a "device lost → re-login" path for passwordless flows;
- the iOS **simulator** clears Keychain items on app deletion (unlike real devices) — verify reinstall stability on a real iPhone;
- Android reinstall resets `firstSeenAt`; treat the server as the source of truth for "first seen";
- some ROMs ship duplicate SSAIDs (reported on emulators/custom ROMs) — deterministic derivation inherits that; dedupe server-side and treat `seedSource=ssaid` + one ID across many accounts as a risk signal;
- debug and release builds (different signing keys) get **different** IDs on the same Android device; per-flavor bundle ids do the same on iOS.

## Manual verification matrix

Run these on real devices before relying on the ID (see `example/integration_test/reinstall_probe_test.dart` for the reinstall probe):

| # | Scenario | Platform | Expected |
|---|---|---|---|
| 1 | First install | both | new ID, `degraded=false` |
| 2 | Process kill & relaunch | both | same ID |
| 3 | Uninstall → reinstall | both | same ID (iOS: **real device only**) |
| 4 | Factory reset / erase | both | new ID |
| 5 | Clone-tool migration to a new device | Android | new ID, `migrated=true` on first read |
| 6 | Clear app data (no uninstall) | Android | same ID |
| 7 | Multi-user / work profile / dual apps | Android | independent IDs |
| 8 | Device-to-device migration | iOS | new ID |
| 9 | Emulator/simulator | both | works, `isPhysicalDevice=false` |
| 10 | Concurrent `get()` calls | both | one platform round-trip |

## 中文说明

本插件为**中国大陆上架的 App** 设计（无 GMS 依赖、显式采集以满足个保法"同意前不采集"要求）。核心特性：

- **主 ID 跨卸载重装稳定**：Android 端由设备级种子（`ANDROID_ID` > MediaDRM > 随机）SHA-256 确定性派生；iOS 端存 Keychain（`ThisDeviceOnly`，不随换机/备份迁移）；
- **防"换机克隆"一码两机**：华为手机克隆/小米换机等工具整体搬运应用数据，插件通过创建时的 SSAID 见证（witness）检测迁移并在新设备重新派生；
- **多 App 对齐**：同一签名 key 的 App 在同一 Android 设备上派生出相同 deviceId；
- **风控信号**：androidId / 哈希 mediaDrmId / idfv / 模拟器检测 / 机型系统信息 / 种子来源；
- API 仅 `get()` 与 `getAndroidId()`，永不抛异常，失败自动降级并重试自愈。

完整语义、设计取舍与合规要点见上方英文章节（表格含"何时变/何时不变"全部场景）。

## License

MIT — see [LICENSE](LICENSE).
