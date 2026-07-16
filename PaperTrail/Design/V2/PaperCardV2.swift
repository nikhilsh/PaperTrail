import SwiftUI

// MARK: - PaperCardV2 (docs/design-v2/DESIGN_LANGUAGE.md §4, pt.css `.paper`/`.dogear`)
//
// The v1 `paperCard()` modifier (`PaperTrail/Design/PTComponents.swift`)
// already matches the v2 spec's filing card pixel-for-pixel: same cream
// gradient stops, same 14pt radius, same dog-ear fold geometry, same shadow
// recipe. This wave doesn't re-derive any of that — `PaperCardV2` is a named
// wrapper so new v2 call sites can spell the component the spec's name while
// rendering exactly like every existing filing card in the app.

struct PaperCardV2<Content: View>: View {
    /// Fold the top-right corner (the default v2 filing-card look). `false`
    /// gives a plain rounded-rect card — used for sheets/certificates where
    /// the dog-ear reads as clutter.
    var dogEar: Bool = true
    /// Gold foil fold vs. plain paper fold. Only meaningful when `dogEar`.
    var goldFold: Bool = false
    /// TODO(design-v2): `pt.css` `.paper::before` overlays a pre-rendered,
    /// 5%-opacity multiply-blend noise texture for paper tooth. The v2 brief
    /// explicitly defers bringing that asset in ("grain optional ... add a
    /// TODO"), so this flag is wired through but currently a no-op. Once the
    /// noise PNG lands, overlay it here with `.blendMode(.multiply)`.
    var grain: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if dogEar {
            content().paperCard(goldFold: goldFold)
        } else {
            content()
                .background(PT.paperFill)
                .clipShape(RoundedRectangle(cornerRadius: PT.Metric.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PT.Metric.cardRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 17, x: 0, y: 18)
                .shadow(color: .black.opacity(0.4), radius: 7, x: 0, y: 6)
        }
    }
}

#Preview("PaperCardV2") {
    VStack(spacing: 16) {
        PaperCardV2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Samsung TV").font(PTFont.serif(19, weight: 600))
                Text("JAN 2026 · $1,899").font(PTFont.mono(10.5)).foregroundStyle(PT.onPaper2)
            }
            .padding(16)
        }
        PaperCardV2(dogEar: false) {
            Text("Flat variant — no dog-ear").font(.system(size: 14)).padding(20)
        }
    }
    .padding(24)
    .ptScreen()
}
