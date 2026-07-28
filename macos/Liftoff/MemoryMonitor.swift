import Foundation
import Darwin

/// Live RAM usage of every terminal in the app.
///
/// A terminal emulator (SwiftTerm here, xterm.js on the web) knows nothing about
/// memory — it only owns a screen buffer. The real cost sits in the shell each
/// tab spawned and everything that shell started (agents, node, compilers), so we
/// walk the process tree from each PTY's `shellPid` and sum the kernel's own
/// accounting for those pids.
///
/// We report `ri_phys_footprint` rather than RSS: RSS counts shared pages once
/// per process, so summing it across a tree double-counts heavily. The footprint
/// is what Activity Monitor shows in its "Memory" column.
@MainActor
@Observable
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    /// Combined footprint of every terminal's process tree.
    private(set) var totalBytes: UInt64 = 0
    /// Footprint per terminal session. Keyed by id rather than snapshotted with
    /// titles so the overlay can render live sessions (titles, agent badges and
    /// busy spinners keep updating between samples).
    private(set) var bytesBySession: [UUID: UInt64] = [:]

    /// How often we resample. The sysctl process snapshot is cheap but not free,
    /// and memory figures this coarse don't need to be smoother than this.
    private let interval: TimeInterval = 3

    private var timer: Timer?
    /// Guards against overlapping samples if one pass runs long under load.
    private var sampling = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        guard !sampling else { return }
        // Roots are collected on the main actor (the view cache lives here), then
        // the process-tree walk happens off it.
        let roots: [(id: UUID, pid: pid_t)] = AppStore.allStores
            .flatMap { $0.projects }
            .flatMap { $0.terminals }
            .compactMap { session in
                guard let view = TerminalHostView.cache[session.id] else { return nil }
                let pid = view.process.shellPid
                guard pid > 0 else { return nil }
                return (session.id, pid)
            }

        guard !roots.isEmpty else {
            totalBytes = 0
            bytesBySession = [:]
            return
        }

        sampling = true
        let pids = roots.map(\.pid)
        DispatchQueue.global(qos: .utility).async {
            let measured = Self.treeFootprints(roots: pids)
            Task { @MainActor in
                self.sampling = false
                var bySession: [UUID: UInt64] = [:]
                var total: UInt64 = 0
                for root in roots {
                    let bytes = measured[root.pid] ?? 0
                    bySession[root.id] = bytes
                    total += bytes
                }
                self.bytesBySession = bySession
                self.totalBytes = total
            }
        }
    }

    /// Compact byte formatting ("1.4 GB"), matching Activity Monitor's units.
    nonisolated static func format(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Combined footprint of a set of sessions (a project's tabs, say).
    func bytes(for sessions: [TerminalSession]) -> UInt64 {
        sessions.reduce(0) { $0 + (bytesBySession[$1.id] ?? 0) }
    }

    // MARK: Process-tree measurement

    /// Footprint of each root pid *including* all of its descendants.
    private nonisolated static func treeFootprints(roots: [pid_t]) -> [pid_t: UInt64] {
        let children = childProcessMap()
        var result: [pid_t: UInt64] = [:]
        for root in roots {
            var total: UInt64 = 0
            var stack: [pid_t] = [root]
            // A pid can only be reached through its single parent, so the walk
            // terminates without a visited set.
            while let pid = stack.popLast() {
                total += footprint(of: pid)
                if let kids = children[pid] { stack.append(contentsOf: kids) }
            }
            result[root] = total
        }
        return result
    }

    /// One snapshot of every visible process, as parent pid → child pids.
    /// Taken once per sample so N terminals cost one sysctl pass, not N.
    private nonisolated static func childProcessMap() -> [pid_t: [pid_t]] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        // Processes can spawn between the sizing call and the fetch; ask for a bit
        // of headroom so a busy moment doesn't fail the whole sample with ENOMEM.
        size += MemoryLayout<kinfo_proc>.stride * 32
        let capacity = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [:] }
        let count = min(size / MemoryLayout<kinfo_proc>.stride, capacity)

        var map: [pid_t: [pid_t]] = [:]
        map.reserveCapacity(count)
        for i in 0..<count {
            let pid = procs[i].kp_proc.p_pid
            let ppid = procs[i].kp_eproc.e_ppid
            guard pid > 0, ppid > 0 else { continue }
            map[ppid, default: []].append(pid)
        }
        return map
    }

    /// Physical footprint of a single pid, or 0 if it exited mid-walk or belongs
    /// to another user (we only ever measure our own children, so that's rare).
    private nonisolated static func footprint(of pid: pid_t) -> UInt64 {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0 else { return 0 }
        return info.ri_phys_footprint
    }
}
