import Testing
import Foundation
@testable import PaperTrail

/// Unit coverage for `addSheetV2`'s pure parts (docs/design-v3/V3_BRIEF.md
/// §3): the "needs proof" predicate LibraryView keys its pill off, the
/// barcode → draft-seed glue, and the voice transcript → draft-seed glue.
/// Everything camera/VisionKit/Speech-dependent lives in `AddSheetView.swift`
/// itself and isn't covered here — these are the parts extracted so they can
/// be tested without a device.
struct AddSheetViewTests {

    // MARK: - NeedsProofPredicate

    @Test func needsProofWhenOnlyAProductPhotoExists() {
        let snapshot = NeedsProofSnapshot(productImageAttachmentID: UUID(), otherAttachmentIDs: [])
        #expect(NeedsProofPredicate.needsProof(snapshot) == true)
    }

    @Test func doesNotNeedProofWithNoProductPhoto() {
        let snapshot = NeedsProofSnapshot(productImageAttachmentID: nil, otherAttachmentIDs: [])
        #expect(NeedsProofPredicate.needsProof(snapshot) == false)
    }

    @Test func doesNotNeedProofOnceADocumentIsAttached() {
        let snapshot = NeedsProofSnapshot(productImageAttachmentID: UUID(), otherAttachmentIDs: [UUID()])
        #expect(NeedsProofPredicate.needsProof(snapshot) == false)
    }

    @Test func doesNotNeedProofWithNeitherPhotoNorDocuments() {
        let snapshot = NeedsProofSnapshot(productImageAttachmentID: nil, otherAttachmentIDs: [])
        #expect(NeedsProofPredicate.needsProof(snapshot) == false)
    }

    // MARK: - BarcodeDraftBuilder

    @Test func barcodeSeedsSerialCandidate() {
        let ocr = BarcodeDraftBuilder.ocrResult(payload: "SN-9XK42PLM")
        #expect(ocr.serialCandidate?.payload == "SN-9XK42PLM")
        #expect(ocr.serialCandidate?.kind == .serial)
    }

    @Test func barcodeInfersKnownBrandFromPayloadText() {
        // A payload whose token happens to carry a known brand name — the
        // "if trivial" case from the brief; most real UPC/EAN payloads won't match.
        let ocr = BarcodeDraftBuilder.ocrResult(payload: "DYSON-V15-SN882231")
        #expect(ocr.suggestedMerchantName == "Dyson")
    }

    @Test func barcodeLeavesMerchantNilWhenBrandUnknown() {
        let ocr = BarcodeDraftBuilder.ocrResult(payload: "8901234567890")
        #expect(ocr.suggestedMerchantName == nil)
        // A pure-digit, 13-char payload reads as a product code, not a serial.
        #expect(ocr.serialCandidate?.kind == .productCode)
    }

    @Test func barcodeNeverPrefillsAProductName() {
        // Unknown-brand payloads must fall through to a plain manual form —
        // no product name is ever guessed from the raw code.
        let ocr = BarcodeDraftBuilder.ocrResult(payload: "SN-9XK42PLM")
        #expect(ocr.suggestedProductName == nil)
    }

    // MARK: - VoiceDraftBuilder

    @Test func voiceDraftCarriesTheRawTranscriptForwardUnedited() {
        let transcript = "Dyson fan, $499, bought today at Courts"
        let payload = VoiceDraftBuilder.payload(transcript: transcript, structured: .empty)
        #expect(payload.ocr.recognizedText == transcript)
        #expect(payload.type == .other)
        #expect(payload.attachments.isEmpty)
        #expect(payload.seedsProductImage == false)
    }

    @Test func voiceDraftSurfacesExtractedFields() {
        var structured = StructuredExtractionResult.empty
        structured.productName = ExtractedField(value: "Dyson fan", confidence: .high)
        structured.amount = ExtractedField(value: 499, confidence: .high)
        structured.merchantName = ExtractedField(value: "Courts", confidence: .medium)

        let payload = VoiceDraftBuilder.payload(transcript: "Dyson fan, $499, bought today at Courts", structured: structured)
        #expect(payload.ocr.suggestedProductName == "Dyson fan")
        #expect(payload.ocr.suggestedAmount == 499)
        #expect(payload.ocr.suggestedMerchantName == "Courts")
    }

    // MARK: - DraftPayload defaults (backward compatibility)

    @Test func draftPayloadDefaultsToNotSeedingAProductImage() {
        // Every pre-existing call site (scan, Photos import, Mail/Files
        // import) constructs `DraftPayload` without `seedsProductImage` —
        // confirms the new field can't silently flip old behavior.
        let payload = DraftPayload(type: .receipt, attachments: [], ocr: .empty)
        #expect(payload.seedsProductImage == false)
    }
}
