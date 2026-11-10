import Foundation
import Darwin
import TaskyfyCore

final class IdleExit: @unchecked Sendable {
    static let shared = IdleExit(timeout: 120.0)

    private let timeout: TimeInterval
    private let lock = NSLock()
    private var lastActivity: CFAbsoluteTime
    private let timer: DispatchSourceTimer

    init(timeout: TimeInterval) {
        self.timeout = timeout
        self.lastActivity = CFAbsoluteTimeGetCurrent()
        self.timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        self.timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
        self.timer.setEventHandler { [weak self] in
            self?.checkIdle()
        }
        self.timer.resume()
    }

    func touch() {
        lock.lock()
        lastActivity = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }

    private func checkIdle() {
        lock.lock()
        let elapsed = CFAbsoluteTimeGetCurrent() - lastActivity
        lock.unlock()
        if elapsed > timeout {
            exit(0)
        }
    }
}

final class HelperService: NSObject, TaskyfyHelperProtocol {
    func protocolVersion(withReply reply: @escaping (Int) -> Void) {
        IdleExit.shared.touch()
        reply(1)
    }

    func sampleProcesses(withReply reply: @escaping (Data) -> Void) {
        IdleExit.shared.touch()

        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else {
            reply(Data())
            return
        }

        let capacity = Int(estimatedCount) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let bytesWritten = proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.stride))
        guard bytesWritten > 0 else {
            reply(Data())
            return
        }

        let count = min(capacity, Int(bytesWritten))
        var pidList = Array(pids.prefix(count))
        if !pidList.contains(0) {
            pidList.insert(0, at: 0)
        }

        var records: [RawProcRecord] = []
        records.reserveCapacity(pidList.count)

        for pid in pidList where pid >= 0 {
            var ri = rusage_info_v6()
            let res = withUnsafeMutablePointer(to: &ri) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, rebound)
                }
            }
            guard res == 0 else { continue }

            records.append(
                RawProcRecord(
                    pid: pid,
                    reserved: 0,
                    userTime: ri.ri_user_time,
                    systemTime: ri.ri_system_time,
                    footprint: ri.ri_phys_footprint,
                    energy: ri.ri_user_time &+ ri.ri_system_time,
                    diskRead: ri.ri_diskio_bytesread,
                    diskWrite: ri.ri_diskio_byteswritten,
                    wakeups: ri.ri_interrupt_wkups
                )
            )
        }

        reply(HelperClient.encodeRecords(records))
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        IdleExit.shared.touch()
        newConnection.exportedInterface = NSXPCInterface(with: TaskyfyHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperClient.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
