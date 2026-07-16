import UIKit
import PDFKit

/// Renders the "Pass it on" buyer packet (docs/design-v3/V3_BRIEF.md §7,
/// V3-1 mock): a cover page ("A dossier for the next owner.") plus one page
/// per selected-and-available section, footer "Kept with PaperTrail" on
/// every page. Follows `InsuranceReportPDF`'s `UIGraphicsPDFRenderer`
/// pattern and visual identity (serif titles, mono labels, PT palette).
enum PassItOnPacketPDF {
    /// Plain value input — decoupled from `PurchaseRecord`/SwiftData, same
    /// rationale as `InsuranceReport.Item`/`DigestRecordSnapshot`.
    struct Input {
        var productName: String
        var merchantName: String?
        var purchaseDate: Date?
        var amount: Double?
        var currency: String?
        var serialNumber: String?
        var warrantyExpiryDate: Date?
        var coverageSummary: String?
        var serviceEntries: [ServiceEntry]
        /// The manual's on-disk URL, if `selection.includeManual` and one's
        /// on file — its pages are embedded verbatim.
        var manualURL: URL?
        var selection: PassItOnPacket.Selection
        var generatedAt: Date = .now
    }

    /// Render the packet to a temporary file URL, or nil on failure. Pure
    /// UIKit/PDFKit work — no SwiftData — so callers run this off the main
    /// actor in a detached `Task`, matching `InsuranceReportPDF.generate`.
    static func generate(_ input: Input) -> URL? {
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
        let sage = rgb(0x6E, 0x85, 0x50)

        func money(_ amount: Double, _ currency: String) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
            return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%@ %.2f", currency, amount)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassItOnPacket-\(UUID().uuidString.prefix(8)).pdf")
        try? FileManager.default.removeItem(at: url)

        do {
            try renderer.writePDF(to: url) { ctx in
                var y: CGFloat = margin

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

                func drawRule() {
                    ctx.cgContext.setFillColor(gold.cgColor)
                    ctx.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 1.5))
                }

                // Fixed-position footer on every page — "Kept with
                // PaperTrail" per V3_BRIEF §7, mirroring
                // `InsuranceReportPDF.drawFooter`'s reserved band.
                func drawFooter() {
                    let footY = pageHeight - margin - footerReserve
                    ctx.cgContext.setFillColor(ink3.withAlphaComponent(0.25).cgColor)
                    ctx.cgContext.fill(CGRect(x: margin, y: footY, width: contentWidth, height: 0.5))
                    let attrs: [NSAttributedString.Key: Any] = [.font: monoRegular(8.5), .foregroundColor: ink2]
                    let text = "Kept with PaperTrail"
                    (text as NSString).draw(
                        with: CGRect(x: margin, y: footY + 8, width: contentWidth, height: footerReserve - 8),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                }

                func newPage() {
                    drawFooter()
                    ctx.beginPage()
                    y = margin
                }

                func sectionHeader(_ title: String) {
                    y += draw("PAPERTRAIL", font: mono(10), color: gold)
                    y += 8
                    y += draw(title.uppercased(), font: monoRegular(9), color: ink3)
                    y += 10
                    drawRule()
                    y += 20
                }

                func kvLine(_ label: String, _ value: String, mono useMono: Bool = false) -> CGFloat {
                    let labelFont = monoRegular(9)
                    let valueFont = useMono ? mono(13) : serif(14, .medium)
                    let labelHeight = draw(label.uppercased(), font: labelFont, color: ink3)
                    y += labelHeight + 3
                    let valueHeight = draw(value, font: valueFont, color: ink)
                    y += valueHeight
                    return labelHeight + 3 + valueHeight
                }

                // MARK: Cover page

                ctx.beginPage()
                y += draw("PAPERTRAIL", font: mono(11), color: gold)
                y += 10
                y += draw("PASS IT ON", font: monoRegular(9), color: ink3)
                y += 20
                y += draw("A dossier for the", font: serif(24), color: ink)
                y += 4
                y += draw("next owner.", font: serif(24, .semibold), color: gold)
                y += 16
                drawRule()
                y += 24
                y += draw(input.productName, font: serif(18, .medium), color: ink)
                y += 6
                let dateStr = PTDate.dayMonthYear.string(from: input.generatedAt)
                y += draw("Prepared \(dateStr)", font: monoRegular(9), color: ink3)

                // MARK: Proof of purchase

                if input.selection.includeProofOfPurchase {
                    newPage()
                    sectionHeader("Proof of purchase")
                    if let merchant = input.merchantName, !merchant.isEmpty {
                        y += kvLine("Store", merchant) + 12
                    }
                    if let purchaseDate = input.purchaseDate {
                        y += kvLine("Purchased", PTDate.dayMonthYear.string(from: purchaseDate)) + 12
                    }
                    if let serial = input.serialNumber, !serial.isEmpty {
                        y += kvLine("Serial no.", serial, mono: true) + 12
                    }
                    // Price paid REDACTED unless the seller explicitly opts
                    // in via "Show price paid" — off by default (V3_BRIEF §7).
                    if input.selection.showPricePaid, let amount = input.amount {
                        let currency = input.currency ?? "SGD"
                        y += kvLine("Price paid", money(amount, currency), mono: true) + 12
                    } else {
                        y += kvLine("Price paid", "— withheld by seller") + 12
                    }
                }

                // MARK: Remaining warranty

                if input.selection.includeRemainingWarranty, let expiry = input.warrantyExpiryDate, expiry > input.generatedAt {
                    newPage()
                    sectionHeader("Remaining warranty")
                    let months = monthsRemaining(from: input.generatedAt, to: expiry)
                    let monthsText = months == 1 ? "1 month remaining" : "\(months) months remaining"
                    y += draw(monthsText, font: serif(18, .medium), color: sage)
                    y += 8
                    y += draw("Transferable to the next owner unless the manufacturer's terms say otherwise.",
                               font: monoRegular(9), color: ink3, maxWidth: contentWidth)
                    y += 16
                    y += kvLine("Expires", PTDate.dayMonthYear.string(from: expiry)) + 12
                    if let coverage = input.coverageSummary, !coverage.isEmpty {
                        y += kvLine("Covers", coverage) + 12
                    }
                }

                // MARK: Service history

                if input.selection.includeServiceHistory, !input.serviceEntries.isEmpty {
                    newPage()
                    sectionHeader("Service history")
                    let entryWord = input.serviceEntries.count == 1 ? "entry" : "entries"
                    y += draw("\(input.serviceEntries.count) \(entryWord)", font: serif(15, .medium), color: ink)
                    y += 14
                    for entry in input.serviceEntries.sortedByDateDescending {
                        let dateLine = "\(PTDate.dayMonthYear.string(from: entry.date)) · \(entry.actorKind?.label ?? "Self")"
                        y += draw(dateLine, font: monoRegular(9), color: ink3)
                        y += 3
                        y += draw(entry.title, font: serif(13, .medium), color: ink, maxWidth: contentWidth)
                        y += 3
                        if let cost = entry.cost {
                            y += draw("Cost \((cost as NSDecimalNumber).stringValue)", font: monoRegular(8.5), color: ink2)
                            y += 3
                        }
                        y += 10
                        ctx.cgContext.setFillColor(ink3.withAlphaComponent(0.15).cgColor)
                        ctx.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5))
                        y += 10

                        if y > pageHeight - margin - footerReserve - 60 {
                            newPage()
                            sectionHeader("Service history (cont'd)")
                        }
                    }
                }

                // MARK: Manual (embedded verbatim)

                if input.selection.includeManual, let manualURL,
                   let manualDocument = CGPDFDocument(manualURL as CFURL) {
                    for pageIndex in 1...max(manualDocument.numberOfPages, 1) {
                        // Downsample/scale each manual page into our own
                        // page bounds and release before the next — bounds
                        // peak memory the same way `InsuranceReportPDF`
                        // brackets each item's proof-image draw.
                        autoreleasepool {
                            guard let page = manualDocument.page(at: pageIndex) else { return }
                            newPage()
                            let pageRect = page.getBoxRect(.mediaBox)
                            let target = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
                            let scale = min(target.width / max(pageRect.width, 1), target.height / max(pageRect.height, 1))
                            let drawnSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                            let origin = CGPoint(x: (target.width - drawnSize.width) / 2, y: (target.height - drawnSize.height) / 2)

                            let cg = ctx.cgContext
                            cg.saveGState()
                            cg.translateBy(x: origin.x, y: origin.y + drawnSize.height)
                            cg.scaleBy(x: scale, y: -scale)
                            cg.drawPDFPage(page)
                            cg.restoreGState()
                        }
                    }
                }

                drawFooter()
            }
            return url
        } catch {
            AppLogger.error("Pass-it-on packet PDF render failed: \(error)", category: "passiton")
            return nil
        }
    }

    /// Whole-month difference, floored at 0 — matches the passport ring's
    /// "months remaining" convention elsewhere in the app.
    private static func monthsRemaining(from now: Date, to expiry: Date, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.month], from: now, to: expiry).month ?? 0)
    }
}
