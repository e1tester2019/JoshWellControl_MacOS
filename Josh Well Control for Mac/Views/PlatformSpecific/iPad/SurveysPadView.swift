import SwiftUI
import SwiftData

#if os(iOS)
/// An iPad-optimized Surveys view that adapts between portrait and landscape.
/// - Landscape: Two-pane layout (list of surveys on the left, details/plot on the right)
/// - Portrait: Stacked layout with the list first, then details below
struct SurveysPadView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @Query(sort: [SortDescriptor(\SurveyStation.md)]) private var queriedSurveys: [SurveyStation]

    // Selection for the list
    @State private var selectedSurveyID: PersistentIdentifier? = nil

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            Group {
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
        }
        .navigationTitle("Surveys")
    }

    // MARK: - Landscape: Split layout
    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            surveyList
                .frame(width: 360)
                .background(.thinMaterial)
            Divider()
            detailsPane
        }
    }

    // MARK: - Portrait: Stacked layout
    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                surveyList
                detailsPane
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Components
    private var surveyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet")
                Text("Survey Stations").font(.headline)
                Spacer()
                Button(action: addSurvey) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if queriedSurveys.isEmpty {
                Text("No surveys yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                List(selection: $selectedSurveyID) {
                    ForEach(queriedSurveys, id: \.id) { s in
                        HStack(spacing: 8) {
                            Text("MD: \(fmt(s.md, 1)) m")
                                .font(.subheadline)
                                .monospacedDigit()
                            Spacer()
                            Text("DLS: \(fmt(s.dls_deg_per30m ?? 0, 1)) °/30m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("TVD: \(fmt(s.tvd ?? 0, 1)) m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .tag(s.persistentModelID as PersistentIdentifier?)
                        .onTapGesture { selectedSurveyID = s.persistentModelID }
                    }
                    .onDelete(perform: deleteSurveys)
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }

    private var detailsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "ruler")
                Text("Details").font(.headline)
                Spacer()
            }

            if let sel = selectedSurvey, let index = queriedSurveys.firstIndex(where: { $0.persistentModelID == sel.persistentModelID }) {
                SurveyEditorRow(station: sel)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        LabeledContent("TVD (m)") { Text("\(fmt(sel.tvd ?? 0, 1))").monospacedDigit() }
                        LabeledContent("VS (m)") { Text("\(fmt(0, 1))").monospacedDigit() }
                        LabeledContent("NS (m)") { Text("\(fmt(0, 1))").monospacedDigit() }
                        LabeledContent("EW (m)") { Text("\(fmt(0, 1))").monospacedDigit() }
                        LabeledContent("DLS (°/30m)") { Text("\(fmt(0, 2))").monospacedDigit() }
                        LabeledContent("Subsea (m)") { Text("\(fmt( (sel.tvd ?? 0), 1))").monospacedDigit() }
                        LabeledContent("Build (°/30m)") { Text("\(fmt(0, 2))").monospacedDigit() }
                        LabeledContent("Turn (°/30m)") { Text("\(fmt(0, 2))").monospacedDigit() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Divider()
                SurveyMiniPlot(surveys: queriedSurveys, highlightedIndex: index)
                    .frame(minHeight: 220)
            } else {
                Text("Select a survey to edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
        .padding(.leading, 12)
    }

    // MARK: - Helpers
    private var selectedSurvey: SurveyStation? {
        guard let id = selectedSurveyID else { return nil }
        return queriedSurveys.first(where: { $0.persistentModelID == id })
    }

    private func addSurvey() {
        let nextMD = (queriedSurveys.last?.md ?? 0) + 30
        let nextTVD = (queriedSurveys.last?.tvd ?? 0) + 30
        let s = SurveyStation(md: nextMD, inc: 0, azi: 0, tvd: nextTVD)
        modelContext.insert(s)
        selectedSurveyID = s.persistentModelID
    }

    private func deleteSurveys(at offsets: IndexSet) {
        let items = offsets.map { queriedSurveys[$0] }
        for s in items {
            modelContext.delete(s)
        }
        // After deletion, the query will refresh; select the first remaining item by md
        if let first = queriedSurveys.first {
            selectedSurveyID = first.persistentModelID
        } else {
            selectedSurveyID = nil
        }
    }

    private func fmt(_ v: Double, _ p: Int = 1) -> String { String(format: "%0.*f", p, v) }
}

// MARK: - Editor Row
private struct SurveyEditorRow: View {
    @Bindable var station: SurveyStation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MD (m)").font(.caption).foregroundStyle(.secondary)
                    TextField("MD (m)", value: $station.md, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inc (°)").font(.caption).foregroundStyle(.secondary)
                    TextField("Inc (°)", value: $station.inc, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Azi (°)").font(.caption).foregroundStyle(.secondary)
                    TextField("Azi (°)", value: $station.azi, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                Spacer()
            }
            .font(.subheadline)
        }
    }
}

// MARK: - Mini Plot
/// A minimal, inline plot for MD vs TVD to provide orientation.
private struct SurveyMiniPlot: View {
    let surveys: [SurveyStation]
    let highlightedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 16
            let rect = proxy.frame(in: .local).insetBy(dx: inset, dy: inset)
            let mds: [Double] = surveys.map { $0.md }
            let tvds: [Double] = surveys.map { ($0.tvd ?? 0.0) as Double }
            let mdMin: Double = mds.min() ?? 0.0
            let mdMax: Double = mds.max() ?? 1.0
            let tvdMin: Double = tvds.min() ?? 0.0
            let tvdMax: Double = tvds.max() ?? 1.0
            let mdRange: Double = max(mdMax - mdMin, 1e-6)
            let tvdRange: Double = max(tvdMax - tvdMin, 1e-6)

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06))
                RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2))

                // Path for MD vs TVD
                Path { path in
                    for (i, s) in surveys.enumerated() {
                        let x = rect.minX + CGFloat((s.md - mdMin) / mdRange) * rect.width
                        let y = rect.minY + CGFloat(((s.tvd ?? 0) - tvdMin) / tvdRange) * rect.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                // Highlighted point
                if let idx = highlightedIndex, surveys.indices.contains(idx) {
                    let s = surveys[idx]
                    let x = rect.minX + CGFloat((s.md - mdMin) / mdRange) * rect.width
                    let y = rect.minY + CGFloat(((s.tvd ?? 0) - tvdMin) / tvdRange) * rect.height
                    Circle().fill(Color.red).frame(width: 8, height: 8).position(x: x, y: y)
                }

                // Midpoint grid lines
                Path { p in
                    // Vertical mid grid (MD mid)
                    let midX = rect.minX + rect.width * 0.5
                    p.move(to: CGPoint(x: midX, y: rect.minY))
                    p.addLine(to: CGPoint(x: midX, y: rect.maxY))
                    // Horizontal mid grid (TVD mid)
                    let midY = rect.minY + rect.height * 0.5
                    p.move(to: CGPoint(x: rect.minX, y: midY))
                    p.addLine(to: CGPoint(x: rect.maxX, y: midY))
                }
                .stroke(Color.gray.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Axis tick labels and titles
                ZStack {
                    // X-axis labels (MD)
                    Text(String(format: "%.0f", mdMin))
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: rect.minX, y: rect.maxY + 10)
                    Text(String(format: "%.0f", (mdMin + mdMax) / 2))
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: rect.midX, y: rect.maxY + 10)
                    Text(String(format: "%.0f", mdMax))
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: rect.maxX, y: rect.maxY + 10)

                    // X-axis title
                    Text("MD (m)")
                        .font(.caption2).bold().foregroundStyle(.secondary)
                        .position(x: rect.midX, y: rect.maxY + 24)

                    // Y-axis labels (TVD)
                    Text(String(format: "%.0f", tvdMax))
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: rect.minX - 14, y: rect.minY)
                    Text(String(format: "%.0f", (tvdMin + tvdMax) / 2))
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: rect.minX - 14, y: rect.midY)
                    Text(String(format: "%.0f", tvdMin))
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: rect.minX - 14, y: rect.maxY)

                    // Y-axis title (vertical)
                    Text("TVD (m)")
                        .font(.caption2).bold().foregroundStyle(.secondary)
                        .rotationEffect(.degrees(-90))
                        .position(x: rect.minX - 30, y: rect.midY)
                }
            }
        }
    }
}
#endif

