//
//  WarrantySpeech.swift
//  PaperTrail
//
//  Spoken-word phrasing for the App Intents (Siri/Shortcuts) surface. Kept
//  separate from `PTWarranty` (Design/PTPresentation.swift), which formats the
//  same underlying facts for on-screen pills/stamps using compact abbreviations
//  ("9 mo", "28 days") that read fine but sound clipped when read aloud by
//  Siri's TTS. These helpers spell things out in full words instead.
//
//  Pure functions (no SwiftData/AppIntents dependency) so they're covered by
//  plain unit tests — see PaperTrailTests/WarrantySpeechTests.swift.
//

import Foundation

enum WarrantySpeech {

    /// The line CheckWarrantyIntent speaks for a single item, e.g.:
    /// "Your LG Washer is covered until 12 Mar 2027 — 8 months left."
    /// "Your LG Washer's warranty expired on 12 Mar 2024."
    /// "Your LG Washer has no warranty info."
    static func statusSentence(productName: String, expiryDate: Date?, now: Date = .now) -> String {
        guard let expiryDate else {
            return "Your \(productName) has no warranty info."
        }
        if expiryDate < now {
            return "Your \(productName)'s warranty expired on \(PTDate.dayMonthYear.string(from: expiryDate))."
        }
        let remaining = remainingPhrase(from: now, to: expiryDate)
        return "Your \(productName) is covered until \(PTDate.dayMonthYear.string(from: expiryDate)) — \(remaining) left."
    }

    /// Full-word coarse distance between two dates, e.g. "8 months", "3 weeks",
    /// "12 days", "1 year". Spoken-friendly counterpart to the abbreviated
    /// `PTWarranty.coarse` used for on-screen pills.
    static func remainingPhrase(from now: Date, to date: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0)
        if days >= 365 {
            let years = max(1, days / 365)
            return "\(years) year\(years == 1 ? "" : "s")"
        } else if days >= 60 {
            let months = max(1, days / 30)
            return "\(months) month\(months == 1 ? "" : "s")"
        } else if days >= 14 {
            let weeks = max(1, days / 7)
            return "\(weeks) week\(weeks == 1 ? "" : "s")"
        } else {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }

    /// "3 Aug", "20 Jul" — short date for the expiring-soon list.
    static func shortDayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    /// The plain-language answer shown on the Siri snippet card (V3_BRIEF.md
    /// §8, mock V3-4), e.g.:
    /// "Yes — 14 months left. Expires 12 Sep 2027."
    /// "No — expired on 12 Mar 2024."
    /// "No warranty info on file."
    /// Deliberately terser than `statusSentence` (no product name — the
    /// snippet card already shows it as the headline) since this doubles as
    /// on-card copy, not just spoken dialog.
    static func snippetAnswer(expiryDate: Date?, now: Date = .now) -> String {
        guard let expiryDate else {
            return "No warranty info on file."
        }
        if expiryDate < now {
            return "No — expired on \(PTDate.dayMonthYear.string(from: expiryDate))."
        }
        let remaining = remainingPhrase(from: now, to: expiryDate)
        return "Yes — \(remaining) left. Expires \(PTDate.dayMonthYear.string(from: expiryDate))."
    }

    /// Fraction of the warranty window elapsed (0...1) — what the snippet
    /// card's sage progress bar fills by, mirroring `PTWarranty.progressElapsed`
    /// (Design/PTPresentation.swift) but as a pure function over raw dates so
    /// it's testable without a `PurchaseRecord`/SwiftData round-trip. Returns
    /// 1 once expired, 0.5 when there's an expiry but no purchase date to
    /// anchor the window (unknown pace), 0 when there's no warranty info at all.
    static func progressElapsed(purchaseDate: Date?, expiryDate: Date?, now: Date = .now) -> Double {
        guard let expiryDate else { return 0 }
        guard let purchaseDate, expiryDate > purchaseDate else {
            return expiryDate < now ? 1 : 0.5
        }
        let total = expiryDate.timeIntervalSince(purchaseDate)
        let elapsed = now.timeIntervalSince(purchaseDate)
        return max(0, min(1, elapsed / total))
    }

    /// ExpiringSoonIntent's summary line, e.g.:
    /// "2 warranties expire soon: AirPods Pro on 20 Jul, LG Washer on 3 Aug."
    /// "1 warranty expires soon: AirPods Pro on 20 Jul."
    /// "No warranties are expiring in the next 60 days."
    ///
    /// `records` should already be sorted by date ascending; only the first
    /// three are named, but the spoken count reflects the full list.
    static func expiringSoonSummary(records: [(name: String, date: Date)]) -> String {
        guard !records.isEmpty else {
            return "No warranties are expiring in the next 60 days."
        }
        let named = records.prefix(3)
            .map { "\($0.name) on \(shortDayMonth($0.date))" }
            .joined(separator: ", ")
        let count = records.count
        let noun = count == 1 ? "warranty expires" : "warranties expire"
        return "\(count) \(noun) soon: \(named)."
    }
}
