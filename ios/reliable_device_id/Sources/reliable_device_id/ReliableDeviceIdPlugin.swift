import Flutter
import UIKit

/**
 * Device unique ID plugin, iOS side.
 *
 * Storage: a UUID v4 generated on first use, persisted as a Keychain
 * generic-password item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
 * * survives app uninstall (Keychain lives outside the app sandbox);
 * * never migrates to another device (ThisDeviceOnly excludes it from
 *   encrypted backups and device-to-device migration), keeping the
 *   "one device = one ID" semantics.
 *
 * Keychain reads that fail for a reason other than "item not found"
 * (e.g. protected data unavailable before first unlock) return a
 * session-only degraded ID instead of minting a new persistent one, so a
 * transient failure can never silently rotate the device identity.
 *
 * No collection happens at registration; work starts only when Flutter
 * invokes `getDeviceId`.
 */
public class ReliableDeviceIdPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "reliable_device_id", binaryMessenger: registrar.messenger())
    let instance = ReliableDeviceIdPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let queue = DispatchQueue(label: "com.ehangwork.reliable_device_id.io", qos: .userInitiated)

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDeviceId":
      queue.async {
        let payload = Self.readDeviceId()
        DispatchQueue.main.async { result(payload) }
      }
    case "getAndroidId":
      // Android-only signal; there is no ANDROID_ID on iOS.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Storage

  private struct StoredRecord: Codable {
    let uuid: String
    let firstSeenAt: Int64
  }

  private enum KeychainRead {
    case record(StoredRecord)
    case notFound
    case unavailable
  }

  private static let keychainService =
    (Bundle.main.bundleIdentifier ?? "unknown.bundle") + ".reliable_device_id"
  private static let keychainAccount = "device_uuid"

  private static func readDeviceId() -> [String: Any?] {
    switch fetchStored() {
    case .record(let record):
      return payload(uuid: record.uuid, firstSeenAt: record.firstSeenAt, degraded: false)
    case .notFound:
      let uuid = UUID().uuidString
      let firstSeen = Self.nowMillis()
      let stored = saveRecord(StoredRecord(uuid: uuid, firstSeenAt: firstSeen))
      return payload(uuid: uuid, firstSeenAt: firstSeen, degraded: !stored)
    case .unavailable:
      // Transient failure: do NOT persist anything, or the next successful
      // read would observe a rotated identity.
      return payload(uuid: UUID().uuidString, firstSeenAt: Self.nowMillis(), degraded: true)
    }
  }

  private static func fetchStored() -> KeychainRead {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return .notFound
    }
    guard status == errSecSuccess, let data = item as? Data else {
      return .unavailable
    }
    guard
      let record = try? JSONDecoder().decode(StoredRecord.self, from: data),
      !record.uuid.isEmpty
    else {
      // Undecodable payload (corrupt or written by another version): treat as
      // absent and let the write path replace it.
      return .notFound
    }
    return .record(record)
  }

  private static func saveRecord(_ record: StoredRecord) -> Bool {
    guard let data = try? JSONEncoder().encode(record) else {
      return false
    }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
  }

  private static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  // MARK: - Signals

  private static func payload(uuid: String, firstSeenAt: Int64, degraded: Bool) -> [String: Any?] {
    [
      "deviceId": uuid,
      "firstSeenAt": firstSeenAt,
      "degraded": degraded,
      "signals": collectSignals(),
    ]
  }

  private static func collectSignals() -> [String: Any?] {
    #if targetEnvironment(simulator)
      let isPhysicalDevice = false
    #else
      let isPhysicalDevice = true
    #endif
    return [
      "idfv": UIDevice.current.identifierForVendor?.uuidString,
      "isPhysicalDevice": isPhysicalDevice,
      "manufacturer": "Apple",
      "model": machineModel(),
      "osVersion": UIDevice.current.systemVersion,
    ]
  }

  private static func machineModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafeBytes(of: &systemInfo.machine) { pointer in
      String(decoding: pointer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
  }
}
