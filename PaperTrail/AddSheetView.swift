import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import Speech

// MARK: - The sheet (C3 mock: "Five ways to shelve")
//
// Presented from `AppShellView` (which already holds `AppRouter` as a plain
// `@State` property, not via `@Environment`) as an `.overlay` alongside
// `.softAskPresentation()` — same dim/rise choreography (`PTMotion.sheetEase`).
// Row taps that produce a draft hand a `DraftPayload` back through the
// router's existing `pendingImportPayload` — the same full-screen review
// cover Mail/Files import and Photos import already use — so `DraftRecordView`
// only needed one small, additive seam (`seedsProductImage`) rather than a
// second review screen.

/// The paper sheet the FAB opens when `addSheetV2` is on. Five rows over a
/// dimmed app: scan (hero, hands off to the existing capture flow), photo,
/// email (non-functional placeholder), barcode, and voice. Each of the last
/// three runs its own short-lived capture UI and, on success, calls
/// `onDraftReady` with a `DraftPayload` ready for `DraftRecordView` review —
/// nothing here ever saves a record directly.
struct AddSheetView: View {
    var onScanReceipt: () -> Void
    var onDraftReady: (DraftPayload) -> Void
    var onCancel: () -> Void

    @State private var showPhotoSourceDialog = false
    @State private var showCameraPicker = false
    @State private var showPhotosPicker = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false

    @State private var showBarcodeScanner = false
    @State private var showVoiceCapture = false

    private var barcodeSupported: Bool { BarcodeScannerView.isSupported }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                header

                AddSheetRow(
                    symbol: "camera.viewfinder",
                    title: "Scan the receipt",
                    subtitle: "Dates, price, store read automatically — on device",
                    action: onScanReceipt
                )
                divider
                AddSheetRow(
                    symbol: "photo",
                    title: "Photograph the thing",
                    subtitle: "Add proof later — a shelf slot is saved",
                    action: { showPhotoSourceDialog = true }
                )
                divider
                AddSheetRow(
                    symbol: "envelope",
                    title: "Forward an email",
                    subtitle: "shelve@papertrail.app · order confirmations file themselves",
                    trailingText: "COMING SOON",
                    disabled: true
                )
                divider
                AddSheetRow(
                    symbol: "barcode.viewfinder",
                    title: "Scan the barcode",
                    subtitle: barcodeSupported ? "Model, brand and manual found for you" : "Not supported on this device",
                    disabled: !barcodeSupported,
                    action: { showBarcodeScanner = true }
                )
                divider
                AddSheetRow(
                    symbol: "mic",
                    title: "Just say it",
                    subtitle: "“Dyson fan, $499, bought today at Courts”",
                    action: { showVoiceCapture = true }
                )
            }
            .padding(.vertical, 4)
            .paperCard(goldFold: false)

            Button(action: onCancel) {
                Text("CANCEL")
                    .font(PTFont.mono(10.5, medium: true))
                    .tracking(2.2)
                    .foregroundStyle(PT.txt3)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if isProcessingPhoto {
                ZStack {
                    PT.inkCanvas.opacity(0.85)
                    ProgressView().tint(PT.gold)
                }
                .clipShape(RoundedRectangle(cornerRadius: PT.Metric.cardRadius, style: .continuous))
            }
        }
        .confirmationDialog("Photograph the thing", isPresented: $showPhotoSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCameraPicker = true }
            }
            Button("Choose from Library") { showPhotosPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItem, matching: .images)
        .onChange(of: photosPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhotosPickerSelection(newItem) }
            photosPickerItem = nil
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraCaptureView(
                onCapture: { image in
                    showCameraPicker = false
                    Task { await handleProductPhoto(image) }
                },
                onCancel: { showCameraPicker = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showBarcodeScanner) {
            BarcodeScannerSheet { payload in
                handleBarcodeScan(payload)
            }
        }
        .sheet(isPresented: $showVoiceCapture) {
            VoiceCaptureSheet { transcript in
                if let transcript {
                    Task { await handleVoiceTranscript(transcript) }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New acquisition")
                .ptMonoLabel(10, tracking: 2.2)
                .foregroundStyle(PT.goldDeep)
            Text("Shelve something")
                .font(PTFont.serif(26, weight: 600))
                .foregroundStyle(PT.onPaper)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var divider: some View {
        Rectangle().fill(PT.onPaperHair).frame(height: 1).padding(.leading, 16)
    }

    // MARK: Photograph the thing (§2)

    private func handlePhotosPickerSelection(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            AppLogger.error("Add-sheet product photo picker returned no usable image", category: "addSheet.photo")
            return
        }
        await handleProductPhoto(image)
    }

    private func handleProductPhoto(_ image: UIImage) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        guard let filename = ImageStorageManager.save(image) else {
            AppLogger.error("Failed to save add-sheet product photo to disk", category: "addSheet.photo")
            return
        }
        let attachment = Attachment(type: .other, localFilename: filename)
        AppLogger.info("Product photo captured for a new shelf slot", category: "addSheet.photo")
        onDraftReady(DraftPayload(type: .other, attachments: [attachment], ocr: .empty, seedsProductImage: true))
    }

    // MARK: Scan the barcode (§4)

    private func handleBarcodeScan(_ payload: String) {
        AppLogger.info("Barcode captured for a new shelf slot", category: "addSheet.barcode")
        onDraftReady(DraftPayload(type: .other, attachments: [], ocr: BarcodeDraftBuilder.ocrResult(payload: payload)))
    }

    // MARK: Just say it (§5)

    private func handleVoiceTranscript(_ transcript: String) async {
        AppLogger.info("Voice transcript captured (\(transcript.count) chars) for a new shelf slot", category: "addSheet.voice")
        let structured = await ExtractionPipeline().extract(from: transcript)
        onDraftReady(VoiceDraftBuilder.payload(transcript: transcript, structured: structured))
    }
}

// MARK: - Row

private struct AddSheetRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var trailingText: String? = nil
    var disabled: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0x211C12, alpha: 0.07))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PT.goldDeep)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(PT.onPaper)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PT.onPaper3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                if let trailingText {
                    Text(trailingText)
                        .font(PTFont.mono(9, medium: true))
                        .tracking(1.1)
                        .foregroundStyle(PT.onPaper3)
                } else {
                    Text("›")
                        .font(.system(size: 19))
                        .foregroundStyle(PT.onPaper3)
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Needs-proof predicate (LibraryView "ADD PROOF" pill)

/// Pure, SwiftData-independent snapshot for the "photographed but not proven"
/// predicate (§2): a record with a product photo but no other attachments
/// yet. Mirrors `ProofScoreSnapshot`'s shape so it's unit-testable without a
/// `ModelContext`. Deliberately NOT a `PurchaseRecord` field — computed only.
struct NeedsProofSnapshot {
    var productImageAttachmentID: UUID?
    var otherAttachmentIDs: [UUID]
}

enum NeedsProofPredicate {
    /// True when the record has a product photo and nothing else — no
    /// receipt, warranty card, or invoice has been added. `otherAttachmentIDs`
    /// must already exclude `productImageAttachmentID`.
    static func needsProof(_ snapshot: NeedsProofSnapshot) -> Bool {
        snapshot.productImageAttachmentID != nil && snapshot.otherAttachmentIDs.isEmpty
    }
}

// MARK: - Barcode → draft seed (§4)

/// Best-effort OCR-shaped seed for a scanned barcode payload: the payload
/// becomes the suggested serial/model, and a trivial brand guess is attempted
/// via the same brand directory the app already uses for support-contact
/// suggestions (`SupportContactDirectory`). Pure/synchronous so it's
/// unit-testable without VisionKit/DataScanner. An unmatched brand simply
/// leaves `suggestedMerchantName` nil — `DraftRecordView` then renders a
/// plain manual form with just the serial prefilled.
enum BarcodeDraftBuilder {
    static func ocrResult(payload: String) -> OCRExtractionResult {
        let kind = SerialCandidateFilter.classify(payload) ?? .productCode
        let brand = SupportContactDirectory.match(merchantName: nil, productName: payload)
        return OCRExtractionResult(
            recognizedText: "",
            suggestedMerchantName: brand?.displayName,
            lineItems: [],
            serialCandidate: SerialBarcodeCandidate(payload: payload, kind: kind)
        )
    }
}

// MARK: - Voice → draft seed (§5)

/// Builds the draft payload for "Just say it": the transcript is run through
/// the same `ExtractionPipeline` a scanned receipt uses (FM → heuristic
/// fallback), then wrapped in the same `DraftPayload` shape `DraftRecordView`
/// already knows how to review. Extracted as a pure function (given an
/// already-computed `StructuredExtractionResult`) so the seeding glue is
/// unit-testable without invoking Foundation Models or Speech.
enum VoiceDraftBuilder {
    static func payload(transcript: String, structured: StructuredExtractionResult) -> DraftPayload {
        let ocr = structured.toOCRExtractionResult(recognizedText: transcript)
        return DraftPayload(type: .other, attachments: [], ocr: ocr)
    }
}

// MARK: - Camera (product photo)

/// Plain single-photo camera capture — deliberately not the receipt document
/// scanner (`DocumentScannerView`/`VNDocumentCameraViewController`), which
/// perspective-corrects for paper and is the wrong shape for "photograph the
/// object". Camera usage description is already configured at the project
/// level (`INFOPLIST_KEY_NSCameraUsageDescription`).
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                AppLogger.warn("Camera capture returned no image", category: "addSheet.photo")
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

// MARK: - Voice capture (§5, "Just say it")

/// The recording UI: requests microphone + speech-recognition permission,
/// transcribes live via on-device `SFSpeechRecognizer` where supported, and
/// hands the final transcript back on Stop. Never saves anything — the
/// transcript is only ever handed to the same extraction pipeline a scanned
/// receipt uses, and the result still requires user confirmation in
/// `DraftRecordView` (never auto-saved).
struct VoiceCaptureSheet: View {
    /// `nil` means the user cancelled, or denied/lacked permission without
    /// producing a transcript.
    var onFinish: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recorder = VoiceRecorder()
    @State private var phase: Phase = .requesting
    @State private var transcript = ""

    enum Phase: Equatable {
        case requesting
        case recording
        case blocked(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                content
                Spacer()
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .ptScreen()
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { finish(nil) }
                        .foregroundStyle(PT.txt2)
                }
            }
        }
        .tint(PT.gold)
        .preferredColorScheme(.dark)
        .task { await start() }
        .onDisappear { recorder.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .requesting:
            ProgressView().tint(PT.gold)
        case .recording:
            recordingContent
        case .blocked(let message):
            blockedContent(message)
        }
    }

    private var recordingContent: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(PT.gold.opacity(0.12)).frame(width: 120, height: 120)
                Circle().fill(PT.gold.opacity(0.18)).frame(width: 88, height: 88)
                Image(systemName: "mic.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(PT.gold)
            }
            Text(transcript.isEmpty ? "Listening…" : transcript)
                .font(PTFont.serif(19, weight: 500))
                .foregroundStyle(PT.txt)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text("On-device speech recognition")
                .ptMonoLabel(9, tracking: 1.6)
                .foregroundStyle(PT.txt3)
            Button {
                finish(transcript.isEmpty ? nil : transcript)
            } label: {
                Text("Stop")
            }
            .buttonStyle(PTGoldButtonStyle())
        }
    }

    private func blockedContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 34))
                .foregroundStyle(PT.txt3)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(PT.txt2)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text("Open Settings")
                }
                .buttonStyle(PTOutlineButtonStyle())
            }
        }
    }

    private func start() async {
        let result = await recorder.requestPermissionsAndStart { partial in
            transcript = partial
        }
        switch result {
        case .started:
            phase = .recording
        case .blocked(let message):
            phase = .blocked(message)
        }
    }

    private func finish(_ transcript: String?) {
        recorder.stop()
        onFinish(transcript)
        dismiss()
    }
}

/// Thin wrapper around `AVAudioEngine` + `SFSpeechRecognizer` for live,
/// on-device-first transcription. Created and used only from
/// `VoiceCaptureSheet`'s `@State` (main-actor by the project's default actor
/// isolation), so there's no cross-actor sharing to reason about.
final class VoiceRecorder {
    enum StartResult: Equatable {
        case started
        case blocked(String)
    }

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    func requestPermissionsAndStart(onPartialResult: @escaping (String) -> Void) async -> StartResult {
        guard let recognizer, recognizer.isAvailable else {
            return .blocked("Speech recognition isn't available on this device right now.")
        }

        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            return .blocked("PaperTrail needs speech recognition access to turn what you say into a draft. Enable it in Settings.")
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            return .blocked("PaperTrail needs microphone access to hear you. Enable it in Settings.")
        }

        do {
            try startEngine(recognizer: recognizer, onPartialResult: onPartialResult)
            return .started
        } catch {
            AppLogger.error("Voice capture engine failed to start: \(error.localizedDescription)", category: "addSheet.voice")
            return .blocked("Couldn't start the microphone. Try again in a moment.")
        }
    }

    private func startEngine(recognizer: SFSpeechRecognizer, onPartialResult: @escaping (String) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    onPartialResult(result.bestTranscription.formattedString)
                }
                if let error {
                    AppLogger.warn("Voice recognition task ended: \(error.localizedDescription)", category: "addSheet.voice")
                }
            }
        }
    }

    func stop() {
        recognitionRequest?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
