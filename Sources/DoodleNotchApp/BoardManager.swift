import Foundation
import Observation
import SwiftUI
import DoodleCore

@Observable
@MainActor
final class BoardManager {
    var items: [DoodleItem] = []
    var waitingCount: Int = 0

    var onCompactHover: ((Bool) -> Void)?
    var onExpandedHover: ((Bool) -> Void)?

    /// Full reload (used on launch + on expand)
    func reload() {
        do {
            let all = try BoardStore.loadFiltered(includeDone: false)
            self.items = all
            self.waitingCount = Self.waitingCount(in: all)
        } catch {
            emit("Reload failed: \(error)")
            self.items = []
            self.waitingCount = 0
        }
    }

    /// Lightweight reload just for badge count (timer)
    func reloadForBadge() {
        do {
            let all = try BoardStore.loadFiltered(includeDone: false)
            self.waitingCount = Self.waitingCount(in: all)
        } catch {
            // silent for timer path
        }
    }

    private static func waitingCount(in items: [DoodleItem]) -> Int {
        items.filter { $0.status == "waiting_on_user" }.count
    }

    /// Full items grouped for the expanded view (called on appear/refresh)
    func loadForDisplay() -> [DoodleItem] {
        do {
            return try BoardStore.loadFiltered(includeDone: false)
        } catch {
            emit("Display load failed: \(error)")
            return []
        }
    }

    private func emit(_ message: String) {
        FileHandle.standardError.write(Data("[BoardManager] \(message)\n".utf8))
    }
}

// Group helper for UI
extension BoardManager {
    struct StatusGroup: Identifiable {
        let id = UUID()
        let title: String
        let statusKey: String
        let items: [DoodleItem]
    }

    func groupedItems(_ raw: [DoodleItem]) -> [StatusGroup] {
        let filtered = raw.filter { $0.status != "done" }
        let grouped = Dictionary(grouping: filtered, by: { $0.status })

        var result: [StatusGroup] = []

        func make(_ key: String, baseTitle: String) {
            if let arr = grouped[key], !arr.isEmpty {
                let titled = "\(baseTitle) · \(arr.count)"
                result.append(StatusGroup(title: titled, statusKey: key, items: arr.sorted { $0.updated_at > $1.updated_at }))
            }
        }

        // Order per plan: Waiting on You → Active → Blocked
        make("waiting_on_user", baseTitle: "Waiting on You")
        make("active", baseTitle: "Active")
        make("blocked", baseTitle: "Blocked")

        return result
    }
}
