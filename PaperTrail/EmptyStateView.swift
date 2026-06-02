import SwiftUI

// MARK: - Folded-paper "P" mark

/// The brand mark: a cream filing card with a gold dog-ear fold and a serif "P".
struct PFoldMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack(alignment: .bottom) {
            Text("P")
                .font(PTFont.serif(size * 0.54, weight: 600))
                .foregroundStyle(PT.onPaper)
                .frame(maxHeight: .infinity)
            // the icon's gold-rule underline motif, made literal
            GoldRule(width: size * 0.46)
                .padding(.bottom, size * 0.2)
        }
        .frame(width: size, height: size * 1.18)
        .paperCard(goldFold: true, ear: size * 0.3)
    }
}

// MARK: - Empty library / first run

/// Shown when there are no records yet. Doubles as onboarding.
struct EmptyLibraryView: View {
    var onScan: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showManualAdd = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            PFoldMark(size: 78)
                .rotationEffect(.degrees(-4))
                .padding(.bottom, 26)

            Text("PaperTrail").ptWordmark()
                .padding(.bottom, 18)

            (Text("Start your\n").foregroundStyle(PT.txt)
             + Text("paper trail.").italic().foregroundStyle(PT.goldHi))
                .font(PTFont.serif(32, weight: 600))
                .multilineTextAlignment(.center)

            Text("Scan a receipt once. Find the proof, the warranty,\nand who to call — the day something breaks.")
                .font(.system(size: 14))
                .foregroundStyle(PT.txt2)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button(action: onScan) {
                    Text("Scan your first receipt")
                }
                .buttonStyle(PTGoldButtonStyle())

                Button { showManualAdd = true } label: {
                    Text("Add by hand")
                }
                .buttonStyle(PTOutlineButtonStyle())
            }
            .padding(.top, 30)
            .padding(.horizontal, 36)

            Spacer()

            Text("Backed up to iCloud · Yours forever")
                .ptMonoLabel(9, tracking: 1.8)
                .foregroundStyle(PT.txt3)
                .padding(.bottom, 120)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showManualAdd) {
            NavigationStack {
                DraftRecordView(seedType: .other)
            }
            .tint(PT.gold)
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    EmptyLibraryView(onScan: {})
        .ptScreen()
        .environmentObject(CloudImageSyncManager.shared)
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
