//
//  SwabbingViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized swabbing view
//

#if os(iOS)
import SwiftUI
import SwiftData
import Charts

struct SwabbingViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var viewModel: SwabbingViewModelIOS?

    private var swabInput: SwabInput {
        project.swab
    }

    var body: some View {
        Form {
            // Input Parameters
            Section("Parameters") {
                HStack {
                    Text("Hoisting Speed")
                    Spacer()
                    TextField("Speed", value: Binding(
                        get: { swabInput.hoistSpeed_m_per_min },
                        set: { swabInput.hoistSpeed_m_per_min = $0 }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Text("m/min")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Pipe OD")
                    Spacer()
                    TextField("OD", value: Binding(
                        get: { swabInput.pipeOD_m },
                        set: { swabInput.pipeOD_m = $0 }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Hole ID")
                    Spacer()
                    TextField("ID", value: Binding(
                        get: { swabInput.holeID_m },
                        set: { swabInput.holeID_m = $0 }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Text("m")
                        .foregroundStyle(.secondary)
                }
            }

            // Mud Properties (from active mud)
            Section("Mud Properties") {
                if let activeMud = project.activeMud {
                    HStack {
                        Text("Active Mud")
                        Spacer()
                        Text(activeMud.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Density")
                        Spacer()
                        Text("\(activeMud.density_kgm3, format: .number) kg/m³")
                            .foregroundStyle(.secondary)
                    }

                    if let pv = activeMud.pv_Pa_s {
                        HStack {
                            Text("PV")
                            Spacer()
                            Text("\(pv * 1000, format: .number) cP")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let yp = activeMud.yp_Pa {
                        HStack {
                            Text("YP")
                            Spacer()
                            Text("\(yp, format: .number) Pa")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No active mud selected")
                        .foregroundStyle(.secondary)
                }
            }

            // Results
            Section("Results") {
                if let vm = viewModel {
                    HStack {
                        Text("Swab Pressure")
                        Spacer()
                        Text(String(format: "%.1f kPa", vm.swabPressure_kPa))
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }

                    HStack {
                        Text("ECD Reduction")
                        Spacer()
                        Text(String(format: "%.0f kg/m³", vm.ecdReduction_kgm3))
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("Underbalance Risk")
                        Spacer()
                        Text(vm.underbalanceRisk ? "Yes" : "No")
                            .fontWeight(.medium)
                            .foregroundStyle(vm.underbalanceRisk ? .red : .green)
                    }
                } else {
                    Text("Configure parameters to see results")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .navigationTitle("Swabbing")
        .onAppear {
            initializeViewModel()
        }
        .onChange(of: project) { _, _ in
            initializeViewModel()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Calculate") {
                    runCalculation()
                }
            }
        }
    }

    private func initializeViewModel() {
        viewModel = SwabbingViewModelIOS(project: project)
    }

    private func runCalculation() {
        viewModel?.calculate()
    }
}

// MARK: - SwabbingViewModelIOS

@Observable
class SwabbingViewModelIOS {
    let project: ProjectState

    var swabPressure_kPa: Double = 0
    var ecdReduction_kgm3: Double = 0
    var underbalanceRisk: Bool = false

    init(project: ProjectState) {
        self.project = project
        calculate()
    }

    func calculate() {
        guard let activeMud = project.activeMud else { return }

        let input = project.swab
        let pipeArea = Double.pi * pow(input.pipeOD_m, 2) / 4.0
        let holeArea = Double.pi * pow(input.holeID_m, 2) / 4.0
        let annularArea = holeArea - pipeArea

        guard annularArea > 0 else { return }

        // Convert m/min to m/s
        let hoistSpeed_m_per_s = input.hoistSpeed_m_per_min / 60.0

        // Simplified swab pressure calculation
        let annularVelocity = hoistSpeed_m_per_s * pipeArea / annularArea
        let hydraulicDiameter = input.holeID_m - input.pipeOD_m

        // Reynolds number
        let pv = activeMud.pv_Pa_s ?? 0.02
        let re = activeMud.density_kgm3 * annularVelocity * hydraulicDiameter / max(pv, 0.001)

        // Friction factor (simplified Blasius)
        let f = re > 2000 ? 0.3164 / pow(re, 0.25) : 64 / max(re, 1)

        // Pressure drop per meter
        let dP_per_m = f * activeMud.density_kgm3 * pow(annularVelocity, 2) / (2 * hydraulicDiameter)

        // Assume 1000m depth for now
        let depth = 1000.0
        swabPressure_kPa = dP_per_m * depth / 1000

        // ECD reduction
        let gravity = 9.80665
        ecdReduction_kgm3 = swabPressure_kPa * 1000 / (gravity * depth)

        // Check underbalance risk against pressure window
        let points = (project.window.points ?? []).sorted { $0.depth_m < $1.depth_m }
        let poreGradient = points.first?.pore_kPa ?? 0
        let currentPressure = activeMud.density_kgm3 * gravity * depth / 1000
        underbalanceRisk = (currentPressure - swabPressure_kPa) < poreGradient
    }
}

#endif
