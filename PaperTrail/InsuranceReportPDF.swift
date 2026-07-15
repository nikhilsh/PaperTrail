import UIKit
import PDFKit

/// Renders an `InsuranceReport.Report` into the Home Inventory Report PDF —
/// the artifact a user hands their insurer after a burglary/fire/flood.
/// Follows `ClaimPacketPDF`'s `UIGraphicsPDFRenderer` pattern and visual
/// identity (serif titles, mono labels, PT palette) so it reads as the same
/// product: a cover page with grand totals, then one section per room.
enum InsuranceReportPDF {

    /// Render the report to a temporary file URL, or nil on failure.
    static func generate(_ report: InsuranceReport.Report) -> URL? {
        let pageWidth: CGFloat = 612   // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2
        let footerReserve: CGFloat = 26

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

        func money(_ amount: Double, _ currency: String) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
            return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%@ %.2f", currency, amount)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeInventoryReport-\(UUID().uuidString.prefix(8)).pdf")
        try? FileManager.default.removeItem(at: url)

        do {
            try renderer.writePDF(to: url) { ctx in
                var y: CGFloat = margin

                // Draws `text` at the current `y` and returns the height consumed —
                // caller advances `y` themselves (mirrors ClaimPacketPDF's `draw`).
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

                func heightOf(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGFloat {
                    ceil((text as NSString).boundingRect(
                        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: font], context: nil).height)
                }

                func drawRule() {
                    ctx.cgContext.setFillColor(gold.cgColor)
                    ctx.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 1.5))
                }

                // Compact running header used on every room page — brand mark,
                // generated date, and a subtitle (room name).
                func drawRunningHeader(_ subtitle: String) {
                    y = margin
                    y += draw("PAPERTRAIL", font: mono(10), color: gold)
                    let dateStr = PTDate.dayMonthYear.string(from: report.generatedAt)
                    let dateAttrs: [NSAttributedString.Key: Any] = [.font: monoRegular(9), .foregroundColor: ink3]
                    let dateSize = (dateStr as NSString).size(withAttributes: dateAttrs)
                    (dateStr as NSString).draw(at: CGPoint(x: pageWidth - margin - dateSize.width, y: y - dateSize.height),
                                                withAttributes: dateAttrs)
                    y += 8
                    y += draw(subtitle, font: monoRegular(9), color: ink3)
                    y += 10
                    drawRule()
                    y += 20
                }

                func currencyUnion(_ a: [String: Double], _ b: [String: Double]) -> [String] {
                    Set(a.keys).union(b.keys).sorted()
                }

                // MARK: Cover page

                ctx.beginPage()
                y += draw("PAPERTRAIL", font: mono(11), color: gold)
                y += 10
                y += draw("HOME INVENTORY REPORT", font: monoRegular(9), color: ink3)
                y += 16
                y += draw("Home Inventory Report", font: serif(28), color: ink)
                y += 6
                y += draw(PTDate.dayMonthYear.string(from: report.generatedAt), font: monoRegular(10), color: ink3)
                y += 16
                drawRule()
                y += 24

                let roomWord = report.sections.count == 1 ? "room" : "rooms"
                let itemWord = report.totalItemCount == 1 ? "item" : "items"
                y += draw("\(report.totalItemCount) \(itemWord) across \(report.sections.count) \(roomWord)",
                           font: serif(15, .medium), color: ink)
                y += 18

                y += draw("ESTIMATED TOTAL VALUE", font: monoRegular(9), color: ink3)
                y += 8
                for currency in currencyUnion(report.grandPurchaseTotalsByCurrency, report.grandEstimatedTotalsByCurrency) {
                    let purchased = report.grandPurchaseTotalsByCurrency[currency] ?? 0
                    let estimated = report.grandEstimatedTotalsByCurrency[currency] ?? 0
                    let line = "\(currency)  Purchased \(money(purchased, currency))  ·  Est. today \(money(estimated, currency))"
                    y += draw(line, font: serif(14, .medium), color: ink)
                    y += 5
                }
                if report.grandPurchaseTotalsByCurrency.isEmpty && report.grandEstimatedTotalsByCurrency.isEmpty {
                    y += draw("No priced items yet.", font: serif(14, .medium), color: ink3)
                }

                let footY = pageHeight - margin - footerReserve
                y = max(y, footY)
                ctx.cgContext.setFillColor(ink3.withAlphaComponent(0.25).cgColor)
                ctx.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5))
                y += 8
                _ = draw("Estimated values are straight-line depreciation estimates — not appraisals.",
                         font: monoRegular(8.5), color: ink2, maxWidth: contentWidth)

                // MARK: Room sections

                for section in report.sections {
                    ctx.beginPage()
                    drawRunningHeader(section.name.uppercased())

                    y += draw(section.name, font: serif(19), color: ink)
                    y += 6
                    let sectionItemWord = section.items.count == 1 ? "item" : "items"
                    y += draw("\(section.items.count) \(sectionItemWord)", font: monoRegular(9), color: ink3)
                    y += 6
                    for currency in currencyUnion(section.purchaseTotalsByCurrency, section.estimatedTotalsByCurrency) {
                        let purchased = section.purchaseTotalsByCurrency[currency] ?? 0
                        let estimated = section.estimatedTotalsByCurrency[currency] ?? 0
                        y += draw("\(currency) totals — purchased \(money(purchased, currency)) · est. today \(money(estimated, currency))",
                                   font: monoRegular(9), color: ink2)
                        y += 3
                    }
                    y += 16

                    let thumb: CGFloat = 80
                    let textX = margin + thumb + 14
                    let textWidth = contentWidth - thumb - 14

                    for item in section.items {
                        // Bound peak memory: each item's proof image is decoded,
                        // drawn, and released before the next item's image loads —
                        // otherwise a large room could hold dozens of full-size
                        // JPEGs in memory simultaneously.
                        autoreleasepool {
                            var lines: [(String, UIFont, UIColor)] = []
                            lines.append((item.name, serif(13), ink))
                            let subLine = [item.merchantName, item.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) }]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !subLine.isEmpty { lines.append((subLine, monoRegular(8.5), ink3)) }
                            let currency = item.currency ?? InsuranceReport.defaultCurrency
                            if let amount = item.amount {
                                lines.append(("Paid \(money(amount, currency))", monoRegular(8.5), ink2))
                            }
                            if let estimated = item.estimatedCurrentValue {
                                lines.append(("Est. today \(money(estimated, currency))", monoRegular(8.5), gold))
                            }
                            if let serial = item.serialNumber, !serial.isEmpty {
                                lines.append(("Serial \(serial)", monoRegular(8), ink3))
                            }
                            let statusColor: UIColor
                            switch item.warrantyStatus {
                            case .active: statusColor = rgb(0x6E, 0x85, 0x50)
                            case .expiringSoon: statusColor = rgb(0xD7, 0xA6, 0x4C)
                            case .expired: statusColor = rgb(0xC5, 0x6A, 0x45)
                            case .unknown: statusColor = ink3
                            }
                            lines.append(("Warranty: \(item.warrantyStatus.label)", monoRegular(8.5), statusColor))

                            var textHeight: CGFloat = 0
                            for (text, font, _) in lines {
                                textHeight += heightOf(text, font: font, maxWidth: textWidth) + 3
                            }
                            let rowHeight = max(thumb, textHeight) + 18

                            if y + rowHeight > pageHeight - margin - footerReserve {
                                ctx.beginPage()
                                drawRunningHeader("\(section.name.uppercased()) (CONT'D)")
                            }

                            let rowTop = y
                            let thumbRect = CGRect(x: margin, y: rowTop, width: thumb, height: thumb)
                            if let image = item.thumbnailAttachment?.image {
                                let fitted = aspectFit(image: image, in: thumbRect)
                                image.draw(in: fitted)
                            }
                            ctx.cgContext.setStrokeColor(ink3.withAlphaComponent(0.3).cgColor)
                            ctx.cgContext.stroke(thumbRect.insetBy(dx: -0.5, dy: -0.5))

                            y = rowTop
                            for (text, font, color) in lines {
                                y += draw(text, font: font, color: color, x: textX, maxWidth: textWidth) + 3
                            }

                            y = rowTop + rowHeight
                            ctx.cgContext.setFillColor(ink3.withAlphaComponent(0.15).cgColor)
                            ctx.cgContext.fill(CGRect(x: margin, y: y - 9, width: contentWidth, height: 0.5))
                        }
                    }
                }
            }
            return url
        } catch {
            AppLogger.error("Insurance report PDF render failed: \(error)", category: "sharing")
            return nil
        }
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
