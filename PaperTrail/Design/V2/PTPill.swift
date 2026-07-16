import SwiftUI

// MARK: - PTPill (docs/design-v2/DESIGN_LANGUAGE.md §4, pt.css `.pill`)
//
// `StatusPill` (`PaperTrail/Design/PTComponents.swift`) already renders this
// exact look, but it's keyed off `WarrantyStatus` — fine for warranty cards,
// awkward for anything else that wants the same pill language (household
// rows, digest badges). `PTPill` carries the identical metrics (10pt mono
// caps, 6pt dot, 9/4 padding) keyed off the spec's four named states instead,
// including the "ghost" state pt.css defines but `WarrantyStatus` has no
// direct equivalent for. Per pt.css, `.pill.ghost` has no `.dot` rule (no
// dot renders) — matched here the same way `StatusPill` already hides its
// dot for `.unknown`.

enum PTPillState: Equatable {
    case covered
    case expiring
    case expired
    case ghost

    var tone: Color {
        switch self {
        case .covered: PT.sage
        case .expiring: PT.amber
        case .expired: PT.terra
        case .ghost: PT.txt2
        }
    }

    var textColor: Color {
        switch self {
        case .covered: Color(hex: 0xCFE0B0)
        case .expiring: Color(hex: 0xF0D49A)
        case .expired: Color(hex: 0xEAB69C)
        case .ghost: PT.txt2
        }
    }

    var background: Color {
        switch self {
        case .covered: Color(hex: 0x93A86F, alpha: 0.14)
        case .expiring: Color(hex: 0xD7A64C, alpha: 0.15)
        case .expired: Color(hex: 0xC56A45, alpha: 0.16)
        case .ghost: Color(hex: 0xE7DCC4, alpha: 0.07)
        }
    }
}

struct PTPill: View {
    let text: String
    var state: PTPillState

    var body: some View {
        HStack(spacing: 6) {
            if state != .ghost {
                Circle().fill(state.tone).frame(width: 6, height: 6)
            }
            Text(text).ptMonoLabel(10, tracking: 1.2)
        }
        .foregroundStyle(state.textColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(state.background, in: Capsule())
    }
}

#Preview("PTPill") {
    HStack(spacing: 10) {
        PTPill(text: "Covered", state: .covered)
        PTPill(text: "Expiring", state: .expiring)
        PTPill(text: "Expired", state: .expired)
        PTPill(text: "Ghost", state: .ghost)
    }
    .padding(24)
    .ptScreen()
}
