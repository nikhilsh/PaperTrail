import SwiftUI

// MARK: - FolderTabCard (docs/design-v2/DESIGN_LANGUAGE.md §5 S2)
//
// A mono tab sticking up above a `PaperCardV2`, 8pt top radii — the
// "folder tab" filing motif for grouped record lists.

struct FolderTabCard<Content: View>: View {
    let tabText: String
    var dogEar: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tabText.uppercased())
                .font(PTFont.mono(9.5, medium: true))
                .tracking(1.9)
                .foregroundStyle(PT.inkStamp)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(PT.paper, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
                .padding(.leading, 14)
                .zIndex(1)
            PaperCardV2(dogEar: dogEar) { content() }
                .padding(.top, -1) // fuse the tab to the card's top edge
        }
    }
}

#Preview("FolderTabCard") {
    FolderTabCard(tabText: "Kitchen") {
        VStack(alignment: .leading, spacing: 6) {
            Text("LG 2 Door Fridge").font(PTFont.serif(18, weight: 600))
            Text("KITCHEN · MAR 2025 · $1,269").font(PTFont.mono(10.5)).foregroundStyle(PT.onPaper2)
        }
        .padding(16)
    }
    .padding(24)
    .ptScreen()
}
