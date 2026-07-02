import SwiftUI
import AppKit
import DoodleCore

struct NotchContentView: View {
    var boardManager: BoardManager
    @State private var displayItems: [DoodleItem] = []
    @State private var showDebug = false
    @State private var optionMonitor: Any?
    @State private var quitHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Divider().opacity(0.3)

            if displayItems.isEmpty {
                emptyState
            } else {
                sections
            }

            Divider().opacity(0.3)

            footer
        }
        .padding(12)
        .frame(width: 380)
        .onAppear {
            refresh()
            setupOptionMonitor()
        }
        .onDisappear {
            removeOptionMonitor()
        }
        .onHover { boardManager.onExpandedHover?($0) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .foregroundStyle(.secondary)
            Text("agent-doodle")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if boardManager.waitingCount > 0 {
                Label("\(boardManager.waitingCount) waiting", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            // Subtle quit affordance in corner of expanded view. Muted until hovered.
            // Cmd+Q is handled at AppDelegate level (real NSEvent monitor); Menu shortcut does not work reliably here.
            Menu {
                Button("Quit Agent Doodle") {
                    NSApplication.shared.terminate(nil)
                }
                // TODO: Launch at Login, other preferences. Menu can grow.
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .opacity(quitHovered ? 0.8 : 0.15)
            }
            .buttonStyle(.plain)
            .onHover { quitHovered = $0 }
            .padding(.leading, 2)
        }
    }

    private var emptyState: some View {
        Text("No active items. Agents will post with `doodle set`.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var sections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(boardManager.groupedItems(displayItems)) { group in
                    SectionHeader(title: group.title)
                    ForEach(group.items) { item in
                        ItemCard(item: item)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private var footer: some View {
        Group {
            if showDebug {
                HStack {
                    Text("Board: \(shortBoardPath())")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Refresh") {
                        refresh()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refresh() {
        displayItems = boardManager.loadForDisplay()
        boardManager.reload() // keep counts fresh
    }

    private func shortBoardPath() -> String {
        let p = BoardPath.resolved
        if let home = FileManager.default.homeDirectoryForCurrentUser.path as String?,
           p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }

    private func setupOptionMonitor() {
        removeOptionMonitor() // safety
        // Seed initial state in case Option is already held when view appears.
        showDebug = NSEvent.modifierFlags.contains(.option)
        optionMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            self.showDebug = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func removeOptionMonitor() {
        if let mon = optionMonitor {
            NSEvent.removeMonitor(mon)
            optionMonitor = nil
        }
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

private struct ItemCard: View {
    let item: DoodleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: glyph + name (body) | metadata right (source · time)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let glyph = glyphFor(type: item.type) {
                    Text(glyph)
                        .font(.system(size: 13))
                }
                Text(item.display_name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(item.source) · \(DoodleDate.relative(from: item.updated_at))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Line 2: single body line (detail preferred for waiting_on_user, summary otherwise)
            let bodyText = preferredBodyText(for: item)
            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundForItem(item))
        )
        .opacity(DoodleDate.isStale(item.updated_at) ? 0.55 : 1.0)
    }

    private func glyphFor(type: String) -> String? {
        switch type.lowercased() {
        case "question": return "❓"
        case "session": return "🔨"
        case "blocker": return "🚧"
        case "note": return "📝"
        default: return nil
        }
    }

    private func preferredBodyText(for item: DoodleItem) -> String {
        let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let candidates = item.status == "waiting_on_user" ? [detail, summary] : [summary, detail]
        return candidates.compactMap { $0 }.first ?? ""
    }

    private func backgroundForItem(_ item: DoodleItem) -> Color {
        if item.status == "waiting_on_user" {
            return Color.red.opacity(0.06)
        }
        if DoodleDate.isStale(item.updated_at) {
            return Color.gray.opacity(0.06)
        }
        return Color.gray.opacity(0.04)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
