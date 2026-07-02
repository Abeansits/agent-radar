import AppKit
import DynamicNotchKit
import SwiftUI
import DoodleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: DynamicNotch<NotchContentView, NotchCompactIcon, EmptyView>!
    private var timer: Timer?
    private var collapseWork: DispatchWorkItem?
    private var keyMonitor: Any?

    private let boardManager = BoardManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        boardManager.reload()

        setupNotch()

        scheduleTimer()
        setupKeyMonitor()

        emit("agent-doodle notch ready. Board: \(BoardPath.resolved)")
    }

    // MARK: - Notch

    private func setupNotch() {
        notch = DynamicNotch(hoverBehavior: .all) {
            NotchContentView(boardManager: self.boardManager)
        } compactLeading: {
            NotchCompactIcon(boardManager: self.boardManager)
        }
        notch.transitionConfiguration = .init(
            openingAnimation: .snappy(duration: 0.25),
            closingAnimation: .smooth(duration: 0.2),
            conversionAnimation: .snappy(duration: 0.25),
            skipIntermediateHides: true
        )

        // Compact icon hover → expand immediately
        boardManager.onCompactHover = { [weak self] hovering in
            guard let self, hovering else { return }
            self.collapseWork?.cancel()
            Task { await self.notch.expand() }
        }

        // Expanded hover end → collapse with debounce
        boardManager.onExpandedHover = { [weak self] hovering in
            guard let self else { return }
            self.collapseWork?.cancel()
            guard !hovering else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { await self.notch.compact() }
            }
            self.collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        Task { await notch.compact() }
    }

    // MARK: - Timer (poll for badge)

    private func scheduleTimer() {
        timer?.invalidate()
        // ~5s per plan
        timer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.boardManager.reloadForBadge()
            }
        }
    }

    private func emit(_ message: String) {
        FileHandle.standardError.write(Data("[doodle-notch] \(message)\n".utf8))
    }

    // App-level Cmd+Q handler for accessory app (no main menu). .keyboardShortcut inside Menu
    // does not reliably work for keyDown in this context per platform behavior.
    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApplication.shared.terminate(nil)
                return nil // consume the event
            }
            return event
        }
    }
}
