import SwiftUI
import SwiftData
import UIKit
import AuthenticationServices
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SettingsView: View {
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]
    @Environment(AuthenticationManager.self) private var authManager
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @AppStorage("activeSyncBackend") private var activeSyncBackend = "Unknown"
    @AppStorage("cloudKitInitError") private var cloudKitInitError = ""
    @AppStorage("cloudKitAccountStatus") private var cloudKitAccountStatus = "Unknown"
    @AppStorage("cloudKitContainerStatus") private var cloudKitContainerStatus = "Not checked"
    @AppStorage("cloudKitContainerIdentifier") private var cloudKitContainerIdentifier = "iCloud.nikhilsh.PaperTrail"
    private let sentryStatus = AppLogger.isSentryEnabled ? "Enabled" : "Disabled"
    private let sentryHost = AppLogger.sentryHost ?? "Not configured"
    @State private var fmDiagResult = ""
    @State private var fmDiagRunning = false

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

    private var missingImageCount: Int {
        attachments.count - localImageCount
    }

    private var imageSyncSummary: String {
        if attachments.isEmpty {
            return "No proof images yet"
        }
        if !cloudImageSync.activeTransfers.isEmpty {
            return "Syncing"
        }
        if !cloudImageSync.transferErrors.isEmpty {
            return "Needs attention"
        }
        return "Synced"
    }

    private var localAvailabilitySummary: String {
        if attachments.isEmpty {
            return "None"
        }
        return "\(localImageCount) of \(attachments.count) available offline"
    }

    private var activeWarrantyCount: Int {
        records.filter { $0.warrantyStatus == .active || $0.warrantyStatus == .expiringSoon }.count
    }

    private var categorySummary: String {
        let categories = Set(records.compactMap(\.category))
        return categories.isEmpty ? "None" : categories.sorted().joined(separator: ", ")
    }

    var body: some View {
        List {
            // Serif title row
            Text("Settings")
                .font(PTFont.serif(34, weight: 600))
                .foregroundStyle(PT.txt)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.top, 4)

            // Account
            Section {
                if authManager.isSignedIn {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(PT.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(authManager.displayName)
                                    .font(PTFont.serif(17, weight: 600))
                                    .foregroundStyle(PT.txt)
                                if let email = authManager.userEmail, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(PT.txt3)
                                } else if let userID = authManager.userID {
                                    Text("Apple ID linked · \(userID.prefix(8))…")
                                        .font(.caption)
                                        .foregroundStyle(PT.txt3)
                                }
                            }
                        }
                        Text("Signed in with Apple")
                            .font(.caption)
                            .foregroundStyle(PT.txt3)
                    }
                    .padding(.vertical, 4)

                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        authManager.handleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 44)

                    Text("Sign in to sync across devices and share records.")
                        .font(.caption)
                        .foregroundStyle(PT.txt3)
                }
            } header: {
                SectionLabel(text: "Account", tone: PT.gold)
            }

            // Sync
            Section {
                row("iCloud", "Automatic")
                row("Backend", activeSyncBackend)
                row("Status", authManager.isSignedIn ? "Active" : "Sign in required")
                row("Sentry", sentryStatus)
                row("CK account", cloudKitAccountStatus)
                row("CK container", cloudKitContainerIdentifier)

                if activeSyncBackend == "Local fallback" {
                    Text("CloudKit failed during startup, so PaperTrail is currently using local-only storage on this device.")
                        .font(.caption)
                        .foregroundStyle(PT.amber)
                }
            } header: {
                SectionLabel(text: "Sync", tone: PT.gold)
            }

            // Storage
            Section {
                row("Records", "\(records.count)")
                row("Attachments", "\(attachments.count)")
                row("Image storage", totalImageSize)
                row("Persistence", "SwiftData + CloudKit")
            } header: {
                SectionLabel(text: "Storage", tone: PT.gold)
            }

            // Image Sync
            Section {
                row("Proof images", imageSyncSummary)
                row("On this device", localAvailabilitySummary)

                if !cloudImageSync.activeTransfers.isEmpty {
                    HStack {
                        ProgressView().tint(PT.gold)
                        Text("Syncing \(cloudImageSync.activeTransfers.count) image(s)…")
                            .font(.caption)
                            .foregroundStyle(PT.txt3)
                    }
                }

                if missingImageCount > 0 {
                    Button("Download missing images") {
                        Task {
                            let syncInfos = attachments.map {
                                AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename)
                            }
                            await cloudImageSync.syncMissingImages(attachments: syncInfos)
                        }
                    }
                    .foregroundStyle(PT.gold)
                }

                if !cloudImageSync.transferErrors.isEmpty {
                    Label("\(cloudImageSync.transferErrors.count) image sync issue(s)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PT.amber)
                }
            } header: {
                SectionLabel(text: "Image Sync", tone: PT.gold)
            }

            // Warranties
            Section {
                row("Active warranties", "\(activeWarrantyCount)")
                row("Notifications", records.filter(\.warrantyNotificationScheduled).count > 0 ? "Scheduled" : "None")
            } header: {
                SectionLabel(text: "Warranties", tone: PT.gold)
            }

            // Categories
            Section {
                Text(categorySummary)
                    .font(.subheadline)
                    .foregroundStyle(PT.txt2)
            } header: {
                SectionLabel(text: "Categories", tone: PT.gold)
            }

            // Advanced / Diagnostics — calm by default
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CloudKit preflight")
                            .font(.caption)
                            .foregroundStyle(PT.txt3)
                        Text(cloudKitContainerStatus)
                            .font(.caption.monospaced())
                            .foregroundStyle(PT.txt2)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)

                    if activeSyncBackend == "Local fallback", !cloudKitInitError.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Startup error")
                                .font(.caption)
                                .foregroundStyle(PT.txt3)
                            Text(cloudKitInitError)
                                .font(.caption.monospaced())
                                .foregroundStyle(PT.amber)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        Task { await runFMDiagnostic() }
                    } label: {
                        HStack {
                            Text("Test Foundation Models")
                            Spacer()
                            if fmDiagRunning { ProgressView().tint(PT.gold) }
                        }
                    }
                    .foregroundStyle(PT.gold)
                    .disabled(fmDiagRunning)

                    if !fmDiagResult.isEmpty {
                        Text(fmDiagResult)
                            .font(.caption.monospaced())
                            .foregroundStyle(PT.txt2)
                            .textSelection(.enabled)
                    }
                } label: {
                    Text("Advanced & Diagnostics")
                        .font(.subheadline)
                        .foregroundStyle(PT.txt)
                }
                .tint(PT.gold)
            } header: {
                SectionLabel(text: "Advanced", tone: PT.gold)
            }

            // About
            Section {
                row("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                row("Build", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                row("Milestone", "Milestone 3")
                row("Focus", "CloudKit sync, Apple auth, sharing")
            } header: {
                SectionLabel(text: "About", tone: PT.gold)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Clear the floating custom tab bar so the last rows can scroll into view.
        .contentMargins(.bottom, 110, for: .scrollContent)
        .ptScreen()
        .listRowBackground(PT.inkCardDark)
        .foregroundStyle(PT.txt)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Row helper (mono value, parchment label)

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PT.txt2)
            Spacer()
            Text(value)
                .font(PTFont.mono(11.5))
                .foregroundStyle(PT.txt)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Foundation Models Diagnostic

    private func runFMDiagnostic() async {
        fmDiagRunning = true
        defer { fmDiagRunning = false }

        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        let rawAvailability = String(describing: availability)
        var result = "Raw availability: \(rawAvailability)\n"

        let deviceModel = Self.deviceModelIdentifier()
        let iosVersion = UIDevice.current.systemVersion
        result += "Device: \(deviceModel)\n"
        result += "iOS: \(iosVersion)\n"

        guard availability == .available else {
            result += "\n⚠️ Model not available.\n"
            result += "State: \(rawAvailability)\n"
            result += "This may mean Apple Intelligence is off, the model is downloading, or the region/language is unsupported."
            fmDiagResult = result
            return
        }

        // Test 1: Plain text generation (no @Generable)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: "Say hello in one word")
            result += "\n✅ Plain text: \(response)\n"
        } catch {
            result += "\n❌ Plain text error: \(error.localizedDescription)\n"
            result += "Full: \(String(describing: error))\n"
        }

        // Test 2: Structured generation with @Generable
        do {
            let session = LanguageModelSession(
                instructions: "Extract receipt fields from the text. Respond in English."
            )
            let structuredResponse = try await session.respond(
                to: "Store: Apple Singapore, Product: iPhone 16 Pro, Amount: $1599, Date: 2025-01-15",
                generating: ReceiptExtractionSchema.self
            )
            let schema = structuredResponse.content
            result += "✅ Structured: product=\(schema.productName ?? "nil"), merchant=\(schema.merchantName ?? "nil"), amount=\(schema.amount.map { String($0) } ?? "nil")\n"
        } catch {
            result += "❌ Structured error: \(error.localizedDescription)\n"
            result += "Full: \(String(describing: error))\n"
        }

        fmDiagResult = result
        #else
        fmDiagResult = "FoundationModels framework not available in this build"
        #endif
    }

    /// Returns the hardware model identifier (e.g. "iPhone17,1").
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

#Preview {
    NavigationStack {
        SettingsView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .environment(AuthenticationManager())
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
