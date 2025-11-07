//  TripSimulationView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import SwiftUI
import SwiftData

typealias TripStep = NumericalTripModel.TripStep
typealias LayerRow = NumericalTripModel.LayerRow

struct KVRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

/// A compact SwiftUI front‑end over the NumericalTripModel.
/// Shows inputs, a steps table, an interactive detail (accordion), and a simple 2‑column mud visualization.
struct TripSimulationView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext

    // You typically have a selected project bound in higher views. If not, you can inject a specific instance here.
    @Bindable var project: ProjectState

    // MARK: - Inputs
    @State private var startBitMD_m: Double = 5983.28
    @State private var endMD_m: Double = 0
    @State private var shoeTVD_m: Double = 2910
    @State private var step_m: Double = 100
    @State private var baseMudDensity_kgpm3: Double = 1260
    @State private var backfillDensity_kgpm3: Double = 1200
    @State private var targetESDAtTD_kgpm3: Double = 1320
    @State private var crackFloat_kPa: Double = 2100
    @State private var initialSABP_kPa: Double = 0
    @State private var holdSABPOpen: Bool = false

    // Visualization options
    @State private var colorByComposition: Bool = false

    // Show/hide details pane
    @State private var showDetails: Bool = false

    // MARK: - Results
    @State private var steps: [TripStep] = []
    @State private var selectedIndex: Int? = nil

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            headerInputs
            Divider()
            content
        }
        .padding(16)
        .onAppear(perform: bootstrapFromProject)
    }

    // MARK: - Sections
    private var headerInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                GroupBox("Bit / Range") {
                    HStack {
                        numberField("Start MD", value: $startBitMD_m)
                        numberField("End MD", value: $endMD_m)
                        numberField("Shoe TVD", value: $shoeTVD_m)
                        numberField("Step (m)", value: $step_m)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Fluids") {
                    HStack {
                        numberField("Base ρ (kg/m³)", value: $baseMudDensity_kgpm3)
                        numberField("Backfill ρ", value: $backfillDensity_kgpm3)
                        numberField("Target ESD@TD", value: $targetESDAtTD_kgpm3)
                    }
                }
            }

            HStack(spacing: 16) {
                GroupBox("Choke / Float") {
                    HStack {
                        numberField("Crack Float (kPa)", value: $crackFloat_kPa)
                        numberField("Initial SABP (kPa)", value: $initialSABP_kPa)
                        Toggle("Hold SABP open (0)", isOn: $holdSABPOpen)
                    }
                }

                GroupBox("View") {
                    Toggle("Composition colors", isOn: $colorByComposition)
                }

                Spacer()

                Toggle("Show details", isOn: $showDetails)
                    .toggleStyle(.switch)

                Button("Seed from MudPlacement & Run", action: runSimulation)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            // LEFT COLUMN: Steps (top) + Details (bottom when shown)
            GeometryReader { g in
                VStack(spacing: 8) {
                    stepsTable
                        .frame(height: showDetails ? max(0, g.size.height * 0.5 - 4) : g.size.height)
                    if showDetails {
                        ScrollView {
                            detailAccordion
                        }
                        .frame(height: max(0, g.size.height * 0.5 - 4))
                    } else {
                        // Reserve 0 height when hidden
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(minWidth: 720, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // RIGHT COLUMN: Well image (own column)
            visualization
                .frame(minWidth: 260, maxWidth: 360, maxHeight: .infinity)
        }
    }

    // MARK: - Selection helpers
    private func indexOf(_ row: TripStep) -> Int? {
        // Heuristic: match by MD & TVD (good enough for selection)
        steps.firstIndex { $0.bitMD_m == row.bitMD_m && $0.bitTVD_m == row.bitTVD_m }
    }

    private func selectableText(_ text: String, for row: TripStep, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .onTapGesture {
                if let i = indexOf(row) { selectedIndex = i }
            }
    }

    // MARK: - Steps Table
    private var stepsTable: some View {
        Table(steps) {
            TableColumn("Bit MD") { row in
                Text(format0(row.bitMD_m))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let i = indexOf(row) { selectedIndex = i } }
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn("Bit TVD") { row in
                selectableText(format0(row.bitTVD_m), for: row)
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn("SABP kPa") { row in
                selectableText(format0(row.SABP_kPa), for: row)
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn("ESD@TD kg/m³") { row in
                selectableText(format0(row.ESDatTD_kgpm3), for: row)
            }
            .width(min: 110, ideal: 140, max: 180)

            TableColumn("Swab Drop kPa") { row in
                selectableText(format0(row.swabDropToBit_kPa), for: row)
            }
            .width(min: 120, ideal: 150, max: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu { Button("Re-run", action: runSimulation) }
    }

    // MARK: - Visualization
    private var visualization: some View {
        GroupBox("Well snapshot at selected step") {
            GeometryReader { geo in
                if let idx = selectedIndex, steps.indices.contains(idx) {
                    let s = steps[idx]
                    let ann = s.layersAnnulus
                    let str = s.layersString
                    let pocket = s.layersPocket
                    let bitMD = s.bitMD_m

                    Canvas { ctx, size in
                        // Three-column layout: Annulus | String | Annulus
                        let gap: CGFloat = 8
                        let colW = (size.width - 2*gap) / 3
                        let annLeft  = CGRect(x: 0, y: 0, width: colW, height: size.height)
                        let strRect  = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
                        let annRight = CGRect(x: 2*(colW + gap), y: 0, width: colW, height: size.height)

                        // Unified vertical scale by MD (surface→bottom, deepest MD→top) FLIPPED
                        let maxPocketMD = pocket.map { $0.bottomMD }.max() ?? bitMD
                        let globalMaxMD = max(bitMD, maxPocketMD)
                        func yGlobal(_ md: Double) -> CGFloat {
                            guard globalMaxMD > 0 else { return 0 }
                            // Surface (0) at TOP; deeper MD increases DOWN the screen
                            return CGFloat(md / globalMaxMD) * size.height
                        }

                        func fill(for rho: Double, color: NumericalTripModel.ColorRGBA?) -> Color {
                            if colorByComposition, let c = color { return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a) }
                            let t = min(max((rho - 800) / 1200, 0), 1)
                            return Color(white: 0.3 + 0.6 * t)
                        }

                        func drawColumn(_ rows: [LayerRow], in rect: CGRect, filter: (LayerRow)->Bool) {
                            for r in rows where filter(r) {
                                let yTop = yGlobal(r.topMD)
                                let yBot = yGlobal(r.bottomMD)
                                let yMin = min(yTop, yBot)
                                let h = max(1, abs(yBot - yTop))
                                let sub = CGRect(x: rect.minX, y: yMin, width: rect.width, height: h)
                                let col = fill(for: r.rho_kgpm3, color: r.color)
                                ctx.fill(Path(sub), with: .color(col))
                            }
                            // Outline to visually separate columns
                            ctx.stroke(Path(rect), with: .color(.black.opacity(0.8)), lineWidth: 1)
                        }

                        // Draw annulus (left & right) and string (center), only above bit
                        drawColumn(ann, in: annLeft,  filter: { $0.bottomMD <= bitMD })
                        drawColumn(str, in: strRect,  filter: { $0.bottomMD <= bitMD })
                        drawColumn(ann, in: annRight, filter: { $0.bottomMD <= bitMD })

                        // Pocket (below bit): show across all columns with slight transparency
                        if !pocket.isEmpty {
                            for r in pocket {
                                let yTop = yGlobal(r.topMD)
                                let yBot = yGlobal(r.bottomMD)
                                let yMin = min(yTop, yBot)
                                let h = max(1, abs(yBot - yTop))
                                let col = fill(for: r.rho_kgpm3, color: r.color).opacity(0.45)
                                let subL = CGRect(x: annLeft.minX,  y: yMin, width: annLeft.width,  height: h)
                                let subS = CGRect(x: strRect.minX,  y: yMin, width: strRect.width,  height: h)
                                let subR = CGRect(x: annRight.minX, y: yMin, width: annRight.width, height: h)
                                ctx.fill(Path(subL), with: .color(col))
                                ctx.fill(Path(subS), with: .color(col))
                                ctx.fill(Path(subR), with: .color(col))
                            }
                        }

                        // Headers
                        ctx.draw(Text("Annulus"), at: CGPoint(x: annLeft.midX,  y: 12))
                        ctx.draw(Text("String"),  at: CGPoint(x: strRect.midX,  y: 12))
                        ctx.draw(Text("Annulus"), at: CGPoint(x: annRight.midX, y: 12))

                        // Bit marker (now yGlobal maps 0 at top, increasing downward)
                        let yBit = yGlobal(bitMD)
                        ctx.fill(Path(CGRect(x: 0, y: yBit - 0.5, width: size.width, height: 1)), with: .color(.accentColor.opacity(0.9)))

                        // Depth ticks: MD (right) and TVD (left)
                        let tickCount = 6
                        for i in 0...tickCount {
                            let md = Double(i) / Double(tickCount) * globalMaxMD
                            let yy = yGlobal(md)
                            let tvd = project.tvd(of: md)
                            // Right MD ticks
                            ctx.fill(Path(CGRect(x: size.width - 10, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                            ctx.draw(Text(String(format: "%.0f", md)), at: CGPoint(x: size.width - 12, y: yy - 6), anchor: .trailing)
                            // Left TVD ticks
                            ctx.fill(Path(CGRect(x: 0, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                            ctx.draw(Text(String(format: "%.0f", tvd)), at: CGPoint(x: 12, y: yy - 6), anchor: .leading)
                        }
                    }
                } else {
                    ContentUnavailableView("Select a step", systemImage: "cursorarrow.click", description: Text("Choose a row on the left to see the well snapshot."))
                }
            }
            .frame(minHeight: 240)
        }
    }

    // MARK: - Detail (Accordion)
    private var detailAccordion: some View {
        GroupBox("Step details") {
            if let idx = selectedIndex, steps.indices.contains(idx) {
                let s = steps[idx]
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup("Summary") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            gridRow("Bit MD", format0(s.bitMD_m))
                            gridRow("Bit TVD", format0(s.bitTVD_m))
                            gridRow("SABP (kPa)", format0(s.SABP_kPa))
                            gridRow("SABP Dynamic (kPa)", format0(s.SABP_Dynamic_kPa))
                            gridRow("Target ESD@TD (kg/m³)", format0(targetESDAtTD_kgpm3))
                            gridRow("ESD@TD (kg/m³)", format0(s.ESDatTD_kgpm3))
                            gridRow("Backfill remaining (m³)", format3(s.backfillRemaining_m3))
                        }
                        .padding(.top, 4)
                    }
                    .disclosureGroupStyle(.automatic)

                    DisclosureGroup("Annulus stack (above bit)") {
                        layerTable(s.layersAnnulus)
                    }
                    DisclosureGroup("String stack (above bit)") {
                        layerTable(s.layersString)
                    }
                    DisclosureGroup("Pocket (below bit)") {
                        layerTable(s.layersPocket)
                    }
                    DisclosureGroup("Debug / KVs") {
                        Text("No debug rows available from the model.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("No step selected.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions
    private func bootstrapFromProject() {
        // Reasonable defaults derived from the project, if available
        if let maxMD = (project.finalLayers.map { $0.bottomMD_m }.max()) {
            startBitMD_m = maxMD
            endMD_m = 0
        }
        baseMudDensity_kgpm3 = project.finalLayers.first?.density_kgm3 ?? baseMudDensity_kgpm3
        backfillDensity_kgpm3 = baseMudDensity_kgpm3
        targetESDAtTD_kgpm3 = baseMudDensity_kgpm3
    }

    private func runSimulation() {
        // Geometry service seeded from project with TVD interpolation if your extension exists
        let geom = ProjectGeometryService(
            project: project,
            currentStringBottomMD: startBitMD_m,
            tvdMapper: { md in project.tvd(of: md) }
        )

        var input = NumericalTripModel.TripInput(
            tvdOfMd: { md in project.tvd(of: md) },
            shoeTVD_m: shoeTVD_m,
            startBitMD_m: startBitMD_m,
            endMD_m: endMD_m,
            crackFloat_kPa: crackFloat_kPa,
            step_m: step_m,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            backfillDensity_kgpm3: backfillDensity_kgpm3,
            targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
            initialSABP_kPa: initialSABP_kPa,
            holdSABPOpen: holdSABPOpen
        )

        // Seed layers from persisted final placement
        let ann = project.finalAnnulusLayersSorted
        let str = project.finalStringLayersSorted

        // Run
        let model = NumericalTripModel()
        self.steps = model.run(input, geom: geom, project: project)
        self.selectedIndex = steps.isEmpty ? nil : 0
    }

    // MARK: - Subviews / helpers
    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 130, alignment: .trailing)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private func gridRow(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v) }
    }

    private func layerTable(_ rows: [LayerRow]) -> some View {
        Table(rows) {
            TableColumn("Top MD") { r in Text(format1(r.topMD)) }
            TableColumn("Bot MD") { r in Text(format1(r.bottomMD)) }
            TableColumn("Top TVD") { r in Text(format1(r.topTVD)) }
            TableColumn("Bot TVD") { r in Text(format1(r.bottomTVD)) }
            TableColumn("ρ kg/m³") { r in Text(format0(r.rho_kgpm3)) }
            TableColumn("ΔP kPa") { r in Text(format0(r.deltaHydroStatic_kPa)) }
            TableColumn("Vol m³") { r in Text(format3(r.volume_m3)) }
        }
        .frame(minHeight: 140)
    }

    private func debugTable(_ kvs: [KVRow]) -> some View {
        Table(kvs) {
            TableColumn("Key") { kv in Text(kv.key) }
            TableColumn("Value") { kv in Text(kv.value) }
        }
        .frame(minHeight: 120)
    }

    // MARK: - Formatters
    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func format3(_ v: Double) -> String { String(format: "%.3f", v) }
}

// MARK: - Preview
#Preview("TripSimulationView") {
    Text("Provide a ProjectState from the app to preview TripSimulationView.")
        .frame(width: 1200, height: 800)
}
