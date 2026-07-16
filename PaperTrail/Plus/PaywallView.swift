import SwiftUI
import StoreKit
import UIKit

/// The PaperTrail Plus paywall — the "Membership Certificate" (docs/design-v2/
/// V2_BRIEF.md §3 P1, DESIGN_LANGUAGE.md §7, ANIMATION_SPEC.md §3/§4/§8b).
/// A full-screen sheet built on `CertificateView` (Wave A, `Design/V2/
/// CertificateView.swift`): kicker, serif title, italic tagline, gold seal,
/// four benefit checks (`PlusConfig.benefits`), gold rule, then a two-plan
/// picker (Annual default-selected + Monthly — v2.1 supersedes the old
/// three-tier paywall; no lifetime tier is sold anymore, see `PlusConfig
/// .ProductID.subscriptionPlans`).
///
/// Purchase choreography per ANIMATION_SPEC §3: the CTA label swaps to
/// "Confirming with the App Store…" on tap, then a MEMBER ✓ `PTStamp` slams
/// onto the certificate on verified success (`.success` haptic) before the
/// sheet dismisses ~1.2s later — Settings then shows the gold member-card
/// entrance (`GoldMemberCard`, Wave A) and a "struck in gold" toast.
///
/// Lifetime stays recognized as a *past* entitlement (see `PlusConfig
/// .ProductID.all` / `PlusEntitlements`) — this screen just never sells it
/// again; `PlusDebugView` keeps its lifetime buy button for sandbox testing.
///
/// Present with `.sheet` wrapped in its own `NavigationStack` (see
/// `SettingsView`/`HouseholdView` call sites) so the trailing close button
/// has a toolbar to live in.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var yearlyProduct: Product?
    @State private var monthlyProduct: Product?
    @State private var selectedIsYearly = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    /// Set on verified purchase success — mounts the MEMBER ✓ stamp overlay
    /// (ANIMATION_SPEC §3.3) and holds the sheet open for the 1.2s dismiss
    /// delay.
    @State private var purchaseSucceeded = false
    @State private var alert: PaywallAlert?

    private var selectedProduct: Product? {
        selectedIsYearly ? yearlyProduct : monthlyProduct
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    CertificateView(
                        tagline: "Renewed yearly, like a library card.",
                        benefits: PlusConfig.benefits.map(\.title)
                    ) {
                        priceSlot
                    }

                    if purchaseSucceeded {
                        MemberStampOverlay(reduceMotion: reduceMotion)
                    }
                }

                if loadState == .loaded {
                    ctaButton
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

    // MARK: - Price slot (certificate content, spec v2.1)

    @ViewBuilder
    private var priceSlot: some View {
        switch loadState {
        case .loading:
            ProgressView().tint(PT.goldDeep).padding(.vertical, 10)
        case .unavailable:
            unavailableBlock
        case .loaded:
            VStack(spacing: 8) {
                if let yearlyProduct {
                    PlanPickerRow(
                        title: "Annual",
                        price: "\(yearlyProduct.displayPrice)/yr",
                        detail: "≈ \(monthlyEquivalent(of: yearlyProduct)) a month",
                        isSelected: selectedIsYearly,
                        action: { selectedIsYearly = true }
                    )
                }
                if let monthlyProduct {
                    PlanPickerRow(
                        title: "Monthly",
                        price: "\(monthlyProduct.displayPrice)/mo",
                        isSelected: !selectedIsYearly,
                        action: { selectedIsYearly = false }
                    )
                }
                PlanFinePrint(text: finePrintText)
            }
            .frame(maxWidth: 262)
        }
    }

    private var unavailableBlock: some View {
        VStack(spacing: 6) {
            Text("Plus isn't available right now")
                .font(PTFont.serif(15, weight: 600))
                .foregroundStyle(PT.onPaper)
            Text("Check back soon — everything free stays free in the meantime.")
                .font(.system(size: 12))
                .foregroundStyle(PT.onPaper3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 240)
    }

    private var finePrintText: String {
        let priceText: String? = selectedIsYearly
            ? yearlyProduct.map { "\($0.displayPrice)/yr" }
            : monthlyProduct.map { "\($0.displayPrice)/mo" }
        return "First 2 weeks free · then \(priceText ?? "—"). We'll remind you before every renewal. Cancel keeps everything."
    }

    private func monthlyEquivalent(of product: Product) -> String {
        (product.price / 12).formatted(product.priceFormatStyle)
    }

    // MARK: - CTA (ANIMATION_SPEC §3.2)

    private var ctaButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Text(isPurchasing ? "Confirming with the App Store…" : "Start 2 weeks free")
        }
        .buttonStyle(PTGoldButtonStyle())
        .opacity(isPurchasing ? 0.7 : 1)
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
            let loaded = try await Product.products(for: PlusConfig.ProductID.subscriptionPlans)
            yearlyProduct = loaded.first { $0.id == PlusConfig.ProductID.yearly }
            monthlyProduct = loaded.first { $0.id == PlusConfig.ProductID.monthly }
            guard yearlyProduct != nil || monthlyProduct != nil else {
                loadState = .unavailable
                return
            }
            selectedIsYearly = yearlyProduct != nil
            loadState = .loaded
        } catch {
            AppLogger.error("Failed to load Plus products: \(error.localizedDescription)", category: "plus")
            loadState = .unavailable
        }
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        // Shared with PlusDebugView's direct buy buttons — one purchase
        // code path, one place that logs (PlusEntitlements.purchase(_:)).
        switch await PlusEntitlements.shared.purchase(product) {
        case .success:
            await handlePurchaseSuccess()
        case .userCancelled:
            break
        case .pending:
            alert = .pending
        case .failed(let message):
            alert = .error(message)
        }
    }

    /// ANIMATION_SPEC §3.3–4: MEMBER ✓ stamp slams on, `.success` haptic,
    /// then a 1.2s hold before the sheet dismisses so the stamp actually
    /// reads before Settings takes over with the gold-strike entrance.
    private func handlePurchaseSuccess() async {
        purchaseSucceeded = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(for: .seconds(1.2))
        dismiss()
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

// MARK: - MEMBER ✓ stamp overlay (ANIMATION_SPEC §3.3)

/// scale 2.4→0.92→1.05→1, rotate −16°→−3°, 500ms `stampEase` — the slight
/// overshoot is the timing curve's own doing (`PTMotion.stampEase`'s control
/// point deliberately exceeds 1), so a single `withAnimation` from the start
/// values to the rest values is enough; no manual keyframe sequence needed
/// (matches `GoldMemberCard.strikeIn()`'s one-shot pattern). On an 88%-opaque
/// paper chip, per spec. Reduce Motion: crossfade, no overshoot.
private struct MemberStampOverlay: View {
    let reduceMotion: Bool

    // `PTStamp`/`StampBadge` already bakes in a fixed -3° rotation
    // (DESIGN_LANGUAGE.md §4's stamp motif), so this wrapper's own rotation
    // only needs to cover the REMAINING swing: -13°→0° composes with that
    // baked-in -3° to the spec's total -16°→-3°.
    @State private var scale: CGFloat = 2.4
    @State private var rotation: Double = -13
    @State private var opacity: Double = 0

    var body: some View {
        PTStamp(text: "Member ✓", state: .paper)
            .padding(14)
            .background(PT.paperFill.opacity(0.88), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onAppear(perform: slamIn)
    }

    private func slamIn() {
        withAnimation(PTMotion.reduced(PTMotion.stampEase(0.5), reduceMotion: reduceMotion)) {
            scale = 1
            rotation = 0
            opacity = 1
        }
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
}
