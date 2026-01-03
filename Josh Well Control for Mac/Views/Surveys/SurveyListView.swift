import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Survey List / Editor
struct SurveyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Use @Query with filter for proper CloudKit sync
    @Query private var surveys: [SurveyStation]

    @State private var vm = ViewModel()

    init(project: ProjectState) {
        self._project = Bindable(wrappedValue: project)
        let projectID = project.persistentModelID
        _surveys = Query(
            filter: #Predicate<SurveyStation> { survey in
                survey.project?.persistentModelID == projectID
            },
            sort: [SortDescriptor(\.md)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $vm.selection) {
                Section {
                    ForEach(surveys) { s in
                        // Use lightweight display row for non-selected, editable for selected
                        if vm.selection?.id == s.id {
                            SurveyRowEditable(station: s, onDelete: { vm.delete(s, from: surveys) }) { field in
                                vm.onSurveyChange(field, surveys: surveys)
                            }
                            .tag(s)
                        } else {
                            SurveyRowDisplay(station: s, onDelete: { vm.delete(s, from: surveys) })
                                .tag(s)
                                .contentShape(Rectangle())
                        }
                    }
                    .onDelete { idx in
                        let items = idx.map { surveys[$0] }
                        items.forEach { vm.delete($0, from: surveys) }
                    }
                } header: { header }
            }
            .listStyle(.inset)
            .scrollIndicators(.hidden)
            footer
        }
        .onAppear { vm.attach(project: project, context: modelContext); vm.recomputeTVD(surveys: surveys) }
        .onChange(of: project) { _, newProject in
            vm.attach(project: newProject, context: modelContext)
            vm.recomputeTVD(surveys: surveys)
        }
        .onChange(of: surveys.count) { vm.recomputeTVD(surveys: surveys) }
        .fileImporter(isPresented: $vm.showingImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .utf8PlainText],
                      allowsMultipleSelection: false) { (result: Result<[URL], Error>) in
            vm.handleImport(result, existingSurveys: surveys)
        }
        .alert("Import Error",
               isPresented: Binding(get: { vm.importError != nil }, set: { if !$0 { vm.importError = nil } })) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "unknown error")
        }
        .toolbar { toolbar }
        #if os(macOS)
        .onDeleteCommand { if let sel = vm.selection { vm.delete(sel, from: surveys) } }
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
        VStack(alignment: .leading, spacing: 8) {
            // Survey calculation settings
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("VSD:")
                        .foregroundStyle(.secondary)
                    TextField("VSD", value: $project.vsdDirection_deg, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .monospacedDigit()
                    Text("°")
                        .foregroundStyle(.secondary)
                }
                .help("Vertical Section Direction - reference azimuth for VS calculation")

                if let well = project.well {
                    HStack(spacing: 4) {
                        Text("KB:")
                            .foregroundStyle(.secondary)
                        TextField("KB", value: Binding(
                            get: { well.kbElevation_m ?? 0 },
                            set: { well.kbElevation_m = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .monospacedDigit()
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
                    .help("Kelly Bushing elevation above sea level")
                }

                Button("Recalculate") {
                    vm.recalculateSurveys(surveys: surveys)
                }
                .buttonStyle(.bordered)
                .help("Recalculate all directional values using minimum curvature")

                Spacer()
            }
            .font(.caption)

            // Action buttons
            HStack {
                Button("Add Station") { vm.add(after: surveys.last) }
                Button("Clear Stations") { vm.clearStations(surveys) }
                Spacer()
                Button("Import Surveys…") { vm.showingImporter = true }
            }
        }
        .padding(.vertical, 8)
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Delete", role: .destructive) {
                if let sel = vm.selection { vm.delete(sel, from: surveys) }
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
        @ObservationIgnored private(set) var project: ProjectState?

        enum SurveyField { case md, inc, azi }

        // UI State
        var selection: SurveyStation? = nil
        var showingImporter: Bool = false
        var importError: String? = nil
        var listVersion: Int = 0

        // Attach once from the view
        func attach(project: ProjectState, context: ModelContext) {
            self.modelContext = context
            self.project = project
        }

        /// Recalculate all directional survey values using minimum curvature method
        func recalculateSurveys(surveys: [SurveyStation]) {
            guard let project else { return }

            // Get KB elevation from well if available
            let kbElevation = project.well?.kbElevation_m

            // Use project's VSD direction
            let vsdDirection = project.vsdDirection_deg

            // Run full minimum curvature calculation
            DirectionalSurveyService.recalculate(
                surveys: surveys,
                vsdDirection: vsdDirection,
                kbElevation: kbElevation
            )
        }

        func onSurveyChange(_ field: SurveyField, surveys: [SurveyStation]) {
            // Recalculate all derived values when primary inputs change
            recalculateSurveys(surveys: surveys)
        }

        /// Legacy function name for compatibility - now calls full recalculation
        func recomputeTVD(surveys: [SurveyStation]) {
            recalculateSurveys(surveys: surveys)
        }

        func clearStations(_ surveys: [SurveyStation]) {
            for s in surveys {
                modelContext.delete(s)
            }
        }

        func add(after lastSurvey: SurveyStation?) {
            guard let project else { return }
            let last = lastSurvey ?? SurveyStation(md: 0, inc: 0, azi: 0, tvd: nil)
            let s = SurveyStation(md: last.md + 30, inc: last.inc, azi: last.azi, tvd: last.tvd)
            // Set relationship for @Query to pick it up
            s.project = project
            modelContext.insert(s)
        }

        func delete(_ s: SurveyStation, from surveys: [SurveyStation]) {
            // Clear selection if deleting selected item
            if selection?.id == s.id {
                selection = nil
            }
            modelContext.delete(s)
        }

        func handleImport(_ result: Result<[URL], Error>, existingSurveys: [SurveyStation]) {
            guard project != nil else { return }
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
                    // Clear existing surveys by deleting them
                    for s in existingSurveys {
                        modelContext.delete(s)
                    }
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
                // Set relationship for @Query to pick it up
                s.project = project
                modelContext.insert(s)
                created.append(s)
            }
            listVersion &+= 1
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
                // Set relationship for @Query to pick it up
                s.project = project
                modelContext.insert(s)
                created.append(s)
            }
            listVersion &+= 1
            selection = created.last
        }
    }
}

// MARK: - Lightweight Display Row (for scrolling performance)
private struct SurveyRowDisplay: View {
    let station: SurveyStation
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(format2(station.md))
                .frame(width: 90, alignment: .leading)
                .monospacedDigit()
            Text(format0(station.inc))
                .frame(width: 80, alignment: .leading)
                .monospacedDigit()
            Text(format0(station.azi))
                .frame(width: 80, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.tvd ?? 0))
                .frame(width: 90, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.vs_m ?? 0))
                .frame(width: 80, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.ns_m ?? 0))
                .frame(width: 80, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.ew_m ?? 0))
                .frame(width: 80, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.dls_deg_per30m ?? 0))
                .frame(width: 110, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.subsea_m ?? 0))
                .frame(width: 90, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.buildRate_deg_per30m ?? 0))
                .frame(width: 120, alignment: .leading)
                .monospacedDigit()
            Text(format2(station.turnRate_deg_per30m ?? 0))
                .frame(width: 120, alignment: .leading)
                .monospacedDigit()
            Spacer()
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format2(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: - Editable Row (only shown for selected station)
private struct SurveyRowEditable: View {
    typealias SurveyField = SurveyListView.ViewModel.SurveyField
    @Bindable var station: SurveyStation
    var onDelete: () -> Void
    var onChange: (SurveyField) -> Void

    private enum Field: Hashable { case md, inc, azi, tvd, vs, ns, ew, dls, subsea, build, turn }
    @FocusState private var focusedField: Field?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("MD", value: $station.md, format: .number)
                .frame(width: 90, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .md)

            TextField("Incl", value: $station.inc, format: .number)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .inc)

            TextField("Azm", value: $station.azi, format: .number)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: .azi)

            TextField("TVD", value: $station.tvd, format: .number)
                .frame(width: 90, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("VS", value: $station.vs_m, format: .number)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("NS", value: $station.ns_m, format: .number)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("EW", value: $station.ew_m, format: .number)
                .frame(width: 80, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("DLS", value: $station.dls_deg_per30m, format: .number)
                .frame(width: 110, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("Subsea", value: $station.subsea_m, format: .number)
                .frame(width: 90, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("Build", value: $station.buildRate_deg_per30m, format: .number)
                .frame(width: 120, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            TextField("Turn", value: $station.turnRate_deg_per30m, format: .number)
                .frame(width: 120, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

            Spacer()
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .onChange(of: focusedField) { oldField, _ in
            // Trigger recalculation when focus leaves MD, Inc, or Azi fields
            switch oldField {
            case .md: onChange(.md)
            case .inc: onChange(.inc)
            case .azi: onChange(.azi)
            default: break
            }
        }
    }
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

#Preview("Surveys – Sample Data") {
    SurveyListPreview()
}
#endif

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
