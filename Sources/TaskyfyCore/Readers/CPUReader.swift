import Foundation
import Darwin

public final class CPUReader: @unchecked Sendable {
    public struct Ticks: Sendable, Equatable {
        public let user: UInt64
        public let system: UInt64
        public let idle: UInt64
        public let nice: UInt64

        public var active: UInt64 { user &+ system &+ nice }
        public var total: UInt64 { active &+ idle }
    }

    private var prevCores: [Ticks] = []
    private let pCoreCount: Int
    private let eCoreCount: Int

    public init() {
        let p = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let e = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        self.pCoreCount = p
        self.eCoreCount = e
    }

    public func sample() -> CPUSample {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        let loadTuple = (loads[0], loads[1], loads[2])

        guard kr == KERN_SUCCESS, let info = cpuInfo, numCPUs > 0 else {
            return CPUSample(loadAverage: loadTuple)
        }

        defer {
            let byteCount = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), byteCount)
        }

        let coreCount = Int(numCPUs)
        var currentCores: [Ticks] = []
        currentCores.reserveCapacity(coreCount)

        for i in 0..<coreCount {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            currentCores.append(Ticks(user: user, system: system, idle: idle, nice: nice))
        }

        guard prevCores.count == coreCount else {
            prevCores = currentCores
            let initialCores = (0..<coreCount).map { idx in
                CoreLoad(id: idx, usage: 0, type: coreType(for: idx, total: coreCount))
            }
            return CPUSample(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                perCore: initialCores,
                loadAverage: loadTuple
            )
        }

        var totalUserDelta: UInt64 = 0
        var totalSysDelta: UInt64 = 0
        var totalAllDelta: UInt64 = 0
        var coreLoads: [CoreLoad] = []
        coreLoads.reserveCapacity(coreCount)

        for i in 0..<coreCount {
            let prev = prevCores[i]
            let cur = currentCores[i]
            let dUser = (cur.user &+ cur.nice) &- (prev.user &+ prev.nice)
            let dSys = cur.system &- prev.system
            let dIdle = cur.idle &- prev.idle
            let dTotal = dUser &+ dSys &+ dIdle

            totalUserDelta &+= dUser
            totalSysDelta &+= dSys
            totalAllDelta &+= dTotal

            let pct = dTotal > 0 ? (Double(dUser &+ dSys) / Double(dTotal)) * 100.0 : 0.0
            coreLoads.append(CoreLoad(id: i, usage: pct, type: coreType(for: i, total: coreCount)))
        }

        prevCores = currentCores

        let userPct = totalAllDelta > 0 ? (Double(totalUserDelta) / Double(totalAllDelta)) * 100.0 : 0.0
        let sysPct = totalAllDelta > 0 ? (Double(totalSysDelta) / Double(totalAllDelta)) * 100.0 : 0.0
        let totalPct = min(max(userPct + sysPct, 0), 100)

        return CPUSample(
            totalUsage: totalPct,
            userUsage: userPct,
            systemUsage: sysPct,
            perCore: coreLoads,
            loadAverage: loadTuple
        )
    }

    private func coreType(for index: Int, total: Int) -> CoreType {
        guard pCoreCount > 0 && eCoreCount > 0, (pCoreCount + eCoreCount) == total else {
            return .standard
        }
        // On Apple Silicon, efficiency cores are enumerated first on M1/M2/M3/M4, followed by performance cores.
        return index < eCoreCount ? .efficiency : .performance
    }

    public static func sysctlInt(_ name: String) -> Int? {
        var val: Int = 0
        var size = MemoryLayout<Int>.size
        if sysctlbyname(name, &val, &size, nil, 0) == 0 {
            return val
        }
        var val32: Int32 = 0
        var size32 = MemoryLayout<Int32>.size
        if sysctlbyname(name, &val32, &size32, nil, 0) == 0 {
            return Int(val32)
        }
        return nil
    }
}
