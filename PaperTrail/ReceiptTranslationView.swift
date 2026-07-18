import SwiftUI
import Translation

/// Quiet Archive-style "Translate this receipt" affordance for a single
/// attachment's OCR text (`Flag.translate`). Lives inside `ImageViewerView`,
/// the one place in `RecordDetailView`'s subview tree where a specific
/// document's OCR text is addressable by attachment id.
///
/// Entirely on-device: `TranslationSession` never leaves the device — no
/// text this view touches is sent anywhere, matching PaperTrail's privacy
/// stance. Translated text is cached in memory only
/// (`ReceiptTranslationCache`) and never written to SwiftData.
///
/// NEEDS ON-DEVICE VERIFICATION — `NLLanguageRecognizer` confidence,
/// `LanguageAvailability.status(from:to:)`, and the system's own
/// download-language-pack sheet can only be exercised on an iOS 26 device
/// with a non-English language pack (e.g. a Japanese receipt). CI is
/// compile-only and cannot drive any of this.
struct ReceiptTranslationPanel: View {
    let attachmentID: UUID
    let ocrText: String
    /// When true the panel drops its own card chrome (material background,
    /// hairline stroke, outer padding) so it can sit inside an existing card
    /// — the Review screen's "Extracted text" card embeds it this way. The
    /// default keeps the floating-card look used over `ImageViewerView`.
    var embedded: Bool = false

    @State private var detected: ReceiptLanguageDetector.Result?
    @State private var isOffered = false
    @State private var mode: DisplayMode = .original
    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var translationConfig: TranslationSession.Configuration?

    private enum DisplayMode { case original, translated }

    private var targetLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private var sourceLanguageDisplayName: String {
        guard let code = detected?.languageCode else { return "" }
        return Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    var body: some View {
        Group {
            if isOffered {
                if embedded {
                    panelContent
                } else {
                    panelContent
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
                        .padding(.horizontal, 16)
                }
            }
        }
        .task { await evaluateOffer() }
        .translationTask(translationConfig) { session in
            await runTranslation(session: session)
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if translatedText == nil {
                offerRow
            } else {
                toggleRow
                Text(mode == .original ? ocrText : (translatedText ?? ""))
                    .font(PTFont.mono(11))
                    .foregroundStyle(PT.txt2)
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
            if let errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(errorMessage)
                        .font(PTFont.mono(9.5))
                }
                .foregroundStyle(PT.amber)
            }
        }
    }

    // MARK: Offer row

    private var offerRow: some View {
        Button {
            AppLogger.info("Translate tapped for attachment \(attachmentID)", category: "translate")
            startTranslation()
        } label: {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView().tint(PT.gold)
                } else {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 12))
                }
                Text(isTranslating ? "Translating…" : "Translate from \(sourceLanguageDisplayName)")
                    .font(PTFont.mono(11))
                    .tracking(0.4)
            }
            .foregroundStyle(PT.gold)
        }
        .buttonStyle(.plain)
        .disabled(isTranslating)
    }

    // MARK: Original/Translated toggle

    private var toggleRow: some View {
        HStack(spacing: 6) {
            segment("Original", isSelected: mode == .original) { mode = .original }
            segment("Translated", isSelected: mode == .translated) { mode = .translated }
            Spacer(minLength: 8)
            Button {
                startTranslation()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(PT.txt3)
            }
            .buttonStyle(.plain)
        }
    }

    private func segment(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ptMonoLabel(9, tracking: 1.6)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .foregroundStyle(isSelected ? PT.inkStamp : PT.txt3)
                .background {
                    if isSelected {
                        Capsule().fill(LinearGradient(colors: [PT.goldHi, PT.gold], startPoint: .top, endPoint: .bottom))
                    } else {
                        Capsule().stroke(PT.hair, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Offer evaluation

    private func evaluateOffer() async {
        guard FeatureFlags.isOn(.translate) else { return }
        guard let result = ReceiptLanguageDetector.detectDominantLanguage(in: ocrText) else {
            AppLogger.info("Translate: no dominant language detected for attachment \(attachmentID)", category: "translate")
            return
        }
        detected = result
        AppLogger.info(
            "Translate: detected \(result.languageCode) (confidence \(String(format: "%.2f", result.confidence))) for attachment \(attachmentID)",
            category: "translate"
        )

        let sourceLanguage = Locale.Language(identifier: result.languageCode)
        let targetLanguage = Locale.Language(identifier: targetLanguageCode)
        let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        let availability: TranslationPairingAvailability
        switch status {
        case .installed: availability = .installed
        case .supported: availability = .supported
        case .unsupported: availability = .unsupported
        @unknown default: availability = .unsupported
        }
        AppLogger.info("Translate: availability \(availability) for attachment \(attachmentID)", category: "translate")

        isOffered = ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: result.languageCode,
            confidence: result.confidence,
            targetLanguageCode: targetLanguageCode,
            availability: availability
        )
    }

    // MARK: Translation

    private func startTranslation() {
        errorMessage = nil
        if let cached = ReceiptTranslationCache.get(attachmentID: attachmentID, targetLanguageCode: targetLanguageCode) {
            translatedText = cached
            mode = .translated
            AppLogger.info("Translate: cache hit for attachment \(attachmentID)", category: "translate")
            return
        }
        guard let detected else { return }
        isTranslating = true
        translatedText = nil
        if translationConfig != nil {
            // Re-run the same configuration in place — this is how the
            // Translation framework re-triggers `.translationTask` (e.g.
            // retry after a declined download) without allocating a brand
            // new session. Must be `translationConfig?.invalidate()` (not an
            // `if let` copy) since `invalidate()` is mutating and needs to
            // act on the actual `@State`-backed value.
            translationConfig?.invalidate()
        } else {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: detected.languageCode),
                target: Locale.Language(identifier: targetLanguageCode)
            )
        }
    }

    private func runTranslation(session: TranslationSession) async {
        guard isTranslating else { return }
        defer { isTranslating = false }

        do {
            // First use of a language pair surfaces iOS's own
            // download-language-pack sheet here, in context with the tap
            // that triggered it.
            try await session.prepareTranslation()
            AppLogger.info("Translate: download prompted for attachment \(attachmentID)", category: "translate")
        } catch {
            // Not fatal on its own — the batch translate below is the real
            // signal of whether translation can proceed (e.g. the user
            // declined the download).
            AppLogger.warn("Translate: prepareTranslation failed: \(error.localizedDescription)", category: "translate")
        }

        let lines = ReceiptLineTranslation.splitLines(ocrText)
        guard !lines.isEmpty else {
            errorMessage = "Nothing to translate"
            return
        }

        do {
            let requests = lines.map { TranslationSession.Request(sourceText: $0) }
            let responses = try await session.translations(from: requests)
            let translatedLines = responses.map(\.targetText)
            let joined = ReceiptLineTranslation.joinLines(translatedLines)
            translatedText = joined
            mode = .translated
            ReceiptTranslationCache.set(joined, attachmentID: attachmentID, targetLanguageCode: targetLanguageCode)
            AppLogger.info("Translate: succeeded (\(translatedLines.count) lines) for attachment \(attachmentID)", category: "translate")
        } catch {
            // Honest inline message, never a crash — most commonly the
            // language pack wasn't downloaded (prompt declined) or isn't
            // available yet.
            errorMessage = "Translation isn't downloaded"
            AppLogger.warn("Translate: translation failed: \(error.localizedDescription)", category: "translate")
        }
    }
}
