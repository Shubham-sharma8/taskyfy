import Foundation
import Darwin
import AppKit

public final class ProcessReader: @unchecked Sendable {
    private struct PrevProc {
        let cpuNs: UInt64
        let diskRead: UInt64
        let diskWrite: UInt64
        let wakeups: UInt64
        let timestamp: TimeInterval
    }

    private struct CachedStatic {
        let name: String
        let path: String?
        let bundleID: String?
        let bundlePath: String?
        let user: String
        let responsiblePID: Int32
        let isApp: Bool
    }

    private var prevByPID: [Int32: PrevProc] = [:]
    private var staticCache: [Int32: CachedStatic] = [:]
    private var userCache: [uid_t: String] = [:]
    private var trailsByGroup: [String: [TrailPoint]] = [:]
    private var portCacheByPID: [Int32: [OpenPortInfo]] = [:]
    private var lastPortSweepTime: TimeInterval = 0
    private let myUID: uid_t = getuid()
    private let timebaseNumer: UInt64
    private let timebaseDenom: UInt64
    private let responsibilityFn: (@convention(c) (pid_t) -> pid_t)?

    public init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        self.timebaseNumer = UInt64(max(1, tb.numer))
        self.timebaseDenom = UInt64(max(1, tb.denom))

        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") {
            self.responsibilityFn = unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)
        } else {
            self.responsibilityFn = nil
        }
    }

    public func sample(helperRecords: [Int32: RawProcRecord] = [:], selectedPID: Int32? = nil) -> ([ProcInfo], [AppGroup], SelfCost) {
        let now = ProcessInfo.processInfo.systemUptime
        let wallNow = Date()
        let myPID = getpid()

        // Map NSWorkspace running applications by PID for rich display names and bundle IDs
        var runningApps: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            runningApps[app.processIdentifier] = app
        }

        let kprocs = Self.fetchKinfoProcs()
        let shouldSweepPorts = (now - lastPortSweepTime) >= 6.0
        if shouldSweepPorts {
            lastPortSweepTime = now
        }
        var nextPrev: [Int32: PrevProc] = [:]
        nextPrev.reserveCapacity(kprocs.count)

        var procs: [ProcInfo] = []
        procs.reserveCapacity(kprocs.count)

        var selfCost = SelfCost()
        var alivePIDs = Set<Int32>()

        for kp in kprocs {
            let pid = kp.kp_proc.p_pid
            guard pid >= 0 else { continue }
            alivePIDs.insert(pid)
            let ppid = kp.kp_eproc.e_ppid
            let uid = kp.kp_eproc.e_ucred.cr_uid
            let isStopped = (kp.kp_proc.p_stat == SSTOP)

            let meta = resolveStatic(pid: pid, kp: kp, uid: uid, runningApps: runningApps)

            // Collect rusage either from proc_pid_rusage or HelperClient XPC
            var userNs: UInt64 = 0
            var sysNs: UInt64 = 0
            var footprint: UInt64 = 0
            var diskR: UInt64 = 0
            var diskW: UInt64 = 0
            var wakeups: UInt64 = 0
            var threadCount: Int = 1

            var ri = rusage_info_v6()
            let rRes = withUnsafeMutablePointer(to: &ri) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, rebound)
                }
            }

            if rRes == 0 {
                userNs = (ri.ri_user_time &* timebaseNumer) / timebaseDenom
                sysNs = (ri.ri_system_time &* timebaseNumer) / timebaseDenom
                footprint = ri.ri_phys_footprint
                diskR = ri.ri_diskio_bytesread
                diskW = ri.ri_diskio_byteswritten
                wakeups = ri.ri_interrupt_wkups
            } else if let helperRec = helperRecords[pid] {
                userNs = (helperRec.userTime &* timebaseNumer) / timebaseDenom
                sysNs = (helperRec.systemTime &* timebaseNumer) / timebaseDenom
                footprint = helperRec.footprint
                diskR = helperRec.diskRead
                diskW = helperRec.diskWrite
                wakeups = helperRec.wakeups
            } else {
                var ti = proc_taskinfo()
                let tSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.stride))
                if tSize == Int32(MemoryLayout<proc_taskinfo>.stride) {
                    userNs = (ti.pti_total_user &* timebaseNumer) / timebaseDenom
                    sysNs = (ti.pti_total_system &* timebaseNumer) / timebaseDenom
                    footprint = ti.pti_resident_size
                    threadCount = max(1, Int(ti.pti_threadnum))
                }
            }

            if pid == selectedPID && threadCount == 1 {
                var ti = proc_taskinfo()
                if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.stride)) == Int32(MemoryLayout<proc_taskinfo>.stride) {
                    threadCount = max(1, Int(ti.pti_threadnum))
                }
            }

            let totalCpuNs = userNs &+ sysNs
            var cpuPct: Double = 0
            var readRate: Double = 0
            var writeRate: Double = 0
            var wakeupRate: Double = 0

            if let prev = prevByPID[pid] {
                let dt = max(0.05, now - prev.timestamp)
                if totalCpuNs >= prev.cpuNs {
                    cpuPct = (Double(totalCpuNs - prev.cpuNs) / (dt * 1_000_000_000.0)) * 100.0
                }
                if diskR >= prev.diskRead {
                    readRate = Double(diskR - prev.diskRead) / dt
                }
                if diskW >= prev.diskWrite {
                    writeRate = Double(diskW - prev.diskWrite) / dt
                }
                if wakeups >= prev.wakeups {
                    wakeupRate = Double(wakeups - prev.wakeups) / dt
                }
            }

            nextPrev[pid] = PrevProc(
                cpuNs: totalCpuNs,
                diskRead: diskR,
                diskWrite: diskW,
                wakeups: wakeups,
                timestamp: now
            )

            // Energy impact proxy matching macOS Activity Monitor heuristics (CPU + wakeups + disk I/O)
            let energyImpact = min(999.0, cpuPct * 0.85 + wakeupRate * 0.015 + ((readRate + writeRate) / (1024 * 1024)) * 0.4)

            let ports: [OpenPortInfo]
            if pid == selectedPID || meta.responsiblePID == selectedPID || (shouldSweepPorts && uid == myUID) {
                let scanned = Self.inspectOpenSockets(pid: pid)
                if scanned.isEmpty {
                    portCacheByPID.removeValue(forKey: pid)
                } else {
                    portCacheByPID[pid] = scanned
                }
                ports = scanned
            } else {
                ports = portCacheByPID[pid] ?? []
            }

            let info = ProcInfo(
                pid: pid,
                ppid: ppid,
                responsiblePID: meta.responsiblePID,
                name: meta.name,
                bundleID: meta.bundleID,
                executablePath: meta.path,
                user: meta.user,
                cpuPercent: cpuPct,
                memoryBytes: footprint,
                energyImpact: energyImpact,
                diskReadRate: readRate,
                diskWriteRate: writeRate,
                wakeupsPerSec: wakeupRate,
                threadCount: threadCount,
                isApp: meta.isApp,
                isSuspended: isStopped,
                openPorts: ports
            )
            procs.append(info)

            if pid == myPID {
                selfCost = SelfCost(
                    cpuPercent: cpuPct,
                    memoryBytes: footprint,
                    diskWrittenBytes: diskW,
                    uptimeSeconds: now
                )
            }
        }

        prevByPID = nextPrev
        if staticCache.count > alivePIDs.count + 200 {
            staticCache = staticCache.filter { alivePIDs.contains($0.key) }
        }

        let groups = buildAppGroups(from: procs, runningApps: runningApps, now: wallNow)
        return (procs, groups, selfCost)
    }

    // MARK: - AppGroup Aggregation

    private func buildAppGroups(
        from procs: [ProcInfo],
        runningApps: [Int32: NSRunningApplication],
        now: Date
    ) -> [AppGroup] {
        let procByPID = Dictionary(uniqueKeysWithValues: procs.map { ($0.pid, $0) })
        var buckets: [String: [ProcInfo]] = [:]
        var groupMeta: [String: (rootPID: Int32, name: String, bundleID: String?, bundlePath: String?, isApp: Bool)] = [:]

        for proc in procs {
            let rpid = proc.responsiblePID
            let leader = procByPID[rpid] ?? proc
            let rApp = runningApps[rpid] ?? runningApps[proc.pid]

            let key: String
            let groupName: String
            let bundleID: String?
            let bundlePath: String?
            let isApp: Bool

            if let rApp, rApp.activationPolicy == .regular || rApp.bundleIdentifier != nil {
                bundleID = rApp.bundleIdentifier ?? leader.bundleID
                bundlePath = rApp.bundleURL?.path
                groupName = rApp.localizedName ?? leader.name
                key = bundleID ?? "pid:\(rApp.processIdentifier)"
                isApp = rApp.activationPolicy == .regular || (bundlePath?.hasSuffix(".app") == true)
            } else {
                bundleID = leader.bundleID
                bundlePath = Self.extractAppBundlePath(from: leader.executablePath)
                groupName = leader.name
                key = bundleID ?? bundlePath ?? "proc:\(leader.name):\(leader.pid)"
                isApp = leader.isApp
            }

            buckets[key, default: []].append(proc)
            if groupMeta[key] == nil || proc.pid == rpid {
                groupMeta[key] = (rpid, groupName, bundleID, bundlePath, isApp)
            }
        }

        let cutoff = now.addingTimeInterval(-15 * 60)
        var groups: [AppGroup] = []
        groups.reserveCapacity(buckets.count)

        for (key, members) in buckets {
            guard let meta = groupMeta[key] else { continue }
            let totalCPU = members.reduce(0.0) { $0 + $1.cpuPercent }
            let totalMem = members.reduce(UInt64(0)) { $0 &+ $1.memoryBytes }
            let totalEnergy = members.reduce(0.0) { $0 + $1.energyImpact }
            let totalRead = members.reduce(0.0) { $0 + $1.diskReadRate }
            let totalWrite = members.reduce(0.0) { $0 + $1.diskWriteRate }
            let totalWakeups = members.reduce(0.0) { $0 + $1.wakeupsPerSec }

            var trail = trailsByGroup[key] ?? []
            if let last = trail.last {
                if now.timeIntervalSince(last.timestamp) >= 10.0 {
                    trail.append(TrailPoint(timestamp: now, memory: totalMem))
                }
            } else {
                trail.append(TrailPoint(timestamp: now, memory: totalMem))
            }
            trail.removeAll { $0.timestamp < cutoff }
            trailsByGroup[key] = trail

            let sortedChildren = members.sorted { $0.memoryBytes > $1.memoryBytes }
            let combinedPorts = Array(Set(members.flatMap(\.openPorts))).sorted { $0.localPort < $1.localPort }

            groups.append(
                AppGroup(
                    id: key,
                    rootPID: meta.rootPID,
                    name: meta.name,
                    bundleID: meta.bundleID,
                    bundlePath: meta.bundlePath,
                    isApp: meta.isApp,
                    cpuPercent: totalCPU,
                    memoryBytes: totalMem,
                    energyImpact: totalEnergy,
                    diskReadRate: totalRead,
                    diskWriteRate: totalWrite,
                    wakeupsPerSec: totalWakeups,
                    processCount: members.count,
                    children: sortedChildren,
                    memoryTrail: trail,
                    openPorts: combinedPorts
                )
            )
        }

        return groups.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    // MARK: - Static Metadata Resolution

    private func resolveStatic(
        pid: Int32,
        kp: kinfo_proc,
        uid: uid_t,
        runningApps: [Int32: NSRunningApplication]
    ) -> CachedStatic {
        if let cached = staticCache[pid] {
            return cached
        }

        let path = Self.pidPath(pid: pid)
        let app = runningApps[pid]
        let commName: String = withUnsafePointer(to: kp.kp_proc.p_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                String(cString: cStr)
            }
        }

        let lastPathName = path.map { ($0 as NSString).lastPathComponent }
        let name = app?.localizedName ?? lastPathName ?? (commName.isEmpty ? "pid-\(pid)" : commName)
        let bundlePath = app?.bundleURL?.path ?? Self.extractAppBundlePath(from: path)
        let bundleID = app?.bundleIdentifier

        let rpid: Int32
        if let fn = responsibilityFn {
            let resolved = fn(pid)
            rpid = resolved > 0 ? resolved : pid
        } else {
            rpid = pid
        }

        let userName: String
        if let u = userCache[uid] {
            userName = u
        } else if let pw = getpwuid(uid), let namePtr = pw.pointee.pw_name {
            let resolvedUser = String(cString: namePtr)
            userCache[uid] = resolvedUser
            userName = resolvedUser
        } else {
            userName = uid == 0 ? "root" : "\(uid)"
        }

        let isApp = (app?.activationPolicy == .regular) || (bundlePath?.hasPrefix("/Applications/") == true) || (bundlePath?.hasPrefix("/System/Applications/") == true)

        let entry = CachedStatic(
            name: name,
            path: path,
            bundleID: bundleID,
            bundlePath: bundlePath,
            user: userName,
            responsiblePID: rpid,
            isApp: isApp
        )
        staticCache[pid] = entry
        return entry
    }

    private static func pidPath(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return nil }
        return String(cString: buf)
    }

    private static func extractAppBundlePath(from execPath: String?) -> String? {
        guard let execPath else { return nil }
        if let range = execPath.range(of: ".app/Contents/MacOS/") {
            return String(execPath[..<range.lowerBound]) + ".app"
        }
        return nil
    }

    private static func fetchKinfoProcs() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }
        let count = (size / MemoryLayout<kinfo_proc>.stride) + 32
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var actualSize = count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &buffer, &actualSize, nil, 0) == 0 else {
            return []
        }
        let actualCount = actualSize / MemoryLayout<kinfo_proc>.stride
        return Array(buffer.prefix(actualCount))
    }

    // MARK: - Open Socket / Port Inspection

    public static func inspectOpenSockets(pid: Int32) -> [OpenPortInfo] {
        guard pid > 0 else { return [] }
        let byteSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard byteSize > 0 else { return [] }

        let fdCount = Int(byteSize) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actualBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, byteSize)
        guard actualBytes > 0 else { return [] }

        let actualCount = Int(actualBytes) / MemoryLayout<proc_fdinfo>.stride
        var ports: [OpenPortInfo] = []
        var seen = Set<String>()

        for i in 0..<min(actualCount, 96) {
            let fd = fds[i]
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }
            var sockInfo = socket_fdinfo()
            let sBytes = proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &sockInfo,
                Int32(MemoryLayout<socket_fdinfo>.stride)
            )
            guard sBytes == Int32(MemoryLayout<socket_fdinfo>.stride) else { continue }

            let family = sockInfo.psi.soi_family
            guard family == AF_INET || family == AF_INET6 else { continue }

            let kind = sockInfo.psi.soi_kind
            guard kind == SOCKINFO_TCP || kind == SOCKINFO_IN else { continue }

            let inInfo: in_sockinfo
            let stateName: String
            let protoName: String

            if kind == SOCKINFO_TCP {
                inInfo = sockInfo.psi.soi_proto.pri_tcp.tcpsi_ini
                protoName = family == AF_INET6 ? "TCP6" : "TCP"
                let st = sockInfo.psi.soi_proto.pri_tcp.tcpsi_state
                stateName = st == TSI_S_LISTEN ? "LISTEN" : (st == TSI_S_ESTABLISHED ? "ESTABLISHED" : "ACTIVE")
            } else {
                inInfo = sockInfo.psi.soi_proto.pri_in
                protoName = family == AF_INET6 ? "UDP6" : "UDP"
                stateName = "OPEN"
            }

            let lport = UInt16(bigEndian: UInt16(truncatingIfNeeded: inInfo.insi_lport))
            let fport = UInt16(bigEndian: UInt16(truncatingIfNeeded: inInfo.insi_fport))
            guard lport > 0 else { continue }

            let remote = fport > 0 ? "*:\(fport)" : "*:*"
            let info = OpenPortInfo(
                proto: protoName,
                localAddress: family == AF_INET6 ? "::" : "0.0.0.0",
                localPort: lport,
                remoteEndpoint: remote,
                state: stateName
            )
            if !seen.contains(info.id) {
                seen.insert(info.id)
                ports.append(info)
            }
        }
        return ports.sorted { $0.localPort < $1.localPort }
    }

    // MARK: - Process Actions

    @discardableResult
    public static func terminate(pid: Int32, force: Bool = false) -> Bool {
        guard pid > 1 else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) {
            if force {
                if app.forceTerminate() { return true }
            } else {
                if app.terminate() { return true }
            }
        }
        let sig = force ? SIGKILL : SIGTERM
        return Darwin.kill(pid, sig) == 0
    }

    @discardableResult
    public static func setSuspended(pid: Int32, suspend: Bool) -> Bool {
        guard pid > 1 else { return false }
        return Darwin.kill(pid, suspend ? SIGSTOP : SIGCONT) == 0
    }

    @discardableResult
    public static func setPriority(pid: Int32, niceValue: Int32) -> Bool {
        guard pid > 1 else { return false }
        let clamped = min(max(niceValue, -20), 20)
        return setpriority(PRIO_PROCESS, id_t(pid), clamped) == 0
    }
}
