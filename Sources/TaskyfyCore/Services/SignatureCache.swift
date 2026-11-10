import Foundation
import AppKit
import Security

public final class SignatureCache: @unchecked Sendable {
    public enum Status: String, Sendable, Equatable {
        case apple = "Apple System / Signed"
        case notarized = "Developer ID + Notarized"
        case signed = "Developer Signed"
        case adHoc = "Ad-Hoc Signed"
        case unsigned = "Unsigned Binary"
        case unknown = "Inspecting…"

        public var symbolName: String {
            switch self {
            case .apple: return "apple.logo"
            case .notarized: return "checkmark.seal.fill"
            case .signed: return "checkmark.shield.fill"
            case .adHoc: return "shield.lefthalf.filled"
            case .unsigned: return "exclamationmark.triangle.fill"
            case .unknown: return "ellipsis.circle"
            }
        }
    }

    public struct Record: Sendable, Equatable {
        public let status: Status
        public let teamIdentifier: String?
        public let signingIdentifier: String?
        public let authority: String?

        public init(
            status: Status,
            teamIdentifier: String? = nil,
            signingIdentifier: String? = nil,
            authority: String? = nil
        ) {
            self.status = status
            self.teamIdentifier = teamIdentifier
            self.signingIdentifier = signingIdentifier
            self.authority = authority
        }
    }

    public static let shared = SignatureCache()

    private let lock = NSLock()
    private var cache: [String: Record] = [:]
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "app.taskyfy.sigcache", qos: .utility, attributes: .concurrent)

    public init() {}

    public func status(forPath path: String?, onUpdate: (@Sendable () -> Void)? = nil) -> Record {
        guard let path, !path.isEmpty else {
            return Record(status: .unknown)
        }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/usr/bin/") {
            return Record(status: .apple, signingIdentifier: (path as NSString).lastPathComponent, authority: "Software Signing (Apple)")
        }

        lock.lock()
        if let existing = cache[path] {
            lock.unlock()
            return existing
        }
        let alreadyRunning = inFlight.contains(path)
        if !alreadyRunning {
            inFlight.insert(path)
        }
        lock.unlock()

        if !alreadyRunning {
            queue.async { [weak self] in
                let evaluated = Self.evaluate(path: path)
                self?.lock.lock()
                self?.cache[path] = evaluated
                self?.inFlight.remove(path)
                self?.lock.unlock()
                if let onUpdate {
                    DispatchQueue.main.async(execute: onUpdate)
                }
            }
        }

        return Record(status: .unknown)
    }

    public static func evaluate(path: String) -> Record {
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return Record(status: .unsigned)
        }

        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            return Record(status: .unsigned)
        }

        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let codeFlags = info[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []

        var authorityName: String?
        if let firstCert = certs.first {
            var commonName: CFString?
            if SecCertificateCopyCommonName(firstCert, &commonName) == errSecSuccess,
               let cn = commonName as String? {
                authorityName = cn
            }
        }

        if (codeFlags & 0x0002) != 0 { // kSecCodeSignatureAdhoc
            return Record(status: .adHoc, teamIdentifier: teamID, signingIdentifier: identifier, authority: "Ad-Hoc")
        }

        if let auth = authorityName {
            if auth.contains("Apple") && teamID == nil {
                return Record(status: .apple, teamIdentifier: nil, signingIdentifier: identifier, authority: auth)
            }
            if auth.contains("Developer ID") {
                return Record(status: .notarized, teamIdentifier: teamID, signingIdentifier: identifier, authority: auth)
            }
            return Record(status: .signed, teamIdentifier: teamID, signingIdentifier: identifier, authority: auth)
        }

        if identifier != nil {
            return Record(status: .signed, teamIdentifier: teamID, signingIdentifier: identifier, authority: nil)
        }

        return Record(status: .unsigned)
    }
}

public final class IconCache: @unchecked Sendable {
    public static let shared = IconCache()

    private let lock = NSLock()
    private var byKey: [String: NSImage] = [:]

    public init() {}

    public func icon(forPath path: String?, bundlePath: String? = nil, pid: Int32? = nil) -> NSImage {
        let key = bundlePath ?? path ?? "pid:\(pid ?? 0)"
        lock.lock()
        if let cached = byKey[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var resolved: NSImage?
        if let pid, pid > 0, let running = NSRunningApplication(processIdentifier: pid), let ic = running.icon {
            resolved = ic
        } else if let bp = bundlePath, FileManager.default.fileExists(atPath: bp) {
            resolved = NSWorkspace.shared.icon(forFile: bp)
        } else if let p = path, FileManager.default.fileExists(atPath: p) {
            resolved = NSWorkspace.shared.icon(forFile: p)
        }

        let finalImage = resolved ?? NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns")
        lock.lock()
        if byKey.count > 512 {
            byKey.removeAll(keepingCapacity: true)
        }
        byKey[key] = finalImage
        lock.unlock()
        return finalImage
    }
}
