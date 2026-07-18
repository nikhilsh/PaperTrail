import Foundation

/// Device feedback (build 44): the auto-note was the boilerplate "Extracted
/// from scanned document." on every scan — zero information. Notes now carry
/// real, compact facts the extraction pipeline finds but has no dedicated
/// field for (order/invoice number, tax paid, merchant tax ID), one
/// "Label: value" line each — and nothing at all otherwise, so the field
/// belongs to the user.
///
/// Persistence stays inside `PurchaseRecord.notes` (a new model property is
/// a CloudKit-migration risk — see CLAUDE.md). Display layers parse the
/// known labels back out and render them as chips, leaving user-written
/// prose untouched: only labels in `knownLabels` are ever chip-ified, so a
/// user's own "TODO: buy filters" line stays prose.
enum NoteFacts {
    struct Fact: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { "\(label)|\(value)" }
    }

    /// Labels this app writes — and therefore trusts as chips on read.
    static let knownLabels: Set<String> = ["Order no", "Tax", "Merchant tax ID"]

    // MARK: Compose (write side — scan pipeline)

    /// The auto-note for a fresh scan: one line per homeless fact, nil when
    /// the extraction found none. Never the old boilerplate.
    static func composeNotes(from structured: StructuredExtractionResult?) -> String? {
        composeNotes(
            orderReference: structured?.orderReference.value,
            taxAmount: structured?.taxAmount.value,
            currency: structured?.currency.value,
            vatId: structured?.vatId.value
        )
    }

    static func composeNotes(orderReference: String?, taxAmount: Double?, currency: String?, vatId: String?) -> String? {
        var lines: [String] = []
        if let orderReference, !orderReference.isEmpty {
            lines.append("Order no: \(orderReference)")
        }
        if let taxAmount {
            lines.append("Tax: \(formattedAmount(taxAmount, currency: currency))")
        }
        if let vatId, !vatId.isEmpty {
            lines.append("Merchant tax ID: \(vatId)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func formattedAmount(_ amount: Double, currency: String?) -> String {
        guard let currency, !currency.isEmpty else {
            return String(format: "%.2f", amount)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(String(format: "%.2f", amount)) \(currency)"
    }

    // MARK: Parse (read side — detail views)

    /// Splits stored notes into chip-able facts (lines matching
    /// "KnownLabel: value") and everything else, preserving prose order.
    static func parse(_ notes: String) -> (facts: [Fact], freeText: String) {
        var facts: [Fact] = []
        var rest: [String] = []
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colon = trimmed.range(of: ": "),
               knownLabels.contains(String(trimmed[..<colon.lowerBound])) {
                let value = String(trimmed[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    facts.append(Fact(label: String(trimmed[..<colon.lowerBound]), value: value))
                    continue
                }
            }
            rest.append(line)
        }
        let freeText = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (facts, freeText)
    }
}
