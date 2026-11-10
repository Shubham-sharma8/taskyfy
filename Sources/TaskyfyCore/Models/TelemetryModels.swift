import Foundation

// MARK: - XPC Protocol & Wire Record

@objc(TaskyfyHelperProtocol)
public protocol TaskyfyHelperProtocol {
    func protocolVersion(withReply reply: @escaping (Int) -> Void)
    func sampleProcesses(withReply reply: @escaping (Data) -> Void)
}

/// Exact 64-byte binary wire record returned by `TaskyfyHelper` over XPC.
public struct RawProcRecord: Sendable, Equatable {
    public var pid: Int32
    public var reserved: Int32
    public var userTime: UInt64
    public var systemTime: UInt64
    public var footprint: UInt64
    public var energy: UInt64
    public var diskRead: UInt64
    public var diskWrite: UInt64
    public var wakeups: UInt64

    public static let byteStride = 64

    public init(
        pid: Int32,
        reserved: Int32 = 0,
        userTime: UInt64,
        systemTime: UInt64,
        footprint: UInt64,
        energy: UInt64,
        diskRead: UInt64,
        diskWrite: UInt64,
        wakeups: UInt64
    ) {
        self.pid = pid
        self.reserved = reserved
        self.userTime = userTime
        self.systemTime = systemTime
        self.footprint = footprint
        self.energy = energy
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.wakeups = wakeups
    }
}

// MARK: - CPU Models

public enum CoreType: String, Sendable, Codable, Equatable {
    case efficiency = "E"
    case performance = "P"
    case standard = "S"

    public var label: String {
        switch self {
        case .efficiency: return "Efficiency"
        case .performance: return "Performance"
        case .standard: return "Core"
        }
    }
}

public struct CoreLoad: Identifiable, Sendable, Equatable {
    public let id: Int
    public let usage: Double
    public let type: CoreType

    public init(id: Int, usage: Double, type: CoreType) {
        self.id = id
        self.usage = min(max(usage, 0), 100)
        self.type = type
    }
}

public struct CPUSample: Sendable, Equatable {
    public let totalUsage: Double
    public let userUsage: Double
    public let systemUsage: Double
    public let perCore: [CoreLoad]
    public let loadAverage: (Double, Double, Double)

    public init(
        totalUsage: Double = 0,
        userUsage: Double = 0,
        systemUsage: Double = 0,
        perCore: [CoreLoad] = [],
        loadAverage: (Double, Double, Double) = (0, 0, 0)
    ) {
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.perCore = perCore
        self.loadAverage = loadAverage
    }

    public static func == (lhs: CPUSample, rhs: CPUSample) -> Bool {
        lhs.totalUsage == rhs.totalUsage &&
        lhs.userUsage == rhs.userUsage &&
        lhs.systemUsage == rhs.systemUsage &&
        lhs.perCore == rhs.perCore &&
        lhs.loadAverage.0 == rhs.loadAverage.0 &&
        lhs.loadAverage.1 == rhs.loadAverage.1 &&
        lhs.loadAverage.2 == rhs.loadAverage.2
    }
}

// MARK: - Memory, GPU, Battery & SelfCost Models

public enum PressureLevel: Int, Sendable, Codable, Comparable {
    case normal = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .normal: return "Nominal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }
}

public struct MemoryStats: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let free: UInt64
    public let swapUsed: UInt64
    public let swapTotal: UInt64
    public let pressure: Double
    public let pressureLevel: PressureLevel

    public var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    public init(
        total: UInt64 = 0,
        used: UInt64 = 0,
        app: UInt64 = 0,
        wired: UInt64 = 0,
        compressed: UInt64 = 0,
        cached: UInt64 = 0,
        free: UInt64 = 0,
        swapUsed: UInt64 = 0,
        swapTotal: UInt64 = 0,
        pressure: Double = 0,
        pressureLevel: PressureLevel = .normal
    ) {
        self.total = total
        self.used = used
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.free = free
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
        self.pressureLevel = pressureLevel
    }
}

public struct GPUStats: Sendable, Equatable {
    public let utilization: Double
    public let rendererUtilization: Double
    public let tilerUtilization: Double
    public let inUseSystemMemory: UInt64
    public let modelName: String

    public init(
        utilization: Double = 0,
        rendererUtilization: Double = 0,
        tilerUtilization: Double = 0,
        inUseSystemMemory: UInt64 = 0,
        modelName: String = "Apple Silicon GPU"
    ) {
        self.utilization = utilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.inUseSystemMemory = inUseSystemMemory
        self.modelName = modelName
    }
}

public struct BatteryStats: Sendable, Equatable {
    public let hasBattery: Bool
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let percentage: Double
    public let watts: Double
    public let adapterWatts: Int
    public let timeRemainingMinutes: Int?
    public let healthPercent: Double
    public let cycleCount: Int
    public let temperature: Double

    public init(
        hasBattery: Bool = false,
        isCharging: Bool = false,
        isPluggedIn: Bool = true,
        percentage: Double = 100,
        watts: Double = 0,
        adapterWatts: Int = 0,
        timeRemainingMinutes: Int? = nil,
        healthPercent: Double = 100,
        cycleCount: Int = 0,
        temperature: Double = 0
    ) {
        self.hasBattery = hasBattery
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.percentage = percentage
        self.watts = watts
        self.adapterWatts = adapterWatts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.temperature = temperature
    }
}

public struct SelfCost: Sendable, Equatable {
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let diskWrittenBytes: UInt64
    public let uptimeSeconds: TimeInterval

    public init(
        cpuPercent: Double = 0,
        memoryBytes: UInt64 = 0,
        diskWrittenBytes: UInt64 = 0,
        uptimeSeconds: TimeInterval = 0
    ) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.diskWrittenBytes = diskWrittenBytes
        self.uptimeSeconds = uptimeSeconds
    }
}

// MARK: - Network & Disk Models

public struct NetworkStats: Sendable, Equatable {
    public let rxRate: Double
    public let txRate: Double
    public let rxTotal: UInt64
    public let txTotal: UInt64
    public let activeInterface: String
    public let localIP: String

    public init(
        rxRate: Double = 0,
        txRate: Double = 0,
        rxTotal: UInt64 = 0,
        txTotal: UInt64 = 0,
        activeInterface: String = "en0",
        localIP: String = "—"
    ) {
        self.rxRate = rxRate
        self.txRate = txRate
        self.rxTotal = rxTotal
        self.txTotal = txTotal
        self.activeInterface = activeInterface
        self.localIP = localIP
    }
}

public struct DiskStats: Sendable, Equatable {
    public let readRate: Double
    public let writeRate: Double
    public let totalRead: UInt64
    public let totalWrite: UInt64
    public let totalSpace: UInt64
    public let freeSpace: UInt64

    public var usedSpace: UInt64 {
        totalSpace > freeSpace ? totalSpace - freeSpace : 0
    }

    public var usedFraction: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }

    public init(
        readRate: Double = 0,
        writeRate: Double = 0,
        totalRead: UInt64 = 0,
        totalWrite: UInt64 = 0,
        totalSpace: UInt64 = 0,
        freeSpace: UInt64 = 0
    ) {
        self.readRate = readRate
        self.writeRate = writeRate
        self.totalRead = totalRead
        self.totalWrite = totalWrite
        self.totalSpace = totalSpace
        self.freeSpace = freeSpace
    }
}

// MARK: - Thermal & Sensor Models

public enum SensorCategory: String, Sendable, Codable, CaseIterable {
    case cpu = "CPU / SoC"
    case gpu = "GPU Cluster"
    case memory = "Memory / ANE"
    case storage = "NVMe Storage"
    case battery = "Battery / PMU"
    case ambient = "System Enclosure"
}

public struct SensorReading: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let category: SensorCategory
    public let celsius: Double

    public init(id: String, name: String, category: SensorCategory, celsius: Double) {
        self.id = id
        self.name = name
        self.category = category
        self.celsius = celsius
    }
}

public struct FanReading: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let rpm: Int
    public let minRPM: Int
    public let maxRPM: Int

    public var loadPercent: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max(Double(rpm - minRPM) / Double(maxRPM - minRPM) * 100.0, 0), 100)
    }

    public init(id: Int, name: String, rpm: Int, minRPM: Int = 1000, maxRPM: Int = 5500) {
        self.id = id
        self.name = name
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public enum ThermalLevel: Int, Sendable, Codable, Comparable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Warm"
        case .serious: return "Throttling"
        case .critical: return "Critical"
        }
    }
}

public struct ThermalStats: Sendable, Equatable {
    public let state: ThermalLevel
    public let socTemp: Double
    public let socMax: Double
    public let gpuTemp: Double?
    public let ssdTemp: Double?
    public let batteryTemp: Double?
    public let sensors: [SensorReading]
    public let fans: [FanReading]

    public init(
        state: ThermalLevel = .nominal,
        socTemp: Double = 42,
        socMax: Double = 45,
        gpuTemp: Double? = nil,
        ssdTemp: Double? = nil,
        batteryTemp: Double? = nil,
        sensors: [SensorReading] = [],
        fans: [FanReading] = []
    ) {
        self.state = state
        self.socTemp = socTemp
        self.socMax = socMax
        self.gpuTemp = gpuTemp
        self.ssdTemp = ssdTemp
        self.batteryTemp = batteryTemp
        self.sensors = sensors
        self.fans = fans
    }
}

// MARK: - Process & AppGroup Models

public struct TrailPoint: Sendable, Equatable {
    public let timestamp: Date
    public let memory: UInt64

    public init(timestamp: Date, memory: UInt64) {
        self.timestamp = timestamp
        self.memory = memory
    }
}

public struct OpenPortInfo: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { "\(proto):\(localPort)->\(remoteEndpoint)" }
    public let proto: String
    public let localAddress: String
    public let localPort: UInt16
    public let remoteEndpoint: String
    public let state: String

    public init(
        proto: String,
        localAddress: String,
        localPort: UInt16,
        remoteEndpoint: String = "*:*",
        state: String = "LISTEN"
    ) {
        self.proto = proto
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteEndpoint = remoteEndpoint
        self.state = state
    }
}

public struct ProcInfo: Identifiable, Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let responsiblePID: Int32
    public let name: String
    public let bundleID: String?
    public let executablePath: String?
    public let user: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let energyImpact: Double
    public let diskReadRate: Double
    public let diskWriteRate: Double
    public let wakeupsPerSec: Double
    public let threadCount: Int
    public let isApp: Bool
    public let isSuspended: Bool
    public let openPorts: [OpenPortInfo]

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        ppid: Int32,
        responsiblePID: Int32,
        name: String,
        bundleID: String? = nil,
        executablePath: String? = nil,
        user: String = "root",
        cpuPercent: Double = 0,
        memoryBytes: UInt64 = 0,
        energyImpact: Double = 0,
        diskReadRate: Double = 0,
        diskWriteRate: Double = 0,
        wakeupsPerSec: Double = 0,
        threadCount: Int = 1,
        isApp: Bool = false,
        isSuspended: Bool = false,
        openPorts: [OpenPortInfo] = []
    ) {
        self.pid = pid
        self.ppid = ppid
        self.responsiblePID = responsiblePID
        self.name = name
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.user = user
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.energyImpact = energyImpact
        self.diskReadRate = diskReadRate
        self.diskWriteRate = diskWriteRate
        self.wakeupsPerSec = wakeupsPerSec
        self.threadCount = threadCount
        self.isApp = isApp
        self.isSuspended = isSuspended
        self.openPorts = openPorts
    }
}

public struct AppGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let rootPID: Int32
    public let name: String
    public let bundleID: String?
    public let bundlePath: String?
    public let isApp: Bool
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let energyImpact: Double
    public let diskReadRate: Double
    public let diskWriteRate: Double
    public let wakeupsPerSec: Double
    public let processCount: Int
    public let children: [ProcInfo]
    public let memoryTrail: [TrailPoint]
    public let openPorts: [OpenPortInfo]

    public var memoryGrowthBytes: Int64 {
        guard let first = memoryTrail.first, let last = memoryTrail.last else { return 0 }
        return Int64(last.memory) - Int64(first.memory)
    }

    public init(
        id: String,
        rootPID: Int32,
        name: String,
        bundleID: String? = nil,
        bundlePath: String? = nil,
        isApp: Bool = false,
        cpuPercent: Double = 0,
        memoryBytes: UInt64 = 0,
        energyImpact: Double = 0,
        diskReadRate: Double = 0,
        diskWriteRate: Double = 0,
        wakeupsPerSec: Double = 0,
        processCount: Int = 1,
        children: [ProcInfo] = [],
        memoryTrail: [TrailPoint] = [],
        openPorts: [OpenPortInfo] = []
    ) {
        self.id = id
        self.rootPID = rootPID
        self.name = name
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.isApp = isApp
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.energyImpact = energyImpact
        self.diskReadRate = diskReadRate
        self.diskWriteRate = diskWriteRate
        self.wakeupsPerSec = wakeupsPerSec
        self.processCount = processCount
        self.children = children
        self.memoryTrail = memoryTrail
        self.openPorts = openPorts
    }
}

// MARK: - Complete System Snapshot & TimeSeries

public struct TelemetrySnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let cpu: CPUSample
    public let memory: MemoryStats
    public let gpu: GPUStats
    public let battery: BatteryStats
    public let thermal: ThermalStats
    public let network: NetworkStats
    public let disk: DiskStats
    public let processes: [ProcInfo]
    public let appGroups: [AppGroup]
    public let selfCost: SelfCost
    public let helperActive: Bool

    public init(
        timestamp: Date = Date(),
        cpu: CPUSample = CPUSample(),
        memory: MemoryStats = MemoryStats(),
        gpu: GPUStats = GPUStats(),
        battery: BatteryStats = BatteryStats(),
        thermal: ThermalStats = ThermalStats(),
        network: NetworkStats = NetworkStats(),
        disk: DiskStats = DiskStats(),
        processes: [ProcInfo] = [],
        appGroups: [AppGroup] = [],
        selfCost: SelfCost = SelfCost(),
        helperActive: Bool = false
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.battery = battery
        self.thermal = thermal
        self.network = network
        self.disk = disk
        self.processes = processes
        self.appGroups = appGroups
        self.selfCost = selfCost
        self.helperActive = helperActive
    }
}

public struct TimePoint: Identifiable, Sendable, Equatable {
    public let timestamp: Date
    public let value: Double
    public var id: TimeInterval { timestamp.timeIntervalSince1970 }

    public init(timestamp: Date, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

public struct CoreSeries: Identifiable, Sendable, Equatable {
    public let id: Int
    public let type: CoreType
    public let currentUsage: Double
    public let points: [TimePoint]

    public init(id: Int, type: CoreType, currentUsage: Double, points: [TimePoint]) {
        self.id = id
        self.type = type
        self.currentUsage = currentUsage
        self.points = points
    }
}
