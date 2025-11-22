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
                        headerKV("AFE #:", transfer.afeNumber ?? "")
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
                    Text("Quantity").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(item.quantity))")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("$/Unit").font(.caption).foregroundStyle(.secondary)
                    Text(currency(item.unitPrice ?? 0))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Description").font(.caption).foregroundStyle(.secondary)
                    Text(item.descriptionText)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(currency(total)).font(.headline)
                }
            }

            // Details (full width)
            if let details = item.detailText, !details.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Details").font(.caption).foregroundStyle(.secondary)
                    Text(details)
                }
            }

            // Receiver Address (full width)
            if let addr = item.receiverAddress, !addr.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiver Address").font(.caption).foregroundStyle(.secondary)
                    Text(addr)
                }
            }

            // Account Code + Condition
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account Code").font(.caption).foregroundStyle(.secondary)
                    Text(item.accountCode ?? (transfer.accountCode ?? ""))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Condition").font(.caption).foregroundStyle(.secondary)
                    Text(item.conditionCode ?? "")
                }
            }

            // Receiver Phone
            if let phone = item.receiverPhone, !phone.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiver Phone").font(.caption).foregroundStyle(.secondary)
                    Text(phone)
                }
            }

            // To Loc/AFE/Vendor + Transported By
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To Loc/AFE/Vendor").font(.caption).foregroundStyle(.secondary)
                    Text(item.vendorOrTo ?? (transfer.destinationName ?? ""))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transported By").font(.caption).foregroundStyle(.secondary)
                    Text(item.transportedBy ?? (transfer.transportedBy ?? ""))
                }
            }

            // Est. Weight
            if let w = item.estimatedWeight, w > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Est. Weight (lb)").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.0f", w))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.03))
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

    // Helper to try vector capture for a given rect
    func vectorPDFSlice(in rect: CGRect) -> Data? {
        let data = hostingView.dataWithPDF(inside: rect)
        return data.count > 1000 && data.starts(with: Array("%PDF".utf8)) ? data : nil
    }

    // Prepare a PDF context to assemble all pages
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        window.orderOut(nil)
        return nil
    }

    // Iterate pages by slicing the content vertically
    let pageCount = Int(ceil(contentHeight / pageSize.height))
    for pageIndex in 0..<pageCount {
        let sliceOriginY = CGFloat(pageIndex) * pageSize.height
        let sliceRect = CGRect(x: 0, y: sliceOriginY, width: pageSize.width, height: pageSize.height)

        // Try vector capture first
        if let sliceData = vectorPDFSlice(in: sliceRect),
           let provider = CGDataProvider(data: sliceData as CFData),
           let page = CGPDFDocument(provider)?.page(at: 1) {
            ctx.beginPDFPage(nil)
            // Draw the captured vector page into the current page's bounds
            let pageBox = page.getBoxRect(.mediaBox)
            let scaleX = pageSize.width / pageBox.width
            let scaleY = pageSize.height / pageBox.height
            ctx.saveGState()
            ctx.translateBy(x: 0, y: 0)
            ctx.scaleBy(x: scaleX, y: scaleY)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            ctx.endPDFPage()
            continue
        }

        // Fallback: bitmap snapshot for this page slice
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: sliceRect) else {
            continue
        }
        rep.size = pageSize
        hostingView.cacheDisplay(in: sliceRect, to: rep)
        guard let cgImage = rep.cgImage else { continue }

        ctx.beginPDFPage(nil)
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: pageSize))
        ctx.endPDFPage()
    }

    ctx.closePDF()
    window.orderOut(nil)
    return data as Data
}
#endif

