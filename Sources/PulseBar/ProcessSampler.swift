import Foundation
import Darwin

struct ProcessUsage: Sendable {
    let pid: Int32
    let name: String
    let cpu: Double // Percentage of one logical CPU; may exceed 100% for multithreaded apps.
    let residentBytes: UInt64
}

actor ProcessSampler {
    private struct Counters {
        let cpuTicks: UInt64
        let startSeconds: UInt64
    }

    private var previous: [Int32: Counters] = [:]
    private var previousTime: Date?
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func sample() -> (cpu: [ProcessUsage], memory: [ProcessUsage]) {
        let now = Date()
        // proc_listpids returns a byte count and can grow between sizing and filling.
        let estimate = max(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0) / Int32(MemoryLayout<Int32>.size), 1)
        var pids = [Int32](repeating: 0, count: Int(estimate) + 256)
        let bytes = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        guard bytes > 0 else { return ([], []) }

        var current: [Int32: Counters] = [:]
        var memory: [ProcessUsage] = []
        var cpu: [ProcessUsage] = []
        let interval = previousTime.map { now.timeIntervalSince($0) } ?? 0

        for pid in pids.prefix(Int(bytes) / MemoryLayout<Int32>.size) where pid > 0 {
            var info = proc_taskinfo()
            let result = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(MemoryLayout<proc_taskinfo>.size))
            }
            guard result == MemoryLayout<proc_taskinfo>.size else { continue }

            var bsd = proc_bsdinfo()
            let bsdResult = withUnsafeMutablePointer(to: &bsd) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
            }
            guard bsdResult == MemoryLayout<proc_bsdinfo>.size else { continue }

            let total = info.pti_total_user.addingReportingOverflow(info.pti_total_system)
            guard !total.overflow else { continue }
            let counters = Counters(cpuTicks: total.partialValue, startSeconds: UInt64(bsd.pbi_start_tvsec))
            current[pid] = counters
            var nameBuffer = [CChar](repeating: 0, count: 256)
            let nameLength = nameBuffer.withUnsafeMutableBufferPointer {
                proc_name(pid, $0.baseAddress, UInt32($0.count))
            }
            let name = nameLength > 0
                ? String(decoding: nameBuffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                : "Process \(pid)"
            let displayName = name.isEmpty ? "Process \(pid)" : name
            let resident = info.pti_resident_size
            var percent = 0.0
            if interval > 0, let old = previous[pid], old.startSeconds == counters.startSeconds,
               counters.cpuTicks >= old.cpuTicks {
                // libproc task times are Mach absolute ticks, not nanoseconds.
                let elapsedTicks = Double(counters.cpuTicks - old.cpuTicks)
                let elapsedNanoseconds = elapsedTicks * Double(timebase.numer) / Double(max(timebase.denom, 1))
                percent = elapsedNanoseconds / (interval * 1_000_000_000) * 100
            }
            let usage = ProcessUsage(pid: pid, name: displayName, cpu: percent, residentBytes: resident)
            memory.append(usage)
            if percent > 0 { cpu.append(usage) }
        }
        previous = current
        previousTime = now
        return (
            Array(cpu.sorted { $0.cpu > $1.cpu }.prefix(5)),
            Array(memory.sorted { $0.residentBytes > $1.residentBytes }.prefix(5))
        )
    }
}
