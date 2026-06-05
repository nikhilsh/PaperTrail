import SwiftUI
import SwiftData
import UIKit

/// "Something broke — get it fixed, proof in hand."
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @Query private var allAttachments: [Attachment]
    let record: PurchaseRecord


    private var attachments: [Attachment] { allAttachments.filter { $0.recordID == record.id } }
    private var support: SupportInfo? { record.supportInfo }

    private var brand: String {
        support?.providerName ?? record.merchantName ?? "the manufacturer"
    }

    private var isCovered: Bool {
        record.warrantyStatus == .active || record.warrantyStatus == .expiringSoon
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let's get it sorted.")
                        .font(PTFont.serif(32, weight: 600))
                        .foregroundStyle(PT.txt)
                    Text("\(record.productName) — here's everything you need to make the call.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                }
                .padding(.top, 8)

                tonePanel

                stepCard(number: 1, title: "Your proof is ready") {
                    if attachments.isEmpty {
                        Text("No proof images on file for this record.")
                            .font(.system(size: 13))
                            .foregroundStyle(PT.onPaper2)
                    } else {
                        ProofChipsOnPaper(attachments: attachments)
                    }
                    // The Claim Packet (§9) supersedes the raw proof-bundle share:
                    // one formatted PDF with everything a claim needs.
                    NavigationLink {
                        ClaimPacketView(record: record)
                    } label: {
                        Text("Get claim packet")
                    }
                    .buttonStyle(PTDarkButtonStyle())
                }

                stepCard(number: 2, title: "Contact \(brand) support") {
                    if let support {
                        Text(support.phoneNumber)
                            .font(PTFont.mono(16, medium: true))
                            .foregroundStyle(PT.onPaper)
                        unverifiedNote(support)
                        Button {
                            call(support.phoneNumber)
                        } label: {
                            Label("Call", systemImage: "phone.fill")
                        }
                        .buttonStyle(PTDarkButtonStyle())
                    } else {
                        Text("No saved support contact. Try the manufacturer's website or your receipt.")
                            .font(.system(size: 13))
                            .foregroundStyle(PT.onPaper2)
                    }
                }

                stepCard(number: 3, title: "Find a service center") {
                    Text("Locate an authorized \(brand) repair center near you.")
                        .font(.system(size: 13))
                        .foregroundStyle(PT.onPaper2)
                    Button {
                        findServiceCenter()
                    } label: {
                        Label("Open in Maps", systemImage: "map.fill")
                    }
                    .buttonStyle(PTDarkButtonStyle())
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
    }

    // MARK: Tone panel — honest about likely cost

    private var tonePanel: some View {
        let tone = record.warrantyStatus.tone
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCovered ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(tone)
            VStack(alignment: .leading, spacing: 3) {
                Text(isCovered ? "Under warranty" : "Out of warranty")
                    .font(PTFont.serif(16, weight: 600))
                    .foregroundStyle(PT.txt)
                Text(isCovered
                     ? "Repairs are likely free. Have your proof ready when you call."
                     : "Repairs are likely paid — but your proof is still on file if you need it.")
                    .font(.system(size: 13))
                    .foregroundStyle(PT.txt2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tone.opacity(0.3), lineWidth: 1))
    }

    // MARK: Step card

    @ViewBuilder
    private func stepCard<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(PTFont.mono(12, medium: true))
                    .foregroundStyle(PT.paper)
                    .frame(width: 24, height: 24)
                    .background(PT.inkStamp, in: Circle())
                    .overlay(Circle().stroke(PT.goldDeep, lineWidth: 1))
                Text(title)
                    .font(PTFont.serif(17, weight: 600))
                    .foregroundStyle(PT.onPaper)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    // MARK: Unverified note (product requirement — keep intent verbatim)

    @ViewBuilder
    private func unverifiedNote(_ support: SupportInfo) -> some View {
        if support.confidence == .verified {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(PT.sageDeep)
                Text("Verified from your receipt")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.sageDeep)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x9A7A33))
                Text("Best guess · looked up, not from your receipt.")
                    .font(PTFont.mono(10))
                    .foregroundStyle(Color(hex: 0x9A7A33))
            }
        }
    }

    // MARK: Actions

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { openURL(url) }
    }

    private func findServiceCenter() {
        let query = "\(brand) service center".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(query)") { openURL(url) }
    }
}

/// Proof chips tinted for a cream surface.
private struct ProofChipsOnPaper: View {
    let attachments: [Attachment]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.type == .warranty ? "shield.lefthalf.filled" : "receipt")
                            .font(.system(size: 10))
                        Text(attachment.type.rawValue)
                            .font(PTFont.mono(10))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(PT.onPaper2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: 0x211C12, alpha: 0.05), in: Capsule())
                    .overlay(Capsule().stroke(PT.onPaperHair, lineWidth: 1))
                }
            }
        }
    }
}

#Preview {
    NavigationStack { Text("Requires SwiftData context") }
        .environmentObject(CloudImageSyncManager.shared)
}
