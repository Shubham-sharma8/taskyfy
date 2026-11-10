import Foundation
import ServiceManagement

public final class HelperClient: @unchecked Sendable {
    public enum InstallState: String, Sendable, Equatable {
        case enabled = "Installed & Active"
        case requiresApproval = "Awaiting System Settings Approval"
        case notInstalled = "Not Installed"
        case notFound = "Helper Bundle Not Found"
    }

    public static let machServiceName = "app.taskyfy.helper"
    public static let daemonPlistName = "app.taskyfy.helper.plist"
    public static let shared = HelperClient()

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var latestRecords: [Int32: RawProcRecord] = [:]
    private var lastSampleTime: Date?
    public private(set) var lastError: String?

    public init() {}

    public var installState: InstallState {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notInstalled
        case .notFound:
            return .notFound
        @unknown default:
            return .notInstalled
        }
    }

    public var isResponding: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let last = lastSampleTime else { return false }
        return Date().timeIntervalSince(last) < 15.0 && !latestRecords.isEmpty
    }

    public func registerDaemon() throws {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        try service.register()
    }

    public func unregisterDaemon() throws {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        try service.unregister()
        disconnect()
    }

    public func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    public func cachedRecords() -> [Int32: RawProcRecord] {
        lock.lock()
        defer { lock.unlock() }
        return latestRecords
    }

    public func pollAsync() {
        guard installState == .enabled else { return }
        let conn = ensureConnection()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] err in
            self?.lock.lock()
            self?.lastError = err.localizedDescription
            self?.connection = nil
            self?.lock.unlock()
        }) as? TaskyfyHelperProtocol else {
            return
        }

        proxy.sampleProcesses { [weak self] data in
            let parsed = Self.decodeRecords(from: data)
            self?.lock.lock()
            self?.latestRecords = parsed
            self?.lastSampleTime = Date()
            self?.lastError = nil
            self?.lock.unlock()
        }
    }

    public static func decodeRecords(from data: Data) -> [Int32: RawProcRecord] {
        let stride = MemoryLayout<RawProcRecord>.stride
        guard stride == RawProcRecord.byteStride, data.count >= stride else {
            return [:]
        }
        let count = data.count / stride
        var map: [Int32: RawProcRecord] = [:]
        map.reserveCapacity(count)

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            let ptr = base.assumingMemoryBound(to: RawProcRecord.self)
            for i in 0..<count {
                let rec = ptr[i]
                map[rec.pid] = rec
            }
        }
        return map
    }

    public static func encodeRecords(_ records: [RawProcRecord]) -> Data {
        records.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let existing = connection {
            return existing
        }
        let conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: TaskyfyHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func disconnect() {
        lock.lock()
        let conn = connection
        connection = nil
        latestRecords = [:]
        lastSampleTime = nil
        lock.unlock()
        conn?.invalidate()
    }
}
