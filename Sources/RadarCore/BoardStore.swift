import Foundation

// MARK: - Locked Store (flock for concurrent writers)
// Single-file JSON + exclusive lock around read-modify-write.
// Readers can read without lock (eventual visibility is fine for this use case).

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum BoardStoreError: Error, CustomStringConvertible {
    case ioError(String)
    case lockFailed(String)

    public var description: String {
        switch self {
        case .ioError(let m): return "IO error: \(m)"
        case .lockFailed(let m): return "Lock error: \(m)"
        }
    }
}

public enum BoardStore {
    /// Load board (best effort). Creates empty board on first use / missing file.
    public static func load() throws -> Board {
        let url = BoardPath.resolvedURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Board()
        }
        do {
            let data = try Data(contentsOf: url)
            if data.isEmpty { return Board() }
            return try JSONDecoder().decode(Board.self, from: data)
        } catch {
            throw BoardStoreError.ioError("Failed to read or decode board at \(url.path): \(error)")
        }
    }

    /// Perform a read-modify-write under exclusive flock on a *stable* sidecar lock file.
    /// The data file may be atomically replaced (rename) without dropping the lock.
    /// Use for any mutation (set, rm).
    public static func withLock<T>(_ body: (inout Board) throws -> T) throws -> T {
        let url = BoardPath.resolvedURL
        let lockURL = BoardPath.resolvedLockURL
        try BoardPath.ensureParentDirectory()

        // Open (or create) the *sidecar lock file* — it is NEVER renamed or deleted.
        // All writers flock this stable inode; data file can be .atomic-replaced safely.
        let lockPath = lockURL.path
        let lockFd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard lockFd >= 0 else {
            throw BoardStoreError.lockFailed("Failed to open lock file for locking: \(String(cString: strerror(errno)))")
        }
        defer { close(lockFd) }

        // Acquire exclusive lock (blocks until available) on the sidecar
        let lockResult = flock(lockFd, LOCK_EX)
        guard lockResult == 0 else {
            throw BoardStoreError.lockFailed("flock(LOCK_EX) failed on sidecar: \(String(cString: strerror(errno)))")
        }
        defer { flock(lockFd, LOCK_UN) }

        // Read current (or default) from the data file (under sidecar lock)
        var board: Board
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                if !data.isEmpty {
                    board = try JSONDecoder().decode(Board.self, from: data)
                } else {
                    board = Board()
                }
            } catch {
                // Corrupt board: rename to preserve evidence, warn on stderr, start fresh.
                // Do this under the lock to avoid races on the corrupt file itself.
                let ts = RadarDate.nowISO().replacingOccurrences(of: ":", with: "-")
                let corruptName = url.lastPathComponent + ".corrupt-" + ts
                let corruptURL = url.deletingLastPathComponent().appendingPathComponent(corruptName)
                do {
                    try fileManager.moveItem(at: url, to: corruptURL)
                    fputs("WARNING: corrupt board at \(url.path) backed up to \(corruptName); starting with fresh board.\n", stderr)
                } catch {
                    fputs("WARNING: corrupt board at \(url.path) (failed to backup: \(error)); starting fresh.\n", stderr)
                }
                board = Board()
            }
        } else {
            board = Board()
        }

        // Mutate
        let result = try body(&board)

        // Write back atomically under lock (rename temp over data; lock remains on sidecar)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(board)
        try data.write(to: url, options: .atomic)

        return result
    }

    /// Convenience: load then filter/sort for presentation.
    public static func loadFiltered(status: String? = nil, includeDone: Bool = false) throws -> [RadarItem] {
        var items = try load().items

        if !includeDone {
            items = items.filter { $0.status != "done" }
        }
        if let status {
            items = items.filter { $0.status == status }
        }

        // Sort: most recent first within groups (presentation can regroup)
        items.sort { $0.updated_at > $1.updated_at }
        return items
    }

    // MARK: - High-level mutators (locked)

    /// Create or update an item by (normalized) name.
    /// Only provided non-nil fields are overwritten for updates.
    /// Always sets updated_at to now and resolves source from env.
    public static func set(
        displayName: String,
        type: String? = nil,
        status: String? = nil,
        summary: String? = nil,
        detail: String? = nil
    ) throws -> RadarItem {
        let normalized = NameNormalizer.normalize(displayName)
        let now = RadarDate.nowISO()
        let resolvedSource = resolvedSource()

        return try withLock { board in
            if let idx = board.items.firstIndex(where: { $0.name == normalized }) {
                // Partial update
                var item = board.items[idx]
                item.display_name = displayName  // last casing wins
                if let type { item.type = type }
                if let status { item.status = status }
                if let summary { item.summary = summary }
                if let detail { item.detail = detail.isEmpty ? nil : detail }
                item.source = resolvedSource
                item.updated_at = now
                board.items[idx] = item
                return item
            } else {
                // New item
                let item = RadarItem(
                    name: normalized,
                    display_name: displayName,
                    type: type ?? "note",
                    status: status ?? "active",
                    summary: summary ?? "",
                    detail: (detail?.isEmpty == false) ? detail : nil,
                    source: resolvedSource,
                    updated_at: now
                )
                board.items.append(item)
                return item
            }
        }
    }

    public static func get(name: String) throws -> RadarItem? {
        let normalized = NameNormalizer.normalize(name)
        let board = try load()
        return board.items.first { $0.name == normalized }
    }

    public static func remove(name: String) throws -> Bool {
        let normalized = NameNormalizer.normalize(name)
        return try withLock { board in
            let before = board.items.count
            board.items.removeAll { $0.name == normalized }
            return board.items.count < before
        }
    }

    public static func resolvedSource() -> String {
        let env = ProcessInfo.processInfo.environment
        if let s = env["RADAR_SOURCE"], !s.isEmpty { return s }
        if let s = env["DOODLE_SOURCE"], !s.isEmpty { return s }
        if let a = env["AGENT_NAME"], !a.isEmpty { return a }
        return "unknown"
    }

    /// For pretty printing / humans (used by CLI --pretty and future).
    public static func prettyPrint(items: [RadarItem]) -> String {
        guard !items.isEmpty else { return "No items." }

        var lines: [String] = []
        let grouped = Dictionary(grouping: items, by: { $0.status })
        let order = ["waiting_on_user", "active", "blocked", "done"]

        for key in order {
            guard let group = grouped[key], !group.isEmpty else { continue }
            let title: String
            switch key {
            case "waiting_on_user": title = "Waiting on You"
            case "active": title = "Active"
            case "blocked": title = "Blocked"
            case "done": title = "Done"
            default: title = key.capitalized
            }
            lines.append("\(title):")
            for item in group.sorted(by: { $0.updated_at > $1.updated_at }) {
                let age = RadarDate.relative(from: item.updated_at)
                let detailLine = item.detail.map { "\n    \($0)" } ?? ""
                lines.append("  • \(item.display_name) [\(item.type)] — \(item.summary)  (\(item.source), \(age))\(detailLine)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
