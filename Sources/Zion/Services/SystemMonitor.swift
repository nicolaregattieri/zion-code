import Foundation
import Darwin

/// Lightweight system-wide CPU + memory monitor for the top toolbar.
///
/// Memory: reads `host_statistics64(HOST_VM_INFO64)` (same Mach call as
/// `MemoryMonitor`).
/// CPU: reads `host_statistics(HOST_CPU_LOAD_INFO)` and computes a delta
/// between successive snapshots — single ticks have no meaning, so the
/// monitor returns 0% until at least two samples have been collected.
///
/// Polling runs on the main actor every `pollInterval` seconds. The Mach
/// syscalls are sub-millisecond; no subprocesses are spawned.
@Observable
@MainActor
final class SystemMonitor {

    // MARK: - Observable State

    /// 0...1 — fraction of host CPU time spent in user + system since the
    /// previous sample.
    private(set) var cpuLoad: Double = 0

    /// 0...1 — fraction of physical memory currently used.
    private(set) var memoryPressure: Double = 0

    /// Used physical memory in bytes.
    private(set) var usedBytes: UInt64 = 0

    /// Total physical memory in bytes.
    private(set) var totalBytes: UInt64 = 0

    // MARK: - Private

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let pollInterval: TimeInterval
    @ObservationIgnored private var lastCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    // MARK: - Init

    init(pollInterval: TimeInterval = 2) {
        self.pollInterval = pollInterval
    }

    // MARK: - Public

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 2) * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollOnce() async {
        // Memory — cheap Mach syscall, run inline.
        let mem = Self.readMemory()
        self.totalBytes = mem.total
        self.usedBytes = mem.used
        self.memoryPressure = mem.total == 0 ? 0 : Double(mem.used) / Double(mem.total)

        // CPU — needs delta between two snapshots.
        let now = Self.readCPUTicks()
        if let prev = lastCPUTicks, let n = now {
            let userD = Self.tickDelta(prev.user, n.user)
            let sysD = Self.tickDelta(prev.system, n.system)
            let idleD = Self.tickDelta(prev.idle, n.idle)
            let niceD = Self.tickDelta(prev.nice, n.nice)
            let busy = Double(userD + sysD + niceD)
            let total = busy + Double(idleD)
            cpuLoad = total > 0 ? min(max(busy / total, 0), 1) : 0
        }
        lastCPUTicks = now
    }

    // MARK: - System reads

    private struct MemSnapshot {
        let total: UInt64
        let used: UInt64
    }

    private static func readMemory() -> MemSnapshot {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { ptr in
                host_statistics64(host, Int32(HOST_VM_INFO64), ptr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return MemSnapshot(total: 0, used: 0) }
        // Resolve page size via host_page_size to avoid the concurrency
        // warning on the global `vm_kernel_page_size` extern.
        var pageSizeRaw: vm_size_t = 0
        host_page_size(host, &pageSizeRaw)
        let pageSize = UInt64(pageSizeRaw)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        return MemSnapshot(total: total, used: used)
    }

    private static func readCPUTicks() -> (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)? {
        var size = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { ptr in
                host_statistics(host, Int32(HOST_CPU_LOAD_INFO), ptr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // `truncatingIfNeeded` — never a trapping conversion. The tick counters
        // are monotonic and cross `Int32.max` after ~15 days of uptime on a
        // many-core host, which made a checked `Int32(...)` conversion trap and
        // kill the app on launch.
        return (
            user: UInt32(truncatingIfNeeded: info.cpu_ticks.0),
            system: UInt32(truncatingIfNeeded: info.cpu_ticks.1),
            idle: UInt32(truncatingIfNeeded: info.cpu_ticks.2),
            nice: UInt32(truncatingIfNeeded: info.cpu_ticks.3)
        )
    }

    /// Compute a tick delta that tolerates the UInt32 wraparound that
    /// happens roughly every ~50 days at 100 ticks/sec.
    private static func tickDelta(_ before: UInt32, _ after: UInt32) -> UInt32 {
        after &- before
    }
}
