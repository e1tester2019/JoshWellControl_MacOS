//  TripSimulationView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
// (assistant) Connected and ready – 2025-11-07
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

    @State private var viewmodel = ViewModel()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            headerInputs
            Divider()
            content
        }
        .padding(16)
        .onAppear { viewmodel.bootstrap(from: project) }
        .onChange(of: viewmodel.selectedIndex) { _, newVal in
            viewmodel.stepSlider = Double(newVal ?? 0)
        }
    }

    // MARK: - Sections
    private var headerInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                GroupBox("Bit / Range") {
                    HStack {
                        numberField("Start MD", value: $viewmodel.startBitMD_m)
                        numberField("End MD", value: $viewmodel.endMD_m)
                        numberField("Control TVD", value: $viewmodel.shoeTVD_m)
                        numberField("Step (m)", value: $viewmodel.step_m)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Fluids") {
                    HStack {
                        numberField("Base ρ (kg/m³)", value: $viewmodel.baseMudDensity_kgpm3)
                        numberField("Backfill ρ", value: $viewmodel.backfillDensity_kgpm3)
                        numberField("Target ESD@TD", value: $viewmodel.targetESDAtTD_kgpm3)
                    }
                }
            }

            HStack(spacing: 16) {
                GroupBox("Choke / Float") {
                    HStack {
                        numberField("Crack Float (kPa)", value: $viewmodel.crackFloat_kPa)
                        numberField("Initial SABP (kPa)", value: $viewmodel.initialSABP_kPa)
                        Toggle("Hold SABP open (0)", isOn: $viewmodel.holdSABPOpen)
                    }
                }

                GroupBox("View") {
                    Toggle("Composition colors", isOn: $viewmodel.colorByComposition)
                }

                if !viewmodel.steps.isEmpty {
                    GroupBox("Bit Depth (m)") {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { viewmodel.stepSlider },
                                    set: { newVal in
                                        viewmodel.stepSlider = newVal
                                        let idx = min(max(Int(round(newVal)), 0), max(viewmodel.steps.count - 1, 0))
                                        viewmodel.selectedIndex = idx
                                    }
                                ),
                                in: 0...Double(max(viewmodel.steps.count - 1, 0)), step: 1
                            )
                            Text(String(format: "%.2f m", viewmodel.steps[min(max(viewmodel.selectedIndex ?? 0, 0), max(viewmodel.steps.count - 1, 0))].bitMD_m))
                                .frame(width: 72, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .frame(width: 240)
                    }
                }

                Spacer()

                Toggle("Show details", isOn: $viewmodel.showDetails)
                    .toggleStyle(.switch)

                Button("Seed from MudPlacement & Run") { viewmodel.runSimulation(project: project) }
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
                        .frame(height: viewmodel.showDetails ? max(0, g.size.height * 0.5 - 4) : g.size.height)
                    if viewmodel.showDetails {
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

            // RIGHT COLUMN: Well image (own column) + ESD@control label
            VStack(alignment: .center, spacing: 4) {
                visualization
                    .frame(minWidth: 260, maxWidth: 360, maxHeight: .infinity)
                if !esdAtControlText.isEmpty {
                    Text(esdAtControlText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Selection helpers
    private func indexOf(_ row: TripStep) -> Int? {
        // Heuristic: match by MD & TVD (good enough for selection)
        viewmodel.steps.firstIndex { $0.bitMD_m == row.bitMD_m && $0.bitTVD_m == row.bitTVD_m }
    }

    private func selectableText(_ text: String, for row: TripStep, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .onTapGesture {
                if let i = indexOf(row) { viewmodel.selectedIndex = i }
            }
    }

    // MARK: - Steps Table
    private var stepsTable: some View {
        Table(viewmodel.steps) {
            TableColumn("Bit MD") { row in
                Text(format0(row.bitMD_m))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let i = indexOf(row) { viewmodel.selectedIndex = i } }
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
        .contextMenu { Button("Re-run") { viewmodel.runSimulation(project: project) } }
    }

    // MARK: - Visualization
    private var visualization: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                Group {
                    if let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) {
                        let s = viewmodel.steps[idx]
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

                            // Unified vertical scale by MD (surface at top, deeper down)
                            let maxPocketMD = pocket.map { $0.bottomMD }.max() ?? bitMD
                            let globalMaxMD = max(bitMD, maxPocketMD)
                            func yGlobal(_ md: Double) -> CGFloat {
                                guard globalMaxMD > 0 else { return 0 }
                                return CGFloat(md / globalMaxMD) * size.height
                            }

                            // Draw annulus (left & right) and string (center), only above bit
                            drawColumn(&ctx, rows: ann, in: annLeft,  isAnnulus: true,  bitMD: bitMD, yGlobal: yGlobal)
                            drawColumn(&ctx, rows: str, in: strRect,  isAnnulus: false, bitMD: bitMD, yGlobal: yGlobal)
                            drawColumn(&ctx, rows: ann, in: annRight, isAnnulus: true,  bitMD: bitMD, yGlobal: yGlobal)

                            // Pocket (below bit): draw FULL WIDTH so it covers both tracks
                            if !pocket.isEmpty {
                                for r in pocket {
                                    let yTop = yGlobal(r.topMD)
                                    let yBot = yGlobal(r.bottomMD)
                                    let yMin = min(yTop, yBot)
                                    let col = fillColor(rho: r.rho_kgpm3, explicit: r.color, mdMid: 0.5 * (r.topMD + r.bottomMD), isAnnulus: false)
                                    // Snap + tiny overlap to hide hairlines
                                    let top = floor(yMin)
                                    let bottom = ceil(max(yTop, yBot))
                                    var sub = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
                                    sub = sub.insetBy(dx: 0, dy: -0.25)
                                    ctx.fill(Path(sub), with: .color(col))
                                }
                            }

                            // Headers
                            ctx.draw(Text("Annulus"), at: CGPoint(x: annLeft.midX,  y: 12))
                            ctx.draw(Text("String"),  at: CGPoint(x: strRect.midX,  y: 12))
                            ctx.draw(Text("Annulus"), at: CGPoint(x: annRight.midX, y: 12))

                            // Bit marker
                            let yBit = yGlobal(bitMD)
                            ctx.fill(Path(CGRect(x: 0, y: yBit - 0.5, width: size.width, height: 1)), with: .color(.accentColor.opacity(0.9)))

                            // Depth ticks (MD right, TVD left)
                            let tickCount = 6
                            for i in 0...tickCount {
                                let md = Double(i) / Double(tickCount) * globalMaxMD
                                let yy = yGlobal(md)
                                let tvd = project.tvd(of: md)
                                ctx.fill(Path(CGRect(x: size.width - 10, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                                ctx.draw(Text(String(format: "%.0f", md)), at: CGPoint(x: size.width - 12, y: yy - 6), anchor: .trailing)
                                ctx.fill(Path(CGRect(x: 0, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                                ctx.draw(Text(String(format: "%.0f", tvd)), at: CGPoint(x: 12, y: yy - 6), anchor: .leading)
                            }
                        }
                    } else {
                        ContentUnavailableView("Select a step", systemImage: "cursorarrow.click", description: Text("Choose a row on the left to see the well snapshot."))
                    }
                }
            }
            .frame(minHeight: 240)
        }
    }
    // MARK: - ESD @ Control TVD (label)
    private var esdAtControlText: String {
        guard let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) else { return "" }
        let s = viewmodel.steps[idx]
        let controlTVD = max(0.0, viewmodel.shoeTVD_m)
        let bitTVD = s.bitTVD_m
        var pressure_kPa: Double = s.SABP_kPa

        if controlTVD <= bitTVD + 1e-9 {
            var remaining = controlTVD
            for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
                let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
                if seg > 1e-9 {
                    let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                    pressure_kPa += r.deltaHydroStatic_kPa * frac
                    remaining -= seg
                    if remaining <= 1e-9 { break }
                }
            }
        } else {
            var remainingA = bitTVD
            for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
                let seg = min(remainingA, max(0.0, min(r.bottomTVD, bitTVD) - r.topTVD))
                if seg > 1e-9 {
                    let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                    pressure_kPa += r.deltaHydroStatic_kPa * frac
                    remainingA -= seg
                    if remainingA <= 1e-9 { break }
                }
            }
            var remainingP = controlTVD - bitTVD
            for r in s.layersPocket where r.bottomTVD > r.topTVD {
                let top = max(r.topTVD, bitTVD)
                let bot = min(r.bottomTVD, controlTVD)
                let seg = max(0.0, bot - top)
                if seg > 1e-9 {
                    let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                    pressure_kPa += r.deltaHydroStatic_kPa * frac
                    remainingP -= seg
                    if remainingP <= 1e-9 { break }
                }
            }
        }

        let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
        return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }

    // MARK: - Drawing helpers
    private func hexColor(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard (h.count == 6 || h.count == 8), let val = UInt64(h, radix: 16) else { return nil }
        let a, r, g, b: Double
        if h.count == 8 {
            a = Double((val >> 24) & 0xFF) / 255.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    private func compositionColor(at md: Double, isAnnulus: Bool) -> Color? {
        let src = isAnnulus ? project.finalAnnulusLayersSorted : project.finalStringLayersSorted
        guard let lay = src.first(where: { md >= $0.topMD_m && md <= $0.bottomMD_m }) else { return nil }
        // Support either a stored hex String or a SwiftUI Color in the model
        let anyVal: Any? = lay.color
        if let hex = anyVal as? String, let c = hexColor(hex) { return c }
        if let c = anyVal as? Color { return c }
        return nil
    }

    private func fillColor(rho: Double, explicit: NumericalTripModel.ColorRGBA?, mdMid: Double, isAnnulus: Bool) -> Color {
        if viewmodel.colorByComposition {
            if let c = explicit { return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a) }
            if let c = compositionColor(at: mdMid, isAnnulus: isAnnulus) { return c }
        }
        let t = min(max((rho - 800) / 1200, 0), 1)
        return Color(white: 0.3 + 0.6 * t)
    }

    private func drawColumn(_ ctx: inout GraphicsContext,
                            rows: [LayerRow],
                            in rect: CGRect,
                            isAnnulus: Bool,
                            bitMD: Double,
                            yGlobal: (Double)->CGFloat) {
        for r in rows where r.bottomMD <= bitMD {
            let yTop = yGlobal(r.topMD)
            let yBot = yGlobal(r.bottomMD)
            let yMin = min(yTop, yBot)
            let h = max(1, abs(yBot - yTop))
            let sub = CGRect(x: rect.minX, y: yMin, width: rect.width, height: h)
            let mdMid = 0.5 * (r.topMD + r.bottomMD)
            let col = fillColor(rho: r.rho_kgpm3, explicit: r.color, mdMid: mdMid, isAnnulus: isAnnulus)
            ctx.fill(Path(sub), with: .color(col))
        }
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.8)), lineWidth: 1)
    }

    // MARK: - Detail (Accordion)
    private var detailAccordion: some View {
        GroupBox("Step details") {
            if let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) {
                let s = viewmodel.steps[idx]
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup("Summary") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            gridRow("Bit MD", format0(s.bitMD_m))
                            gridRow("Bit TVD", format0(s.bitTVD_m))
                            gridRow("SABP (kPa)", format0(s.SABP_kPa))
                            gridRow("SABP Dynamic (kPa)", format0(s.SABP_Dynamic_kPa))
                            gridRow("Target ESD@TD (kg/m³)", format0(viewmodel.targetESDAtTD_kgpm3))
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

extension TripSimulationView {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 5983.28
    var endMD_m: Double = 0
    var shoeTVD_m: Double = 2910
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1260
    var backfillDensity_kgpm3: Double = 1200
    var targetESDAtTD_kgpm3: Double = 1320
    var crackFloat_kPa: Double = 2100
    var initialSABP_kPa: Double = 0
    var holdSABPOpen: Bool = false

    // View options
    var colorByComposition: Bool = false
    var showDetails: Bool = false

    // Results / selection
    var steps: [TripStep] = []
    var selectedIndex: Int? = nil
    var stepSlider: Double = 0

    func bootstrap(from project: ProjectState) {
      if let maxMD = project.finalLayers.map({ $0.bottomMD_m }).max() {
        startBitMD_m = maxMD
        endMD_m = 0
      }
      let base = project.finalLayers.first?.density_kgm3 ?? baseMudDensity_kgpm3
      baseMudDensity_kgpm3 = base
      backfillDensity_kgpm3 = base
      targetESDAtTD_kgpm3 = base
    }

    func runSimulation(project: ProjectState) {
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in project.tvd(of: md) }
      )
      let input = NumericalTripModel.TripInput(
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
      let model = NumericalTripModel()
      self.steps = model.run(input, geom: geom, project: project)
      self.selectedIndex = steps.isEmpty ? nil : 0
      self.stepSlider = 0
    }

    func esdAtControlText(project: ProjectState) -> String {
      guard let idx = selectedIndex, steps.indices.contains(idx) else { return "" }
      let s = steps[idx]
      let controlTVD = max(0.0, shoeTVD_m)
      let bitTVD = s.bitTVD_m
      var pressure_kPa: Double = s.SABP_kPa

      if controlTVD <= bitTVD + 1e-9 {
        var remaining = controlTVD
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remaining -= seg
            if remaining <= 1e-9 { break }
          }
        }
      } else {
        var remainingA = bitTVD
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remainingA, max(0.0, min(r.bottomTVD, bitTVD) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingA -= seg
            if remainingA <= 1e-9 { break }
          }
        }
        var remainingP = controlTVD - bitTVD
        for r in s.layersPocket where r.bottomTVD > r.topTVD {
          let top = max(r.topTVD, bitTVD)
          let bot = min(r.bottomTVD, controlTVD)
          let seg = max(0.0, bot - top)
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingP -= seg
            if remainingP <= 1e-9 { break }
          }
        }
      }

      let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
      return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }
  }
}


#if DEBUG
private struct TripSimulationPreview: View {
  let container: ModelContainer
  let project: ProjectState

  init() {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    self.container = try! ModelContainer(
      for: ProjectState.self,
           DrillStringSection.self,
           AnnulusSection.self,
           FinalFluidLayer.self,
      configurations: config
    )
    let ctx = container.mainContext
    let p = ProjectState()
    ctx.insert(p)
    // Seed some layers so the visualization has data
    let a1 = FinalFluidLayer(project: p, name: "Annulus Mud", placement: .annulus, topMD_m: 0, bottomMD_m: 3000, density_kgm3: 1260, color: .yellow)
    let s1 = FinalFluidLayer(project: p, name: "String Mud", placement: .string, topMD_m: 0, bottomMD_m: 2000, density_kgm3: 1260, color: .yellow)
    ctx.insert(a1); ctx.insert(s1)
    try? ctx.save()
    self.project = p
  }

  var body: some View {
    NavigationStack { TripSimulationView(project: project) }
      .modelContainer(container)
      .frame(width: 1200, height: 800)
  }
}

#Preview("Trip Simulation – Sample Data") {
  TripSimulationPreview()
}
#endif
