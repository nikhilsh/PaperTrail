import Foundation
import OSLog
import Sentry

/// Privacy-safe extraction telemetry.
///
/// Per the research roadmap (§7), every change to the extraction stack should
/// be measurable. These counters answer "did this change actually help?":
///   • **per-field correction rate** — how often the user edits each field
///     (the truest accuracy signal),
///   • **source mix** — Foundation Model vs heuristic vs structured OCR,
///   • **amount-override rate** — how often the structural total disagreed with
///     the guessed amount (should fall as structured OCR matures).
///
/// Everything emitted here is non-PII: field *names*, booleans, counts, and
/// coarse buckets — never the field *values* (no merchant names, no amounts,
/// no dates). Breadcrumbs ride along on whatever event Sentry next records.
enum ExtractionMetrics {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.metrics")

    // MARK: - Pipeline outcome

    /// Records which extraction path produced a result and key structural signals.
    static func recordPipelineOutcome(
        source: ExtractionSource,
        usedStructuredOCR: Bool,
        foundationModelAvailable: Bool,
        fmFieldCount: Int,
        heuristicFieldCount: Int,
        hadStructuralTotal: Bool,
        lineItemCount: Int,
        structuredTableCount: Int = 0,
        structuredTableLineItemCount: Int = 0
    ) {
        let crumb = Breadcrumb()
        crumb.category = "extraction.metrics"
        crumb.message = "pipeline_outcome"
        crumb.level = .info
        crumb.data = [
            "source": source.rawValue,
            "used_structured_ocr": usedStructuredOCR,
            "fm_available": foundationModelAvailable,
            "fm_field_count": fmFieldCount,
            "heuristic_field_count": heuristicFieldCount,
            "had_structural_total": hadStructuralTotal,
            "line_item_count": lineItemCount,
            // Diagnostics: did RecognizeDocumentsRequest actually find tables?
            "structured_table_count": structuredTableCount,
            "structured_table_items": structuredTableLineItemCount,
        ]
        SentrySDK.addBreadcrumb(crumb)
        logger.info("metrics.pipeline source=\(source.rawValue, privacy: .public) structuredOCR=\(usedStructuredOCR, privacy: .public) structuralTotal=\(hadStructuralTotal, privacy: .public)")
    }

    /// Records that a structurally-read total replaced the guessed amount.
    /// Logs only the *direction* of the disagreement, never the values.
    static func recordStructuralTotalOverride(previous: Double?, structural: Double) {
        let direction: String
        if let previous {
            if structural > previous + 0.01 { direction = "structural_higher" }
            else if structural + 0.01 < previous { direction = "structural_lower" }
            else { direction = "agree" }
        } else {
            direction = "filled_blank"
        }
        let crumb = Breadcrumb()
        crumb.category = "extraction.metrics"
        crumb.message = "amount_override"
        crumb.level = .info
        crumb.data = ["direction": direction]
        SentrySDK.addBreadcrumb(crumb)
        logger.info("metrics.amount_override direction=\(direction, privacy: .public)")
    }

    // MARK: - Per-field correction rate

    /// One field's correction outcome, derived by comparing what extraction
    /// suggested against what the user saved.
    enum FieldOutcome: String {
        /// Extraction suggested a value and the user kept it.
        case kept
        /// Extraction suggested a value and the user changed it.
        case corrected
        /// Extraction suggested nothing and the user filled it in.
        case filledBlank = "filled_blank"
        /// Nothing suggested, nothing entered.
        case empty
    }

    /// Records per-field correction outcomes for a single saved record.
    /// `outcomes` maps field name → outcome. Emitted as one breadcrumb so the
    /// fields stay correlated for a given scan.
    static func recordCorrectionOutcomes(_ outcomes: [String: FieldOutcome], source: ExtractionSource?) {
        var data: [String: Any] = ["source": source?.rawValue ?? "none"]
        for (field, outcome) in outcomes {
            data[field] = outcome.rawValue
        }
        let crumb = Breadcrumb()
        crumb.category = "extraction.metrics"
        crumb.message = "field_corrections"
        crumb.level = .info
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)

        let correctedCount = outcomes.values.filter { $0 == .corrected }.count
        logger.info("metrics.corrections corrected=\(correctedCount, privacy: .public)/\(outcomes.count, privacy: .public) source=\(source?.rawValue ?? "none", privacy: .public)")
    }
}
