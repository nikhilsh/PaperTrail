import SwiftUI

// MARK: - DossierTabBar (docs/design-v3/V3_BRIEF.md §4, `PaperTrail v3
// Ideas.html` C2 mock `.dossier-tab`/`.dt`/`.dt.on`)
//
// Proof / Service / Papers segmented control below the coverage passport.
// Which segments appear depends on which of `serviceLedger`/`manualOnFile`
// are on (see `RecordDetailView.visibleDossierTabs`) — this view just
// renders whatever list it's given, gold-pill active state per the mock.

/// The three dossier tabs. Not every record shows all three — see
/// `RecordDetailView.visibleDossierTabs`.
enum DossierTab: Hashable {
    case proof
    case service
    case papers

    var label: String {
        switch self {
        case .proof: "Proof"
        case .service: "Service"
        case .papers: "Papers"
        }
    }
}

struct DossierTabBar: View {
    let tabs: [DossierTab]
    @Binding var selection: DossierTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.label)
                        .ptMonoLabel(9, tracking: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(tab == selection ? PT.inkStamp : PT.txt3)
                        .background {
                            if tab == selection {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LinearGradient(colors: [PT.goldHi, PT.gold], startPoint: .top, endPoint: .bottom))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(PT.hair, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? [.isSelected] : [])
            }
        }
    }
}

#Preview("DossierTabBar") {
    VStack(spacing: 16) {
        DossierTabBar(tabs: [.proof, .service, .papers], selection: .constant(.service))
        DossierTabBar(tabs: [.proof, .papers], selection: .constant(.proof))
    }
    .padding(24)
    .background(PT.inkCanvas)
}
