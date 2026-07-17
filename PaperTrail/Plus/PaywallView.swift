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
    /// Per-plan intro-offer eligibility, resolved once at `loadProducts` —
    /// true only when the product both defines an intro offer AND this
    /// account is actually eligible for it (`isEligibleForIntroOffer`).
    /// Monthly never has an intro offer in ASC, so this is always false for
    /// it regardless of eligibility — the trial copy must never promise a
    /// trial monthly doesn't have (§2).
    @State private var yearlyOffersTrial = false
    @State private var monthlyOffersTrial = false
    @State private var selectedIsYearly = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    /// Set on verified purchase success — mounts the MEMBER ✓ stamp overlay
    /// (ANIMATION_SPEC §3.3) and holds the sheet open for the 1.2s dismiss
    /// delay.
    @State private var purchaseSucceeded = false
    @State private var alert: PaywallAlert?
    /// A product refetch triggered from an unloaded-plan row or the
    /// unavailable block — drives the row's "Checking the App Store…" copy.
    @State private var isRetrying = false

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

                freeForeverSection

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
                      message: Text("Your purchase needs approval before it's complete — Plus starts as soon as it's confirmed."))
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
                } else {
                    unloadedPlanRow(title: "Annual")
                }
                if let monthlyProduct {
                    PlanPickerRow(
                        title: "Monthly",
                        price: "\(monthlyProduct.displayPrice)/mo",
                        isSelected: !selectedIsYearly,
                        action: { selectedIsYearly = false }
                    )
                } else {
                    unloadedPlanRow(title: "Monthly")
                }
                PlanFinePrint(text: finePrintText)
            }
            .frame(maxWidth: 262)
        }
    }

    /// A plan whose product the App Store didn't return still gets a row —
    /// hiding it silently made a two-plan paywall look single-plan whenever
    /// one product lagged (seen live: yearly missing while sandbox caught up
    /// after an ASC metadata change). Tapping retries the fetch; both plans
    /// are configured products, so the row never lies about what's on offer.
    private func unloadedPlanRow(title: String) -> some View {
        PlanPickerRow(
            title: title,
            price: "—",
            detail: isRetrying ? "Checking the App Store…" : "Couldn't load · tap to retry",
            isSelected: false,
            action: retryLoad
        )
    }

    private func retryLoad() {
        guard !isRetrying else { return }
        Task {
            isRetrying = true
            await loadProducts()
            isRetrying = false
        }
    }

    // MARK: - Free forever (docs/MONETIZATION.md "the trust move")

    /// The free-forever list, shown *on the paywall itself* — the trust
    /// move of showing what you're NOT paying for (docs/MONETIZATION.md
    /// §4). A compact checked list under a mono kicker, placed below the
    /// certificate/CTA and above Restore.
    private var freeForeverSection: some View {
        VStack(spacing: 10) {
            Text("FREE FOREVER, ALWAYS")
                .ptMonoLabel(10, tracking: 2.4)
                .foregroundStyle(PT.goldDeep)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(PlusConfig.freeForever, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PT.sageDeep)
                            .padding(.top, 1.5)
                        Text(item)
                            .font(.system(size: 12.5))
                            .foregroundStyle(PT.txt2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: 280)
        .padding(.top, 4)
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
            if PlusConfig.enabled {
                Button(action: retryLoad) {
                    Text(isRetrying ? "Checking the App Store…" : "Try again")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PT.goldDeep)
                }
                .disabled(isRetrying)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 240)
    }

    /// Live per-plan price text, e.g. "S$39.98/yr" / "S$5.98/mo" — `nil`
    /// until that plan's product has loaded.
    private var selectedPriceText: String? {
        selectedIsYearly
            ? yearlyProduct.map { "\($0.displayPrice)/yr" }
            : monthlyProduct.map { "\($0.displayPrice)/mo" }
    }

    /// Whether the SELECTED plan actually offers a trial to this account —
    /// monthly is always false (no intro offer exists on it in ASC); yearly
    /// is only true when both the product defines one AND this account is
    /// eligible (§2: never promise a trial that won't apply).
    private var selectedOffersTrial: Bool {
        selectedIsYearly ? yearlyOffersTrial : monthlyOffersTrial
    }

    private var finePrintText: String {
        PaywallCopy.finePrint(offersTrial: selectedOffersTrial, isYearly: selectedIsYearly, priceText: selectedPriceText)
    }

    private func monthlyEquivalent(of product: Product) -> String {
        (product.price / 12).formatted(product.priceFormatStyle)
    }

    // MARK: - CTA (ANIMATION_SPEC §3.2)

    private var ctaButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Text(isPurchasing ? "Confirming with the App Store…" : ctaTitle)
        }
        .buttonStyle(PTGoldButtonStyle())
        .opacity(isPurchasing ? 0.7 : 1)
        .disabled(isPurchasing || selectedProduct == nil)
    }

    private var ctaTitle: String {
        PaywallCopy.ctaTitle(offersTrial: selectedOffersTrial, priceText: selectedPriceText)
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
            // Never let a flaky refetch drop a product we already have —
            // a retry that fails must not turn a loaded row back into "—".
            yearlyProduct = loaded.first { $0.id == PlusConfig.ProductID.yearly } ?? yearlyProduct
            monthlyProduct = loaded.first { $0.id == PlusConfig.ProductID.monthly } ?? monthlyProduct
            if yearlyProduct == nil || monthlyProduct == nil {
                let missing = [yearlyProduct == nil ? PlusConfig.ProductID.yearly : nil,
                               monthlyProduct == nil ? PlusConfig.ProductID.monthly : nil]
                    .compactMap(\.self)
                AppLogger.warn("Plus products missing from store response: \(missing.joined(separator: ", "))", category: "plus")
            }
        } catch {
            AppLogger.error("Failed to load Plus products: \(error.localizedDescription)", category: "plus")
        }
        guard yearlyProduct != nil || monthlyProduct != nil else {
            loadState = .unavailable
            return
        }
        yearlyOffersTrial = await offersTrial(yearlyProduct)
        monthlyOffersTrial = await offersTrial(monthlyProduct)
        // Only pick a default selection on first load — a retry that fills
        // in the other plan must not stomp what the user already selected.
        if loadState != .loaded {
            selectedIsYearly = yearlyProduct != nil
        }
        loadState = .loaded
    }

    /// True only when `product` both defines an intro offer AND this
    /// account is actually eligible for it — checking eligibility alone
    /// isn't enough (a product with no intro offer, like monthly, would
    /// still report an eligibility value that means nothing here).
    private func offersTrial(_ product: Product?) async -> Bool {
        guard let subscription = product?.subscription, subscription.introductoryOffer != nil else { return false }
        return await subscription.isEligibleForIntroOffer
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
    //
    // Reduce Motion (ANIMATION_SPEC "Don'ts": "skip sheen and stamp
    // overshoot"): `scale`/`rotation` start already at their end values —
    // set in `init`, from the caller-supplied `reduceMotion` (a plain
    // property here, unlike `@Environment`, so it's readable before the
    // view even appears) — so nothing about them ever animates; only
    // `opacity` (below) actually crossfades in.
    @State private var scale: CGFloat
    @State private var rotation: Double
    @State private var opacity: Double = 0

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        _scale = State(initialValue: reduceMotion ? 1 : 2.4)
        _rotation = State(initialValue: reduceMotion ? 0 : -13)
    }

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

// MARK: - Paywall copy (§2/§3 trial-copy + renewal-promise honesty)

/// Pure paywall CTA/fine-print copy logic — extracted for testability
/// (`PaywallCopyTests`): given only the selected plan's resolved trial
/// eligibility and price, decides what to say. No StoreKit `Product`
/// involved, so no live App Store Connect state is needed to test the
/// eligible×hasIntro matrix (§2).
enum PaywallCopy {
    /// "Start 2 weeks free" only when the selected plan actually offers a
    /// trial to this account; otherwise "Subscribe — <price>" (or the bare
    /// "Subscribe" while price hasn't loaded yet) — monthly (no intro offer
    /// in ASC) always falls here, never promising a trial it doesn't have.
    static func ctaTitle(offersTrial: Bool, priceText: String?) -> String {
        if offersTrial { return "Start 2 weeks free" }
        guard let priceText else { return "Subscribe" }
        return "Subscribe — \(priceText)"
    }

    /// Fine print for the selected plan: trial copy only when
    /// `offersTrial`; a paid annual keeps the renewal-reminder promise
    /// (it's real — `RenewalReminder` schedules it); a paid monthly drops
    /// it (no renewal reminder is ever scheduled for monthly — see
    /// `PlusEntitlements.updateRenewalReminder`), so the copy shouldn't
    /// promise one either.
    static func finePrint(offersTrial: Bool, isYearly: Bool, priceText: String?) -> String {
        let priceText = priceText ?? "—"
        if offersTrial {
            return "First 2 weeks free · then \(priceText). We'll remind you before every renewal. Cancel keeps everything."
        }
        if isYearly {
            return "\(priceText). We'll remind you before every renewal. Cancel keeps everything."
        }
        return "\(priceText). Cancel keeps everything."
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
}
