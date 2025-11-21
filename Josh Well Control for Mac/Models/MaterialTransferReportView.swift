import SwiftUI
#if os(macOS)
import AppKit
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
                        .stroke(Color.gray.opacity(0.85), lineWidth: 1.75)
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
                        .stroke(Color.gray.opacity(0.75), lineWidth: 1.5)
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
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .foregroundStyle(.black)
        }
        .frame(width: pageSize.width, height: pageSize.height)
    }

    // MARK: - Subviews
    private func headerKV(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.body)
        }
    }

    private func itemCard(_ item: MaterialTransferItem) -> some View {
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
                .stroke(Color.gray.opacity(0.8), lineWidth: 1.5)
        )
    }
}

// MARK: - PDF rendering helper (macOS)
#if os(macOS)
func pdfDataForView<V: View>(_ view: V, pageSize: CGSize) -> Data? {
    let hosting = NSHostingView(rootView: AnyView(view).frame(width: pageSize.width, height: pageSize.height))
    hosting.frame = CGRect(origin: .zero, size: pageSize)
    let data = hosting.dataWithPDF(inside: hosting.bounds)
    return data
}
#endif

