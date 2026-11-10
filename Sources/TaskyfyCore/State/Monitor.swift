import Foundation
import Observation

@Observable
public final class Monitor: @unchecked Sendable {
    public var snapshot: TelemetrySnapshot = TelemetrySnapshot()
    public var pinnedBaseline: TelemetrySnapshot?
    public var recentEvents: [SystemEvent] = []
    public private(set) var isBackgroundMode: Bool = false

    public var cpuSeries: [TimePoint] = []
    public var memorySeries: [TimePoint] = []
    public var powerSeries: [TimePoint] = []
    public var gpuSeries: [TimePoint] = []
    public var tempSeries: [TimePoint] = []
    public var rxSeries: [TimePoint] = []
    public var txSeries: [TimePoint] = []
    public var diskReadSeries: [TimePoint] = []
    public var diskWriteSeries: [TimePoint] = []
    public var perCoreSeries: [CoreSeries] = []
    public var appSeries: [String: [TimePoint]] = [:]

    public let history: HistoryStore
    public let settings: AppSettings
    private let sampler = Sampler()
    private let minuteAccum = MinuteAccumulator()
    private let eventDetector = EventDetector()
    private let queue = DispatchQueue(label: "app.taskyfy.monitor", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let maxPoints = 90
    public var selectedPIDForDeepScan: Int32?

    public init(history: HistoryStore = HistoryStore(), settings: AppSettings = .shared) {
        self.history = history
        self.settings = settings
    }

    public func start() {
        guard timer == nil else { return }
        // Take two initial samples quickly so delta rates (CPU/Net/Disk) populate immediately
        queue.async { [weak self] in
            guard let self else { return }
            let first = self.sampler.takeSnapshot(selectedPID: self.selectedPIDForDeepScan)
            DispatchQueue.main.async {
                self.apply(first)
            }
            Thread.sleep(forTimeInterval: 0.25)
            let second = self.sampler.takeSnapshot(selectedPID: self.selectedPIDForDeepScan)
            DispatchQueue.main.async {
                self.apply(second)
            }
        }

        scheduleTimer(interval: settings.sampleInterval.rawValue)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        minuteAccum.flushNow(to: history)
    }

    public func updateInterval(_ interval: SampleInterval) {
        if !isBackgroundMode {
            scheduleTimer(interval: interval.rawValue)
        }
    }

    public func setSurfaceVisibility(windowVisible: Bool, popoverVisible: Bool) {
        let shouldBackground = !windowVisible && !popoverVisible
        guard shouldBackground != isBackgroundMode else { return }
        isBackgroundMode = shouldBackground
        let targetInterval = shouldBackground ? max(5.0, settings.sampleInterval.rawValue) : settings.sampleInterval.rawValue
        scheduleTimer(interval: targetInterval)
    }

    public func pinBaseline() {
        pinnedBaseline = snapshot
    }

    public func clearBaseline() {
        pinnedBaseline = nil
    }

    public func refreshNow() {
        let pid = selectedPIDForDeepScan
        queue.async { [weak self] in
            guard let self else { return }
            let snap = self.sampler.takeSnapshot(selectedPID: pid)
            DispatchQueue.main.async {
                self.apply(snap)
            }
        }
    }

    private func scheduleTimer(interval: Double) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let snap = self.sampler.takeSnapshot(selectedPID: self.selectedPIDForDeepScan)
            let detected = self.eventDetector.evaluate(
                snapshot: snap,
                sensitivityMultiplier: self.settings.alertSensitivity.multiplier
            )
            self.minuteAccum.ingest(snap, into: self.history)
            for ev in detected {
                self.history.recordEvent(ev)
                AlertCenter.shared.post(event: ev, enabled: self.settings.notificationsEnabled)
            }
            DispatchQueue.main.async {
                self.apply(snap, newEvents: detected)
            }
        }
        t.resume()
        timer = t
    }

    public func apply(_ snap: TelemetrySnapshot, newEvents: [SystemEvent] = []) {
        snapshot = snap
        let ts = snap.timestamp

        cpuSeries = Self.appendPoint(cpuSeries, ts: ts, val: snap.cpu.totalUsage, maxCount: maxPoints)
        memorySeries = Self.appendPoint(memorySeries, ts: ts, val: snap.memory.usedFraction * 100.0, maxCount: maxPoints)
        powerSeries = Self.appendPoint(powerSeries, ts: ts, val: snap.battery.watts, maxCount: maxPoints)
        gpuSeries = Self.appendPoint(gpuSeries, ts: ts, val: snap.gpu.utilization, maxCount: maxPoints)
        tempSeries = Self.appendPoint(tempSeries, ts: ts, val: snap.thermal.socTemp, maxCount: maxPoints)
        rxSeries = Self.appendPoint(rxSeries, ts: ts, val: snap.network.rxRate, maxCount: maxPoints)
        txSeries = Self.appendPoint(txSeries, ts: ts, val: snap.network.txRate, maxCount: maxPoints)
        diskReadSeries = Self.appendPoint(diskReadSeries, ts: ts, val: snap.disk.readRate, maxCount: maxPoints)
        diskWriteSeries = Self.appendPoint(diskWriteSeries, ts: ts, val: snap.disk.writeRate, maxCount: maxPoints)

        var updatedCores: [CoreSeries] = []
        updatedCores.reserveCapacity(snap.cpu.perCore.count)
        for core in snap.cpu.perCore {
            let existing = perCoreSeries.first(where: { $0.id == core.id })?.points ?? []
            let nextPts = Self.appendPoint(existing, ts: ts, val: core.usage, maxCount: 40)
            updatedCores.append(CoreSeries(id: core.id, type: core.type, currentUsage: core.usage, points: nextPts))
        }
        perCoreSeries = updatedCores

        var nextAppSeries = appSeries
        for grp in snap.appGroups.prefix(25) {
            let existing = nextAppSeries[grp.id] ?? []
            nextAppSeries[grp.id] = Self.appendPoint(existing, ts: ts, val: grp.cpuPercent, maxCount: 45)
        }
        appSeries = nextAppSeries

        if !newEvents.isEmpty {
            recentEvents = Array((newEvents + recentEvents).prefix(50))
        }
    }

    private static func appendPoint(_ array: [TimePoint], ts: Date, val: Double, maxCount: Int) -> [TimePoint] {
        var next = array
        next.append(TimePoint(timestamp: ts, value: val))
        if next.count > maxCount {
            next.removeFirst(next.count - maxCount)
        }
        return next
    }
}
