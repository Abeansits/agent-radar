import SwiftUI
import AppKit
import RadarCore

// Round 4 contrast lifts for dark panel (WCAG AA-ish targets)
private let panelHeaderColor = Color.white.opacity(0.78)
private let summaryColor = Color.white.opacity(0.92)
private let metaColor = Color.white.opacity(0.58)

struct NotchContentView: View {
    var boardManager: BoardManager
    @State private var displayItems: [RadarItem] = []
    @State private var showDebug = false
    @State private var optionMonitor: Any?
    @State private var quitHovered = false
    @State private var copiedNumber: Int? = nil
    @State private var keyMonitor: Any?

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
        .frame(width: 640)  // round 3: +~33% (decisively larger expanded panel; text kept proportionate)
        .onAppear {
            refresh()
            setupOptionMonitor()
            setupKeyMonitor()
        }
        .onDisappear {
            removeOptionMonitor()
            removeKeyMonitor()
        }
        .onHover { boardManager.onExpandedHover?($0) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .foregroundStyle(.secondary)
            Text("agent-radar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(summaryColor)
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
            .foregroundStyle(metaColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var sections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(boardManager.groupedItems(displayItems)) { group in
                    SectionHeader(title: group.title)
                    let isWaitingGroup = group.statusKey == "waiting_on_user"
                    ForEach(Array(group.items.enumerated()), id: \.1.id) { idx, item in
                        let pick = isWaitingGroup ? (idx + 1) : nil
                        let isCopied = (pick != nil && copiedNumber == pick)
                        ItemCard(
                            item: item,
                            boardManager: boardManager,
                            showDebug: showDebug,
                            pickNumber: pick,
                            onCopy: pick != nil ? { self.copyForNumber(pick!) } : nil,
                            isCopied: isCopied
                        )
                    }
                }
            }
        }
        .frame(maxHeight: 380)
    }

    private var footer: some View {
        Group {
            if showDebug {
                HStack {
                    Text("Board: \(shortBoardPath())")
                        .font(.system(size: 11))
                        .foregroundStyle(metaColor)
                    Spacer()
                    Button("Refresh") {
                        refresh()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(metaColor)
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

    private var waitingItems: [RadarItem] {
        displayItems.filter { $0.status == "waiting_on_user" }.prefix(9).map { $0 }
    }

    private func copyToPasteboard(_ item: RadarItem) {
        let age = RadarDate.relative(from: item.updated_at)
        let updated = String(item.updated_at.prefix(10))
        let detailText = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "(none)"
        let content = """
        [radar item] \(item.display_name) (\(item.type), \(item.status), \(age))
        Summary: \(item.summary)
        Detail: \(detailText)
        (source: \(item.source), updated \(updated))
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
    }

    private func copyForNumber(_ n: Int) {
        guard n >= 1 && n <= waitingItems.count else { return }
        let item = waitingItems[n - 1]
        copyToPasteboard(item)
        withAnimation(.easeInOut(duration: 0.1)) {
            copiedNumber = n
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if copiedNumber == n {
                withAnimation {
                    copiedNumber = nil
                }
            }
        }
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let chars = event.characters, chars.count == 1, let n = Int(chars), n >= 1 && n <= 9 {
                copyForNumber(n)
                return nil // consume the number key while expanded
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(panelHeaderColor)
            .padding(.top, 4)
    }
}

private struct ItemCard: View {
    let item: RadarItem
    let boardManager: BoardManager
    let showDebug: Bool
    let pickNumber: Int?
    let onCopy: (() -> Void)?
    let isCopied: Bool

    @State private var isExpanded: Bool
    @State private var isHovered = false
    @State private var hasUserToggled: Bool

    init(item: RadarItem, boardManager: BoardManager, showDebug: Bool = false, pickNumber: Int? = nil, onCopy: (() -> Void)? = nil, isCopied: Bool = false) {
        self.item = item
        self.boardManager = boardManager
        self.showDebug = showDebug
        self.pickNumber = pickNumber
        self.onCopy = onCopy
        self.isCopied = isCopied
        let trimmedDetail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultExpand = item.status == "waiting_on_user" && !trimmedDetail.isEmpty
        _isExpanded = State(initialValue: defaultExpand)
        _hasUserToggled = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Entire card row is now the tap target for expand/collapse *iff* has non-empty detail.
            // Chevron is passive visual only (no longer a tiny button).
            // ✓ done button is isolated hover control: its clicks must never expand; row clicks must never mark done.
            // No chevron + no row action when detail is nil/empty (after trim).
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let n = pickNumber {
                    ZStack {
                        if isCopied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                        } else {
                            Text("\(n)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 12, height: 12)
                    .background(
                        Circle().fill(isCopied ? Color.green.opacity(0.2) : Color.white.opacity(0.15))
                    )
                    .padding(.trailing, 2)
                }
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
                        .foregroundStyle(summaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // metadata: just time, or source·time in debug view
                let age = RadarDate.relative(from: item.updated_at)
                let meta = showDebug ? "\(item.source) · \(age)" : age
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(metaColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if hasDetail {
                    // Passive indicator only — the row tap handles expand.
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }

                // Always reserve trailing slot for the done button (hover only).
                // Keeps layout stable and guarantees non-overlapping hit areas.
                Color.clear
                    .frame(width: 44, height: 16)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if hasDetail {
                    isExpanded.toggle()
                    hasUserToggled = true
                }
                // else: no detail → no chevron → row click is a no-op (no empty expansion)
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 4) {
                    if pickNumber != nil && isHovered, let doCopy = onCopy {
                        Button {
                            doCopy()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy context to pasteboard")
                    }
                    if isHovered {
                        Button {
                            boardManager.markDone(item)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(5)
                                .background(
                                    Circle().fill(Color.secondary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Mark done")
                        // Larger explicit padding for clearly-bounded isolated hit target
                        .padding(.trailing, 4)
                    }
                }
            }

            // detail revealed on expand (default for waiting_on_user items that have detail)
            if isExpanded, let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                let detailAttr = attributedStringWithLinks(from: detail)
                let firstLink = firstLink(in: detail)
                Text(detailAttr)
                    .font(.system(size: 15))
                    .foregroundStyle(summaryColor)
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
                    .lineLimit(4)
                    .padding(.top, 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let link = firstLink {
                            NSWorkspace.shared.open(link)
                        }
                    }
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
        .onChange(of: item.status) { _, _ in
            syncDefaultExpansion()
        }
        .onChange(of: item.detail) { _, _ in
            syncDefaultExpansion()
        }
    }

    private var hasDetail: Bool {
        item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil
    }

    /// Keep isExpanded in sync when the underlying item is refreshed (same id reused across board polls).
    /// Respects explicit user toggles; adopts the waiting+detail default only when the user has not toggled.
    private func syncDefaultExpansion() {
        let has = hasDetail
        if !has {
            isExpanded = false
            hasUserToggled = false
            return
        }
        if !hasUserToggled {
            isExpanded = (item.status == "waiting_on_user")
        }
        // If user has toggled, preserve their choice across refreshes.
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

private func firstLink(in detail: String) -> URL? {
    let attr = attributedStringWithLinks(from: detail)
    for run in attr.runs {
        if let link = run.link {
            return link
        }
    }
    return nil
}

// Delegate to the correctly implemented version in RadarCore (fixes UTF-16 vs character offset bug for non-ASCII).
private func attributedStringWithLinks(from text: String) -> AttributedString {
    RadarCore.attributedStringWithLinks(from: text)
}
