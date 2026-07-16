import SwiftUI
import StoreKit

/// The PaperTrail Plus paywall (docs/MONETIZATION.md "Paywall") — a single
/// themed sheet in the Archive identity, shown from any gate (household
/// invite beyond one member, the whole-home insurance report, Settings).
///
/// Order matters here and is deliberate: the free-forever list comes FIRST
/// (a trust move — show what you're NOT paying for before asking for money),
/// then the three Plus benefits, then plan selection defaulting to yearly.
/// No dark patterns: no fake urgency, no pre-selected upsell beyond the
/// yearly default, close button immediately visible.
///
/// Present with `.sheet` wrapped in its own `NavigationStack` (see
/// `HouseholdView`/`SettingsView` call sites) so the trailing close button
/// has a toolbar to live in — mirrors how `CaptureView` is presented.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case loaded
        case unavailable
    }

    private enum PaywallAlert: Identifiable {
        case error(String)
        case pending

        var id: String {
            switch self {
            case .error(let message): "error-\(message)"
            case .pending: "pending"
            }
        }
    }

    @State private var loadState: LoadState = .loading
    @State private var products: [Product] = []
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alert: PaywallAlert?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                freeForeverCard

                benefitsCard

                planSection

                if loadState == .loaded {
                    purchaseButton
                }

                restoreButton

                legalLinks
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .ptScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PT.txt2)
                }
            }
        }
        .navigationBarBackButtonHidden()
        .task { await loadProducts() }
        .alert(item: $alert) { alert in
            switch alert {
            case .error(let message):
                Alert(title: Text("Couldn't complete purchase"), message: Text(message))
            case .pending:
                Alert(title: Text("Purchase pending"),
                      message: Text("Your purchase needs approval before it's complete — Plus unlocks as soon as it's confirmed."))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAPERTRAIL")
                .ptMonoLabel(9.5, tracking: 2.4)
                .foregroundStyle(PT.goldDeep)
            Text("\(Text("PaperTrail\n").foregroundStyle(PT.txt))\(Text("Plus.").foregroundStyle(PT.goldHi))")
                .font(PTFont.serif(34, weight: 600))
            Text("The payoff moments, for people with a lot to protect.")
                .font(.system(size: 14))
                .foregroundStyle(PT.txt2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - Free forever

    private var freeForeverCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FREE FOREVER, ALWAYS")
                .ptMonoLabel(9.5, tracking: 2.4)
                .foregroundStyle(PT.onPaper3)
                .padding(.bottom, 12)

            ForEach(Array(PlusConfig.freeForever.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(PT.onPaperHair).frame(height: 1) }
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PT.sageDeep)
                        .frame(width: 18)
                    Text(item)
                        .font(.system(size: 13.5))
                        .foregroundStyle(PT.onPaper)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    // MARK: - Plus benefits

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "What Plus adds")
            SettingsCard {
                ForEach(Array(PlusConfig.benefits.enumerated()), id: \.offset) { index, benefit in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(icon: benefit.icon, iconColor: PT.gold, title: benefit.title, subtitle: benefit.subtitle)
                }
            }
        }
    }

    // MARK: - Plan selection

    @ViewBuilder
    private var planSection: some View {
        switch loadState {
        case .loading:
            HStack {
                Spacer()
                ProgressView().tint(PT.gold)
                Spacer()
            }
            .padding(.vertical, 12)
        case .unavailable:
            unavailableCard
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionLabel(text: "Choose a plan")
                VStack(spacing: 10) {
                    ForEach(products, id: \.id) { product in
                        planRow(for: product)
                    }
                }
            }
        }
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plus isn't available right now")
                .font(PTFont.serif(16, weight: 600))
                .foregroundStyle(PT.txt)
            Text("Check back soon — everything free stays free in the meantime.")
                .font(.system(size: 12.5))
                .foregroundStyle(PT.txt3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private func planRow(for product: Product) -> some View {
        let selected = selectedProduct?.id == product.id
        let isYearly = product.id == PlusConfig.ProductID.yearly
        return Button {
            selectedProduct = product
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(selected ? PT.gold : PT.txt3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(PTFont.serif(15.5, weight: 600))
                            .foregroundStyle(PT.txt)
                        if isYearly {
                            Text("SAVE ~44%")
                                .font(PTFont.mono(8.5, medium: true))
                                .tracking(1.0)
                                .foregroundStyle(PT.inkStamp)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PT.goldHi, in: Capsule())
                        }
                    }
                    if isYearly {
                        Text("14-day free trial, then \(product.displayPrice)/yr")
                            .font(.system(size: 11.5))
                            .foregroundStyle(PT.txt3)
                    } else if product.id == PlusConfig.ProductID.lifetime {
                        Text("One-time — pay once, own it forever")
                            .font(.system(size: 11.5))
                            .foregroundStyle(PT.txt3)
                    } else {
                        Text("Billed monthly")
                            .font(.system(size: 11.5))
                            .foregroundStyle(PT.txt3)
                    }
                }

                Spacer(minLength: 8)

                Text(product.displayPrice)
                    .font(PTFont.mono(13, medium: true))
                    .foregroundStyle(PT.txt)
            }
            .padding(14)
            .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? PT.gold : PT.hair, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing { ProgressView().tint(PT.inkStamp) }
                Text(isPurchasing ? "Processing…" : "Get Plus")
            }
        }
        .buttonStyle(PTGoldButtonStyle())
        .disabled(isPurchasing || selectedProduct == nil)
    }

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            HStack(spacing: 6) {
                if isRestoring { ProgressView().tint(PT.txt2) }
                Text("Restore purchases")
            }
            .font(.system(size: 13))
            .foregroundStyle(PT.txt2)
            .frame(maxWidth: .infinity)
        }
        .disabled(isRestoring)
        .padding(.top, 2)
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Spacer()
            Button("Privacy") { openURL("https://papertrail.kaopeh.com/privacy") }
            Text("·").foregroundStyle(PT.txt3)
            Button("Terms") { openURL("https://papertrail.kaopeh.com/terms") }
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(PT.txt3)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func loadProducts() async {
        guard PlusConfig.enabled else {
            loadState = .unavailable
            return
        }
        do {
            let loaded = try await Product.products(for: PlusConfig.ProductID.all)
            guard !loaded.isEmpty else {
                loadState = .unavailable
                return
            }
            // Stable display order: monthly, yearly, lifetime — regardless of
            // what order the App Store returns them in.
            products = PlusConfig.ProductID.all.compactMap { id in loaded.first { $0.id == id } }
            selectedProduct = products.first { $0.id == PlusConfig.ProductID.yearly } ?? products.first
            loadState = .loaded
        } catch {
            AppLogger.error("Failed to load Plus products: \(error.localizedDescription)", category: "monetization")
            loadState = .unavailable
        }
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await PlusEntitlements.shared.refresh()
                dismiss()
            case .userCancelled:
                break
            case .pending:
                alert = .pending
            @unknown default:
                break
            }
        } catch {
            AppLogger.error("Plus purchase failed: \(error.localizedDescription)", category: "monetization")
            alert = .error(error.localizedDescription)
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await PlusEntitlements.shared.restore()
        if PlusEntitlements.shared.hasPlus {
            dismiss()
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
}
