import Foundation
import Darwin
import os.log
import os.signpost

/// Process-level performance monitor for the Zion app.
///
/// Unlike `SystemMonitor` (host-wide CPU + memory), `PerfMonitor` reads
/// metrics scoped to the current process:
/// - RSS (resident set size) via `task_info(MACH_TASK_BASIC_INFO)`
/// - CPU time via `task_info(TASK_THREAD_TIMES_INFO)` (delta between samples)
/// - Thread count via `task_threads`
///
/// When enabled via the `ZION_PERF=1` environment variable, it appends one
/// CSV row per sample to `~/Library/Logs/Zion/perf.log`. Always exposes
/// `OSSignposter` helpers for ad-hoc instrumentation regardless of env var.
///
/// Sampling cost: a few mach syscalls per tick, sub-millisecond. Safe to
/// leave at 5s polling in shipped builds.
@MainActor
final class PerfMonitor {

    static let shared = PerfMonitor()

    static let signpostLog = OSLog(subsystem: "dev.zion.perf", category: .pointsOfInterest)
    static let signposter = OSSignposter(logHandle: signpostLog)

    /// Marks a synchronous block on the points-of-interest signpost log.
    /// Shows up as a range in Instruments' os_signpost track.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    // MARK: - State

    private(set) var rssBytes: UInt64 = 0
    private(set) var cpuPercent: Double = 0
    private(set) var threadCount: Int = 0

    // MARK: - Private

    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval
    private var lastCPUTime: TimeInterval?
    private var lastSampleAt: Date?
    private var csvHandle: FileHandle?
    private var startupAt: Date?
    private var samplesWritten: UInt64 = 0

    private init(pollInterval: TimeInterval = 5) {
        self.pollInterval = pollInterval
    }

    // MARK: - Lifecycle

    /// Boots the monitor when `ZION_PERF=1` is set. No-op otherwise.
    /// Call once at app launch.
    func startIfEnabled() {
        guard ProcessInfo.processInfo.environment["ZION_PERF"] == "1" else { return }
        start()
    }

    func start() {
        guard pollTask == nil else { return }
        startupAt = Date()
        openCSV()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        try? csvHandle?.close()
        csvHandle = nil
    }

    // MARK: - Sampling

    private func pollOnce() async {
        let rss = Self.readRSS()
        let cpuTotal = Self.readCPUSeconds()
        let threads = Self.readThreadCount()
        let now = Date()

        rssBytes = rss
        threadCount = threads

        if let prevCPU = lastCPUTime, let prevAt = lastSampleAt {
            let dCPU = cpuTotal - prevCPU
            let dWall = now.timeIntervalSince(prevAt)
            if dWall > 0 {
                cpuPercent = max(0, min(100 * dCPU / dWall, 100 * Double(ProcessInfo.processInfo.activeProcessorCount)))
            }
        }

        lastCPUTime = cpuTotal
        lastSampleAt = now

        writeCSVRow(at: now)
    }

    // MARK: - CSV

    private func openCSV() {
        let fm = FileManager.default
        guard let logsDir = try? logsDirectory(fm: fm) else { return }
        let path = logsDir.appendingPathComponent("perf.log")
        let isNew = !fm.fileExists(atPath: path.path)
        if isNew {
            fm.createFile(atPath: path.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: path) else { return }
        _ = try? handle.seekToEnd()
        csvHandle = handle
        if isNew {
            write("timestamp,uptime_s,rss_mb,cpu_pct,threads\n")
        } else {
            write("# session start \(ISO8601DateFormatter().string(from: Date()))\n")
        }
    }

    private func logsDirectory(fm: FileManager) throws -> URL {
        let lib = try fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let dir = lib.appendingPathComponent("Logs/Zion", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func writeCSVRow(at date: Date) {
        guard csvHandle != nil else { return }
        let uptime = startupAt.map { date.timeIntervalSince($0) } ?? 0
        let rssMB = Double(rssBytes) / (1024 * 1024)
        let ts = ISO8601DateFormatter().string(from: date)
        let row = String(format: "%@,%.2f,%.2f,%.2f,%d\n", ts, uptime, rssMB, cpuPercent, threadCount)
        write(row)
        samplesWritten &+= 1
        if samplesWritten % 12 == 0 {
            try? csvHandle?.synchronize()
        }
    }

    private func write(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        try? csvHandle?.write(contentsOf: data)
    }

    // MARK: - Mach reads

    private static func readRSS() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    /// Total CPU seconds consumed by this task across all threads
    /// (user + system, live + terminated).
    private static func readCPUSeconds() -> TimeInterval {
        var basic = task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let krBasic = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { ptr in
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), ptr, &basicCount)
            }
        }
        var totalUser: TimeInterval = 0
        var totalSystem: TimeInterval = 0
        if krBasic == KERN_SUCCESS {
            totalUser = TimeInterval(basic.user_time.seconds) + TimeInterval(basic.user_time.microseconds) / 1_000_000
            totalSystem = TimeInterval(basic.system_time.seconds) + TimeInterval(basic.system_time.microseconds) / 1_000_000
        }

        var threadTimes = task_thread_times_info()
        var ttCount = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)
        let krThreads = withUnsafeMutablePointer(to: &threadTimes) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(ttCount)) { ptr in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), ptr, &ttCount)
            }
        }
        if krThreads == KERN_SUCCESS {
            totalUser += TimeInterval(threadTimes.user_time.seconds) + TimeInterval(threadTimes.user_time.microseconds) / 1_000_000
            totalSystem += TimeInterval(threadTimes.system_time.seconds) + TimeInterval(threadTimes.system_time.microseconds) / 1_000_000
        }
        return totalUser + totalSystem
    }

    private static func readThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let list = threadList else { return 0 }
        let count = Int(threadCount)
        let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), size)
        return count
    }
}
