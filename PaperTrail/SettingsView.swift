import SwiftUI
import SwiftData
import AuthenticationServices

struct SettingsView: View {
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]
    @Environment(AuthenticationManager.self) private var authManager
    @AppStorage("activeSyncBackend") private var activeSyncBackend = "Unknown"

    private var totalImageSize: String {
        let totalBytes = attachments.reduce(into: 0) { total, attachment in
            let url = ImageStorageManager.url(for: attachment.localFilename)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            total += size
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
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
            // Account
            Section("Account") {
                if authManager.isSignedIn {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(authManager.userName ?? "Apple User")
                                    .font(.headline)
                                if let email = authManager.userEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Signed in with Apple")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)

                    Text("Sign in to sync across devices and share records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Sync
            Section("Sync") {
                LabeledContent("iCloud", value: "Automatic")
                LabeledContent("Backend", value: activeSyncBackend)
                LabeledContent("Status", value: authManager.isSignedIn ? "Active" : "Sign in required")

                if activeSyncBackend == "Local fallback" {
                    Text("CloudKit failed during startup, so PaperTrail is currently using local-only storage on this device.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Storage
            Section("Storage") {
                LabeledContent("Records", value: "\(records.count)")
                LabeledContent("Attachments", value: "\(attachments.count)")
                LabeledContent("Image storage", value: totalImageSize)
                LabeledContent("Persistence", value: "SwiftData + CloudKit")
            }

            // Warranties
            Section("Warranties") {
                LabeledContent("Active warranties", value: "\(activeWarrantyCount)")
                LabeledContent("Notifications", value: records.filter(\.warrantyNotificationScheduled).count > 0 ? "Scheduled" : "None")
            }

            // Categories
            Section("Categories") {
                Text(categorySummary)
                    .foregroundStyle(.secondary)
            }

            // About
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }

            Section("Milestone") {
                LabeledContent("Current", value: "Milestone 3")
                LabeledContent("Focus", value: "CloudKit sync, Apple auth, sharing")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthenticationManager())
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
