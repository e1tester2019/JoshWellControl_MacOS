//
//  OperationResultView.swift
//  Josh Well Control for Mac
//
//  Displays results for a completed operation in the Super Simulation.
//

import SwiftUI

struct OperationResultView: View {
    let operation: SuperSimOperation
    @Bindable var viewModel: SuperSimViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)

            switch operation.type {
            case .tripOut:
                tripOutResults
            case .tripIn:
                tripInResults
            case .circulate:
                circulationResults
            }
        }
    }

    // MARK: - Trip Out Results

    private var tripOutResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.tripOutSteps.isEmpty {
                Text("No results available")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(viewModel.tripOutSteps.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepSlider(count: viewModel.tripOutSteps.count)
                }

                // Step table
                Table(viewModel.tripOutSteps) {
                    TableColumn("MD (m)") { step in
                        Text(String(format: "%.0f", step.bitMD_m))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("TVD (m)") { step in
                        Text(String(format: "%.0f", step.bitTVD_m))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("ESD TD") { step in
                        Text(String(format: "%.1f", step.ESDatTD_kgpm3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("SABP (kPa)") { step in
                        Text(String(format: "%.0f", step.SABP_kPa))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("Fill (m\u{00B3})") { step in
                        Text(String(format: "%.2f", step.cumulativeBackfill_m3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Float") { step in
                        Text(step.floatState)
                    }
                    .width(min: 70, max: 100)
                }
                .frame(minHeight: 200, maxHeight: 400)
            }
        }
    }

    // MARK: - Trip In Results

    private var tripInResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.tripInSteps.isEmpty {
                Text("No results available")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(viewModel.tripInSteps.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepSlider(count: viewModel.tripInSteps.count)
                }

                Table(viewModel.tripInSteps) {
                    TableColumn("MD (m)") { step in
                        Text(String(format: "%.0f", step.bitMD_m))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("TVD (m)") { step in
                        Text(String(format: "%.0f", step.bitTVD_m))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("ESD Ctrl") { step in
                        Text(String(format: "%.1f", step.ESDAtControl_kgpm3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Fill (m\u{00B3})") { step in
                        Text(String(format: "%.2f", step.cumulativeFillVolume_m3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Disp (m\u{00B3})") { step in
                        Text(String(format: "%.2f", step.cumulativeDisplacementReturns_m3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Choke (kPa)") { step in
                        Text(String(format: "%.0f", step.requiredChokePressure_kPa))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("Float") { step in
                        Text(step.floatState)
                    }
                    .width(min: 70, max: 100)

                    TableColumn("HP Below (kPa)") { step in
                        let sum = step.layersPocket
                            .filter { $0.topMD >= step.bitMD_m }
                            .reduce(0.0) { $0 + $1.deltaHydroStatic_kPa }
                        Text(String(format: "%.0f", sum))
                    }
                    .width(min: 80, max: 110)
                }
                .frame(minHeight: 200, maxHeight: 400)
            }
        }
    }

    // MARK: - Circulation Results

    private var circulationResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.circulationSteps.isEmpty {
                Text("No results available")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(viewModel.circulationSteps.count) steps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Table(viewModel.circulationSteps) {
                    TableColumn("Step") { step in
                        Text("\(step.stepIndex)")
                    }
                    .width(min: 40, max: 60)

                    TableColumn("Pumped (m\u{00B3})") { step in
                        Text(String(format: "%.2f", step.volumePumped_m3))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("ESD (kg/m\u{00B3})") { step in
                        Text(String(format: "%.1f", step.ESDAtControl_kgpm3))
                    }
                    .width(min: 80, max: 100)

                    TableColumn("SABP (kPa)") { step in
                        Text(String(format: "%.0f", step.requiredSABP_kPa))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("Description") { step in
                        Text(step.description)
                    }
                    .width(min: 100)
                }
                .frame(minHeight: 200, maxHeight: 400)
            }
        }
    }

    // MARK: - Step Slider

    private func stepSlider(count: Int) -> some View {
        HStack(spacing: 4) {
            Text("Step: \(viewModel.selectedStepIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: $viewModel.stepSlider,
                in: 0...Double(max(0, count - 1)),
                step: 1
            )
            .frame(width: 120)
            .onChange(of: viewModel.stepSlider) {
                viewModel.updateFromSlider()
            }
        }
    }
}
