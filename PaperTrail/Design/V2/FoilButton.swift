import SwiftUI

// MARK: - FoilButton (docs/design-v2/DESIGN_LANGUAGE.md §4, pt.css `.btn-gold`)
//
// `PTGoldButtonStyle` (`PaperTrail/Design/PTComponents.swift`) already is
// `.btn-gold`: same cream-gold gradient (#F2EAD7→#E7DABC), same border
// (#C9B988), same gold glow shadow. No new style needed — `FoilButtonStyle`
// is a v2-named alias, and `FoilButton` is a thin convenience view for the
// common "icon? + label" case so v2 call sites don't have to hand-assemble
// the `HStack` + `.buttonStyle(...)` every time.

typealias FoilButtonStyle = PTGoldButtonStyle

struct FoilButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(PT.inkStamp)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(FoilButtonStyle())
        .disabled(isLoading)
    }
}

#Preview("FoilButton") {
    VStack(spacing: 14) {
        FoilButton(title: "Take the lifetime") {}
        FoilButton(title: "Build claim packet", systemImage: "shippingbox") {}
        FoilButton(title: "Processing…", isLoading: true) {}
    }
    .padding(24)
    .ptScreen()
}
