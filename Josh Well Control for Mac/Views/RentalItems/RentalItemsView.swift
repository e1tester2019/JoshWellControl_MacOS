import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RentalItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var well: Well

    @State private var selection: RentalItem? = nil

    init(well: Well) { self._well = Bindable(wrappedValue: well) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Rentals for \(well.name)").font(.title3).bold()
                Spacer()
                Button("New Rental", systemImage: "plus") { addRental() }
            }

            // Card list (no column header)
            List(selection: $selection) {
                ForEach(sortedRentals) { r in
                    RentalCard(rental: r, selected: selection?.id == r.id) { selection = r }
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Edit Details", systemImage: "square.and.pencil") { openEditor(r) }
                            Button("Copy Summary", systemImage: "doc.on.doc") { copySummary(r) }
                            Button("Copy Well + Rental", systemImage: "doc.on.clipboard") { copyWellPlusRental(r) }
                            Button(role: .destructive) { delete(r) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                .onDelete { idx in
                    let items = idx.map { sortedRentals[$0] }
                    items.forEach(delete)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer actions
            HStack {
                Button("Edit Details", systemImage: "square.and.pencil") {
                    if let s = selection { openEditor(s) }
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(12)
        .navigationTitle("Rentals")
    }

    private var sortedRentals: [RentalItem] {
        // Prefer most recent start date first; fallback to name
        well.rentals.sorted { a, b in
            let asd = a.startDate ?? .distantPast
            let bsd = b.startDate ?? .distantPast
            if asd != bsd { return asd > bsd }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func addRental() {
        let r = RentalItem(name: "New Rental", detail: "", serialNumber: "", startDate: Date(), endDate: Date(), usageDates: [], onLocation: true, invoiced: false, costPerDay: 0, well: well)
        well.rentals.append(r)
        modelContext.insert(r)
        try? modelContext.save()
        selection = r
        openEditor(r)
    }

    private func delete(_ r: RentalItem) {
        if let i = well.rentals.firstIndex(where: { $0 === r }) { well.rentals.remove(at: i) }
        modelContext.delete(r)
        try? modelContext.save()
        if selection === r { selection = well.rentals.first }
    }

    private func openEditor(_ r: RentalItem) {
        #if os(macOS)
        let host = WindowHost(title: "Rental – \(r.name)") {
            RentalDetailEditor(rental: r)
                .environment(\.locale, Locale(identifier: "en_GB"))
                .frame(minWidth: 720, minHeight: 520)
        }
        host.show()
        #else
        // TODO: Implement iPad-compatible editor (e.g., using NavigationLink or sheet)
        #endif
    }

    private func copySummary(_ r: RentalItem) {
        // Build the same summary as RentalCard
        let cal = Calendar.current
        let dates: [Date]
        if !r.usageDates.isEmpty {
            dates = r.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        } else if let s = r.startDate, let e = r.endDate {
            var out: [Date] = []
            var day = cal.startOfDay(for: min(s, e))
            let end = cal.startOfDay(for: max(s, e))
            while day <= end { out.append(day); day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            dates = out
        } else {
            dates = []
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        var parts: [String] = []
        if !dates.isEmpty {
            var start = dates[0]; var prev = dates[0]
            func push() {
                if start == prev { parts.append(df.string(from: start)) } else { parts.append("\(df.string(from: start))–\(df.string(from: prev))") }
            }
            for d in dates.dropFirst() {
                if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) { prev = d } else { push(); start = d; prev = d }
            }
            push()
        }
        let total = !dates.isEmpty ? dates.count : r.totalDays
        var lines: [String] = []
        lines.append("Tool: \(r.name)")
        if let d = r.detail, !d.isEmpty { lines.append("Desc: \(d)") }
        if let sn = r.serialNumber, !sn.isEmpty { lines.append("SN: \(sn)") }
        if !parts.isEmpty { lines.append("Days: \(parts.joined(separator: "; ")) (total: \(total))") } else { lines.append("Days: (total: \(total))") }
        let summary = lines.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        #else
        UIPasteboard.general.string = summary
        #endif
    }

    private func copyWellPlusRental(_ r: RentalItem) {
        // Well header
        let wellName = well.name
        let uwi = well.uwi ?? ""
        let afe = well.afeNumber ?? ""
        let req = well.requisitioner ?? ""
        let wellHeader = "Well Name: \(wellName)\nUWI: \(uwi)\nAFE: \(afe)\nRequisitioner: \(req)"

        // Rental summary (condensed ranges + total)
        let cal = Calendar.current
        let dates: [Date]
        if !r.usageDates.isEmpty {
            dates = r.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        } else if let s = r.startDate, let e = r.endDate {
            var out: [Date] = []
            var day = cal.startOfDay(for: min(s, e))
            let end = cal.startOfDay(for: max(s, e))
            while day <= end { out.append(day); day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            dates = out
        } else {
            dates = []
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        var parts: [String] = []
        if !dates.isEmpty {
            var start = dates[0]; var prev = dates[0]
            func push() {
                if start == prev { parts.append(df.string(from: start)) }
                else { parts.append("\(df.string(from: start))–\(df.string(from: prev))") }
            }
            for d in dates.dropFirst() {
                if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) { prev = d } else { push(); start = d; prev = d }
            }
            push()
        }
        let total = !dates.isEmpty ? dates.count : r.totalDays
        var rentalLines: [String] = []
        rentalLines.append("Tool: \(r.name)")
        if let d = r.detail, !d.isEmpty { rentalLines.append("Desc: \(d)") }
        if let sn = r.serialNumber, !sn.isEmpty { rentalLines.append("SN: \(sn)") }
        if !parts.isEmpty { rentalLines.append("Days: \(parts.joined(separator: "; ")) (total: \(total))") } else { rentalLines.append("Days: (total: \(total))") }
        let rentalSummary = rentalLines.joined(separator: "\n")

        // Combined
        let combined = wellHeader + "\n\n" + rentalSummary
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        #else
        UIPasteboard.general.string = combined
        #endif
    }
}

// MARK: - Card Row
private struct RentalCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var rental: RentalItem
    var selected: Bool
    var onSelect: () -> Void

    private var cardFill: Color { selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08) }
    private var cardStroke: Color { selected ? Color.accentColor : Color.secondary.opacity(0.25) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Name", text: $rental.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Description").font(.caption).foregroundStyle(.secondary)
                    TextField("Description", text: Binding(get: { rental.detail ?? "" }, set: { rental.detail = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Serial #").font(.caption).foregroundStyle(.secondary)
                    TextField("Serial #", text: Binding(get: { rental.serialNumber ?? "" }, set: { rental.serialNumber = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("$/Day").font(.caption).foregroundStyle(.secondary)
                    TextField("0", value: $rental.costPerDay, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                Button {
                    copySummary()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy rental summary")
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(get: { rental.startDate ?? Date() }, set: { rental.startDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: rental.startDate) { _, _ in syncUsageDatesFromRange() }
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("End").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(get: { rental.endDate ?? Date() }, set: { rental.endDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: rental.endDate) { _, _ in syncUsageDatesFromRange() }
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("On Loc").font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: $rental.onLocation).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invoiced").font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: $rental.invoiced).labelsHidden()
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Additional").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", rental.additionalCostsTotal)).monospacedDigit()
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", rental.totalCost)).bold().monospacedDigit()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardStroke, lineWidth: selected ? 1.5 : 1))
        .onTapGesture { onSelect() }
        .onDisappear { try? modelContext.save() }
    }

    private func syncUsageDatesFromRange() {
        guard let s = rental.startDate, let e = rental.endDate else { return }
        let cal = Calendar.current
        var day = cal.startOfDay(for: min(s, e))
        let end = cal.startOfDay(for: max(s, e))
        var days: [Date] = []
        while day <= end {
            days.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        rental.usageDates = days
        try? modelContext.save()
    }

    private func copySummary() { copySummary(for: rental) }

    private func copySummary(for r: RentalItem) {
        let summary = rentalSummaryString(for: r)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        #else
        UIPasteboard.general.string = summary
        #endif
    }

    private func rentalSummaryString(for r: RentalItem) -> String {
        let name = r.name
        let desc = r.detail?.isEmpty == false ? r.detail! : ""
        let sn = r.serialNumber?.isEmpty == false ? r.serialNumber! : ""
        let dates = normalizedDates(for: r)
        let ranges = condensedRangesString(from: dates)
        let total = dates.count > 0 ? dates.count : r.totalDays
        var lines: [String] = []
        lines.append("Tool: \(name)")
        if !desc.isEmpty { lines.append("Desc: \(desc)") }
        if !sn.isEmpty { lines.append("SN: \(sn)") }
        if !ranges.isEmpty { lines.append("Days: \(ranges) (total: \(total))") } else { lines.append("Days: (total: \(total))") }
        return lines.joined(separator: "\n")
    }

    private func normalizedDates(for r: RentalItem) -> [Date] {
        let cal = Calendar.current
        if !r.usageDates.isEmpty {
            return r.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        }
        guard let s = r.startDate, let e = r.endDate else { return [] }
        var out: [Date] = []
        var day = cal.startOfDay(for: min(s, e))
        let end = cal.startOfDay(for: max(s, e))
        while day <= end {
            out.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    private func condensedRangesString(from dates: [Date]) -> String {
        guard !dates.isEmpty else { return "" }
        let cal = Calendar.current
        let dfShort = DateFormatter(); dfShort.dateStyle = .medium; dfShort.timeStyle = .none
        var parts: [String] = []
        var start = dates[0]
        var prev = dates[0]
        func pushCurrent() {
            if start == prev {
                parts.append(dfShort.string(from: start))
            } else {
                let left = dfShort.string(from: start)
                let right = dfShort.string(from: prev)
                parts.append("\(left)–\(right)")
            }
        }
        for d in dates.dropFirst() {
            if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) {
                prev = d
            } else {
                pushCurrent()
                start = d
                prev = d
            }
        }
        pushCurrent()
        return parts.joined(separator: "; ")
    }
}

// MARK: - Detail Editor
private struct RentalDetailEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var rental: RentalItem

    @State private var newCostDesc: String = ""
    @State private var newCostAmount: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Details") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Name").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Name", text: $rental.name).textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Description").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Description", text: Binding(get: { rental.detail ?? "" }, set: { rental.detail = $0 }))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Serial #").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Serial Number", text: Binding(get: { rental.serialNumber ?? "" }, set: { rental.serialNumber = $0 }))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Start Date").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            DatePicker("", selection: Binding(get: { rental.startDate ?? Date() }, set: { rental.startDate = $0 }), displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .onChange(of: rental.startDate) { _, _ in syncUsageDatesFromRange() }
                        }
                        GridRow {
                            Text("End Date").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            DatePicker("", selection: Binding(get: { rental.endDate ?? Date() }, set: { rental.endDate = $0 }), displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .onChange(of: rental.endDate) { _, _ in syncUsageDatesFromRange() }
                        }
                        GridRow {
                            Text("On Location").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            Toggle("", isOn: $rental.onLocation).labelsHidden()
                        }
                        GridRow {
                            Text("Invoiced").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            Toggle("", isOn: $rental.invoiced).labelsHidden()
                        }
                    }
                }

                GroupBox("Usage Days") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adjusting Start/End updates this list automatically. You can still add/remove days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button { addToday() } label: { Label("Add Today", systemImage: "calendar.badge.plus") }
                            Button { clearUsage() } label: { Label("Clear", systemImage: "trash") }
                            Spacer()
                            Text("Total days: \(rental.totalDays)")
                        }
                        .controlSize(.small)

                        let dates = rental.usageDates.sorted()
                        if dates.isEmpty {
                            Text("No specific usage days. Using Start/End.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                                ForEach(dates, id: \.self) { d in
                                    HStack(spacing: 4) {
                                        Text(dateString(d)).font(.caption)
                                        Button(role: .destructive) { rental.toggleUsage(on: d) } label: { Image(systemName: "xmark.circle.fill") }
                                            .buttonStyle(.borderless)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                                }
                            }
                        }
                    }
                }

                GroupBox("Costs") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Cost per day ($)").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("0", value: $rental.costPerDay, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        Divider()
                        Text("Additional Costs").font(.caption).foregroundStyle(.secondary)
                        ForEach(rental.additionalCosts) { c in
                            HStack(spacing: 8) {
                                TextField("Description", text: Binding(get: { c.descriptionText }, set: { c.descriptionText = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Amount", value: Binding(get: { c.amount }, set: { c.amount = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                Button(role: .destructive) {
                                    if let i = rental.additionalCosts.firstIndex(where: { $0 === c }) { rental.additionalCosts.remove(at: i) }
                                    modelContext.delete(c)
                                } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("Description", text: $newCostDesc)
                                .textFieldStyle(.roundedBorder)
                            TextField("Amount", text: $newCostAmount)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .onSubmit { addAdditionalCost() }
                            Button("Add Cost") { addAdditionalCost() }
                        }
                        HStack {
                            Spacer()
                            Text("Addl: $\(String(format: "%.2f", rental.additionalCostsTotal))   Total: $\(String(format: "%.2f", rental.totalCost))")
                                .font(.callout)
                                .bold()
                        }
                    }
                }
            }
            .padding(12)
            .onChange(of: rental.startDate ?? Date.distantPast) { _, _ in
                syncUsageDatesFromRange()
            }
            .onChange(of: rental.endDate ?? Date.distantFuture) { _, _ in
                syncUsageDatesFromRange()
            }
        }
        .onDisappear { try? modelContext.save() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    copyWellPlusRental()
                } label: {
                    Label("Copy Well + Rental", systemImage: "doc.on.clipboard")
                }
            }
        }
    }

    private func addToday() { rental.toggleUsage(on: Date()); try? modelContext.save() }
    private func clearUsage() { rental.usageDates.removeAll(); try? modelContext.save() }
    private func addAdditionalCost() {
        let amount = Double(newCostAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        guard !newCostDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount != 0 else { return }
        let c = RentalAdditionalCost(descriptionText: newCostDesc, amount: amount, date: Date())
        rental.additionalCosts.append(c)
        modelContext.insert(c)
        newCostDesc = ""; newCostAmount = ""
        try? modelContext.save()
    }
    private func syncUsageDatesFromRange() {
        guard let s = rental.startDate, let e = rental.endDate else { return }
        let cal = Calendar.current
        var day = cal.startOfDay(for: min(s, e))
        let end = cal.startOfDay(for: max(s, e))
        var days: [Date] = []
        while day <= end {
            days.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        rental.usageDates = days
        try? modelContext.save()
    }
    private func dateString(_ d: Date) -> String { let df = DateFormatter(); df.dateStyle = .medium; return df.string(from: d) }

    private func copyWellPlusRental() {
        let wellName = rental.well?.name ?? ""
        let uwi = rental.well?.uwi ?? ""
        let afe = rental.well?.afeNumber ?? ""
        let req = rental.well?.requisitioner ?? ""
        let wellHeader = "Well Name: \(wellName)\nUWI: \(uwi)\nAFE: \(afe)\nRequisitioner: \(req)"

        let cal = Calendar.current
        let dates: [Date]
        if !rental.usageDates.isEmpty {
            dates = rental.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        } else if let s = rental.startDate, let e = rental.endDate {
            var out: [Date] = []
            var day = cal.startOfDay(for: min(s, e))
            let end = cal.startOfDay(for: max(s, e))
            while day <= end { out.append(day); day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            dates = out
        } else {
            dates = []
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        var parts: [String] = []
        if !dates.isEmpty {
            var start = dates[0]; var prev = dates[0]
            func push() {
                if start == prev { parts.append(df.string(from: start)) }
                else { parts.append("\(df.string(from: start))–\(df.string(from: prev))") }
            }
            for d in dates.dropFirst() {
                if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) { prev = d } else { push(); start = d; prev = d }
            }
            push()
        }
        let total = !dates.isEmpty ? dates.count : rental.totalDays
        var rentalLines: [String] = []
        rentalLines.append("Tool: \(rental.name)")
        if let d = rental.detail, !d.isEmpty { rentalLines.append("Desc: \(d)") }
        if let sn = rental.serialNumber, !sn.isEmpty { rentalLines.append("SN: \(sn)") }
        if !parts.isEmpty { rentalLines.append("Days: \(parts.joined(separator: "; ")) (total: \(total))") } else { rentalLines.append("Days: (total: \(total))") }
        let combined = wellHeader + "\n\n" + rentalLines.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        #else
        UIPasteboard.general.string = combined
        #endif
    }
}

// Simple flow layout for chips
private struct FlowLayout<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            var width: CGFloat = 0
            var height: CGFloat = 0
            ZStack(alignment: Alignment(horizontal: alignment, vertical: .top)) {
                content
                    .alignmentGuide(.leading) { d in
                        if width + d.width > geometry.size.width {
                            width = 0
                            height -= (d.height + spacing)
                        }
                        let result = width
                        width += d.width + spacing
                        return result
                    }
                    .alignmentGuide(.top) { d in
                        let result = height
                        return result
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct RentalItemsView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! ModelContainer(
            for: Well.self, RentalItem.self, RentalAdditionalCost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let well = Well(name: "Test Well")
        ctx.insert(well)
        let r1 = RentalItem(name: "MWD Tool", detail: "Telemetry", startDate: Date().addingTimeInterval(-86400*3), endDate: Date(), usageDates: [Date().addingTimeInterval(-86400*2), Date().addingTimeInterval(-86400)], onLocation: true, invoiced: false, costPerDay: 1200, well: well)
        let c1 = RentalAdditionalCost(descriptionText: "Delivery", amount: 250)
        r1.additionalCosts.append(c1)
        well.rentals.append(r1)
        ctx.insert(r1); ctx.insert(c1)
        try? ctx.save()

        return NavigationStack { RentalItemsView(well: well) }
            .modelContainer(container)
            .frame(width: 980, height: 640)
    }
}
#endif

