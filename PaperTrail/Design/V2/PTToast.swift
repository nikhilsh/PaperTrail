import SwiftUI

// MARK: - PTToast (docs/design-v2/ANIMATION_SPEC.md §7, pt.css `.toast`)
//
// Dark blur pill, bottom offset 108pt (clears the tab bar), fade+scale
// .985→1 over 200ms, auto-dismisses after 2.2s. Presented as a view
// modifier driven by a single `@State private var toast: PTToastItem?` —
// set it to show a message, it clears itself.

struct PTToastItem: Equatable, Identifiable {
    let id = UUID()
    let message: String

    static func == (lhs: PTToastItem, rhs: PTToastItem) -> Bool { lhs.id == rhs.id }
}

private struct PTToastModifier: ViewModifier {
    @Binding var item: PTToastItem?
    var autoDismiss: Double

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let item {
                toastPill(item)
                    .padding(.bottom, 108)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.985).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .task(id: item.id) {
                        try? await Task.sleep(for: .seconds(autoDismiss))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.2)) { self.item = nil }
                    }
                    // The toast is a transient overlay VoiceOver has no
                    // reason to focus on its own — announce it explicitly so
                    // it isn't silently missed.
                    .onAppear {
                        AccessibilityNotification.Announcement(item.message).post()
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: item)
    }

    private func toastPill(_ item: PTToastItem) -> some View {
        Text(item.message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(PT.txt)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color(hex: 0x14110D, alpha: 0.92), in: Capsule())
            .overlay(Capsule().stroke(PT.hair, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 12)
    }
}

extension View {
    /// Presents a `PTToast` pill anchored above the tab bar whenever `item`
    /// is non-nil; auto-dismisses after `autoDismiss` seconds (2.2s default,
    /// per spec).
    func ptToast(_ item: Binding<PTToastItem?>, autoDismiss: Double = 2.2) -> some View {
        modifier(PTToastModifier(item: item, autoDismiss: autoDismiss))
    }
}

#Preview("PTToast") {
    struct Demo: View {
        @State private var toast: PTToastItem?
        var body: some View {
            VStack {
                Button("Show toast") { toast = PTToastItem(message: "Serial copied — ready to paste") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ptScreen()
            .ptToast($toast)
        }
    }
    return Demo()
}
