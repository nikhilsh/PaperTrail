import Foundation

protocol ScanningService {
    func beginCapture() async throws -> Attachment
}

struct PlaceholderScanningService: ScanningService {
    func beginCapture() async throws -> Attachment {
        .preview
    }
}
