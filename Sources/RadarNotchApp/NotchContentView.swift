import SwiftUI
import AppKit
import RadarCore

struct NotchContentView: View {
    var boardManager: BoardManager
    @State private var displayItems: [RadarItem] = []
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
        .frame(width: 480)  // ~25-30% larger for room-glance
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
            Text("agent-radar")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if boardManager.waitingCount > 0 {
                Label("\(boardManager.waitingCount) waiting", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            // Subtle quit affordance in corner of expanded view. Muted until hovered.
            // Cmd+Q is handled at AppDelegate level (real NSEvent monitor); Menu shortcut does not work reliably here.
            Menu {
                Button("Quit Radar") {
                    NSApplication.shared.terminate(nil)
                }
                // TODO: Launch at Login, other preferences. Menu can grow.
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .opacity(quitHovered ? 0.8 : 0.15)
            }
            .buttonStyle(.plain)
            .onHover { quitHovered = $0 }
            .padding(.leading, 2)
        }
    }

    private var emptyState: some View {
        Text("No active items. Agents will post with `radar set`.")
            .font(.system(size: 15))
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
                        ItemCard(item: item, boardManager: boardManager, showDebug: showDebug)
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
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Refresh") {
                        refresh()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

private struct ItemCard: View {
    let item: RadarItem
    let boardManager: BoardManager
    let showDebug: Bool

    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(item: RadarItem, boardManager: BoardManager, showDebug: Bool = false) {
        self.item = item
        self.boardManager = boardManager
        self.showDebug = showDebug
        _isExpanded = State(initialValue: item.status == "waiting_on_user")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line: glyph + name + summary (one line) | time (+ source in debug) | chevron | hover done
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let glyph = glyphFor(type: item.type) {
                    Text(glyph)
                        .font(.system(size: 14))
                }
                Text(item.display_name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                // summary in the one line (glanceable)
                if let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // metadata: just time, or source·time in debug view
                let age = RadarDate.relative(from: item.updated_at)
                let meta = showDebug ? "\(item.source) · \(age)" : age
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if hasDetail {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isHovered {
                    Button {
                        boardManager.markDone(item)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Mark done")
                }
            }

            // detail revealed on expand (default for waiting_on_user)
            if isExpanded, let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                let detailAttr = attributedStringWithLinks(from: detail)
                Text(detailAttr)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
                    .lineLimit(4)
                    .padding(.top, 1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(bgColor(for: item.status))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor(for: item.status), lineWidth: item.status == "waiting_on_user" ? 1 : 0)
        )
        .opacity( (item.status == "blocked" ? 0.65 : 1.0) * (RadarDate.isStale(item.updated_at) ? 0.55 : 1.0) )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var hasDetail: Bool {
        item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil
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

    private func bgColor(for status: String) -> Color {
        switch status {
        case "waiting_on_user": return Color.red.opacity(0.12)
        case "blocked": return Color.yellow.opacity(0.08)
        default: return Color.gray.opacity(0.04)
        }
    }

    private func borderColor(for status: String) -> Color {
        status == "waiting_on_user" ? Color.red.opacity(0.4) : .clear
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// Delegate to the correctly implemented version in RadarCore (fixes UTF-16 vs character offset bug for non-ASCII).
private func attributedStringWithLinks(from text: String) -> AttributedString {
    RadarCore.attributedStringWithLinks(from: text)
}
