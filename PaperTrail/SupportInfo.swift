import Foundation

enum SupportInfoConfidence: String, Codable, Hashable {
    case verified
    case estimated
}

struct SupportInfo: Hashable {
    var providerName: String
    var phoneNumber: String
    var confidence: SupportInfoConfidence
    var note: String?
}
