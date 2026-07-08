import Foundation

/// Whether a decoded barcode payload plausibly represents a device serial
/// number, and if so what kind of code it looks like.
enum SerialCandidateKind: String, Sendable, Hashable {
    /// Alphanumeric-shaped serial number (e.g. Apple's "C02XK1ABJGH5").
    case serial
    /// A numeric UPC/EAN-style barcode. Usually a product/SKU code rather
    /// than a unique device serial, but still worth surfacing as a
    /// lower-priority suggestion when nothing more serial-like was found.
    case productCode

    /// Label shown next to the suggested value in the review UI.
    var label: String {
        switch self {
        case .serial: "Serial number"
        case .productCode: "Product code"
        }
    }
}

/// A barcode payload decoded from a scanned page, classified as a possible
/// device serial number.
struct SerialBarcodeCandidate: Sendable, Hashable, Identifiable {
    var id: String { payload }
    let payload: String
    let kind: SerialCandidateKind
}

/// Pure content-shape filter deciding whether a decoded barcode payload is
/// "serial-like" enough to surface as a suggested serial number.
///
/// Deliberately Vision-independent (no `import Vision`) so it's directly
/// unit-testable without a device/simulator camera or barcode fixtures —
/// only the decoded payload string matters, not which symbology produced it.
enum SerialCandidateFilter {
    /// Real serials and product codes plausibly fall within this length range.
    /// Below it: page numbers, quantities, short codes. Above it: URLs and
    /// other long structured payloads that occasionally use QR/dataMatrix.
    private static let lengthRange = 6...25

    /// All-digit payloads shorter than this are quantities/short codes, not
    /// UPC/EAN barcodes (the shortest common retail symbology, EAN-8, is 8
    /// digits; this is set a little below that to stay permissive).
    private static let minProductCodeDigits = 11

    /// Classify a decoded barcode payload. Returns `nil` when the payload
    /// doesn't look like a serial or product code at all — URLs, short
    /// numeric codes, or junk containing whitespace/unexpected punctuation.
    static func classify(_ payload: String) -> SerialCandidateKind? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lengthRange.contains(trimmed.count) else { return nil }
        guard !trimmed.contains(where: \.isWhitespace) else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.contains("://") || lower.hasPrefix("www.") {
            return nil
        }

        // Serials/product codes: letters, digits, and the hyphen separator
        // some vendors use (e.g. "SN-9XK42"). Anything else (spaces already
        // excluded above; slashes, colons, etc.) isn't a plausible serial.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        if trimmed.allSatisfy(\.isNumber) {
            // All-digit payloads are typically UPC/EAN product codes, not
            // unique serials — keep as a lower-priority candidate once long
            // enough to plausibly be a real barcode rather than e.g. a
            // 4-digit quantity.
            return trimmed.count >= minProductCodeDigits ? .productCode : nil
        }

        // Require at least one letter so dash/digit junk ("12-34-56-78")
        // doesn't get mistaken for a serial.
        guard trimmed.contains(where: \.isLetter) else { return nil }
        return .serial
    }

    /// Picks the best candidate from a batch of decoded payloads (e.g. every
    /// barcode found across every scanned page): prefer a `.serial`-shaped
    /// payload; fall back to a `.productCode` only when no serial-shaped
    /// candidate exists anywhere in the batch.
    static func bestCandidate(from payloads: [String]) -> SerialBarcodeCandidate? {
        var firstProductCode: SerialBarcodeCandidate?
        for payload in payloads {
            guard let kind = classify(payload) else { continue }
            let candidate = SerialBarcodeCandidate(payload: payload, kind: kind)
            if kind == .serial { return candidate }
            if firstProductCode == nil { firstProductCode = candidate }
        }
        return firstProductCode
    }
}
