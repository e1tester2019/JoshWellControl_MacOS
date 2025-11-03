//  MudPlacementView.swift
//  Josh Well Control for Mac
//
//  Interval-based mud placement calculator. Computes annular volume (outside),
//  string capacity (inside), string displacement, and open-hole capacity between two depths.
//  Also supports manually placing final layers (Annulus / String / Both) from editable steps.

import SwiftUI
import SwiftData

// MARK: - Step & Layer Models
private enum Placement: String, CaseIterable, Identifiable {
    case annulus = "Annulus"
    case string  = "String"
    case both    = "Both"
    var id: String { rawValue }
}

private struct MudStep: Identifiable, Equatable {
    let id: UUID = UUID()
    var name: String
    var top_m: Double
    var bottom_m: Double
    var density_kgm3: Double
    var color: Color
    var placement: Placement
}

private enum Domain { case annulus, string }

private struct FinalLayer: Identifiable {
    let id = UUID()
    let domain: Domain
    let top: Double
    let bottom: Double
    let name: String
    let color: Color
    let density: Double
}

// MARK: - View
struct MudPlacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Interval inputs (meters). Used for the quick calculator row.
    @State private var top_m: Double = 3150
    @State private var bottom_m: Double = 6000

    // Steps (editable plan). These are treated as final layers when you press "Place Layers".
    @State private var steps: [MudStep] = [
        MudStep(name: "Annulus Kill",  top_m: 687,  bottom_m: 1010, density_kgm3: 1800, color: .blue,   placement: .annulus),
        MudStep(name: "Active Mud",    top_m: 1010, bottom_m: 2701, density_kgm3: 1250, color: .yellow, placement: .annulus),
        MudStep(name: "Lube Blend",    top_m: 2701, bottom_m: 6000, density_kgm3: 1200, color: .orange, placement: .both),
        MudStep(name: "Active Mud",    top_m: 2040, bottom_m: 2701, density_kgm3: 1250, color: .yellow, placement: .string),
        MudStep(name: "Balance Slug",  top_m: 1705, bottom_m: 2040, density_kgm3: 1800, color: .blue,   placement: .string),
        MudStep(name: "Active Mud",    top_m: 596,  bottom_m: 1705, density_kgm3: 1250, color: .yellow, placement: .string),
        MudStep(name: "Dry Pipe Slug", top_m: 220,  bottom_m: 596,  density_kgm3: 2100, color: .brown,  placement: .string),
        MudStep(name: "Air",           top_m: 0,    bottom_m: 221,  density_kgm3: 1.2,  color: .cyan,   placement: .string)
    ]

    // Placed (final) layers for display
    @State private var finalAnnulus: [FinalLayer] = []
    @State private var finalString:  [FinalLayer] = []

    // Base fluids for initial full column
    @State private var baseAnnulusDensity_kgm3: Double = 1200
    @State private var baseStringDensity_kgm3: Double = 1200

    // Hydrostatic evaluation depth (defaults to TD)
    @State private var pressureDepth_m: Double = 6000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mud Placement").font(.title2).bold()
                    Text("Build steps (top/bottom/ρ/name/color/where) and place them as final layers. The interval calculator uses your geometry.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    // Steps Editor
                    GroupBox("Steps") {
                        VStack(alignment: .leading, spacing: 8) {
                            if steps.isEmpty {
                                Text("No steps yet. Add one below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(steps.indices, id: \.self) { i in
                                    stepEditorRow($steps[i])
                                }
                            }

                            HStack(spacing: 8) {
                                Button("Add Step") {
                                    steps.append(MudStep(name: "Step \(steps.count + 1)", top_m: top_m, bottom_m: bottom_m, density_kgm3: 1200, color: .blue, placement: .both))
                                }
                                Button("Sort by Top") {
                                    steps.sort { min($0.top_m, $0.bottom_m) < min($1.top_m, $1.bottom_m) }
                                }
                                Button("Clear All", role: .destructive) {
                                    steps.removeAll()
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }

                    if stepsHaveOverlap(steps) {
                        Text("Note: Steps overlap in depth. Review tops/bottoms.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    GroupBox("Base fluids (initial full column)") {
                        HStack(spacing: 16) {
                            label("Annulus ρ")
                            TextField("kg/m³", value: $baseAnnulusDensity_kgm3, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            label("String ρ")
                            TextField("kg/m³", value: $baseStringDensity_kgm3, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text("Used to fill the well before replacing with steps.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Manual placement action
                    HStack(spacing: 12) {
                        Button("Apply Base + Layers") {
                            rebuildFinalFromBase()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Text("Fills each domain with a base fluid, then overlays steps (Annulus/String/Both).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Final placed layers table
                    if !finalString.isEmpty || !finalAnnulus.isEmpty {
                        GroupBox("Final spotted fluids (base + steps)") {
                            HStack(alignment: .top, spacing: 24) {

                                // String column
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("String layers").font(.caption).foregroundStyle(.secondary)
                                    ForEach(finalString) { lay in
                                        let vol = volumeForLayer(lay)
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Rectangle().fill(lay.color).frame(width: 16, height: 12).cornerRadius(2)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(lay.name)").font(.caption)
                                                Text("\(fmt(lay.top,0))–\(fmt(lay.bottom,0)) m  •  ρ=\(fmt(lay.density,0)) kg/m³")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 12)
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("\(fmt(vol.total_m3)) m³").font(.caption).monospacedDigit()
                                                Text("\(fmt(vol.perM_m3perm)) m³/m").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(6)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
                                    }
                                }

                                Divider()

                                // Annulus column
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Annulus layers").font(.caption).foregroundStyle(.secondary)
                                    ForEach(finalAnnulus) { lay in
                                        let vol = volumeForLayer(lay)
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Rectangle().fill(lay.color).frame(width: 16, height: 12).cornerRadius(2)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(lay.name)").font(.caption)
                                                Text("\(fmt(lay.top,0))–\(fmt(lay.bottom,0)) m  •  ρ=\(fmt(lay.density,0)) kg/m³")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 12)
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("\(fmt(vol.total_m3)) m³").font(.caption).monospacedDigit()
                                                Text("\(fmt(vol.perM_m3perm)) m³/m").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(6)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Hydrostatic panel
                    GroupBox("Hydrostatic (from final layers)") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                label("Depth (m)")
                                TextField("Depth", value: $pressureDepth_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                Text("Computed from surface to depth using the final layers above.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            let pAnn = hydrostatic(from: finalAnnulus, to: pressureDepth_m)
                            let pStr = hydrostatic(from: finalString,  to: pressureDepth_m)
                            HStack(spacing: 24) {
                                resultBox(title: "Annulus P", value: pAnn, unit: "kPa")
                                resultBox(title: "String P", value: pStr, unit: "kPa")
                                resultBox(title: "ΔP (Ann − Str)", value: pAnn - pStr, unit: "kPa")
                            }
                        }
                    }

                    // Interval calculator inputs
                    GroupBox("Interval") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                label("Top (m)")
                                TextField("Top", value: $top_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 140)
                                Spacer(minLength: 24)
                                label("Bottom (m)")
                                TextField("Bottom", value: $bottom_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 140)
                            }
                            Text("Tip: Top < Bottom. Uses auto-sliced annulus and overlapping drill-string geometry.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Quick results for the Interval calculator
                    let t = min(top_m, bottom_m)
                    let b = max(top_m, bottom_m)
                    let r = computeVolumesBetween(top: t, bottom: b)

                    Grid(horizontalSpacing: 24, verticalSpacing: 14) {
                        GridRow {
                            resultBox(title: "Annular volume (outside)", value: r.annular_m3, unit: "m³", perM: r.annularPerM_m3perm, length: r.length_m)
                            resultBox(title: "String capacity (inside)", value: r.stringCapacity_m3, unit: "m³", perM: r.stringCapacityPerM_m3perm, length: r.length_m)
                            resultBox(title: "String displacement", value: r.stringDisp_m3, unit: "m³", perM: r.stringDispPerM_m3perm, length: r.length_m)
                        }
                        GridRow {
                            resultBox(title: "Open hole (no pipe)", value: r.openHole_m3, unit: "m³", perM: r.openHolePerM_m3perm, length: r.length_m)
                            resultBox(title: "Total mud in interval", value: r.annular_m3 + r.stringCapacity_m3, unit: "m³")
                            Spacer().gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }

                    GroupBox("Planning hints") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• To spot a **balanced** mud: pump inside = outside volumes so hydrostatic heads match.")
                            Text("• To chase to a target top in string: add the **string capacity** from current top to target depth.")
                            Text("• Results update as you change depths and respect OD changes and section boundaries.")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .navigationTitle("Mud Placement")
            }
        }
    }

    // MARK: - Final layering helpers
    private var maxDepth_m: Double {
        max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    /// Fill a domain with a single base layer 0..TD
    private func baseLayer(for domain: Domain) -> FinalLayer {
        let rho = (domain == .annulus) ? baseAnnulusDensity_kgm3 : baseStringDensity_kgm3
        return FinalLayer(domain: domain, top: 0, bottom: maxDepth_m, name: "Base", color: .gray.opacity(0.35), density: rho)
    }

    /// Overlay `newLay` onto `layers` by replacing covered intervals (slicing where needed)
    private func overlay(_ layers: inout [FinalLayer], with newLay: FinalLayer) {
        var out: [FinalLayer] = []
        let t = min(newLay.top, newLay.bottom)
        let b = max(newLay.top, newLay.bottom)
        for L in layers {
            if L.bottom <= t || L.top >= b { // no overlap
                out.append(L)
            } else {
                // left remainder
                if L.top < t {
                    out.append(FinalLayer(domain: L.domain, top: L.top, bottom: t, name: L.name, color: L.color, density: L.density))
                }
                // right remainder
                if L.bottom > b {
                    out.append(FinalLayer(domain: L.domain, top: b, bottom: L.bottom, name: L.name, color: L.color, density: L.density))
                }
                // overlapped middle will be replaced by newLay below
            }
        }
        out.append(FinalLayer(domain: newLay.domain, top: t, bottom: b, name: newLay.name, color: newLay.color, density: newLay.density))
        // normalize order
        out.sort { $0.top < $1.top }
        layers = out
    }

    /// Rebuild finalAnnulus/finalString from base fill + user steps
    private func rebuildFinalFromBase() {
        var ann: [FinalLayer] = [ baseLayer(for: .annulus) ]
        var str: [FinalLayer] = [ baseLayer(for: .string) ]
        for s in steps {
            let t = min(s.top_m, s.bottom_m)
            let b = max(s.top_m, s.bottom_m)
            let layA = FinalLayer(domain: .annulus, top: t, bottom: b, name: s.name, color: s.color, density: s.density_kgm3)
            let layS = FinalLayer(domain: .string,  top: t, bottom: b, name: s.name, color: s.color, density: s.density_kgm3)
            if s.placement == .annulus || s.placement == .both { overlay(&ann, with: layA) }
            if s.placement == .string  || s.placement == .both { overlay(&str, with: layS) }
        }
        finalAnnulus = ann
        finalString  = str
        pressureDepth_m = maxDepth_m
    }

    // MARK: - Hydrostatic calculation
    private let g_ms2 = 9.80665
    private func hydrostatic(from layers: [FinalLayer], to depth: Double) -> Double { // kPa
        guard depth > 0 else { return 0 }
        var p = 0.0
        let d = max(0, min(depth, maxDepth_m))
        for L in layers {
            let t = max(0, L.top)
            let b = min(d, L.bottom)
            if b <= t { continue }
            p += L.density * g_ms2 * (b - t) / 1000.0
        }
        return p
    }

    // MARK: - Row helper
    @ViewBuilder private func stepEditorRow(_ s: Binding<MudStep>) -> some View {
        let stepVal = s.wrappedValue
        let vols = volumes(for: stepVal)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TextField("Name", text: s.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
                ColorPicker("Color", selection: s.color)
                    .labelsHidden()
                    .frame(width: 44)
                Spacer(minLength: 8)
                label("Top (m)")
                TextField("Top", value: s.top_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                label("Bottom (m)")
                TextField("Bottom", value: s.bottom_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                label("ρ (kg/m³)")
                TextField("Density", value: s.density_kgm3, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Picker("",selection: s.placement) {
                    ForEach(Placement.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            Text("Ann: \(fmt(vols.annular_m3)) m³   Inside: \(fmt(vols.string_m3)) m³   Disp: \(fmt(vols.disp_m3)) m³   OpenHole: \(fmt(vols.openHole_m3)) m³")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
    }

    // MARK: - UI Helpers
    @ViewBuilder private func label(_ s: String) -> some View {
        Text(s).frame(width: 80, alignment: .leading)
    }

    @ViewBuilder
    private func resultBox(title: String, value: Double, unit: String, perM: Double? = nil, length: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(fmt(value)) \(unit)")
                .font(.headline)
                .monospacedDigit()
            if let perM, let L = length, L > 0 {
                Text("(\(fmt(perM)) m³/m across \(fmt(L, 0)) m)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }

    // MARK: - Geometry & Math
    /// Returns a sorted list of depth boundaries with tolerance-based de-duplication.
    private func uniqueBoundaries(_ values: [Double], tol: Double = 1e-6) -> [Double] {
        let sorted = values.sorted()
        var out: [Double] = []
        for v in sorted {
            if let last = out.last, abs(last - v) <= tol { continue }
            out.append(v)
        }
        return out
    }

    /// Integrate volumes between `top` and `bottom` using current annulus + drill string geometry.
    private func computeVolumesBetween(top: Double, bottom: Double) -> (
        length_m: Double,
        annular_m3: Double, annularPerM_m3perm: Double,
        stringCapacity_m3: Double, stringCapacityPerM_m3perm: Double,
        stringDisp_m3: Double, stringDispPerM_m3perm: Double,
        openHole_m3: Double, openHolePerM_m3perm: Double
    ) {
        guard bottom > top else { return (0,0,0,0,0,0,0,0,0) }
        var bounds: [Double] = [top, bottom]
        for a in project.annulus where a.bottomDepth_m > top && a.topDepth_m < bottom {
            bounds.append(max(a.topDepth_m, top))
            bounds.append(min(a.bottomDepth_m, bottom))
        }
        for d in project.drillString where d.bottomDepth_m > top && d.topDepth_m < bottom {
            bounds.append(max(d.topDepth_m, top))
            bounds.append(min(d.bottomDepth_m, bottom))
        }
        let uniq = uniqueBoundaries(bounds)
        if uniq.count < 2 { return (0,0,0,0,0,0,0,0,0) }

        var annular = 0.0, openHole = 0.0, strCap = 0.0, strDisp = 0.0, L = 0.0
        for i in 0..<(uniq.count - 1) {
            let t = uniq[i], b = uniq[i+1]
            guard b > t else { continue }
            L += (b - t)
            let ann = project.annulus.first { $0.topDepth_m <= t && $0.bottomDepth_m >= b }
            let str = project.drillString.first { $0.topDepth_m <= t && $0.bottomDepth_m >= b }
            if let a = ann {
                let id = max(a.innerDiameter_m, 0)
                openHole += (.pi * id * id / 4.0) * (b - t)
                let od = max(str?.outerDiameter_m ?? 0, 0)
                let areaAnn = max(0, .pi * (id*id - od*od) / 4.0)
                annular += areaAnn * (b - t)
            }
            if let s = str {
                let idStr = max(s.innerDiameter_m, 0)
                let odStr = max(s.outerDiameter_m, 0)
                strCap += (.pi * idStr * idStr / 4.0) * (b - t)
                strDisp += (.pi * odStr * odStr / 4.0) * (b - t)
            }
        }
        return (
            L,
            annular, L>0 ? annular/L : 0,
            strCap,  L>0 ? strCap/L  : 0,
            strDisp, L>0 ? strDisp/L : 0,
            openHole, L>0 ? openHole/L : 0
        )
    }

    private func volumes(for step: MudStep) -> (annular_m3: Double, string_m3: Double, disp_m3: Double, openHole_m3: Double) {
        let t = min(step.top_m, step.bottom_m)
        let b = max(step.top_m, step.bottom_m)
        let r = computeVolumesBetween(top: t, bottom: b)
        return (r.annular_m3, r.stringCapacity_m3, r.stringDisp_m3, r.openHole_m3)
    }
    
    // Volume for a final layer based on its domain
    private func volumeForLayer(_ lay: FinalLayer) -> (total_m3: Double, perM_m3perm: Double) {
        let r = computeVolumesBetween(top: lay.top, bottom: lay.bottom)
        switch lay.domain {
        case .annulus:
            return (r.annular_m3, r.annularPerM_m3perm)
        case .string:
            return (r.stringCapacity_m3, r.stringCapacityPerM_m3perm)
        }
    }

    // Detect if any steps overlap in depth (Top/Bottom), using a small tolerance
    private func stepsHaveOverlap(_ steps: [MudStep]) -> Bool {
        guard steps.count > 1 else { return false }
        let sorted = steps.sorted { min($0.top_m, $0.bottom_m) < min($1.top_m, $1.bottom_m) }
        for i in 0..<(sorted.count - 1) {
            _ = min(sorted[i].top_m, sorted[i].bottom_m)
            let aBot = max(sorted[i].top_m, sorted[i].bottom_m)
            let bTop = min(sorted[i+1].top_m, sorted[i+1].bottom_m)
            if bTop < aBot - 1e-6 { return true }
        }
        return false
    }

    // MARK: - Formatting
    private func fmt(_ v: Double, _ p: Int = 3) -> String { String(format: "%0.*f", p, v) }
}

// MARK: - Preview
#if DEBUG
import SwiftData
struct MudPlacementView_Previews: PreviewProvider {
    static var previews: some View {
        // In-memory SwiftData container for previews
        let container = try! ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let project = ProjectState()
        ctx.insert(project)

        // Sample geometry: casing + open hole
        let a = AnnulusSection(name: "Casing", topDepth_m: 0, length_m: 615, innerDiameter_m: 0.2266, outerDiameter_m: 0)
        let b = AnnulusSection(name: "OpenHole", topDepth_m: 615, length_m: 6000 - 615, innerDiameter_m: 0.159, outerDiameter_m: 0)
        a.project = project; b.project = project
        project.annulus.append(contentsOf: [a,b])
        ctx.insert(a); ctx.insert(b)

        let ds1 = DrillStringSection(name: "4\" DP", topDepth_m: 0, length_m: 6000, outerDiameter_m: 0.1016, innerDiameter_m: 0.0803)
        ds1.project = project
        project.drillString.append(ds1)
        ctx.insert(ds1)

        return MudPlacementView(project: project)
            .modelContainer(container)
            .frame(width: 980, height: 700)
    }
}
#endif
