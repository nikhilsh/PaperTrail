import UIKit
import PDFKit

/// Renders a record + its proof images into a single formatted "Claim Packet"
/// PDF (§9) — everything a repair, retailer, or insurer asks for, ready to send.
/// Supersedes the old raw proof-bundle share.
enum ClaimPacketPDF {

    /// A short, deterministic document number derived from the record id.
    static func documentNumber(for record: PurchaseRecord) -> String {
        let hex = String(record.id.uuidString.prefix(8)).uppercased()
        return "PT-\(hex)"
    }

    /// Render the claim packet to a temporary file URL, or nil on failure.
    static func generate(record: PurchaseRecord, attachments: [Attachment]) -> URL? {
        let pageWidth: CGFloat = 612   // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        // Fonts — system serif/mono so rendering never depends on font loading.
        let mono = { (size: CGFloat) in UIFont.monospacedSystemFont(ofSize: size, weight: .medium) }
        let monoRegular = { (size: CGFloat) in UIFont.monospacedSystemFont(ofSize: size, weight: .regular) }
        func serif(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: d, size: size)
            }
            return base
        }

        func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
            UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
        let ink = rgb(0x21, 0x1C, 0x12)
        let ink2 = rgb(0x5F, 0x56, 0x41)
        let ink3 = rgb(0x7C, 0x72, 0x57)
        let gold = rgb(0x8A, 0x6E, 0x3A)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaimPacket-\(documentNumber(for: record)).pdf")
        try? FileManager.default.removeItem(at: url)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y = margin

                func draw(_ text: String, font: UIFont, color: UIColor, x: CGFloat = margin, maxWidth: CGFloat? = nil) -> CGFloat {
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let w = maxWidth ?? (contentWidth - (x - margin))
                    let bounding = (text as NSString).boundingRect(
                        with: CGSize(width: w, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attrs, context: nil)
                    (text as NSString).draw(with: CGRect(x: x, y: y, width: w, height: ceil(bounding.height)),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            attributes: attrs, context: nil)
                    return ceil(bounding.height)
                }

                // Header
                y += draw("PAPERTRAIL", font: mono(11), color: gold)
                let docNo = documentNumber(for: record)
                let docAttrs: [NSAttributedString.Key: Any] = [.font: monoRegular(11), .foregroundColor: ink3]
                let docSize = (docNo as NSString).size(withAttributes: docAttrs)
                (docNo as NSString).draw(at: CGPoint(x: pageWidth - margin - docSize.width, y: y - docSize.height - 2), withAttributes: docAttrs)
                y += 10
                y += draw("PROOF OF PURCHASE & WARRANTY", font: monoRegular(9), color: ink3)
                y += 14

                // Product name
                y += draw(record.productName, font: serif(26), color: ink)
                y += 14

                // Gold rule
                ctx.cgContext.setFillColor(gold.cgColor)
                ctx.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 2))
                y += 18

                // Key / value lines
                func kv(_ label: String, _ value: String, valueColor: UIColor = ink) {
                    let labelAttrs: [NSAttributedString.Key: Any] = [.font: monoRegular(9), .foregroundColor: ink3]
                    (label.uppercased() as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
                    let valAttrs: [NSAttributedString.Key: Any] = [.font: serif(14, .medium), .foregroundColor: valueColor]
                    let h = (value as NSString).boundingRect(
                        with: CGSize(width: contentWidth - 150, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin], attributes: valAttrs, context: nil).height
                    (value as NSString).draw(with: CGRect(x: margin + 150, y: y - 2, width: contentWidth - 150, height: ceil(h)),
                                             options: [.usesLineFragmentOrigin], attributes: valAttrs, context: nil)
                    y += max(20, ceil(h) + 8)
                }

                kv("Model", record.productName)
                if let serial = record.serialNumber, !serial.isEmpty { kv("Serial no.", serial) }
                let purchased = [record.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) }, record.merchantName]
                    .compactMap { $0 }.joined(separator: " · ")
                kv("Purchased", purchased.isEmpty ? "—" : purchased)
                kv("Price paid", record.formattedAmount ?? "—")
                let warrantyText = record.warrantyExpiryDate.map { "Until \(PTDate.dayMonthYear.string(from: $0))" } ?? "Not on file"
                kv("Warranty", warrantyText)
                if let coverage = record.coverageSummary, !coverage.isEmpty { kv("Covers", coverage) }

                let statusColor: UIColor
                switch record.warrantyStatus {
                case .active: statusColor = rgb(0x6E, 0x85, 0x50)
                case .expiringSoon: statusColor = rgb(0xD7, 0xA6, 0x4C)
                case .expired: statusColor = rgb(0xC5, 0x6A, 0x45)
                case .unknown: statusColor = ink3
                }
                kv("Status", record.warrantyStatus.label, valueColor: statusColor)

                y += 16

                // Attached proof thumbnails
                let images = orderedProofImages(record: record, attachments: attachments)
                if !images.isEmpty {
                    y += draw("ATTACHED PROOF", font: monoRegular(9), color: ink3)
                    y += 8
                    let thumbW: CGFloat = 130, thumbH: CGFloat = 170, gap: CGFloat = 14
                    var x = margin
                    for (image, label) in images {
                        if x + thumbW > pageWidth - margin {
                            // Out of horizontal room — stop adding more on this row.
                            break
                        }
                        let rect = CGRect(x: x, y: y, width: thumbW, height: thumbH)
                        let fitted = aspectFit(image: image, in: rect)
                        image.draw(in: fitted)
                        ctx.cgContext.setStrokeColor(ink3.withAlphaComponent(0.4).cgColor)
                        ctx.cgContext.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
                        let lblAttrs: [NSAttributedString.Key: Any] = [.font: monoRegular(8), .foregroundColor: ink2]
                        (label.uppercased() as NSString).draw(at: CGPoint(x: x, y: y + thumbH + 4), withAttributes: lblAttrs)
                        x += thumbW + gap
                    }
                    y += thumbH + 22
                }

                // Tamper-evident line near the bottom.
                let captured = earliestCaptureDate(attachments: attachments)
                let capturedText: String
                if let captured {
                    capturedText = "Captured \(PTDate.dayMonthYear.string(from: captured)) · original kept on file since purchase."
                } else {
                    capturedText = "Original proof kept on file since purchase."
                }
                let footY = pageHeight - margin - 24
                y = max(y, footY)
                ctx.cgContext.setFillColor(ink3.withAlphaComponent(0.25).cgColor)
                ctx.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5))
                y += 8
                _ = draw(capturedText, font: monoRegular(8.5), color: ink2)
            }
            return url
        } catch {
            AppLogger.error("Claim packet PDF render failed: \(error)", category: "sharing")
            return nil
        }
    }

    /// Receipt, then warranty, then product — the canonical proof order, each
    /// with a human label, skipping any whose image isn't available locally.
    private static func orderedProofImages(record: PurchaseRecord, attachments: [Attachment]) -> [(UIImage, String)] {
        var result: [(UIImage, String)] = []
        let productID = record.productImageAttachmentID

        if let receipt = attachments.first(where: { $0.type == .receipt && $0.id != productID })?.image {
            result.append((receipt, "Receipt"))
        }
        if let warranty = attachments.first(where: { $0.type == .warranty && $0.id != productID })?.image {
            result.append((warranty, "Warranty"))
        }
        if let id = productID, let product = attachments.first(where: { $0.id == id })?.image {
            result.append((product, "Product"))
        }
        // Fall back to any remaining images if the typed ones were absent.
        if result.isEmpty {
            for att in attachments {
                if let img = att.image {
                    result.append((img, att.type.rawValue.capitalized))
                    if result.count == 3 { break }
                }
            }
        }
        return result
    }

    private static func earliestCaptureDate(attachments: [Attachment]) -> Date? {
        attachments.map(\.createdAt).min()
    }

    private static func aspectFit(image: UIImage, in rect: CGRect) -> CGRect {
        let imgRatio = image.size.width / max(image.size.height, 1)
        let rectRatio = rect.width / rect.height
        var w = rect.width, h = rect.height
        if imgRatio > rectRatio {
            h = rect.width / imgRatio
        } else {
            w = rect.height * imgRatio
        }
        let x = rect.minX + (rect.width - w) / 2
        let y = rect.minY + (rect.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
