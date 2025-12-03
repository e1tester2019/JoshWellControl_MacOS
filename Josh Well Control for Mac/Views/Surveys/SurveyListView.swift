import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Survey List / Editor
struct SurveyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @State private var vm = ViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $vm.selection) {
                Section {
                    ForEach(vm.sortedSurveys) { s in
                        SurveyRow(station: s, onDelete: { vm.delete(s) }) { field in
                            vm.onSurveyChange(field)
                        }
                        .tag(s)
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.sortedSurveys[$0] }
                        items.forEach { vm.delete($0) }
                    }
                } header: { header }
            }
            .listStyle(.inset)
            .scrollIndicators(.hidden)
            .id(vm.listVersion)
            footer
        }
        .onAppear { vm.attach(project: project, context: modelContext); vm.recomputeTVD() }
        .fileImporter(isPresented: $vm.showingImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .utf8PlainText],
                      allowsMultipleSelection: false) { (result: Result<[URL], Error>) in
            vm.handleImport(result)
        }
        .alert("Import Error",
               isPresented: Binding(get: { vm.importError != nil }, set: { if !$0 { vm.importError = nil } })) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "unknown error")
        }
        .toolbar { toolbar }
        #if os(macOS)
        .onDeleteCommand { if let sel = vm.selection { vm.delete(sel) } }
        #endif
    }

    private var header: some View {
        HStack {
            Text("MD (m)").frame(width: 90, alignment: .leading)
            Text("Incl (°)").frame(width: 80, alignment: .leading)
            Text("Azm (°)").frame(width: 80, alignment: .leading)
            Text("TVD (m)").frame(width: 90, alignment: .leading)
            Text("VS (m)").frame(width: 80, alignment: .leading)
            Text("NS (m)").frame(width: 80, alignment: .leading)
            Text("EW (m)").frame(width: 80, alignment: .leading)
            Text("DLS (°/30m)").frame(width: 110, alignment: .leading)
            Text("Subsea (m)").frame(width: 90, alignment: .leading)
            Text("Build (°/30m)").frame(width: 120, alignment: .leading)
            Text("Turn (°/30m)").frame(width: 120, alignment: .leading)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Button("Add Station") { vm.add() }
            Button("Clear Stations") { vm.clearStations() }
            Spacer()
            Button("Import Surveys…") { vm.showingImporter = true }
        }
        .padding(.vertical, 8)
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Delete", role: .destructive) {
                if let sel = vm.selection { vm.delete(sel) }
            }
            .disabled(vm.selection == nil)
            .keyboardShortcut(.delete, modifiers: [])
        }
    }

// ViewModel implementation for SurveyListView
}

extension SurveyListView {
    @Observable
    class ViewModel {
        @ObservationIgnored var modelContext: ModelContext!
        @ObservationIgnored private(set) var project: ProjectState!

        enum SurveyField { case md, inc, azi }

        // UI State
        var selection: SurveyStation? = nil
        var showingImporter: Bool = false
        var importError: String? = nil
        var listVersion: Int = 0

        // Attach once from the view
        func attach(project: ProjectState, context: ModelContext) {
            if self.project == nil { self.project = project }
            // Bind the model context for internal saves
            self.modelContext = context
        }

        var sortedSurveys: [SurveyStation] {
            guard let project else { return [] }
            return (project.surveys ?? []).sorted { (lhs: SurveyStation, rhs: SurveyStation) -> Bool in
                if lhs.md != rhs.md { return lhs.md < rhs.md }
                if lhs.inc != rhs.inc { return lhs.inc < rhs.inc }
                if lhs.azi != rhs.azi { return lhs.azi < rhs.azi }
                let lt = lhs.tvd ?? .infinity
                let rt = rhs.tvd ?? .infinity
                return lt < rt
            }
        }

        func sortByMDAndRefresh() {
            guard let project else { return }
            project.surveys?.sort { (lhs: SurveyStation, rhs: SurveyStation) -> Bool in
                if lhs.md != rhs.md { return lhs.md < rhs.md }
                if lhs.inc != rhs.inc { return lhs.inc < rhs.inc }
                if lhs.azi != rhs.azi { return lhs.azi < rhs.azi }
                let lt = lhs.tvd ?? .infinity
                let rt = rhs.tvd ?? .infinity
                return lt < rt
            }
            listVersion &+= 1
            recomputeTVD()
            try? modelContext.save()
        }

        func recomputeTVD() {
            guard let project else { return }
            let ordered = (project.surveys ?? []).sorted { (lhs: SurveyStation, rhs: SurveyStation) -> Bool in
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

        func onSurveyChange(_ field: SurveyField) {
            if case .md = field { sortByMDAndRefresh() } else { recomputeTVD() }
        }

        func clearStations() {
            guard let project else { return }
            project.surveys?.removeAll()
            try? modelContext.save()
        }

        func add() {
            guard let project else { return }
            let lastSurvey = sortedSurveys.last ?? SurveyStation(md: 0, inc: 0, azi: 0, tvd: nil)
            let s = SurveyStation(md: lastSurvey.md + 30, inc: lastSurvey.inc, azi: lastSurvey.azi, tvd: lastSurvey.tvd)
            project.surveys?.append(s)
            modelContext.insert(s)
            try? modelContext.save()
            recomputeTVD()
        }

        func delete(_ s: SurveyStation) {
            guard let project else { return }

            // Determine new selection BEFORE deleting (to avoid accessing deleted objects)
            var newSelection: SurveyStation? = selection
            if selection?.id == s.id {
                newSelection = nil
            }

            // Remove from array
            if let i = (project.surveys ?? []).firstIndex(where: { $0.id == s.id }) {
                project.surveys?.remove(at: i)
            }

            // Delete from context (after determining new selection)
            modelContext.delete(s)
            try? modelContext.save()

            // Apply the new selection
            selection = newSelection
        }

        func handleImport(_ result: Result<[URL], Error>) {
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
                    project.surveys?.removeAll()
                    if PasonParser.looksLikePason(text) {
                        try importPasonText(text, fileName: url.lastPathComponent)
                    } else {
                        let rows = CSVParser.parse(text: text)
                        try importRows(rows)
                    }
                } catch {
                    importError = error.localizedDescription
                }
            }
        }

        // MARK: Import helpers
        private func importRows(_ rows: [[String: String]]) throws {
            guard let project else { return }
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

                let s = SurveyStation(md: mdVal ?? 0, inc: incVal ?? 0, azi: azmVal ?? 0, tvd: tvdVal)
                s.tvd = tvdVal

                created.append(s)
                project.surveys?.append(s)
                modelContext.insert(s)
            }
            try? modelContext.save()
            sortByMDAndRefresh()
            selection = created.last
        }

        private func importPasonText(_ text: String, fileName: String?) throws {
            guard let project else { return }
            var lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
            guard !lines.isEmpty else { return }

            var vsd: Double? = nil
            for hdr in lines.prefix(while: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }) {
                if let r = hdr.range(of: "VSD =") {
                    let tail = hdr[r.upperBound...].trimmingCharacters(in: .whitespaces)
                    vsd = Double(tail)
                }
            }
            while let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("#") { lines.removeFirst() }

            guard let headerLine = lines.first else { return }
            let headers = headerLine.split(separator: "\t").map { String($0) }
            let idx = PasonParser.indexMap(headers: headers)
            guard idx.md >= 0, idx.inc >= 0, idx.azm >= 0 else {
                throw NSError(domain: "Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns in Pason file."])
            }

            var created: [SurveyStation] = []
            for line in lines.dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if trimmed == "#EOF" { break }
                let cols = line.split(separator: "\t").map { String($0) }
                func val(_ i: Int) -> Double? { (i >= 0 && i < cols.count) ? Double(cols[i].replacingOccurrences(of: ",", with: "")) : nil }

                let md  = val(idx.md)  ?? 0
                let inc = val(idx.inc) ?? 0
                let azm = val(idx.azm) ?? 0
                let tvd = val(idx.tvd)

                let s = SurveyStation(md: md, inc: inc, azi: azm, tvd: tvd)
                s.vs_m = val(idx.vs)
                s.ns_m = val(idx.ns)
                s.ew_m = val(idx.ew)
                s.dls_deg_per30m = val(idx.dls)
                s.subsea_m = val(idx.subsea)
                s.buildRate_deg_per30m = val(idx.build)
                s.turnRate_deg_per30m = val(idx.turn)
                s.vsd_direction_deg = vsd
                s.sourceFileName = fileName

                project.surveys?.append(s)
                modelContext.insert(s)
                created.append(s)
            }
            try? modelContext.save()
            sortByMDAndRefresh()
            selection = created.last
        }
    }
}

private struct SurveyRow: View {
    typealias SurveyField = SurveyListView.ViewModel.SurveyField
    @Bindable var station: SurveyStation
    var onDelete: () -> Void
    var onChange: (SurveyField) -> Void

    // Local UI state so we don't mutate the model while typing
    @State private var mdText: String = ""
    @State private var incText: String = ""
    @State private var aziText: String = ""
    @State private var tvdText: String = ""
    @State private var vsText: String = ""
    @State private var nsText: String = ""
    @State private var ewText: String = ""
    @State private var dlsText: String = ""
    @State private var subseaText: String = ""
    @State private var buildText: String = ""
    @State private var turnText: String = ""

    // Track focus to commit on focus changes
    private enum Field { case md, inc, azi, tvd, vs, ns, ew, dls, subsea, build, turn }
    @FocusState private var focusedField: Field?
    @State private var lastFocused: Field? = nil

    init(station: SurveyStation, onDelete: @escaping () -> Void, onChange: @escaping (SurveyField) -> Void) {
        self._station = Bindable(wrappedValue: station)
        self.onDelete = onDelete
        self.onChange = onChange
        // seed local text values
        _mdText = State(initialValue: Self.format2(station.md))
        _incText = State(initialValue: Self.format2(station.inc))
        _aziText = State(initialValue: Self.format2(station.azi))
        _tvdText = State(initialValue: Self.format2(station.tvd ?? 0))
        _vsText = State(initialValue: Self.format2(station.vs_m ?? 0))
        _nsText = State(initialValue: Self.format2(station.ns_m ?? 0))
        _ewText = State(initialValue: Self.format2(station.ew_m ?? 0))
        _dlsText = State(initialValue: Self.format2(station.dls_deg_per30m ?? 0))
        _subseaText = State(initialValue: Self.format2(station.subsea_m ?? 0))
        _buildText = State(initialValue: Self.format2(station.buildRate_deg_per30m ?? 0))
        _turnText = State(initialValue: Self.format2(station.turnRate_deg_per30m ?? 0))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("MD", text: $mdText)
                .frame(width: 90, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .md)
                .onSubmit { commitMD() }

            TextField("Incl", text: $incText)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .inc)
                .onSubmit { commitInc() }

            TextField("Azm", text: $aziText)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .azi)
                .onSubmit { commitAzi() }

            TextField("TVD", text: $tvdText)
                .frame(width: 90, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .tvd)
                .onSubmit { commitTVD() }

            TextField("VS", text: $vsText)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .vs)
                .onSubmit { commitVS() }

            TextField("NS", text: $nsText)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .ns)
                .onSubmit { commitNS() }

            TextField("EW", text: $ewText)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .ew)
                .onSubmit { commitEW() }

            TextField("DLS", text: $dlsText)
                .frame(width: 110, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .dls)
                .onSubmit { commitDLS() }

            TextField("Subsea", text: $subseaText)
                .frame(width: 90, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .subsea)
                .onSubmit { commitSubsea() }

            TextField("Build", text: $buildText)
                .frame(width: 120, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .build)
                .onSubmit { commitBuild() }

            TextField("Turn", text: $turnText)
                .frame(width: 120, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .turn)
                .onSubmit { commitTurn() }

            Spacer()
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .onChange(of: focusedField) { newValue, oldValue in
            // When focus moves away from a field, commit the previous field
            defer { lastFocused = newValue }
            switch lastFocused {
            case .md?: commitMD()
            case .inc?: commitInc()
            case .azi?: commitAzi()
            case .tvd?: commitTVD()
            case .vs?: commitVS()
            case .ns?: commitNS()
            case .ew?: commitEW()
            case .dls?: commitDLS()
            case .subsea?: commitSubsea()
            case .build?: commitBuild()
            case .turn?: commitTurn()
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
    private func commitVS() {
        if let v = Self.parse(vsText) { station.vs_m = v; vsText = Self.format2(v) } else { vsText = Self.format2(station.vs_m ?? 0) }
    }
    private func commitNS() {
        if let v = Self.parse(nsText) { station.ns_m = v; nsText = Self.format2(v) } else { nsText = Self.format2(station.ns_m ?? 0) }
    }
    private func commitEW() {
        if let v = Self.parse(ewText) { station.ew_m = v; ewText = Self.format2(v) } else { ewText = Self.format2(station.ew_m ?? 0) }
    }
    private func commitDLS() {
        if let v = Self.parse(dlsText) { station.dls_deg_per30m = v; dlsText = Self.format2(v) } else { dlsText = Self.format2(station.dls_deg_per30m ?? 0) }
    }
    private func commitSubsea() {
        if let v = Self.parse(subseaText) { station.subsea_m = v; subseaText = Self.format2(v) } else { subseaText = Self.format2(station.subsea_m ?? 0) }
    }
    private func commitBuild() {
        if let v = Self.parse(buildText) { station.buildRate_deg_per30m = v; buildText = Self.format2(v) } else { buildText = Self.format2(station.buildRate_deg_per30m ?? 0) }
    }
    private func commitTurn() {
        if let v = Self.parse(turnText) { station.turnRate_deg_per30m = v; turnText = Self.format2(v) } else { turnText = Self.format2(station.turnRate_deg_per30m ?? 0) }
    }

    private func syncFromModel() {
        mdText = Self.format2(station.md)
        incText = Self.format0(station.inc)
        aziText = Self.format0(station.azi)
        tvdText = Self.format2(station.tvd ?? 0)
        vsText = Self.format2(station.vs_m ?? 0)
        nsText = Self.format2(station.ns_m ?? 0)
        ewText = Self.format2(station.ew_m ?? 0)
        dlsText = Self.format2(station.dls_deg_per30m ?? 0)
        subseaText = Self.format2(station.subsea_m ?? 0)
        buildText = Self.format2(station.buildRate_deg_per30m ?? 0)
        turnText = Self.format2(station.turnRate_deg_per30m ?? 0)
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
private struct SurveyListPreview: View {
    let container: ModelContainer
    let project: ProjectState

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Use try! in preview-only code to avoid do/catch in the result builder
        self.container = try! ModelContainer(
            for: ProjectState.self,
                 SurveyStation.self,
            configurations: config
        )
        let ctx = container.mainContext
        let p = ProjectState()
        ctx.insert(p)
        let s1 = SurveyStation(md: 0, inc: 0, azi: 0, tvd: 0)
        let s2 = SurveyStation(md: 500, inc: 5, azi: 45, tvd: 498)
        let s3 = SurveyStation(md: 1000, inc: 10, azi: 90, tvd: 980)
        [s1, s2, s3].forEach { p.surveys?.append($0); ctx.insert($0) }
        try? ctx.save()
        self.project = p
    }

    var body: some View {
        NavigationStack { SurveyListView(project: project) }
            .modelContainer(container)
            .frame(width: 760, height: 520)
    }
}
#endif

#Preview("Surveys – Sample Data") {
    SurveyListPreview()
}

// MARK: - Pason Text Parser Utility
private enum PasonParser {
    static func looksLikePason(_ text: String) -> Bool {
        // Heuristic: has a header line with tab-separated column names including MD(m) and Inc(deg)
        return text.contains("MD(m)\tInc(deg)") || text.contains("MD (m)\tInc (deg)")
    }

    struct IndexMap { let md, inc, azm, tvd, vs, ns, ew, dls, subsea, build, turn: Int }

    static func indexMap(headers: [String]) -> IndexMap {
        func find(_ needle: String) -> Int { headers.firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(needle) == .orderedSame } ?? -1 }
        return IndexMap(
            md: find("MD(m)"),
            inc: find("Inc(deg)"),
            azm: find("Azm(deg)"),
            tvd: find("TVD(m)"),
            vs: find("VS(m)"),
            ns: find("NS(m)"),
            ew: find("EW(m)"),
            dls: find("DLS(deg/30m)"),
            subsea: find("Subsea(m)"),
            build: find("Build Rate(deg/30m)"),
            turn: find("Turn Rate(deg/30m)")
        )
    }
}
