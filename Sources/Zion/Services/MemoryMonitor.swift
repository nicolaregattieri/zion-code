import Foundation
import Darwin

/// Lightweight system-memory monitor for the Zion Talks status bar.
///
/// Reads `host_statistics64` to compute current memory pressure (free / total)
/// and `lsof -ti :<port>` + `ps -o rss=` to get the RSS of a local LLM server
/// when one is bound to a known port. No background process is spawned by this
/// monitor; the user opts in to autostart via `LocalAutoStartPolicy` and can
/// disconnect at any time from the status bar.
@Observable
@MainActor
final class MemoryMonitor {

    // MARK: - Observable State

    /// System-wide memory pressure in the range 0...1 (1 = fully used).
    private(set) var systemPressure: Double = 0
    /// Total physical memory in bytes.
    private(set) var totalBytes: UInt64 = 0
    /// Used physical memory in bytes (= totalBytes * systemPressure).
    private(set) var usedBytes: UInt64 = 0
    /// RSS of the local-server process bound to `monitoredPort`, in bytes.
    /// Nil when the port is not bound or the lookup failed.
    private(set) var localServerRSSBytes: UInt64?
    /// Port currently monitored. Set via `setMonitoredPort(_:)` when the user
    /// enables / connects to a local LLM. Nil = no port watch.
    private(set) var monitoredPort: Int?

    // MARK: - Private

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let pollInterval: TimeInterval

    // MARK: - Init

    init(pollInterval: TimeInterval = 5) {
        self.pollInterval = pollInterval
    }

    // MARK: - Public API

    /// Begin polling. Safe to call repeatedly; second call is a no-op.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 5) * 1_000_000_000))
            }
        }
    }

    /// Stop polling. RSS / pressure values are preserved (last known snapshot).
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Watch the given port for local-server RSS. Pass `nil` to clear.
    func setMonitoredPort(_ port: Int?) {
        monitoredPort = port
        if port == nil { localServerRSSBytes = nil }
    }

    /// One-shot poll. Safe to call from tests.
    /// `host_statistics64` is cheap (Mach syscall) but `lsof + ps` spawn
    /// subprocesses — those run on a detached Task so the UI never hitches.
    func pollOnce() async {
        let snapshot = await Task.detached(priority: .background) {
            Self.readSystemMemory()
        }.value
        self.systemPressure = snapshot.pressure
        self.totalBytes = snapshot.total
        self.usedBytes = snapshot.used

        if let port = monitoredPort {
            let rss = await Task.detached(priority: .background) {
                Self.readRSS(forPort: port)
            }.value
            self.localServerRSSBytes = rss
            // When a local server is detected for the first time (or returns
            // after being down), stamp `localLastHealthyAt` so the orchestrator's
            // `isConnected(.local)` returns true on the next Auto turn. Without
            // this, the chain falls through to the next provider (Haiku/CLI)
            // even though the local LLM is right there ready to serve.
            if rss != nil {
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: UserDefaultsKeys.AI.localLastHealthyAt
                )
            }
        }
    }

    // MARK: - System memory

    struct Snapshot: Equatable {
        let total: UInt64
        let used: UInt64
        var pressure: Double {
            total == 0 ? 0 : Double(used) / Double(total)
        }
    }

    /// Reads vm statistics from the Mach host. Pressure = (used / total) where
    /// used = active + wired + compressed. Falls back to zeros on any failure.
    nonisolated static func readSystemMemory() -> Snapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return Snapshot(total: 0, used: 0) }

        // `vm_kernel_page_size` is a kernel-mutable global; ask Mach for the
        // page size via `host_page_size` to stay Sendable-clean under Swift 6.
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let pageSizeU64 = UInt64(pageSize)
        let active     = UInt64(stats.active_count) * pageSizeU64
        let wired      = UInt64(stats.wire_count) * pageSizeU64
        let compressed = UInt64(stats.compressor_page_count) * pageSizeU64
        let used = active + wired + compressed

        let total: UInt64 = {
            var size: UInt64 = 0
            var sizeLen = MemoryLayout<UInt64>.size
            sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)
            return size
        }()
        return Snapshot(total: total, used: used)
    }

    // MARK: - Per-process RSS by port

    /// Resolves the PID listening on `port` via `lsof -ti :<port>` and then
    /// reads RSS via `ps -o rss=`. Returns bytes (RSS reported in KB).
    /// Synchronous shells; cheap (10–30 ms). Returns nil on any failure.
    nonisolated static func readRSS(forPort port: Int) -> UInt64? {
        guard let pid = pidListening(onPort: port) else { return nil }
        let psPath = "/bin/ps"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: psPath)
        task.arguments = ["-o", "rss=", "-p", String(pid)]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let rssKB = UInt64(String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else { return nil }
        return rssKB * 1024
    }

    nonisolated static func pidListening(onPort port: Int) -> Int32? {
        let lsofPath = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsofPath)
        task.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let first = String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .first(where: { !$0.isEmpty }),
            let pid = Int32(first) else { return nil }
        return pid
    }
}

// MARK: - Formatting helpers

extension MemoryMonitor {
    static func formatBytes(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useGB, .useMB]
        return f.string(fromByteCount: Int64(bytes))
    }
}
