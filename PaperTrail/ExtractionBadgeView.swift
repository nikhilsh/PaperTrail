import SwiftUI

/// A lightweight inline badge showing extraction confidence for a field.
///
/// High-confidence fields show nothing (clean UI). Medium/heuristic/low fields
/// get a subtle icon + label so the user knows to double-check.
struct ExtractionBadgeView: View {
    let confidence: ExtractionConfidence

    var body: some View {
        if let icon = confidence.badgeIcon, let label = confidence.badgeLabel {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption2)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.1), in: Capsule())
        }
    }

    private var badgeColor: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .heuristic: .blue
        case .low: .yellow
        case .none: .secondary
        }
    }
}

/// A field row that shows a text field with an optional confidence badge.
struct ExtractedTextField: View {
    let title: String
    @Binding var text: String
    let confidence: ExtractionConfidence?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: $text)
                if let confidence, confidence.needsReview {
                    ExtractionBadgeView(confidence: confidence)
                }
            }
        }
    }
}

#Preview {
    Form {
        ExtractedTextField(title: "Product name", text: .constant("iPhone 16 Pro"), confidence: .high)
        ExtractedTextField(title: "Store", text: .constant("Apple Store"), confidence: .medium)
        ExtractedTextField(title: "Category", text: .constant("Electronics"), confidence: .heuristic)
        ExtractedTextField(title: "Amount", text: .constant("1,599.00"), confidence: .low)
        ExtractedTextField(title: "Notes", text: .constant(""), confidence: nil)
    }
}
