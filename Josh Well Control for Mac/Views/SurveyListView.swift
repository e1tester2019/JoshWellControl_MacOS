import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum SurveyField { case md, inc, azi }

// MARK: - Survey List / Editor
struct SurveyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @State private var selection: SurveyStation?
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var listVersion: Int = 0

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                header
                List(selection: $selection) {
                    ForEach(sortedSurveys) { s in
                        SurveyRow(station: s, onDelete: { delete(s) }) { field in
                            onSurveyChange(field)
                        }
                        .tag(s)
                    }
                    .onDelete { idx in
                        let items = idx.map { sortedSurveys[$0] }
                        items.forEach { delete($0) }
                    }
                }
                .id(listVersion)
                footer
            }
            .padding(.horizontal)
            .navigationTitle("Surveys")
            .onAppear { recomputeTVD() }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .utf8PlainText],
                          allowsMultipleSelection: false) { (result: Result<[URL], Error>) in
                handleImport(result)
            }
            .alert("Import Error",
                   isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "unknown error")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("MD (m)").frame(width: 90, alignment: .leading)
            Text("Incl (°)").frame(width: 80, alignment: .leading)
            Text("Azm (°)").frame(width: 80, alignment: .leading)
            Text("TVD (m)").frame(width: 90, alignment: .leading)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Button("Add Station") { add() }
            Spacer()
            Button("Import CSV…") { showingImporter = true }
        }
        .padding(.vertical, 8)
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Delete", role: .destructive) {
                if let sel = selection { delete(sel) }
            }
            .disabled(selection == nil)
            .keyboardShortcut(.delete, modifiers: [])
        }
    }

    private var sortedSurveys: [SurveyStation] {
        // Prefer MD for ordering if available; fallback to creation order
        project.surveys.sorted { (lhs: SurveyStation, rhs: SurveyStation) -> Bool in
            if lhs.md != rhs.md { return lhs.md < rhs.md }
            if lhs.inc != rhs.inc { return lhs.inc < rhs.inc }
            if lhs.azi != rhs.azi { return lhs.azi < rhs.azi }
            let lt = lhs.tvd ?? .infinity
            let rt = rhs.tvd ?? .infinity
            return lt < rt
        }
    }

    private func sortByMDAndRefresh() {
        project.surveys.sort { (lhs: SurveyStation, rhs: SurveyStation) -> Bool in
            if lhs.md != rhs.md { return lhs.md < rhs.md }
            if lhs.inc != rhs.inc { return lhs.inc < rhs.inc }
            if lhs.azi != rhs.azi { return lhs.azi < rhs.azi }
            let lt = lhs.tvd ?? .infinity
            let rt = rhs.tvd ?? .infinity
            return lt < rt
        }
        listVersion &+= 1 // wraparound-safe increment
        recomputeTVD()
        try? modelContext.save()
    }

    private func recomputeTVD() {
        // Compute TVD using an MD-sorted **view** of the data without reordering the UI array
        let ordered = project.surveys.sorted { (lhs: SurveyStation, rhs: SurveyStation) -> Bool in
            if lhs.md != rhs.md { return lhs.md < rhs.md }
            if lhs.inc != rhs.inc { return lhs.inc < rhs.inc }
            if lhs.azi != rhs.azi { return lhs.azi < rhs.azi }
            let lt = lhs.tvd ?? .infinity
            let rt = rhs.tvd ?? .infinity
            return lt < rt
        }
        var last: SurveyStation? = nil
        for s in ordered {
            if let prev = last {
                let dmd = s.md - prev.md
                let inc1 = prev.inc * .pi / 180.0
                let inc2 = s.inc * .pi / 180.0
                let avgInc = 0.5 * (inc1 + inc2)
                let prevTVD = prev.tvd ?? 0
                let dTVD = dmd * cos(avgInc)
                s.tvd = prevTVD + dTVD
            } else {
                s.tvd = s.tvd ?? 0
            }
            last = s
        }
        try? modelContext.save()
    }

    private func onSurveyChange(_ field: SurveyField) {
        if case .md = field { sortByMDAndRefresh() } else { recomputeTVD() }
    }

    private func add() {
        let lastSurvey = sortedSurveys.last ?? SurveyStation(md: 0, inc: 0, azi: 0)
        let s = SurveyStation(md: lastSurvey.md + 30, inc: lastSurvey.inc, azi: lastSurvey.azi)
        project.surveys.append(s)
        modelContext.insert(s)
        try? modelContext.save()
        recomputeTVD()
    }

    private func delete(_ s: SurveyStation) {
        if let i = project.surveys.firstIndex(where: { $0.id == s.id }) {
            project.surveys.remove(at: i)
        }
        modelContext.delete(s)
        try? modelContext.save()
        if selection?.id == s.id { selection = nil }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                    throw NSError(domain: "Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file as UTF‑8 or ASCII."])
                }
                let rows = CSVParser.parse(text: text)
                try importRows(rows)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func importRows(_ rows: [[String: String]]) throws {
        // Try common header names (case‑insensitive)
        func col(_ names: [String]) -> String? {
            let keys: [String] = rows.first.map { Array($0.keys) } ?? []
            return keys.first { (raw: String) in
                let k = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{FEFF}", with: "")
                return names.contains { k.caseInsensitiveCompare($0) == .orderedSame }
            }
        }
        guard !rows.isEmpty else { return }
        let mdKey   = col(["MD", "Measured Depth", "MD (m)", "Depth"]) ?? ""
        let incKey  = col(["Incl", "Inc", "Inclination", "Inclination (deg)", "INCL (°)"]) ?? ""
        let azmKey  = col(["Azm", "Azi", "Azimuth", "Azimuth (deg)", "AZI (°)"]) ?? ""
        let tvdKey  = col(["TVD", "TVD (m)"]) ?? ""

        // Helper to parse numbers like "1,460" or " 500 "
        func toDouble(_ raw: String?) -> Double? {
            guard var s = raw else { return nil }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: ",", with: "")
            return Double(s)
        }

        var created: [SurveyStation] = []
        for row in rows {
            let mdVal = toDouble(row[mdKey])
            let incVal = toDouble(row[incKey])
            let azmVal = toDouble(row[azmKey])
            let tvdVal = toDouble(row[tvdKey])

            let s = SurveyStation(md: mdVal ?? 0, inc: incVal ?? 0, azi: azmVal ?? 0)
            s.tvd = tvdVal

            created.append(s)
            project.surveys.append(s)
            modelContext.insert(s)
        }
        try? modelContext.save()
        sortByMDAndRefresh()
        // Select last imported
        selection = created.last
    }
}

private struct SurveyRow: View {
    @Bindable var station: SurveyStation
    var onDelete: () -> Void
    var onChange: (SurveyField) -> Void

    // Local UI state so we don't mutate the model while typing
    @State private var mdText: String = ""
    @State private var incText: String = ""
    @State private var aziText: String = ""
    @State private var tvdText: String = ""

    // Track focus to commit on focus changes
    private enum Field { case md, inc, azi, tvd }
    @FocusState private var focusedField: Field?
    @State private var lastFocused: Field? = nil

    init(station: SurveyStation, onDelete: @escaping () -> Void, onChange: @escaping (SurveyField) -> Void) {
        self._station = Bindable(wrappedValue: station)
        self.onDelete = onDelete
        self.onChange = onChange
        // seed local text values
        _mdText = State(initialValue: Self.format2(station.md))
        _incText = State(initialValue: Self.format0(station.inc))
        _aziText = State(initialValue: Self.format0(station.azi))
        _tvdText = State(initialValue: Self.format2(station.tvd ?? 0))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("MD", text: $mdText)
                .frame(width: 90, alignment: .leading)
                .focused($focusedField, equals: .md)
                .onSubmit { commitMD() }

            TextField("Incl", text: $incText)
                .frame(width: 80, alignment: .leading)
                .focused($focusedField, equals: .inc)
                .onSubmit { commitInc() }

            TextField("Azm", text: $aziText)
                .frame(width: 80, alignment: .leading)
                .focused($focusedField, equals: .azi)
                .onSubmit { commitAzi() }

            TextField("TVD", text: $tvdText)
                .frame(width: 90, alignment: .leading)
                .focused($focusedField, equals: .tvd)
                .onSubmit { commitTVD() }

            Spacer()
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .onChange(of: focusedField) { newValue in
            // When focus moves away from a field, commit the previous field
            defer { lastFocused = newValue }
            switch lastFocused {
            case .md?: commitMD()
            case .inc?: commitInc()
            case .azi?: commitAzi()
            case .tvd?: commitTVD()
            case nil: break
            }
        }
        .onAppear { syncFromModel() }
    }

    // MARK: - Commit helpers
    private func commitMD() {
        if let v = Self.parse(mdText) {
            if v != station.md { station.md = v; onChange(.md) }
            mdText = Self.format2(station.md)
        } else {
            mdText = Self.format2(station.md)
        }
    }
    private func commitInc() {
        if let v = Self.parse(incText) {
            if v != station.inc { station.inc = v; onChange(.inc) }
            incText = Self.format0(station.inc)
        } else {
            incText = Self.format0(station.inc)
        }
    }
    private func commitAzi() {
        if let v = Self.parse(aziText) {
            if v != station.azi { station.azi = v; onChange(.azi) }
            aziText = Self.format0(station.azi)
        } else {
            aziText = Self.format0(station.azi)
        }
    }
    private func commitTVD() {
        if let v = Self.parse(tvdText) {
            station.tvd = v
            tvdText = Self.format2(v)
        } else {
            tvdText = Self.format2(station.tvd ?? 0)
        }
    }

    private func syncFromModel() {
        mdText = Self.format2(station.md)
        incText = Self.format0(station.inc)
        aziText = Self.format0(station.azi)
        tvdText = Self.format2(station.tvd ?? 0)
    }

    // MARK: - Formatting & parsing
    private static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }
    private static func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private static func format2(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: - Tiny CSV helper (robust enough for common cases; not RFC‑complete)
private enum CSVParser {
    // Normalize header: trim whitespace/newlines and remove UTF-8 BOM if present
    private static func normalizeHeader(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    static func parse(text: String) -> [[String: String]] {
        var rows: [[String: String]] = []
        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard let headerLine = lines.first else { return [] }
        let headers = splitCSVLine(headerLine).map { normalizeHeader($0) }
        for line in lines.dropFirst() {
            let cols = splitCSVLine(line)
            var row: [String: String] = [:]
            for (i, h) in headers.enumerated() {
                row[h] = i < cols.count ? cols[i] : ""
            }
            rows.append(row)
        }
        return rows
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let ch = iterator.next() {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == "," && !inQuotes { result.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            current.append(ch)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}

#if DEBUG
#Preview("Surveys – Sample Data") {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProjectState.self,
                 SurveyStation.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 PressureWindow.self,
                 PressureWindowPoint.self,
                 SlugPlan.self,
                 SlugStep.self,
                 BackfillPlan.self,
                 BackfillRule.self,
                 TripSettings.self,
                 SwabInput.self,
            configurations: config
        )
        let ctx = container.mainContext
        let project = ProjectState()
        ctx.insert(project)
        // Seed a few stations
        let s1 = SurveyStation(md: 0, inc: 0, azi: 0); s1.tvd = 0
        let s2 = SurveyStation(md: 500, inc: 5, azi: 45); s2.tvd = 498
        let s3 = SurveyStation(md: 1000, inc: 10, azi: 90); s3.tvd = 980
        [s1,s2,s3].forEach { project.surveys.append($0); ctx.insert($0) }
        try? ctx.save()

        return NavigationStack { SurveyListView(project: project) }
            .modelContainer(container)
            .frame(width: 760, height: 520)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
#endif
