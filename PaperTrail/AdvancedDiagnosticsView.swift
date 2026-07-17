import SwiftUI
import SwiftData
import UIKit

/// The new home for every technical value that used to greet users on the main
/// Settings surface (§2). Pushed from Settings → "Advanced & Diagnostics".
/// Invaluable for support; calm by default. Adds a real `Copy diagnostics`.
struct AdvancedDiagnosticsView: View {
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]
    @Query private var merchantProfiles: [MerchantProfile]
    @Query private var productMemories: [ProductCategoryMemory]
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("activeSyncBackend") private var activeSyncBackend = "Unknown"
    @AppStorage("cloudKitAccountStatus") private var cloudKitAccountStatus = "Unknown"
    @AppStorage("crashReportingEnabled") private var crashReportingEnabled = true

    @State private var copied = false
    @State private var correctionHealth = CorrectionLogger.CorrectionHealth()

    private var totalImageSize: String {
        let totalBytes = attachments.reduce(into: 0) { total, attachment in
            let url = ImageStorageManager.url(for: attachment.localFilename)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            total += size
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    private var localImageCount: Int {
        attachments.filter { FileManager.default.fileExists(atPath: ImageStorageManager.url(for: $0.localFilename).path) }.count
    }

    private var proofImagesSummary: String {
        if attachments.isEmpty { return "None" }
        if !cloudImageSync.activeTransfers.isEmpty { return "Syncing" }
        if !cloudImageSync.transferErrors.isEmpty { return "Needs attention" }
        return "Synced"
    }

    private var onDeviceSummary: String {
        attachments.isEmpty ? "None" : "\(localImageCount) of \(attachments.count) offline"
    }

    private var syncStatusText: String {
        activeSyncBackend == "Local fallback" ? "Local fallback" : (cloudKitAccountStatus == "Available" ? "Active" : "iCloud required")
    }

    private var activeWarrantyCount: Int {
        records.filter { $0.warrantyStatus == .active || $0.warrantyStatus == .expiringSoon }.count
    }

    private var scheduledNotificationsSummary: String {
        records.contains(where: \.warrantyNotificationScheduled) ? "Scheduled" : "None"
    }

    private var versionString: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var buildString: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostics")
                        .font(PTFont.serif(30, weight: 600))
                        .foregroundStyle(PT.txt)
                    Text("Nothing here needs your attention day-to-day. It's for debugging and for when you contact support.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { copyDiagnostics() } label: {
                    Label(copied ? "Copied" : "Copy diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(PTGoldButtonStyle())

                // iCloud & sync
                SettingsSectionLabel(text: "iCloud & sync")
                    .padding(.top, 2)
                SettingsCard {
                    SettingsRow(title: "Sync status", value: syncStatusText, valueColor: activeSyncBackend == "Local fallback" ? PT.amber : PT.sage)
                    SettingsRowDivider()
                    SettingsRow(title: "iCloud account", value: cloudKitAccountStatus, valueColor: cloudKitAccountStatus == "Available" ? PT.sage : PT.txt3)
                    SettingsRowDivider()
                    SettingsRow(title: "Sync engine", value: "CloudKit")
                    SettingsRowDivider()
                    SettingsRow(title: "Local persistence", value: "SwiftData + CloudKit")
                }

                if activeSyncBackend == "Local fallback" {
                    Text("CloudKit failed during startup, so PaperTrail is using local-only storage on this device.")
                        .font(.caption)
                        .foregroundStyle(PT.amber)
                        .padding(.horizontal, 4)
                }

                // Storage
                SettingsSectionLabel(text: "Storage")
                SettingsCard {
                    SettingsRow(title: "Records", value: "\(records.count)")
                    SettingsRowDivider()
                    SettingsRow(title: "Attachments", value: "\(attachments.count)")
                    SettingsRowDivider()
                    SettingsRow(title: "Image storage", value: totalImageSize)
                    SettingsRowDivider()
                    SettingsRow(title: "Proof images", value: proofImagesSummary, valueColor: proofImagesSummary == "Synced" ? PT.sage : PT.txt3)
                    SettingsRowDivider()
                    SettingsRow(title: "On this device", value: onDeviceSummary)
                }

                if localImageCount < attachments.count {
                    Button("Download missing images") { downloadMissing() }
                        .font(PTFont.mono(11, medium: true))
                        .foregroundStyle(PT.gold)
                        .padding(.horizontal, 4)
                }
                if !cloudImageSync.transferErrors.isEmpty {
                    Label("\(cloudImageSync.transferErrors.count) image sync issue(s)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PT.amber)
                        .padding(.horizontal, 4)
                }

                // Warranties — the two counts the old Settings surfaced.
                SettingsSectionLabel(text: "Warranties")
                SettingsCard {
                    SettingsRow(title: "Active warranties", value: "\(activeWarrantyCount)")
                    SettingsRowDivider()
                    SettingsRow(title: "Warranty notifications", value: scheduledNotificationsSummary)
                }

                // Learning — how the extraction self-improvement loop is doing.
                SettingsSectionLabel(text: "Learning")
                SettingsCard {
                    SettingsRow(title: "Merchant profiles", value: "\(merchantProfiles.count)")
                    SettingsRowDivider()
                    SettingsRow(title: "Product memories", value: "\(productMemories.count)")
                    SettingsRowDivider()
                    SettingsRow(title: "Corrections logged",
                                subtitle: "\(correctionHealth.last30Days) in the last 30 days",
                                value: "\(correctionHealth.totalCorrections)")
                    if let field = correctionHealth.mostCorrectedField {
                        SettingsRowDivider()
                        SettingsRow(title: "Most corrected field", value: field)
                    }
                }

                // Observability
                SettingsSectionLabel(text: "Observability")
                SettingsCard {
                    SettingsRow(
                        title: "Crash & error reporting",
                        subtitle: "Anonymous diagnostics via Sentry · applies on next launch",
                        toggle: $crashReportingEnabled
                    )
                }

                // Build
                SettingsSectionLabel(text: "Build")
                SettingsCard {
                    SettingsRow(title: "Version", value: versionString)
                    SettingsRowDivider()
                    SettingsRow(title: "Build", value: buildString)
                }

                // Plus (debug) — only when the debug console is compiled in.
                // MUST be false (and this section gone) before an App Store
                // submission; see PlusConfig.debugConsoleEnabled.
                if PlusConfig.debugConsoleEnabled {
                    SettingsSectionLabel(text: "Plus (debug)")
                    SettingsCard {
                        NavigationLink { PlusDebugView() } label: {
                            SettingsRow(icon: "sparkles", iconColor: PT.gold, title: "Plus Debug",
                                        subtitle: "IAP entitlements, products & event log", showChevron: true)
                        }.buttonStyle(.plain)
                    }
                }

                // v3 flags — compiled out of App Store builds entirely (see
                // FlagsView.swift); this row goes with it.
                #if !APPSTORE
                SettingsSectionLabel(text: "v3")
                SettingsCard {
                    NavigationLink { FlagsView() } label: {
                        SettingsRow(icon: "flag", iconColor: PT.amber, title: "Flags",
                                    subtitle: "Toggle v3 features for this build", showChevron: true)
                    }.buttonStyle(.plain)
                }
                #endif
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 6)
            .padding(.bottom, 130)
        }
        .ptScreen()
        .task {
            // File IO off the render path — counts only, never values.
            correctionHealth = CorrectionLogger.healthSummary()
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Settings")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
    }

    // MARK: - Copy diagnostics

    private func copyDiagnostics() {
        var lines: [String] = []
        lines.append("PaperTrail Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: .now))")
        lines.append("")
        lines.append("[App]")
        lines.append("Version: \(versionString)")
        lines.append("Build: \(buildString)")
        lines.append("Device: \(Self.deviceModelIdentifier())")
        lines.append("iOS: \(UIDevice.current.systemVersion)")
        lines.append("")
        lines.append("[iCloud & sync]")
        lines.append("Sync status: \(syncStatusText)")
        lines.append("Sync engine: CloudKit")
        lines.append("Local persistence: SwiftData + CloudKit")
        lines.append("Active backend: \(activeSyncBackend)")
        lines.append("iCloud account: \(cloudKitAccountStatus)")
        lines.append("")
        lines.append("[Storage]")
        lines.append("Records: \(records.count)")
        lines.append("Attachments: \(attachments.count)")
        lines.append("Image storage: \(totalImageSize)")
        lines.append("Proof images: \(proofImagesSummary)")
        lines.append("On device: \(onDeviceSummary)")
        lines.append("Image sync errors: \(cloudImageSync.transferErrors.count)")
        lines.append("Active warranties: \(activeWarrantyCount)")
        lines.append("Warranty notifications: \(scheduledNotificationsSummary)")
        lines.append("")
        lines.append("[Learning]")
        lines.append("Merchant profiles: \(merchantProfiles.count)")
        lines.append("Product memories: \(productMemories.count)")
        lines.append("Corrections logged: \(correctionHealth.totalCorrections) (\(correctionHealth.last30Days) last 30 days)")
        if let field = correctionHealth.mostCorrectedField {
            lines.append("Most corrected field: \(field)")
        }
        lines.append("")
        lines.append("[Observability]")
        lines.append("Crash reporting enabled: \(crashReportingEnabled)")

        UIPasteboard.general.string = lines.joined(separator: "\n")
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func downloadMissing() {
        Task {
            let infos = attachments.map { AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename) }
            await cloudImageSync.syncMissingImages(attachments: infos)
        }
    }

    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? UIDevice.current.model
            }
        }
    }

}
