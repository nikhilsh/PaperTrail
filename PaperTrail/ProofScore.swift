import Foundation

/// Plain, model-independent snapshot of the fields that feed a Proof Score.
/// Deliberately decoupled from `PurchaseRecord`/`Attachment` (both SwiftData
/// models) so the scorer stays a pure function callers can unit test without
/// spinning up a `ModelContext`.
struct ProofScoreSnapshot {
    var hasAttachment: Bool
    var purchaseDate: Date?
    var amount: Double?
    var warrantyExpiryDate: Date?
    var serialNumber: String?
    var productImageAttachmentID: UUID?

    init(
        hasAttachment: Bool,
        purchaseDate: Date?,
        amount: Double?,
        warrantyExpiryDate: Date?,
        serialNumber: String?,
        productImageAttachmentID: UUID?
    ) {
        self.hasAttachment = hasAttachment
        self.purchaseDate = purchaseDate
        self.amount = amount
        self.warrantyExpiryDate = warrantyExpiryDate
        self.serialNumber = serialNumber
        self.productImageAttachmentID = productImageAttachmentID
    }
}

/// "Is this record claim-ready?" — a 0–100 score over the proof a record would
/// need to back an insurance or warranty claim, plus a human-readable verdict
/// and the ordered list of what's missing.
struct ProofScore: Equatable {
    enum Level: String, Equatable {
        case claimReady = "Proof complete"
        case nearlyThere = "Nearly there"
        case needsProof = "Needs proof"

        static func level(forScore score: Int) -> Level {
            switch score {
            case 90...: return .claimReady
            case 60..<90: return .nearlyThere
            default: return .needsProof
            }
        }
    }

    /// One scoring component: how many points it's worth, and the label shown
    /// when it's missing.
    private struct Component {
        let points: Int
        let missingLabel: String
        let isPresent: Bool
    }

    let score: Int
    let level: Level
    /// Missing components, most valuable first — ties keep the declaration
    /// order below (stable sort).
    let missingItems: [String]

    init(snapshot: ProofScoreSnapshot) {
        let components = [
            Component(points: 30, missingLabel: "No document attached", isPresent: snapshot.hasAttachment),
            Component(points: 15, missingLabel: "No purchase date", isPresent: snapshot.purchaseDate != nil),
            Component(points: 15, missingLabel: "No purchase amount", isPresent: snapshot.amount != nil),
            Component(points: 15, missingLabel: "No warranty expiry date", isPresent: snapshot.warrantyExpiryDate != nil),
            Component(points: 15, missingLabel: "No serial number", isPresent: !(snapshot.serialNumber ?? "").isEmpty),
            Component(points: 10, missingLabel: "No product photo", isPresent: snapshot.productImageAttachmentID != nil)
        ]

        self.score = components.reduce(0) { $0 + ($1.isPresent ? $1.points : 0) }
        self.level = Level.level(forScore: score)
        self.missingItems = components
            .filter { !$0.isPresent }
            .sorted { $0.points > $1.points }
            .map(\.missingLabel)
    }
}
