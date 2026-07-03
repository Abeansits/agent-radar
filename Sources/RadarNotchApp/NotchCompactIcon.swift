import SwiftUI
import RadarCore

// Compact icon shown in the notch when collapsed. Shows a simple badge.

struct NotchCompactIcon: View {
    var boardManager: BoardManager
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        // Use overlay + explicit trailing padding so the red badge is never clipped by the notch chrome.
        Image(systemName: "list.bullet.clipboard")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .overlay(alignment: .topTrailing) {
                if boardManager.waitingCount > 0 {
                    Text("\(boardManager.waitingCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 4, y: -3)
                }
            }
            .padding(.trailing, 6)  // room for badge
            .opacity(pulseOpacity)
            .onHover { boardManager.onCompactHover?($0) }
            .onChange(of: boardManager.waitingCount) { _, newCount in
                if newCount > 0 {
                    withAnimation(.easeOut(duration: 0.1)) { pulseOpacity = 0.6 }
                    withAnimation(.easeInOut(duration: 0.35).delay(0.1)) { pulseOpacity = 1.0 }
                }
            }
    }
}
