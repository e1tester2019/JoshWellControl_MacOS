import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct MaterialTransferReportView: View {
    var well: Well
    var transfer: MaterialTransfer

    // Letter @ 72 dpi
    let pageSize: CGSize = CGSize(width: 612, height: 792)
    let margin: CGFloat = 40

    private var contentWidth: CGFloat { pageSize.width - 2 * margin }

    private func currency(_ v: Double) -> String { String(format: "$%.2f", v) }

    var body: some View {
        ZStack {
            Color.white
            VStack(alignment: .leading, spacing: 12) {
                // Title
                Text("Material Transfer Report")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                // Header block
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        headerKV("Operator:", transfer.operatorName ?? "")
                        Spacer(minLength: 16)
                        headerKV("M.T.#:", "\(transfer.number)")
                        headerKV("Date:", DateFormatter.localizedString(from: transfer.date, dateStyle: .medium, timeStyle: .none))
                    }
                    HStack(alignment: .firstTextBaseline) {
                        headerKV("UWI:", well.uwi ?? "")
                        Spacer(minLength: 16)
                        headerKV("Well Name:", well.name)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        headerKV("Country:", transfer.country ?? "")
                        headerKV("Province:", transfer.province ?? "")
                        headerKV("Activity:", transfer.activity ?? "")
                        headerKV("AFE #:", well.afeNumber ?? "")
                    }
                    if let ship = transfer.shippingCompany, !ship.isEmpty {
                        headerKV("Shipping Company:", ship)
                    }
                    if let surf = transfer.surfaceLocation, !surf.isEmpty {
                        headerKV("Surface:", surf)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black, lineWidth: 1.75)
                )

                // Outgoing transfers table replaced with card-based layout
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(transfer.items) { item in
                        itemCard(item)
                    }
                }
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: 1.5)
                )

                Spacer()
                HStack {
                    Spacer()
                    Text("Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, margin)
            .padding(.vertical, margin)
            .frame(width: pageSize.width, alignment: .topLeading)
            .foregroundStyle(.black)
        }
        .frame(width: pageSize.width)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.black, lineWidth: 1)
        )
    }

    // MARK: - Subviews
    func headerKV(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.body)
        }
    }

    func itemCard(_ item: MaterialTransferItem) -> some View {
        let total = (item.unitPrice ?? 0) * item.quantity
        return VStack(alignment: .leading, spacing: 6) {
            // Top row: qty, $/unit, description, total (with small labels)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quantity").font(.caption).foregroundColor(.gray)
                    Text("\(Int(item.quantity))").foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("$/Unit").font(.caption).foregroundColor(.gray)
                    Text(currency(item.unitPrice ?? 0)).foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Description").font(.caption).foregroundColor(.gray)
                    Text(item.descriptionText).foregroundColor(.black)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption).foregroundColor(.gray)
                    Text(currency(total)).font(.headline).foregroundColor(.black)
                }
            }

            // Details (full width)
            if let details = item.detailText, !details.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Details").font(.caption).foregroundColor(.gray)
                    Text(details).foregroundColor(.black)
                }
            }

            // Receiver Address (full width)
            if let addr = item.receiverAddress, !addr.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiver Address").font(.caption).foregroundColor(.gray)
                    Text(addr).foregroundColor(.black)
                }
            }

            // Account Code + Condition
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account Code").font(.caption).foregroundColor(.gray)
                    Text(item.accountCode ?? (transfer.accountCode ?? "")).foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Condition").font(.caption).foregroundColor(.gray)
                    Text(item.conditionCode ?? "").foregroundColor(.black)
                }
            }

            // Receiver Phone
            if let phone = item.receiverPhone, !phone.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiver Phone").font(.caption).foregroundColor(.secondary)
                    Text(phone).foregroundColor(.black)
                }
            }

            // To Loc/AFE/Vendor + Transported By
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To Loc/AFE/Vendor").font(.caption).foregroundColor(.gray)
                    Text(item.vendorOrTo ?? (transfer.destinationName ?? "")).foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Truck #").font(.caption).foregroundColor(.gray)
                    Text(item.transportedBy ?? (transfer.transportedBy ?? "")).foregroundColor(.black)
                }
            }

            // Est. Weight
            if let w = item.estimatedWeight, w > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Est. Weight (lb)").font(.caption).foregroundColor(.gray)
                    Text(String(format: "%.0f", w)).foregroundColor(.black)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 1.5)
        )
    }
}

#if os(macOS)
struct MaterialTransferReportPreview: View {
    var well: Well
    var transfer: MaterialTransfer
    @State private var exportError: String? = nil

    private let pageSize = CGSize(width: 612, height: 792)

    private var report: MaterialTransferReportView {
        MaterialTransferReportView(well: well, transfer: transfer)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview – Material Transfer #\(transfer.number)")
                    .font(.headline)
                Spacer()
                Button {
                    export()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
            }
            .padding(8)
            Divider()
            ScrollView {
                report
            }
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private func export() {
        if let data = pdfDataForView(report, pageSize: pageSize) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "MaterialTransfer_\(transfer.number).pdf"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                do { try data.write(to: url) } catch { exportError = error.localizedDescription }
            }
        } else {
            exportError = "Failed to generate PDF"
        }
    }
}
#endif

// MARK: - PDF rendering helper (macOS)
#if os(macOS)
func pdfDataForView<V: View>(_ view: V, pageSize: CGSize) -> Data? {
    // Create a hosting view sized to the content's intrinsic height and the given page width
    // We'll paginate by capturing page-sized vertical slices.
    let root = AnyView(
        view
            .frame(width: pageSize.width) // constrain width to page width
            .fixedSize(horizontal: false, vertical: true) // allow height to expand
    )

    let hostingView = NSHostingView(rootView: root)
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    // Build a temporary offscreen window to layout the content at full height
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: pageSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: true
    )
    window.isOpaque = true
    window.hasShadow = false
    window.backgroundColor = .white
    window.contentView = NSView(frame: CGRect(origin: .zero, size: pageSize))
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))

    guard let container = window.contentView else { return nil }
    container.addSubview(hostingView)

    // Pin hostingView to container with fixed width and flexible height
    NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: container.topAnchor),
        hostingView.widthAnchor.constraint(equalToConstant: pageSize.width)
    ])

    // Ask AppKit to compute the fitting size (intrinsic height) for the content at this width
    // Ensure layout and display have occurred before measuring
    container.layoutSubtreeIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let fittingSize = hostingView.fittingSize
    let contentHeight = max(fittingSize.height, pageSize.height)

    hostingView.frame = CGRect(x: 0, y: 0, width: pageSize.width, height: contentHeight)
    container.frame = hostingView.frame

    hostingView.needsLayout = true
    hostingView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    hostingView.display()

    // Helper: create a hosting view sized to intrinsic height at fixed width
    func makeHostingView<V: View>(_ swiftUIView: V, width: CGFloat) -> NSHostingView<V> {
        let hv = NSHostingView(rootView: swiftUIView)
        hv.translatesAutoresizingMaskIntoConstraints = false
        let temp = NSView(frame: CGRect(x: 0, y: 0, width: width, height: 10))
        temp.addSubview(hv)
        NSLayoutConstraint.activate([
            hv.leadingAnchor.constraint(equalTo: temp.leadingAnchor),
            hv.trailingAnchor.constraint(equalTo: temp.trailingAnchor),
            hv.topAnchor.constraint(equalTo: temp.topAnchor),
            hv.widthAnchor.constraint(equalToConstant: width)
        ])
        temp.layoutSubtreeIfNeeded()
        let size = hv.fittingSize
        hv.frame = CGRect(x: 0, y: 0, width: width, height: max(size.height, 1))
        temp.frame = hv.frame
        hv.layoutSubtreeIfNeeded()
        return hv
    }

    // Helper: cache an NSView's display into a CGImage
    func captureCGImage(from view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    // Prepare PDF context
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        window.orderOut(nil)
        return nil
    }

    // Build header view (reuse on every page)
    guard let rpt = view as? MaterialTransferReportView else {
        ctx.closePDF()
        window.orderOut(nil)
        return data as Data
    }

    let availableWidth = pageSize.width
    let contentAreaHeight = pageSize.height

    let headerHV = makeHostingView(
        VStack(alignment: .leading, spacing: 12) {
            Text("Material Transfer Report")
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    rpt.headerKV("Operator:", rpt.transfer.operatorName ?? "")
                    Spacer(minLength: 16)
                    rpt.headerKV("M.T.#:", "\(rpt.transfer.number)")
                    rpt.headerKV("Date:", DateFormatter.localizedString(from: rpt.transfer.date, dateStyle: .medium, timeStyle: .none))
                }
                HStack(alignment: .firstTextBaseline) {
                    rpt.headerKV("UWI:", rpt.well.uwi ?? "")
                    Spacer(minLength: 16)
                    rpt.headerKV("Well Name:", rpt.well.name)
                }
                HStack(alignment: .firstTextBaseline) {
                    rpt.headerKV("Country:", rpt.transfer.country ?? "")
                    rpt.headerKV("Province:", rpt.transfer.province ?? "")
                    rpt.headerKV("Activity:", rpt.transfer.activity ?? "")
                    rpt.headerKV("AFE #:", rpt.well.afeNumber ?? "")
                }
                if let ship = rpt.transfer.shippingCompany, !ship.isEmpty {
                    rpt.headerKV("Shipping Company:", ship)
                }
                if let surf = rpt.transfer.surfaceLocation, !surf.isEmpty {
                    rpt.headerKV("Surface:", surf)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black, lineWidth: 1.75)
            )
        }
        .foregroundStyle(.black)
        .padding(.horizontal, rpt.margin)
        .padding(.top, rpt.margin)
    , width: availableWidth)

    // Build item card captures
    var cards: [(image: CGImage, height: CGFloat)] = []
    for item in rpt.transfer.items {
        let cardHV = makeHostingView(rpt.itemCard(item), width: availableWidth - 2 * rpt.margin)
        if let cg = captureCGImage(from: cardHV) {
            cards.append((cg, cardHV.bounds.height))
        }
    }

    // If no cards, render header-only page
    if cards.isEmpty {
        if let headerCG = captureCGImage(from: headerHV) {
            ctx.beginPDFPage(nil as CFDictionary?)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: pageSize))
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(origin: .zero, size: pageSize))
            let headerRect = CGRect(x: 0, y: contentAreaHeight - headerHV.bounds.height, width: availableWidth, height: headerHV.bounds.height)
            ctx.draw(headerCG, in: headerRect)
            // Last-page footer timestamp
            let footerText = "Generated " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let att = NSAttributedString(string: footerText, attributes: attrs)
            let size = att.size()
            let rect = CGRect(x: availableWidth - size.width - rpt.margin, y: 8, width: size.width, height: size.height)
            att.draw(in: rect)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        window.orderOut(nil)
        return data as Data
    }

    // Pagination: header + full cards only
    var index = 0
    while index < cards.count {
        ctx.beginPDFPage(nil as CFDictionary?)
        // Background + border
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: pageSize))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(origin: .zero, size: pageSize))

        // Header
        if let headerCG = captureCGImage(from: headerHV) {
            let headerRect = CGRect(x: 0, y: contentAreaHeight - headerHV.bounds.height, width: availableWidth, height: headerHV.bounds.height)
            ctx.draw(headerCG, in: headerRect)
            var yCursor = headerRect.minY - 8

            // Place cards
            while index < cards.count {
                let card = cards[index]
                let needed = card.height
                let willHaveMore = (index + 1) < cards.count
                let footerReserve: CGFloat = willHaveMore ? 28 : 0
                if (yCursor - needed - footerReserve) < 0 { break }
                let cardRect = CGRect(x: rpt.margin, y: yCursor - needed, width: availableWidth - 2 * rpt.margin, height: needed)
                ctx.draw(card.image, in: cardRect)
                yCursor = cardRect.minY - 8
                index += 1
            }

            // Footer
            if index < cards.count {
                // continued…
                let continuedHV = makeHostingView(
                    HStack { Spacer(); Text("continued…").font(.footnote).foregroundStyle(.secondary) }
                        .padding(.horizontal, rpt.margin)
                        .padding(.bottom, rpt.margin)
                , width: availableWidth)
                if let continuedCG = captureCGImage(from: continuedHV) {
                    let continuedRect = CGRect(x: 0, y: 0, width: availableWidth, height: continuedHV.bounds.height)
                    ctx.draw(continuedCG, in: continuedRect)
                }
            } else {
                // Last page timestamp
                let footerText = "Generated " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                let att = NSAttributedString(string: footerText, attributes: attrs)
                let size = att.size()
                let rect = CGRect(x: availableWidth - size.width - rpt.margin, y: 8, width: size.width, height: size.height)
                att.draw(in: rect)
            }
        }

        ctx.endPDFPage()
    }

    ctx.closePDF()
    window.orderOut(nil)
    return data as Data
}
#endif

