import Foundation

// MARK: - Data Model (locked per plan-opencode.md)

public struct RadarItem: Codable, Sendable, Identifiable {
    /// Normalized key (trim + case-folded). Stable for updates.
    /// Also serves as the stable Identifiable id.
    public var name: String

    public var id: String { name }
    /// Original casing from the last write. What humans see.
    public var display_name: String
    /// Free-form type: "session", "question", "blocker", "note", etc.
    public var type: String
    /// "active" | "waiting_on_user" | "blocked" | "done"
    public var status: String
    /// One-line what's happening.
    public var summary: String
    /// Optional rich context / ask / blocker reason. Human-readable.
    public var detail: String?
    /// Attribution: from DOODLE_SOURCE or AGENT_NAME env.
    public var source: String
    /// ISO8601 timestamp, updated on every write.
    public var updated_at: String

    public init(
        name: String,
        display_name: String,
        type: String,
        status: String,
        summary: String,
        detail: String? = nil,
        source: String,
        updated_at: String
    ) {
        self.name = name
        self.display_name = display_name
        self.type = type
        self.status = status
        self.summary = summary
        self.detail = detail
        self.source = source
        self.updated_at = updated_at
    }
}

public struct Board: Codable, Sendable {
    public var version: Int
    public var items: [RadarItem]

    public init(version: Int = 1, items: [RadarItem] = []) {
        self.version = version
        self.items = items
    }
}

// MARK: - Normalization (Vigil gap #3)

public enum NameNormalizer {
    /// Trim + case-fold for stable key. Display name keeps original casing.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// MARK: - Board path resolution (RADAR_BOARD_PATH primary, DOODLE_ fallback for migration)

public enum BoardPath {
    public static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".agent-radar/board.json")
    }()

    public static var resolved: String {
        let env = ProcessInfo.processInfo.environment
        if let s = env["RADAR_BOARD_PATH"], !s.isEmpty {
            return s
        }
        if let s = env["DOODLE_BOARD_PATH"], !s.isEmpty {
            return s
        }
        let path = defaultPath
        let oldPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".agent-doodle/board.json")
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) && fm.fileExists(atPath: oldPath) {
            do {
                try fm.copyItem(atPath: oldPath, toPath: path)
                fputs("[agent-radar] Migrated board from ~/.agent-doodle/board.json (left as backup).\n", stderr)
            } catch {
                fputs("[agent-radar] Failed to migrate old board: \(error)\n", stderr)
            }
        }
        return path
    }

    public static var resolvedURL: URL {
        URL(fileURLWithPath: resolved)
    }

    public static func ensureParentDirectory() throws {
        let url = resolvedURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Stable sidecar for locking. Never renamed or deleted; data file may be atomically replaced.
    public static var resolvedLockURL: URL {
        URL(fileURLWithPath: resolved + ".lock")
    }
}

// MARK: - Date helpers

public enum RadarDate {
    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    public static func nowISO() -> String {
        makeFormatter().string(from: Date())
    }

    public static func parse(_ iso: String) -> Date? {
        makeFormatter().date(from: iso)
    }

    /// Relative age string for humans, e.g. "2m ago", "3h ago"
    public static func relative(from iso: String, now: Date = Date()) -> String {
        guard let date = parse(iso) else { return "unknown" }
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    /// True if older than the staleness threshold (MVP: 6 hours)
    public static func isStale(_ iso: String, thresholdHours: Double = 6.0, now: Date = Date()) -> Bool {
        guard let date = parse(iso) else { return true }
        let age = now.timeIntervalSince(date)
        return age > (thresholdHours * 3600)
    }
}

// MARK: - Link helper (for UI attributed strings with tappable links)
// Correctly bridges UTF-16 NSRange (from NSDataDetector/NSRegularExpression) to AttributedString
// character offsets using String.Index conversion. Handles non-ASCII (glyphs, emoji).
public func attributedStringWithLinks(from text: String) -> AttributedString {
    var result = AttributedString(text)
    var fullURLRanges: [Range<String.Index>] = []

    // Full URLs via NSDataDetector (UTF-16 NSRange -> String.Index -> Attributed char offset)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        for match in detector.matches(in: text, options: [], range: nsRange) {
            if let url = match.url,
               let stringRange = Range(match.range, in: text) {
                let lowerOffset = text.distance(from: text.startIndex, to: stringRange.lowerBound)
                let charCount = text.distance(from: stringRange.lowerBound, to: stringRange.upperBound)
                let start = result.index(result.startIndex, offsetByCharacters: lowerOffset)
                let end = result.index(start, offsetByCharacters: charCount)
                result[start..<end].link = url
                // Only protect actual full URLs (with scheme) from bare-domain https forcing
                if text[stringRange].lowercased().hasPrefix("http") {
                    fullURLRanges.append(stringRange)
                }
            }
        }
    }

    // Bare domains e.g. github.com/foo/bar (no scheme) - skip only if overlaps a full-URL range (protect http:// etc. from being forced to https)
    if let bare = try? NSRegularExpression(pattern: #"\b([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9./_-]*)?)\b"#, options: []) {
        let nsText = text as NSString
        let matches = bare.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let domain = nsText.substring(with: match.range)
            if !domain.lowercased().hasPrefix("http"),
               let url = URL(string: "https://" + domain),
               let stringRange = Range(match.range, in: text) {
                if fullURLRanges.contains(where: { $0.overlaps(stringRange) }) {
                    continue
                }
                let lowerOffset = text.distance(from: text.startIndex, to: stringRange.lowerBound)
                let charCount = text.distance(from: stringRange.lowerBound, to: stringRange.upperBound)
                let start = result.index(result.startIndex, offsetByCharacters: lowerOffset)
                let end = result.index(start, offsetByCharacters: charCount)
                result[start..<end].link = url
            }
        }
    }
    return result
}
