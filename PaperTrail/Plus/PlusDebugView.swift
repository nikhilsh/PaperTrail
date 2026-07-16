import SwiftUI
import StoreKit
import UIKit

/// A debug-only console for PaperTrail Plus (StoreKit 2 IAP). Reachable from
/// Advanced & Diagnostics only when `PlusConfig.debugConsoleEnabled`.
///
/// Why this exists: there is no Mac/Xcode on the machine PaperTrail builds
/// on (see CLAUDE.md), so Xcode's StoreKit Transaction Manager isn't
/// available for sandbox testing. Ad Hoc OTA builds run against the real
/// sandbox App Store environment, so the app itself has to expose raw
/// StoreKit state — entitlements, product metadata, purchase outcomes — for
/// the flow to be diagnosable off a device transcript.
///
/// ⚠️ Debug tooling only. `PlusConfig.debugConsoleEnabled` MUST be `false`
/// before any App Store submission — see its doc comment.
struct PlusDebugView: View {
    @Environment(\.dismiss) private var dismiss

    private var entitlements: PlusEntitlements { PlusEntitlements.shared }

    // Entitlement dump
    @State private var entitlementRows: [EntitlementRow] = []

    // Products
    @State private var products: [Product] = []
    @State private var productsError: String?
    @State private var loadingProducts = false

    // Actions
    @State private var isBusy = false
    @State private var actionResult: String?
    @State private var purchaseOutcomes: [String: String] = [:]
    @State private var showPaywall = false
    @State private var showOfferCodeRedemption = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                entitlementSection
                productsSection
                actionsSection
                simulateSection
                eventLogSection
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 6)
            .padding(.bottom, 60)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Diagnostics")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
        .task { await refreshAll() }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
                .tint(PT.gold)
                .preferredColorScheme(.dark)
        }
        .offerCodeRedemption(isPresented: $showOfferCodeRedemption) { result in
            switch result {
            case .success:
                actionResult = "Offer code redemption completed"
            case .failure(let error):
                AppLogger.error("Plus Debug: offer code redemption failed: \(error.localizedDescription)", category: "plus")
                actionResult = "Offer code redemption failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plus Debug")
                .font(PTFont.serif(28, weight: 600))
                .foregroundStyle(PT.txt)
            Text("Debug-only IAP console — never ships to the App Store. Sandbox testing without Xcode's Transaction Manager.")
                .font(.system(size: 13))
                .foregroundStyle(PT.txt2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Entitlement state

    private var entitlementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Entitlement state")
            SettingsCard {
                SettingsRow(title: "hasPlus (effective)", value: entitlements.hasPlus ? "true" : "false",
                            valueColor: entitlements.hasPlus ? PT.sage : PT.txt3)
                SettingsRowDivider()
                SettingsRow(title: "Real entitlement (persisted)", value: entitlements.realHasPlus ? "true" : "false",
                            valueColor: entitlements.realHasPlus ? PT.sage : PT.txt3)
                SettingsRowDivider()
                SettingsRow(title: "PlusConfig.enabled", value: PlusConfig.enabled ? "true" : "false")
            }

            if entitlementRows.isEmpty {
                Text("No current entitlements from Transaction.currentEntitlements.")
                    .font(.system(size: 12))
                    .foregroundStyle(PT.txt3)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entitlementRows) { row in
                        entitlementRowView(row)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.bottom, 4)
    }

    private func entitlementRowView(_ row: EntitlementRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.productID)
                .font(PTFont.mono(12, medium: true))
                .foregroundStyle(PT.txt)
            Text("purchased \(row.purchaseDate.formatted(date: .abbreviated, time: .shortened)) · env \(row.environment)")
                .font(PTFont.mono(10.5))
                .foregroundStyle(PT.txt3)
            if let expirationDate = row.expirationDate {
                Text("expires \(expirationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(PTFont.mono(10.5))
                    .foregroundStyle(PT.txt3)
            }
            if let revocationDate = row.revocationDate {
                Text("REVOKED \(revocationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(PTFont.mono(10.5, medium: true))
                    .foregroundStyle(PT.terra)
            }
            if !row.verified {
                Text("UNVERIFIED\(row.verificationError.map { " — \($0)" } ?? "")")
                    .font(PTFont.mono(10.5, medium: true))
                    .foregroundStyle(PT.terra)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    // MARK: - Products

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Products (App Store Connect)")

            if loadingProducts {
                HStack { Spacer(); ProgressView().tint(PT.gold); Spacer() }
                    .padding(.vertical, 10)
            } else if let productsError {
                Text("Failed to load products — this is the #1 diagnostic for ASC metadata/propagation issues:")
                    .font(.system(size: 12))
                    .foregroundStyle(PT.terra)
                Text(productsError)
                    .font(PTFont.mono(11))
                    .foregroundStyle(PT.terra)
                    .padding(.top, 2)
            } else if products.isEmpty {
                Text("Product.products(for:) returned zero products for \(PlusConfig.ProductID.all.joined(separator: ", ")).")
                    .font(.system(size: 12))
                    .foregroundStyle(PT.amber)
            } else {
                VStack(spacing: 8) {
                    ForEach(products, id: \.id) { product in
                        productRowView(product)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func productRowView(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(product.id)
                    .font(PTFont.mono(12, medium: true))
                    .foregroundStyle(PT.txt)
                Spacer()
                Text(product.displayPrice)
                    .font(PTFont.mono(12, medium: true))
                    .foregroundStyle(PT.gold)
            }
            Text("type \(productTypeText(product))\(subscriptionSuffix(product))")
                .font(PTFont.mono(10.5))
                .foregroundStyle(PT.txt3)

            HStack {
                Button {
                    Task { await buy(product) }
                } label: {
                    Text("Buy")
                        .font(PTFont.mono(11, medium: true))
                }
                .buttonStyle(.bordered)
                .tint(PT.gold)
                .disabled(isBusy)

                if let outcome = purchaseOutcomes[product.id] {
                    Text(outcome)
                        .font(PTFont.mono(10.5))
                        .foregroundStyle(PT.txt2)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private func productTypeText(_ product: Product) -> String {
        switch product.type {
        case .consumable: "consumable"
        case .nonConsumable: "non-consumable"
        case .autoRenewable: "auto-renewable subscription"
        case .nonRenewable: "non-renewing subscription"
        default: "unknown"
        }
    }

    private func subscriptionSuffix(_ product: Product) -> String {
        guard let subscription = product.subscription else { return "" }
        var text = " · \(periodText(subscription.subscriptionPeriod))"
        if subscription.introductoryOffer != nil {
            text += " · has intro offer"
        }
        return text
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        default: unit = "period"
        }
        return "\(period.value) \(unit)\(period.value == 1 ? "" : "s")"
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Actions")
            SettingsCard {
                SettingsRow(icon: "arrow.clockwise", iconColor: PT.gold, title: "Refresh entitlements", showChevron: true,
                            action: { Task { await refreshEntitlementsAction() } })
                SettingsRowDivider()
                SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: PT.gold, title: "Restore purchases", subtitle: "AppStore.sync()", showChevron: true,
                            action: { Task { await restoreAction() } })
                SettingsRowDivider()
                SettingsRow(icon: "sparkles", iconColor: PT.gold, title: "Show paywall", showChevron: true,
                            action: { showPaywall = true })
                SettingsRowDivider()
                SettingsRow(icon: "gearshape", iconColor: PT.gold, title: "Manage subscriptions", subtitle: "AppStore.showManageSubscriptions(in:)", showChevron: true,
                            action: { manageSubscriptions() })
                SettingsRowDivider()
                SettingsRow(icon: "ticket", iconColor: PT.gold, title: "Present offer code redemption", showChevron: true,
                            action: { showOfferCodeRedemption = true })
            }
            if let actionResult {
                Text(actionResult)
                    .font(PTFont.mono(11))
                    .foregroundStyle(PT.txt2)
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Simulate Plus

    private var simulateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Simulate Plus (local override)")
            SettingsCard {
                SettingsRow(
                    icon: "theatermasks",
                    iconColor: PT.gold,
                    title: "Simulate Plus (this device only, debug builds)",
                    subtitle: "Bypasses payment so gates/paywall can be tested. Ignored unless the debug console is enabled.",
                    toggle: Binding(
                        get: { entitlements.simulateOverride },
                        set: { entitlements.simulateOverride = $0 }
                    )
                )
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Event log

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Event log (last \(entitlements.eventLog.count))")
            if entitlements.eventLog.isEmpty {
                Text("No Plus activity logged yet this session.")
                    .font(.system(size: 12))
                    .foregroundStyle(PT.txt3)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entitlements.eventLog.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(PTFont.mono(10.5))
                            .foregroundStyle(PT.txt2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PT.hair, lineWidth: 1))
            }
        }
    }

    // MARK: - Action handlers

    private func refreshAll() async {
        await loadEntitlementDump()
        await loadProducts()
    }

    private func refreshEntitlementsAction() async {
        isBusy = true
        defer { isBusy = false }
        await entitlements.refresh()
        await loadEntitlementDump()
        actionResult = "Entitlements refreshed"
    }

    private func restoreAction() async {
        isBusy = true
        defer { isBusy = false }
        await entitlements.restore()
        await loadEntitlementDump()
        actionResult = "Restore requested — hasPlus is now \(entitlements.hasPlus)"
    }

    private func buy(_ product: Product) async {
        isBusy = true
        defer { isBusy = false }
        let outcome = await entitlements.purchase(product)
        purchaseOutcomes[product.id] = outcome.summary
        await loadEntitlementDump()
    }

    private func manageSubscriptions() {
        guard let scene = foregroundWindowScene() else {
            actionResult = "Manage subscriptions: no active window scene"
            return
        }
        Task {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                actionResult = "Manage subscriptions presented"
            } catch {
                AppLogger.error("Plus Debug: manage subscriptions failed: \(error.localizedDescription)", category: "plus")
                actionResult = "Manage subscriptions failed: \(error.localizedDescription)"
            }
        }
    }

    private func foregroundWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func loadEntitlementDump() async {
        var rows: [EntitlementRow] = []
        // Qualified: SwiftUI also exports a `Transaction` type (animation
        // transactions), so plain `Transaction` is ambiguous once this file
        // imports both SwiftUI and StoreKit.
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                rows.append(EntitlementRow(transaction: transaction, verified: true, verificationError: nil))
            case .unverified(let transaction, let error):
                rows.append(EntitlementRow(transaction: transaction, verified: false, verificationError: error.localizedDescription))
            @unknown default:
                continue
            }
        }
        entitlementRows = rows.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private func loadProducts() async {
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            let loaded = try await Product.products(for: PlusConfig.ProductID.all)
            products = PlusConfig.ProductID.all.compactMap { id in loaded.first { $0.id == id } }
            productsError = nil
        } catch {
            products = []
            productsError = error.localizedDescription
            AppLogger.error("Plus Debug: failed to load products: \(error.localizedDescription)", category: "plus")
        }
    }
}

/// A single row from `Transaction.currentEntitlements`, flattened for display.
private struct EntitlementRow: Identifiable {
    let id: String
    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let environment: String
    let verified: Bool
    let verificationError: String?

    init(transaction: StoreKit.Transaction, verified: Bool, verificationError: String?) {
        self.id = String(transaction.id)
        self.productID = transaction.productID
        self.purchaseDate = transaction.purchaseDate
        self.expirationDate = transaction.expirationDate
        self.revocationDate = transaction.revocationDate
        self.environment = Self.describe(transaction.environment)
        self.verified = verified
        self.verificationError = verificationError
    }

    private static func describe(_ environment: AppStore.Environment) -> String {
        switch environment {
        case .production: "production"
        case .sandbox: "sandbox"
        case .xcode: "xcode"
        default: "unknown"
        }
    }
}
