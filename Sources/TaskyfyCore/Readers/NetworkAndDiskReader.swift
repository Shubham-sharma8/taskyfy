import Foundation
import Darwin
import IOKit

// MARK: - NetworkReader

public final class NetworkReader: @unchecked Sendable {
    public struct Counters: Sendable {
        public let rx: UInt64
        public let tx: UInt64
        public let time: TimeInterval
        public let interface: String
        public let ip: String
    }

    private var prev: Counters?

    public init() {}

    public func sample() -> NetworkStats {
        let now = ProcessInfo.processInfo.systemUptime
        let current = Self.readCounters(timestamp: now)

        guard let previous = prev else {
            prev = current
            return NetworkStats(
                rxRate: 0,
                txRate: 0,
                rxTotal: current.rx,
                txTotal: current.tx,
                activeInterface: current.interface,
                localIP: current.ip
            )
        }

        let dt = max(0.05, current.time - previous.time)
        let dRx = current.rx >= previous.rx ? Double(current.rx - previous.rx) : 0
        let dTx = current.tx >= previous.tx ? Double(current.tx - previous.tx) : 0
        prev = current

        return NetworkStats(
            rxRate: dRx / dt,
            txRate: dTx / dt,
            rxTotal: current.rx,
            txTotal: current.tx,
            activeInterface: current.interface,
            localIP: current.ip
        )
    }

    private static func readCounters(timestamp: TimeInterval) -> Counters {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return Counters(rx: 0, tx: 0, time: timestamp, interface: "en0", ip: "—")
        }
        defer { freeifaddrs(first) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var bestInterface = "en0"
        var bestTraffic: UInt64 = 0
        var ipByInterface: [String: String] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor?.pointee {
            defer { cursor = ifa.ifa_next }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let nameC = ifa.ifa_name else { continue }
            let name = String(cString: nameC)
            guard let addr = ifa.ifa_addr else { continue }

            let family = Int32(addr.pointee.sa_family)
            if family == AF_LINK, let dataPtr = ifa.ifa_data {
                let ifData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                let rx = UInt64(ifData.ifi_ibytes)
                let tx = UInt64(ifData.ifi_obytes)
                if name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") || name.hasPrefix("pdp_ip") {
                    totalRx &+= rx
                    totalTx &+= tx
                    if name.hasPrefix("en") && (rx &+ tx) > bestTraffic {
                        bestTraffic = rx &+ tx
                        bestInterface = name
                    }
                }
            } else if family == AF_INET {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") {
                        ipByInterface[name] = ip
                    }
                }
            }
        }

        let chosenIP = ipByInterface[bestInterface] ?? ipByInterface["en0"] ?? ipByInterface.values.first ?? "—"
        return Counters(rx: totalRx, tx: totalTx, time: timestamp, interface: bestInterface, ip: chosenIP)
    }
}

// MARK: - DiskReader

public final class DiskReader: @unchecked Sendable {
    public struct Counters: Sendable {
        public let read: UInt64
        public let write: UInt64
        public let time: TimeInterval
    }

    private var prev: Counters?
    private var lastCapacityCheck: TimeInterval = 0
    private var cachedCapacity: (UInt64, UInt64) = (0, 0)

    public init() {}

    public func sample() -> DiskStats {
        let now = ProcessInfo.processInfo.systemUptime
        let (readBytes, writeBytes) = Self.readIOKitBlockCounters()
        if cachedCapacity.0 == 0 || (now - lastCapacityCheck) >= 30.0 {
            cachedCapacity = Self.readRootVolumeCapacity()
            lastCapacityCheck = now
        }
        let (totalCap, freeCap) = cachedCapacity

        let current = Counters(read: readBytes, write: writeBytes, time: now)
        guard let previous = prev else {
            prev = current
            return DiskStats(
                readRate: 0,
                writeRate: 0,
                totalRead: readBytes,
                totalWrite: writeBytes,
                totalSpace: totalCap,
                freeSpace: freeCap
            )
        }

        let dt = max(0.05, current.time - previous.time)
        let dRead = current.read >= previous.read ? Double(current.read - previous.read) : 0
        let dWrite = current.write >= previous.write ? Double(current.write - previous.write) : 0
        prev = current

        return DiskStats(
            readRate: dRead / dt,
            writeRate: dWrite / dt,
            totalRead: readBytes,
            totalWrite: writeBytes,
            totalSpace: totalCap,
            freeSpace: freeCap
        )
    }

    private static func readIOKitBlockCounters() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else {
                continue
            }
            if let r = stats["Bytes (Read)"] as? UInt64 {
                totalRead &+= r
            } else if let rNum = stats["Bytes (Read)"] as? NSNumber {
                totalRead &+= rNum.uint64Value
            }
            if let w = stats["Bytes (Write)"] as? UInt64 {
                totalWrite &+= w
            } else if let wNum = stats["Bytes (Write)"] as? NSNumber {
                totalWrite &+= wNum.uint64Value
            }
        }
        return (totalRead, totalWrite)
    }

    private static func readRootVolumeCapacity() -> (UInt64, UInt64) {
        let rootURL = URL(fileURLWithPath: "/")
        if let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) {
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let availImportant = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
            let availBasic = values.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
            let free = availImportant ?? availBasic ?? 0
            return (total, free)
        }
        return (0, 0)
    }
}
