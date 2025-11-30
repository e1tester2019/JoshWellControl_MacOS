//
//  MixingCalculatorView.swift (reworked)
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08. Refactored to use @Observable + @Bindable bindings correctly.
//

import SwiftUI
import SwiftData
import Observation

fileprivate func label(_ s: String) -> some View {
    Text(s).frame(maxWidth: .infinity, alignment: .leading)
}

struct MixingCalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @State private var viewModel: ViewModel

    init(project: ProjectState) {
        self.project = project
        _viewModel = State(initialValue: ViewModel(project: project))
    }

    var body: some View {
        // Enable direct bindings into the @Observable view model
        @Bindable var vm = viewModel
        let totals = vm.computeTotals()
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 260), spacing: 16)]

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Density Change Calculations").font(.title2).bold()
                Text("Simple mass balance and weight-up with barite calculators")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Adaptive grid of summary boxes
                LazyVGrid(columns: columns, spacing: 16) {
                    VolumeBox(title: "Drill String Capacity", value: totals.dsCapacity_m3, caption: "Inner fluid capacity volume (m³)", fmt: vm.fmt3)
                    VolumeBox(title: "Annular Volume (with pipe)", value: totals.annularWithPipe_m3, caption: "Annulus volume accounting for drill string (m³)", fmt: vm.fmt3)
                    VolumeBox(title: "Mud Tank Volume", value: project.activeMudVolume_m3, caption: "Mud in the active mud tanks (m³)", fmt: vm.fmt3)
                    VolumeBox(title: "Surface Line Volume", value: project.surfaceLineVolume_m3, caption: "Mud in the surface lines (m³)", fmt: vm.fmt3)
                    VolumeBox(title: "Total Circulating Volume", value: totals.totalCirculatingVolume, caption: "Sum of system volumes (m³)", fmt: vm.fmt3)
                }
                .padding(.top, 4)
                
                Divider()

                WeightUpWithBariteSection(model: vm, totals: totals)

                WeightChangeWithMudSection(model: vm, totals: totals)
            }
            .padding()
        }
        .onAppear {
            if vm.intervalMudID == nil { vm.intervalMudID = viewModel.mudsSortedByName.first?.id }
            if vm.killMudID == nil {
                vm.killMudID = viewModel.mudsSortedByName.first?.id
                if let id = vm.killMudID, let m = viewModel.mudsSortedByName.first(where: { $0.id == id }) {
                    vm.killMudDensity_kgm3 = m.density_kgm3
                }
            }
            vm.compute()
            vm.newActiveMudVolume = max(project.activeMudVolume_m3 + project.surfaceLineVolume_m3, 0)
            vm.killMudVolume = 0
        }
    }

    // MARK: - UI Helpers
}

// MARK: - Subviews to reduce type-checking complexity
private struct WeightUpWithBariteSection: View {
    var model: MixingCalculatorView.ViewModel
    var totals: MixingCalculatorView.VolumeTotals
    var body: some View {
        @Bindable var vm = model
        GroupBox("Weight up with Barite") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    label("Active mud")
                    Picker("", selection: $vm.intervalMudID) {
                        ForEach(model.mudsSortedByName, id: \.id) { (m: MudProperties) in
                            Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                        }
                    }
                    .onChange(of: vm.intervalMudID) { oldID, newID in
                        if let newID, let m = model.mudsSortedByName.first(where: { $0.id == newID }) {
                            vm.previewDensity_kgm3 = m.density_kgm3
                        }
                    }
                    .frame(width: 260)
                    .pickerStyle(.menu)

                    label("Desired Weight (kg/m³)")
                    HStack(spacing: 4) {
                        TextField("Desired Weight (kg/m³)", value: $vm.desiredMudDensity_kgm3, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $vm.desiredMudDensity_kgm3, in: 800...2200, step: 5)
                            .labelsHidden()
                            .frame(width: 20)
                    }

                    label("Barite Weight (kg/sx)")
                    HStack(spacing: 4) {
                        TextField("kg/sx", value: $vm.bariteWeightPerSack, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $vm.bariteWeightPerSack, in: 1...100, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }

                    label("Constant")
                    HStack(spacing: 4) {
                        TextField("Constant", value: $vm.bariteFormulaConstant, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $vm.bariteFormulaConstant, in: 1000...5000, step: 5)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                    Spacer(minLength: 24)
                }
                Text("The # of sacks required to raise the mud density to the target is \(vm.sacksRequired).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WeightChangeWithMudSection: View {
    var model: MixingCalculatorView.ViewModel
    var totals: MixingCalculatorView.VolumeTotals
    var body: some View {
        @Bindable var vm = model
        GroupBox("Weight change with Mud") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    label("Active mud")
                    Picker("", selection: $vm.intervalMudID) {
                        ForEach(model.mudsSortedByName, id: \.id) { (m: MudProperties) in
                            Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                        }
                    }
                    .onChange(of: vm.intervalMudID) { oldID, newID in
                        if let newID, let m = model.mudsSortedByName.first(where: { $0.id == newID }) {
                            vm.previewDensity_kgm3 = m.density_kgm3
                        }
                    }
                    .frame(width: 260)
                    .pickerStyle(.menu)

                    label("Active mud volume (m³)")
                    HStack(spacing: 4) {
                        TextField("Active mud volume (m³)", value: $vm.newActiveMudVolume, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $vm.newActiveMudVolume, in: totals.openHole_m3...500, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                    label("Kill mud")
                    Picker("", selection: $vm.killMudID) {
                        ForEach(model.mudsSortedByName, id: \.id) { (m: MudProperties) in
                            Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                        }
                    }
                    .onChange(of: vm.killMudID) { oldID, newID in
                        if let newID, let m = model.mudsSortedByName.first(where: { $0.id == newID }) {
                            vm.killMudDensity_kgm3 = m.density_kgm3
                        }
                    }
                    .frame(width: 260)
                    .pickerStyle(.menu)

                    label("Kill mud volume (m³)")
                    HStack(spacing: 4) {
                        TextField("Kill mud volume (m³)", value: $vm.killMudVolume, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $vm.killMudVolume, in: 0...500, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                    Spacer(minLength: 24)
                }
                Text("Blended density from mass balance = \(vm.fmt0(vm.densityFromMassBalance)) kg/m³")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ViewModel
extension MixingCalculatorView {
    @Observable
    class ViewModel {
        var project: ProjectState
        init(project: ProjectState) { self.project = project }
        
        // Selected/preview mud for calculations
        var intervalMudID: UUID? = nil
        var previewDensity_kgm3: Double = 1260
        var killMudID: UUID? = nil
        
        // Add mudsSortedByName computed property
        var mudsSortedByName: [MudProperties] {
            (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        
        // Densities
        var killMudDensity_kgm3: Double = 1260 { didSet { computeMassBalance() } }
        
        // Barite inputs
        var desiredMudDensity_kgm3: Double = 1500 { didSet { compute() } }
        var bariteWeightPerSack: Double = 40 { didSet { compute() } } // kg/sack
        var bariteFormulaConstant: Double = 4250 { didSet { compute() } } // kg/m³ (approx. barite density)
        
        // Results
        var deltaDensity: Double = 0
        var densityIncrease: Double = 0
        var sacksRequired: Int = 0
        
        // Mass balance inputs/outputs
        var newActiveMudVolume: Double = 0 { didSet { computeMassBalance() } }
        var killMudVolume: Double = 0 { didSet { computeMassBalance() } }
        var densityFromMassBalance: Double = 0
        
        // MARK: Formatting helpers
        func fmt0(_ v: Double) -> String { String(format: "%.0f", v) }
        func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }
        
        // MARK: Compute – Barite requirement
        fileprivate func compute() {
            deltaDensity = desiredMudDensity_kgm3 - previewDensity_kgm3
            densityIncrease = max(deltaDensity, 0)
            guard densityIncrease > 0 else { sacksRequired = 0; return }
            
            // Simple engineering approximation: weight of barite per m³ required to raise density
            // Wb = (rho_b * Δrho) / (rho_b - rho_target)
            let rhoB = max(bariteFormulaConstant, 1)
            let Wb_per_m3 = (rhoB * densityIncrease) / max(rhoB - desiredMudDensity_kgm3, 1)
            let total_m3 = computeTotals().totalCirculatingVolume
            let total_kg = Wb_per_m3 * total_m3
            sacksRequired = Int((total_kg / max(bariteWeightPerSack, 1)).rounded())
        }
        
        // MARK: Compute – Mass balance blend
        fileprivate func computeMassBalance() {
            // Two-component mass balance: rho_t = (rho1*V1 + rho2*V2) / (V1 + V2)
            let V1 = max(newActiveMudVolume, 0)
            let V2 = max(killMudVolume, 0)
            let rho1 = max(previewDensity_kgm3, 0)
            let rho2 = max(killMudDensity_kgm3, 0)
            let Vt = V1 + V2
            guard Vt > 0 else { densityFromMassBalance = 0; return }
            let m1 = V1 * rho1
            let m2 = V2 * rho2
            densityFromMassBalance = (m1 + m2) / Vt
        }
        
        // MARK: Totals & geometry
        func computeTotals() -> VolumeTotals {
            let dsCapacity = (project.drillString ?? []).reduce(0.0) { $0 + (.pi * pow(max($1.innerDiameter_m, 0), 2) / 4.0) * max($1.length_m, 0) }
            let dsDisplacement = (project.drillString ?? []).reduce(0.0) { $0 + (.pi * (pow(max($1.outerDiameter_m, 0), 2) - pow(max($1.innerDiameter_m, 0), 2)) / 4.0) * max($1.length_m, 0) }
            let dsWet = dsCapacity + dsDisplacement
            
            // Open hole is simply the casing/annulus IDs ignoring pipe
            let openHole = (project.annulus ?? []).reduce(0.0) { $0 + (.pi * pow(max($1.innerDiameter_m, 0), 2) / 4.0) * max($1.length_m, 0) }
            
            let slices = buildAnnularSlices()
            let annularWithPipe = slices.reduce(0.0) { $0 + $1.volume_m3 }
            
            let mudTankVolume = project.activeMudVolume_m3
            let surfaceLineVolume_m3 = project.surfaceLineVolume_m3
            let totalCirculatingVolume = dsCapacity + annularWithPipe + mudTankVolume + surfaceLineVolume_m3
            
            return VolumeTotals(
                dsCapacity_m3: dsCapacity,
                dsDisplacement_m3: dsDisplacement,
                dsWet_m3: dsWet,
                annularWithPipe_m3: annularWithPipe,
                openHole_m3: openHole,
                slices: slices,
                totalCirculatingVolume: totalCirculatingVolume
            )
        }
        
        private func buildAnnularSlices() -> [VolumeSlice] {
            var boundaries = Set<Double>()
            for a in (project.annulus ?? []) { boundaries.insert(a.topDepth_m); boundaries.insert(a.bottomDepth_m) }
            for d in (project.drillString ?? []) { boundaries.insert(d.topDepth_m); boundaries.insert(d.bottomDepth_m) }
            let sorted = boundaries.sorted()
            guard sorted.count > 1 else { return [] }
            
            func annulusAt(_ t: Double, _ b: Double) -> AnnulusSection? { (project.annulus ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b } }
            func stringAt(_ t: Double, _ b: Double) -> DrillStringSection? { (project.drillString ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b } }
            
            var slices: [VolumeSlice] = []
            for i in 0..<(sorted.count - 1) {
                let top = sorted[i]
                let bottom = sorted[i + 1]
                guard bottom > top else { continue }
                if let annulus = annulusAt(top, bottom) {
                    let id = max(annulus.innerDiameter_m, 0)
                    let od = max(stringAt(top, bottom)?.outerDiameter_m ?? 0, 0)
                    let area = max(0, .pi * (id * id - od * od) / 4.0)
                    let vol = area * (bottom - top)
                    slices.append(VolumeSlice(top: top, bottom: bottom, area_m2: area, volume_m3: vol))
                }
            }
            return slices
        }
    }

    // MARK: - Small UI helpers
    private struct VolumeBox: View {
        let title: String
        let value: Double
        let caption: String
        let fmt: (Double) -> String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(fmt(value)).font(.headline).monospacedDigit()
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
        }
    }

    // MARK: - Data structs used locally
    struct VolumeSlice {
        var top: Double
        var bottom: Double
        var area_m2: Double
        var volume_m3: Double
    }

    struct VolumeTotals {
        var dsCapacity_m3: Double
        var dsDisplacement_m3: Double
        var dsWet_m3: Double
        var annularWithPipe_m3: Double
        var openHole_m3: Double
        var slices: [VolumeSlice]
        var totalCirculatingVolume: Double
    }
}

