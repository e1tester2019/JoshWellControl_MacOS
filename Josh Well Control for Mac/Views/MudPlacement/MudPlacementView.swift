//  MudPlacementView.swift
//  Josh Well Control for Mac
//
//  Interval-based mud placement calculator. Computes annular volume (outside),
//  string capacity (inside), string displacement, and open-hole capacity between two depths.
//  Also supports manually placing final layers (Annulus / String / Both) from editable steps.

import SwiftUI
import SwiftData

// MARK: - Note: FinalLayer model now in ViewModels/MudPlacementViewModel.swift


// MARK: - View
struct MudPlacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var viewmodel: MudPlacementViewModel

    // Interval inputs (meters). Used for the quick calculator row.
    @State private var top_m: Double = 3150
    @State private var bottom_m: Double = 6000

    // Preview mud density for quick interval pressure/step add
    @State private var previewDensity_kgm3: Double = 1260
    @State private var intervalMudID: UUID? = nil

    init(project: ProjectState) {
        self._project = Bindable(wrappedValue: project)
        _viewmodel = State(initialValue: MudPlacementViewModel(project: project))
    }



    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "drop.triangle")
                                .font(.title)
                                .foregroundStyle(.blue.gradient)
                            Text("Mud Placement").font(.title2).bold()
                        }
                        Text("Build steps (top/bottom/ρ/name/color/where) and place them as final layers. The interval calculator uses your geometry.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))

                    // Steps Editor
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Steps", icon: "square.stack.3d.up.fill", color: .blue)

                        GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewmodel.steps.isEmpty {
                                Text("No steps yet. Add one below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewmodel.steps) { step in
                                    StepRowView(step: step, compute: { t, b in
                                        let r = viewmodel.computeVolumesBetween(top: t, bottom: b)
                                        return (r.annular_m3, r.stringCapacity_m3, r.stringDisp_m3, r.openHole_m3)
                                    }, onDelete: { s in
                                        viewmodel.deleteStep(s)
                                    }, muds: viewmodel.mudsSortedByName)
                                }
                            }

                            HStack(spacing: 8) {
                                Button("Add Step") {
                                    let active = project.activeMud
                                    let s = MudStep(name: "Step \(viewmodel.steps.count + 1)",
                                                    top_m: top_m,
                                                    bottom_m: bottom_m,
                                                    density_kgm3: active?.density_kgm3 ?? 1200,
                                                    color: active?.color ?? .blue,
                                                    placement: .both,
                                                    project: project,
                                                    mud: active)
                                    if project.mudSteps == nil { project.mudSteps = [] }
                                    project.mudSteps?.append(s)
                                    modelContext.insert(s)
                                }
                                Button("Seed Initial") {
                                    viewmodel.seedInitialSteps()
                                }
                                Button("Clear All", role: .destructive) {
                                    viewmodel.clearAllSteps()
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 4)

                        if stepsHaveOverlap(viewmodel.steps) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Steps overlap in depth. Review tops/bottoms.")
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
                        }
                    }
                    }

                    // Base Fluids Section
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Base Fluids", icon: "drop.fill", color: .green)

                        GroupBox {
                        HStack(spacing: 12) {
                            label("Annulus ρ")
                            TextField("kg/m³", value: $project.baseAnnulusDensity_kgm3, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            label("String ρ")
                            TextField("kg/m³", value: $project.baseStringDensity_kgm3, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text("Used to fill the well before replacing with steps.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    }

                    // Apply Section
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Apply Placement", icon: "arrow.down.circle.fill", color: .purple)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button {
                                        rebuildFinalFromBase()
                                    } label: {
                                        Label("Apply Base + Layers", systemImage: "arrow.down.circle.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .help("Persist final layers and make them available to seed the numerical trip model")
                                }

                                Text("Fills each domain with a base fluid, then overlays steps (Annulus/String/Both).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Final Layers Section
                    if let finalLayers = project.finalLayers {
                        VStack(alignment: .leading, spacing: 0) {
                            sectionHeader(title: "Final Spotted Fluids", icon: "layers.fill", color: .orange)

                            GroupBox {
                            HStack(alignment: .top, spacing: 16) {
                                // String column
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("String layers").font(.caption).foregroundStyle(.secondary)
                                    let stringLayers = finalLayers
                                        .filter { $0.placement == .string || $0.placement == .both }
                                        .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
                                    ForEach(stringLayers, id: \.id) { L in
                                        let lay = FinalLayer(
                                            domain: .string,
                                            top: min(L.topMD_m, L.bottomMD_m),
                                            bottom: max(L.topMD_m, L.bottomMD_m),
                                            name: L.name,
                                            color: L.color,
                                            density: L.density_kgm3,
                                            mud: L.mud
                                        )
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
                                    let annulusLayers = finalLayers
                                        .filter { $0.placement == .annulus || $0.placement == .both }
                                        .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
                                    ForEach(annulusLayers, id: \.id) { L in
                                        let lay = FinalLayer(
                                            domain: .annulus,
                                            top: min(L.topMD_m, L.bottomMD_m),
                                            bottom: max(L.topMD_m, L.bottomMD_m),
                                            name: L.name,
                                            color: L.color,
                                            density: L.density_kgm3,
                                            mud: L.mud
                                        )
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
                    }

                    // Hydrostatic Section
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Hydrostatic Pressure", icon: "gauge", color: .indigo)

                        GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                label("Measured Depth (m)")
                                TextField("(m)", value: $project.pressureDepth_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                Text("Computed from surface to **TVD** using final layers (MD→TVD mapped via surveys).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // Show the TVD that will be used in the calculation for verification
                            // Reference: if the value above were MD, this would be the mapped TVD
                            Text("TVD(MD)=\(fmt(viewmodel.mdToTVD(project.pressureDepth_m), 0)) m")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            let depthTVD = viewmodel.mdToTVD(project.pressureDepth_m)
                            // Build working layer arrays from persisted ProjectState so hydrostatic survives reloads
                            let annLayers: [FinalLayer] = (project.finalLayers ?? [])
                                .filter { $0.placement == .annulus || $0.placement == .both }
                                .map { L in
                                    FinalLayer(
                                        domain: .annulus,
                                        top: min(L.topMD_m, L.bottomMD_m),
                                        bottom: max(L.topMD_m, L.bottomMD_m),
                                        name: L.name,
                                        color: L.color,
                                        density: L.density_kgm3,
                                        mud: L.mud
                                    )
                                }
                                .sorted { $0.top < $1.top }

                            let strLayers: [FinalLayer] = (project.finalLayers ?? [])
                                .filter { $0.placement == .string || $0.placement == .both }
                                .map { L in
                                    FinalLayer(
                                        domain: .string,
                                        top: min(L.topMD_m, L.bottomMD_m),
                                        bottom: max(L.topMD_m, L.bottomMD_m),
                                        name: L.name,
                                        color: L.color,
                                        density: L.density_kgm3,
                                        mud: L.mud
                                    )
                                }
                                .sorted { $0.top < $1.top }

                            let pAnn = hydrostatic(from: annLayers, to: depthTVD)
                            let pStr = hydrostatic(from: strLayers, to: depthTVD)
                            HStack(spacing: 24) {
                                resultBox(title: "Annulus P", value: pAnn, unit: "kPa", valueFmt: fmtP)
                                resultBox(title: "String P", value: pStr, unit: "kPa", valueFmt: fmtP)
                                resultBox(title: "ΔP (Ann − Str)", value: pAnn - pStr, unit: "kPa", valueFmt: fmtP)
                            }
                        }
                        }
                    }

                    // Interval Calculator Section
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Interval Calculator", icon: "function", color: .teal)

                        GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                label("Top (m)")
                                HStack(spacing: 4) {
                                    TextField("Top", value: $top_m, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)

                                    Stepper("", value: $top_m, in: 0...10_000, step: 0.1)
                                        .labelsHidden()
                                        .frame(width: 20)
                                }
                                label("Bottom (m)")
                                HStack(spacing: 4) {
                                    TextField("Bottom", value: $bottom_m, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)

                                    Stepper("", value: $bottom_m, in: top_m...10_000, step: 0.1)
                                        .labelsHidden()
                                        .frame(width: 20)
                                }
                                label("Preview mud")
                                Picker("", selection: Binding<UUID?>(
                                    get: { intervalMudID ?? viewmodel.mudsSortedByName.first?.id },
                                    set: { newID in
                                        intervalMudID = newID
                                        if let id = newID, let m = viewmodel.mudsSortedByName.first(where: { $0.id == id }) {
                                            previewDensity_kgm3 = m.density_kgm3
                                        }
                                    }
                                )) {
                                    ForEach(viewmodel.mudsSortedByName, id: \.id) { m in
                                        Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                                    }
                                }
                                .frame(width: 220)
                                .pickerStyle(.menu)
                                Spacer(minLength: 24)
                            }
                            Text("Tip: Top < Bottom. Open-hole uses [Top, Bottom]. 'Total mud in interval' solves a longer pipe-in length so volumes match after pulling the string.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // Insert preview density HStack here
                            HStack(spacing: 12) {
                                Text("Use this mud to preview ΔP over the selected TVD span, or add a step from this interval.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Add Step from Interval") {
                                    let tNow = min(top_m, bottom_m)
                                    let bNow = max(top_m, bottom_m)
                                    let chosenMud = viewmodel.mudsSortedByName.first(where: { $0.id == intervalMudID })
                                    let s = MudStep(name: "Preview Step", top_m: tNow, bottom_m: bNow, density_kgm3: chosenMud?.density_kgm3 ?? previewDensity_kgm3, color: chosenMud?.color ?? .purple, placement: .both, project: project, mud: chosenMud)
                                    if project.mudSteps == nil { project.mudSteps = [] }
                                    project.mudSteps?.append(s)
                                    modelContext.insert(s)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)

                    // Interval Results
                    Divider().padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interval Results")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    let t = min(top_m, bottom_m)
                    let b = max(top_m, bottom_m)
                    let r = viewmodel.computeVolumesBetween(top: t, bottom: b)
                    let equal = viewmodel.solvePipeInIntervalForEqualVolume(targetTop: t, targetBottom: b)
                    // TVD and pressure preview calculations
                    let tvdTop = viewmodel.mdToTVD(t)
                    let tvdBot = viewmodel.mdToTVD(b)
                    let tvdSpan = abs(tvdBot - tvdTop)
                    let dp_kPa = previewDensity_kgm3 * g_ms2 * tvdSpan / 1000.0
                    let checksum_m3 = r.openHole_m3 - (r.annular_m3 + r.stringCapacity_m3 + r.stringMetal_m3)

                    Grid(horizontalSpacing: 24, verticalSpacing: 14) {
                        GridRow {
                            resultBox(title: "Annular volume (outside)", value: r.annular_m3, unit: "m³",
                                      perM: r.annularPerM_m3perm, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)

                            resultBox(title: "String capacity (inside)", value: r.stringCapacity_m3, unit: "m³",
                                      perM: r.stringCapacityPerM_m3perm, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)

                            resultBox(title: "Wet displacement", value: r.stringDisp_m3, unit: "m³",
                                      perM: r.stringDispPerM_m3perm, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)

                            resultBox(title: "Dry displacement", value: r.stringMetal_m3, unit: "m³",
                                      perM: r.stringMetalPerM_m3perm, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)
                        }
                        GridRow {
                            resultBox(title: "Open hole (no pipe)", value: r.openHole_m3, unit: "m³",
                                      perM: r.openHolePerM_m3perm, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)

                            resultBox(title: "Total mud in interval (pipe in)", value: equal.total_m3, unit: "m³",
                                      perM: equal.length_m > 0 ? (equal.total_m3 / equal.length_m) : 0, length: equal.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)

                            resultBox(title: "Identity check (should be 0)", value: checksum_m3, unit: "m³",
                                      perM: r.length_m > 0 ? (checksum_m3 / r.length_m) : 0, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)
                            resultBox(title: "Volume inside and outside", value: (r.annular_m3 + r.stringCapacity_m3), unit: "m³",
                                      perM: r.length_m > 0 ? (r.annularPerM_m3perm + r.stringCapacityPerM_m3perm) : 0, length: r.length_m,
                                      valueFmt: fmtCap, perMFmt: fmtCap, lengthFmt: fmtLen)
                        }
                        GridRow {
                            resultBox(title: "Pipe-in interval length", value: equal.length_m, unit: "m", valueFmt: fmtLen)
                            resultBox(title: "Mud top with string in", value: equal.mudTop_m, unit: "m", valueFmt: fmtLen)
                            resultBox(title: "TVD span (top→bottom)", value: tvdSpan, unit: "m", valueFmt: fmtLen)
                            resultBox(title: "ΔP over section (preview)", value: dp_kPa, unit: "kPa", valueFmt: fmtP)
                        }
                    }
                        }
                    }

                    // Planning Hints Section
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Planning Hints", icon: "lightbulb.fill", color: .yellow)

                        GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• To spot a **balanced** mud: pump inside = outside volumes so hydrostatic heads match.")
                            Text("• To chase to a target top in string: add the **string capacity** from current top to target depth.")
                            Text("• Results update as you change depths and respect OD changes and section boundaries.")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .navigationTitle("Mud Placement")
        }
        .onAppear {
            viewmodel.attach(context: modelContext)
            if intervalMudID == nil { intervalMudID = viewmodel.mudsSortedByName.first?.id }
            if let id = intervalMudID, let m = viewmodel.mudsSortedByName.first(where: { $0.id == id }) {
                previewDensity_kgm3 = m.density_kgm3
            }
        }
    }

    // MARK: - Section Header Helper
    @ViewBuilder
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color.gradient)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(8, corners: [.topLeft, .topRight])
    }

    // MARK: - Final layering helpers
    private var maxDepth_m: Double {
        max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    /// Fill a domain with a single base layer 0..TD
    private func baseLayer(for domain: FinalLayer.Domain) -> FinalLayer {
        let active = project.activeMud
        let rho = (domain == .annulus) ? (active?.density_kgm3 ?? project.baseAnnulusDensity_kgm3) : (active?.density_kgm3 ?? project.baseStringDensity_kgm3)
        let col = active?.color ?? Color.gray.opacity(0.35)
        return FinalLayer(domain: domain, top: 0, bottom: maxDepth_m, name: "Base", color: col, density: rho, mud: active)
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
                    out.append(FinalLayer(domain: L.domain, top: L.top, bottom: t, name: L.name, color: L.color, density: L.density, mud: L.mud))
                }
                // right remainder
                if L.bottom > b {
                    out.append(FinalLayer(domain: L.domain, top: b, bottom: L.bottom, name: L.name, color: L.color, density: L.density, mud: L.mud))
                }
                // overlapped middle will be replaced by newLay below
            }
        }
        out.append(FinalLayer(domain: newLay.domain, top: t, bottom: b, name: newLay.name, color: newLay.color, density: newLay.density, mud: newLay.mud))
        // normalize order
        out.sort { $0.top < $1.top }
        layers = out
    }

    /// Rebuild finalAnnulus/finalString from base fill + user steps
    private func rebuildFinalFromBase() {
        var ann: [FinalLayer] = [ baseLayer(for: .annulus) ]
        var str: [FinalLayer] = [ baseLayer(for: .string) ]

        for s in viewmodel.steps {
            let t = min(s.top_m, s.bottom_m)
            let b = max(s.top_m, s.bottom_m)
            let chosenMud = s.mud

            let layA = FinalLayer(domain: .annulus,
                                   top: t, bottom: b,
                                   name: s.name,
                                   color: chosenMud?.color ?? s.color,
                                   density: s.density_kgm3,
                                   mud: chosenMud)

            let layS = FinalLayer(domain: .string,
                                   top: t, bottom: b,
                                   name: s.name,
                                   color: chosenMud?.color ?? s.color,
                                   density: s.density_kgm3,
                                   mud: chosenMud)

            if s.placement == .annulus || s.placement == .both { overlay(&ann, with: layA) }
            if s.placement == .string  || s.placement == .both { overlay(&str, with: layS) }
        }

        // Persist to SwiftData (keeps mud link if available)
        viewmodel.persistFinalLayers(from: ann, str)
    }

    // MARK: - Hydrostatic calculation
    private let g_ms2 = 9.80665
    /// Integrate hydrostatic head from surface to a **TVD** depth using final layers defined in **MD** (MD→TVD via surveys).
    private func hydrostatic(from layers: [FinalLayer], to depthTVD: Double) -> Double { // kPa
        let limitTVD = max(0, min(depthTVD, maxDepth_m))
        guard limitTVD > 0 else { return 0 }
        var p = 0.0
        for L in layers {
            // Convert this layer's MD bounds to TVD bounds
            let tTVD = mdToTVD(L.top)
            let bTVD = mdToTVD(L.bottom)
            let lo = min(tTVD, bTVD)
            let hi = max(tTVD, bTVD)
            // Intersect with [0, limitTVD]
            let segTop = max(0, lo)
            let segBot = min(limitTVD, hi)
            if segBot <= segTop { continue }
            p += L.density * g_ms2 * (segBot - segTop) / 1000.0 // Pa → kPa
        }
        return p
    }

    // MARK: - Row subview for a persisted MudStep
    private struct StepRowView: View {
        @Bindable var step: MudStep
        let compute: (_ top: Double, _ bottom: Double) -> (annular_m3: Double, string_m3: Double, disp_m3: Double, openHole_m3: Double)
        let onDelete: (MudStep) -> Void
        let muds: [MudProperties]

        @ViewBuilder private func rowLabel(_ s: String) -> some View {
            Text(s).frame(width: 80, alignment: .leading)
        }

        private func fmtLocal(_ v: Double, _ p: Int = 3) -> String { String(format: "%0.*f", p, v) }
        var body: some View {
            let t = min(step.top_m, step.bottom_m)
            let b = max(step.top_m, step.bottom_m)
            let vols = compute(t, b)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    TextField("Name", text: $step.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160)
                    // Color is derived from the selected MudProperties; not editable here
                    Rectangle()
                        .fill(step.mud?.color ?? step.color)
                        .frame(width: 24, height: 16)
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.3)))
                    Spacer(minLength: 8)
                    rowLabel("Top (m)")
                    TextField("Top", value: $step.top_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    rowLabel("Bottom (m)")
                    TextField("Bottom", value: $step.bottom_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    rowLabel("Mud")
                    Picker("", selection: Binding<UUID?>(
                        get: { step.mud?.id },
                        set: { newID in
                            if let id = newID, let m = muds.first(where: { $0.id == id }) {
                                step.mud = m
                                step.density_kgm3 = m.density_kgm3
                                step.colorHex = m.color.toHexRGB() ?? step.colorHex
                            }
                        }
                    )) {
                        ForEach(muds, id: \.id) { m in
                            Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                        }
                    }
                    .frame(width: 220)
                    .pickerStyle(.menu)
                    Picker("", selection: Binding(get: { step.placement }, set: { step.placement = $0 })) {
                        ForEach(Placement.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    Button(role: .destructive) { onDelete(step) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete step")
                }
                Text("Ann: \(fmtLocal(vols.annular_m3)) m³   Inside: \(fmtLocal(vols.string_m3)) m³   Disp: \(fmtLocal(vols.disp_m3)) m³   OpenHole: \(fmtLocal(vols.openHole_m3)) m³")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
        }
    }

    // MARK: - UI Helpers
    @ViewBuilder private func label(_ s: String) -> some View {
        Text(s).frame(width: 80, alignment: .leading)
    }

    @ViewBuilder
    private func resultBox(
        title: String,
        value: Double,
        unit: String,
        perM: Double? = nil,
        length: Double? = nil,
        valueFmt: ((Double) -> String)? = nil,
        perMFmt: ((Double) -> String)? = nil,
        lengthFmt: ((Double) -> String)? = nil
    ) -> some View {
        let vf = valueFmt ?? { fmt($0) }
        let pf = perMFmt ?? { fmt($0) }
        let lf = lengthFmt ?? { fmt($0, 0) }
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(vf(value)) \(unit)")
                .font(.headline)
                .monospacedDigit()
            if let perM, let L = length, L > 0 {
                Text("(\(pf(perM)) m³/m across \(lf(L)) m)")
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
        openHole_m3: Double, openHolePerM_m3perm: Double,
        stringMetal_m3: Double, stringMetalPerM_m3perm: Double
    ) {
        guard bottom > top else { return (0,0,0,0,0,0,0,0,0,0,0) }
        var bounds: [Double] = [top, bottom]
        for a in (project.annulus ?? []) where a.bottomDepth_m > top && a.topDepth_m < bottom {
            bounds.append(max(a.topDepth_m, top))
            bounds.append(min(a.bottomDepth_m, bottom))
        }
        for d in (project.drillString ?? []) where d.bottomDepth_m > top && d.topDepth_m < bottom {
            bounds.append(max(d.topDepth_m, top))
            bounds.append(min(d.bottomDepth_m, bottom))
        }
        let uniq = uniqueBoundaries(bounds)
        if uniq.count < 2 { return (0,0,0,0,0,0,0,0,0,0,0) }

        var annular = 0.0, openHole = 0.0, strCap = 0.0, strDisp = 0.0, strMetal = 0.0, L = 0.0
        for i in 0..<(uniq.count - 1) {
            let t = uniq[i], b = uniq[i+1]
            guard b > t else { continue }
            L += (b - t)
            let ann = (project.annulus ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b }
            let str = (project.drillString ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b }
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
                strMetal += max(0, .pi * (odStr*odStr - idStr*idStr) / 4.0) * (b - t)
            }
        }
        return (
            L,
            annular, L>0 ? annular/L : 0,
            strCap,  L>0 ? strCap/L  : 0,
            strDisp, L>0 ? strDisp/L : 0,
            openHole, L>0 ? openHole/L : 0,
            strMetal, L>0 ? strMetal/L : 0
        )
    }

    /// Compute total mud volume with pipe in between [top, bottom]
    private func totalMudWithPipeBetween(top: Double, bottom: Double) -> (total_m3: Double, annular_m3: Double, string_m3: Double) {
        guard bottom > top else { return (0,0,0) }
        let r = computeVolumesBetween(top: top, bottom: bottom)
        return (r.annular_m3 + r.stringCapacity_m3, r.annular_m3, r.stringCapacity_m3)
    }

    /// Solve the pipe-in interval length L such that the total mud (annulus + inside) over [bottom-L, bottom]
    /// equals the open-hole volume over [targetTop, targetBottom]. Returns length, total, split, and mud-top depth.
    private func solvePipeInIntervalForEqualVolume(targetTop: Double, targetBottom: Double, tol: Double = 1e-6, maxIter: Int = 60) -> (length_m: Double, total_m3: Double, annular_m3: Double, string_m3: Double, mudTop_m: Double) {
        let t = min(targetTop, targetBottom)
        let b = max(targetTop, targetBottom)
        guard b > t else { return (0,0,0,0,b) }

        // Target volume is open-hole over [t,b]
        let target = computeVolumesBetween(top: t, bottom: b).openHole_m3

        // Bracket L in [0, Lmax] where Lmax cannot exceed bottom depth (surface at 0)
        var lo = 0.0
        var hi = max(0.0, b) // cannot pull top above surface

        // Ensure hi is sufficient to exceed target volume
        let vHi = totalMudWithPipeBetween(top: max(0.0, b - hi), bottom: b).total_m3
        if vHi < target {
            // Geometry degenerate; fall back to using the target interval length so UI still behaves
            let fallback = totalMudWithPipeBetween(top: t, bottom: b)
            return (b - t, fallback.total_m3, fallback.annular_m3, fallback.string_m3, t)
        }

        // Bisection solve for L where V(L) = target
        for _ in 0..<maxIter {
            let mid = 0.5 * (lo + hi)
            let vMid = totalMudWithPipeBetween(top: max(0.0, b - mid), bottom: b).total_m3
            if abs(vMid - target) <= max(1e-9, tol * max(target, 1.0)) { // relative/absolute tol
                let topWithPipe = max(0.0, b - mid)
                let parts = totalMudWithPipeBetween(top: topWithPipe, bottom: b)
                return (mid, vMid, parts.annular_m3, parts.string_m3, topWithPipe)
            }
            if vMid < target { lo = mid } else { hi = mid }
        }
        let L = hi
        let topWithPipe = max(0.0, b - L)
        let parts = totalMudWithPipeBetween(top: topWithPipe, bottom: b)
        return (L, parts.total_m3, parts.annular_m3, parts.string_m3, topWithPipe)
    }

    private func volumes(for step: MudStep) -> (annular_m3: Double, string_m3: Double, disp_m3: Double, openHole_m3: Double) {
        let t = min(step.top_m, step.bottom_m)
        let b = max(step.top_m, step.bottom_m)
        let r = computeVolumesBetween(top: t, bottom: b)
        return (r.annular_m3, r.stringCapacity_m3, r.stringDisp_m3, r.openHole_m3)
    }
    
    // Volume for a final layer based on its domain
    private func volumeForLayer(_ lay: FinalLayer) -> (total_m3: Double, perM_m3perm: Double) {
        let r = viewmodel.computeVolumesBetween(top: lay.top, bottom: lay.bottom)
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
    
    /// Map an input MD (m) to TVD (m) using the project's surveys. Falls back to identity if surveys are missing.
    private func mdToTVD(_ md: Double) -> Double {
        // Expect project.surveys to hold stations with md and tvd
        let stations = (project.surveys ?? []).sorted { $0.md < $1.md }
        guard let first = stations.first else { return md }
        guard let last  = stations.last  else { return md }
        let tvd0 = first.tvd ?? 0
        let tvdN = last.tvd  ?? tvd0
        if md <= first.md { return tvd0 }
        if md >= last.md  { return tvdN }
        // Linear interpolate TVD between bracketing MDs
        for i in 0..<(stations.count - 1) {
            let a = stations[i]
            let b = stations[i+1]
            if md >= a.md && md <= b.md {
                let tvdA = a.tvd ?? 0
                let tvdB = b.tvd ?? tvdA
                let span = max(b.md - a.md, 1e-9)
                let f = (md - a.md) / span
                return tvdA + f * (tvdB - tvdA)
            }
        }
        return tvdN
    }

    // MARK: - Formatting
    private func fmt(_ v: Double, _ p: Int = 5) -> String { String(format: "%0.*f", p, v) }
    private func fmtCap(_ v: Double) -> String { fmt(v, 5) }   // capacities/volumes to 5 dp
    private func fmtP(_ v: Double)   -> String { fmt(v, 0) }   // pressures to 0 dp
    private func fmtLen(_ v: Double) -> String { fmt(v, 2) }   // lengths to 2 dp
    
    // MARK: - seed initial steps
    private func seedInitialSteps() {
        let samples: [MudStep] = [
            MudStep(name: "Annulus Kill", top_m: 687,  bottom_m: 1010, density_kgm3: 1800, color: .blue,   placement: .annulus, project: project),
            MudStep(name: "Active Mud",   top_m: 1010, bottom_m: 2701, density_kgm3: 1260, color: .yellow, placement: .annulus, project: project),
            MudStep(name: "Lube Blend",   top_m: 2701, bottom_m: 6000, density_kgm3: 1260, color: .orange, placement: .both,    project: project),
            MudStep(name: "Active Mud",   top_m: 2040, bottom_m: 2701, density_kgm3: 1260, color: .yellow, placement: .string,  project: project),
            MudStep(name: "Balance Slug", top_m: 1705, bottom_m: 2040, density_kgm3: 1800, color: .blue,   placement: .string,  project: project),
            MudStep(name: "Active Mud",   top_m: 596,  bottom_m: 1705, density_kgm3: 1260, color: .yellow, placement: .string,  project: project),
            MudStep(name: "Dry Pipe Slug",top_m: 220,  bottom_m: 596,  density_kgm3: 2100, color: .brown,  placement: .string,  project: project),
            MudStep(name: "Air",          top_m: 0,    bottom_m: 221,  density_kgm3: 1.2,  color: .cyan,   placement: .string,  project: project)
        ]

        // Avoid duplicates: skip if a step with same name+top+bottom already exists for this project
        let existing = Set(viewmodel.steps.map { "\($0.name)|\($0.top_m)|\($0.bottom_m)" })
        for s in samples {
            let key = "\(s.name)|\(s.top_m)|\(s.bottom_m)"
            if !existing.contains(key) { modelContext.insert(s) }
        }
    }
    

    // No longer needed: persistFinalLayers handled by ViewModel
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                       radius: tr,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(0),
                       clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                       radius: br,
                       startAngle: .degrees(0),
                       endAngle: .degrees(90),
                       clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                       radius: bl,
                       startAngle: .degrees(90),
                       endAngle: .degrees(180),
                       clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                       radius: tl,
                       startAngle: .degrees(180),
                       endAngle: .degrees(270),
                       clockwise: false)
        }

        return path
    }
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
                 MudStep.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let project = ProjectState()
        ctx.insert(project)

        // Sample geometry: casing + open hole
        let a = AnnulusSection(name: "Casing", topDepth_m: 0, length_m: 615, innerDiameter_m: 0.2266, outerDiameter_m: 0)
        let b = AnnulusSection(name: "OpenHole", topDepth_m: 615, length_m: 6000 - 615, innerDiameter_m: 0.159, outerDiameter_m: 0)
        if project.annulus == nil { project.annulus = [] }
        project.annulus?.append(contentsOf: [a,b])
        ctx.insert(a); ctx.insert(b)

        let ds1 = DrillStringSection(name: "4\" DP", topDepth_m: 0, length_m: 6000, outerDiameter_m: 0.1016, innerDiameter_m: 0.0803)
        if project.drillString == nil { project.drillString = [] }
        project.drillString?.append(ds1)
        ctx.insert(ds1)

        return MudPlacementView(project: project)
            .modelContainer(container)
            .frame(width: 980, height: 700)
    }
}
#endif


// ViewModel now in: ViewModels/MudPlacementViewModel.swift


