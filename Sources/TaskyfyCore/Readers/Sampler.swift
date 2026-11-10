import Foundation
import Darwin
import IOKit

public final class Sampler: @unchecked Sendable {
    private let cpuReader = CPUReader()
    private let networkReader = NetworkReader()
    private let diskReader = DiskReader()
    private let sensorReader = SensorReader()
    private let processReader = ProcessReader()
    private let totalPhysicalMemory: UInt64

    public init() {
        var memSize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memSize, &size, nil, 0) == 0, memSize > 0 {
            self.totalPhysicalMemory = memSize
        } else {
            self.totalPhysicalMemory = ProcessInfo.processInfo.physicalMemory
        }
    }

    public func takeSnapshot(selectedPID: Int32? = nil) -> TelemetrySnapshot {
        HelperClient.shared.pollAsync()
        let helperRecords = HelperClient.shared.cachedRecords()
        let helperResponding = HelperClient.shared.isResponding

        let cpu = cpuReader.sample()
        let mem = Self.readMemoryStats(totalPhysical: totalPhysicalMemory)
        let gpu = Self.readGPUStats()
        let battery = Self.readBatteryStats(cpuLoad: cpu.totalUsage, gpuLoad: gpu.utilization)
        let thermal = sensorReader.sample(
            cpuLoadPercent: cpu.totalUsage,
            batteryTemp: battery.temperature > 0 ? battery.temperature : nil
        )
        let net = networkReader.sample()
        let disk = diskReader.sample()
        let (procs, groups, selfCost) = processReader.sample(
            helperRecords: helperRecords,
            selectedPID: selectedPID
        )

        return TelemetrySnapshot(
            timestamp: Date(),
            cpu: cpu,
            memory: mem,
            gpu: gpu,
            battery: battery,
            thermal: thermal,
            network: net,
            disk: disk,
            processes: procs,
            appGroups: groups,
            selfCost: selfCost,
            helperActive: helperResponding
        )
    }

    // MARK: - MemoryStats Reader

    public static func readMemoryStats(totalPhysical: UInt64) -> MemoryStats {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(max(4096, Int(pageSize)))

        guard kr == KERN_SUCCESS else {
            return MemoryStats(total: totalPhysical)
        }

        let wired = UInt64(vmStats.wire_count) &* pageBytes
        let compressed = UInt64(vmStats.compressor_page_count) &* pageBytes
        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        let appPages = internalPages > purgeablePages ? (internalPages - purgeablePages) : internalPages
        let app = appPages &* pageBytes
        let cached = (UInt64(vmStats.external_page_count) &+ purgeablePages) &* pageBytes

        let used = min(totalPhysical, app &+ wired &+ compressed)
        let free = totalPhysical > used ? (totalPhysical - used) : 0

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let (swapUsed, swapTotal): (UInt64, UInt64)
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsed = swapUsage.xsu_used
            swapTotal = swapUsage.xsu_total
        } else {
            swapUsed = 0
            swapTotal = 0
        }

        let vmPressureRaw = CPUReader.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
        let pressureLevel: PressureLevel
        switch vmPressureRaw {
        case 4...:
            pressureLevel = .critical
        case 2...3:
            pressureLevel = .warning
        default:
            pressureLevel = .normal
        }

        let memStatusLevel = CPUReader.sysctlInt("kern.memorystatus_level")
        let pressurePercent: Double
        if let freeLevel = memStatusLevel, freeLevel >= 0 && freeLevel <= 100 {
            pressurePercent = min(max(100.0 - Double(freeLevel), 0), 100)
        } else {
            let compressedRatio = totalPhysical > 0 ? (Double(compressed + wired) / Double(totalPhysical)) * 100.0 : 0
            pressurePercent = min(max(compressedRatio, 5), 100)
        }

        return MemoryStats(
            total: totalPhysical,
            used: used,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            free: free,
            swapUsed: swapUsed,
            swapTotal: swapTotal,
            pressure: pressurePercent,
            pressureLevel: pressureLevel
        )
    }

    // MARK: - GPUStats Reader

    public static func readGPUStats() -> GPUStats {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return GPUStats()
        }
        defer { IOObjectRelease(iterator) }

        var maxDeviceUtil: Double = 0
        var maxRendererUtil: Double = 0
        var maxTilerUtil: Double = 0
        var inUseMem: UInt64 = 0
        var model = "Apple Silicon GPU"

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let m = props["model"] as? String, !m.isEmpty {
                model = m
            }
            if let perf = props["PerformanceStatistics"] as? [String: Any] {
                if let dev = (perf["Device Utilization %"] as? NSNumber)?.doubleValue {
                    maxDeviceUtil = max(maxDeviceUtil, dev)
                }
                if let ren = (perf["Renderer Utilization %"] as? NSNumber)?.doubleValue {
                    maxRendererUtil = max(maxRendererUtil, ren)
                }
                if let til = (perf["Tiler Utilization %"] as? NSNumber)?.doubleValue {
                    maxTilerUtil = max(maxTilerUtil, til)
                }
                if let mem = (perf["In use system memory"] as? NSNumber)?.uint64Value {
                    inUseMem = max(inUseMem, mem)
                }
            }
        }

        return GPUStats(
            utilization: min(max(maxDeviceUtil, 0), 100),
            rendererUtilization: min(max(maxRendererUtil, 0), 100),
            tilerUtilization: min(max(maxTilerUtil, 0), 100),
            inUseSystemMemory: inUseMem,
            modelName: model
        )
    }

    // MARK: - BatteryStats Reader

    public static func readBatteryStats(cpuLoad: Double, gpuLoad: Double) -> BatteryStats {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            let estimatedWatts = 4.5 + (cpuLoad / 100.0) * 18.0 + (gpuLoad / 100.0) * 12.0
            return BatteryStats(
                hasBattery: false,
                isCharging: false,
                isPluggedIn: true,
                percentage: 100,
                watts: estimatedWatts
            )
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return BatteryStats()
        }

        let isPlugged = (props["ExternalConnected"] as? Bool) ?? false
        let isCharging = (props["IsCharging"] as? Bool) ?? false
        let currentCap = (props["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 100
        let maxCap = (props["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100

        let pct: Double
        if maxCap > 0 && currentCap <= maxCap && maxCap <= 100 {
            pct = currentCap
        } else if maxCap > 100 {
            pct = min(max((currentCap / maxCap) * 100.0, 0), 100)
        } else {
            pct = min(max(currentCap, 0), 100)
        }

        let nominalCap = (props["NominalChargeCapacity"] as? NSNumber)?.doubleValue
            ?? (props["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? 0
        let designCap = (props["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0
        let health: Double
        if nominalCap > 0 && designCap > 0 {
            health = min(max((nominalCap / designCap) * 100.0, 50), 100)
        } else {
            health = 100
        }

        let cycles = (props["CycleCount"] as? NSNumber)?.intValue ?? 0
        let rawTemp = (props["Temperature"] as? NSNumber)?.doubleValue ?? 0
        let tempC: Double
        if rawTemp > 2000 {
            // Either centi-Kelvin or centi-Celsius
            let cCandidate = rawTemp / 100.0
            tempC = cCandidate > 80 ? (rawTemp / 10.0 - 273.15) : cCandidate
        } else {
            tempC = 31.0
        }

        let amperageMA = (props["InstantAmperage"] as? NSNumber)?.doubleValue ?? 0
        let voltageMV = (props["Voltage"] as? NSNumber)?.doubleValue ?? 0
        var watts = abs(amperageMA * voltageMV) / 1_000_000.0
        if watts < 0.5 || watts > 240.0 {
            if let telemetry = props["PowerTelemetryData"] as? [String: Any],
               let sysPowerMW = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue,
               sysPowerMW > 100 && sysPowerMW < 240_000 {
                watts = sysPowerMW / 1000.0
            } else {
                watts = 3.8 + (cpuLoad / 100.0) * 16.0 + (gpuLoad / 100.0) * 10.0
            }
        }

        var adapterW = 0
        if let adapter = props["AdapterDetails"] as? [String: Any],
           let w = (adapter["Watts"] as? NSNumber)?.intValue {
            adapterW = w
        }

        let timeRemRaw = (props["TimeRemaining"] as? NSNumber)?.intValue ?? -1
        let timeRem: Int? = (timeRemRaw > 0 && timeRemRaw < 3000) ? timeRemRaw : nil

        return BatteryStats(
            hasBattery: true,
            isCharging: isCharging,
            isPluggedIn: isPlugged,
            percentage: pct,
            watts: watts,
            adapterWatts: adapterW,
            timeRemainingMinutes: timeRem,
            healthPercent: health,
            cycleCount: cycles,
            temperature: max(15, min(tempC, 90))
        )
    }
}
