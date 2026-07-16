import SwiftUI

// MARK: - PTStamp (docs/design-v2/DESIGN_LANGUAGE.md §4, pt.css `.stamp`)
//
// `StampBadge` (`PaperTrail/Design/PTComponents.swift`) already implements
// the v2 rubber-stamp spec exactly: 2pt `currentColor` border, mono caps,
// rotate(-3°). It takes an arbitrary `tone: Color`; `PTStamp` wraps it with
// the three named states the spec calls out, so v2 call sites don't have to
// know the raw hex-to-tone mapping.

enum PTStampState {
    case covered
    case expired
    case paper

    var tone: Color {
        switch self {
        case .covered: PT.sageDeep
        case .expired: PT.terra
        case .paper: PT.goldDeep
        }
    }
}

struct PTStamp: View {
    let text: String
    var state: PTStampState
    /// Smaller variant for dense cards — forwarded to `StampBadge`.
    var compact: Bool = false

    var body: some View {
        StampBadge(text: text, tone: state.tone, compact: compact)
    }
}

#Preview("PTStamp") {
    VStack(spacing: 24) {
        PTStamp(text: "Covered", state: .covered)
        PTStamp(text: "Expired", state: .expired)
        PTStamp(text: "Paper", state: .paper)
        PTStamp(text: "Covered", state: .covered, compact: true)
    }
    .padding(40)
    .background(PT.paperFill)
}
