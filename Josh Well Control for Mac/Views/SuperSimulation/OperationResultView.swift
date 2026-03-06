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
            case .reamOut:
                reamOutResults
            case .reamIn:
                reamInResults
            }
        }
    }

    // MARK: - Formatters

    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func format2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func format3(_ v: Double) -> String { String(format: "%.3f", v) }

    // MARK: - Metric Pill (compact labeled value)

    private func metricPill(_ label: String, _ value: String, _ unit: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            HStack(spacing: 1) {
                Text(value)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(highlight ? .orange : .primary)
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                #if os(iOS)
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.tripOutSteps.enumerated()), id: \.element.id) { idx, step in
                        tripOutStepRow(step, index: idx)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(idx == viewModel.selectedStepIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedStepIndex = idx
                                viewModel.stepSlider = Double(idx)
                                viewModel.updateFromSlider()
                            }
                        Divider().padding(.leading)
                    }
                }
                #else
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

                    TableColumn("Pickup (kDaN)") { step in
                        if let v = step.pickupHookLoad_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Slack-off (kDaN)") { step in
                        if let v = step.slackOffHookLoad_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Free (kDaN)") { step in
                        if let v = step.freeHangingWeight_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)
                }
                .frame(minHeight: 200, maxHeight: 400)
                #endif
            }
        }
    }

    #if os(iOS)
    private func tripOutStepRow(_ step: NumericalTripModel.TripStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MD: \(format0(step.bitMD_m))m")
                    .font(.subheadline.bold())
                Text("TVD: \(format0(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                metricPill("SABP", format0(step.SABP_kPa), "kPa")
                metricPill("Dyn SABP", format0(step.SABP_Dynamic_kPa), "kPa")
                metricPill("ESD@TD", format1(step.ESDatTD_kgpm3), "kg/m\u{00B3}")
                metricPill("ESD@Ctrl", format1(step.ESDatControl_kgpm3), "kg/m\u{00B3}")
            }

            HStack(spacing: 0) {
                metricPill("DP Wet", format3(step.expectedFillIfClosed_m3), "m\u{00B3}")
                metricPill("Fill", format3(step.stepBackfill_m3), "m\u{00B3}")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Float")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(step.floatState)
                        .font(.caption2)
                        .foregroundStyle(step.floatState.contains("OPEN") ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                metricPill("Backfill", format2(step.backfillRemaining_m3), "m\u{00B3}")
            }

            if let pickup = step.pickupHookLoad_kN, let slackOff = step.slackOffHookLoad_kN {
                HStack(spacing: 0) {
                    metricPill("Pickup", format1(pickup / 10.0), "kDaN")
                    metricPill("Slack-off", format1(slackOff / 10.0), "kDaN")
                    if let free = step.freeHangingWeight_kN {
                        metricPill("Free", format1(free / 10.0), "kDaN")
                    }
                    if let torque = step.surfaceTorque_kNm {
                        metricPill("Torque", String(format: "%.0f", torque * 737.5621), "ft·lbs")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    #endif

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

                #if os(iOS)
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.tripInSteps.enumerated()), id: \.element.id) { idx, step in
                        tripInStepRow(step, index: idx)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(idx == viewModel.selectedStepIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedStepIndex = idx
                                viewModel.stepSlider = Double(idx)
                                viewModel.updateFromSlider()
                            }
                        Divider().padding(.leading)
                    }
                }
                #else
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

                    TableColumn("Pickup (kDaN)") { step in
                        if let v = step.pickupHookLoad_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Slack-off (kDaN)") { step in
                        if let v = step.slackOffHookLoad_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)
                }
                .frame(minHeight: 200, maxHeight: 400)
                #endif
            }
        }
    }

    #if os(iOS)
    private func tripInStepRow(_ step: TripInService.TripInStepResult, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MD: \(format0(step.bitMD_m))m")
                    .font(.subheadline.bold())
                Text("TVD: \(format0(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if step.isBelowTarget {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            HStack(spacing: 0) {
                metricPill("Fill", format3(step.stepFillVolume_m3), "m\u{00B3}")
                metricPill("Cum", format3(step.cumulativeFillVolume_m3), "m\u{00B3}")
                metricPill("ESD", format1(step.ESDAtControl_kgpm3), "kg/m\u{00B3}", highlight: step.isBelowTarget)
                metricPill("Choke", format0(step.requiredChokePressure_kPa), "kPa")
            }

            if step.surgePressure_kPa > 0 {
                HStack(spacing: 0) {
                    metricPill("Surge", format0(step.surgePressure_kPa), "kPa")
                    metricPill("Dyn ESD", format1(step.dynamicESDAtControl_kgpm3), "kg/m\u{00B3}")
                }
            }

            HStack(spacing: 0) {
                metricPill("Disp", format3(step.cumulativeDisplacementReturns_m3), "m\u{00B3}")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Float")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(step.floatState)
                        .font(.caption2)
                        .foregroundStyle(step.floatState.contains("OPEN") ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                metricPill("\u{0394}P", format0(step.differentialPressureAtBottom_kPa), "kPa")
            }

            if let pickup = step.pickupHookLoad_kN, let slackOff = step.slackOffHookLoad_kN {
                HStack(spacing: 0) {
                    metricPill("Pickup", format1(pickup / 10.0), "kDaN")
                    metricPill("Slack-off", format1(slackOff / 10.0), "kDaN")
                    if let free = step.freeHangingWeight_kN {
                        metricPill("Free", format1(free / 10.0), "kDaN")
                    }
                    if let torque = step.surfaceTorque_kNm {
                        metricPill("Torque", String(format: "%.0f", torque * 737.5621), "ft·lbs")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    #endif

    // MARK: - Circulation Results

    private var circulationResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.circulationSteps.isEmpty {
                Text("No results available")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(viewModel.circulationSteps.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepSlider(count: viewModel.circulationSteps.count)
                }

                #if os(iOS)
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.circulationSteps.enumerated()), id: \.element.id) { idx, step in
                        circulationStepRow(step, index: idx)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(idx == viewModel.selectedStepIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedStepIndex = idx
                                viewModel.stepSlider = Double(idx)
                                viewModel.updateFromSlider()
                            }
                        Divider().padding(.leading)
                    }
                }
                #else
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

                    TableColumn("Pickup (kDaN)") { step in
                        if let v = step.pickupHookLoad_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Slack-off (kDaN)") { step in
                        if let v = step.slackOffHookLoad_kN {
                            Text(String(format: "%.1f", v / 10.0))
                        }
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Description") { step in
                        Text(step.description)
                    }
                    .width(min: 100)
                }
                .frame(minHeight: 200, maxHeight: 400)
                #endif
            }
        }
    }

    #if os(iOS)
    private func circulationStepRow(_ step: CirculationService.CirculateOutStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(step.stepIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(step.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                metricPill("Pumped", format2(step.volumePumped_m3), "m\u{00B3}")
                metricPill("ESD", format1(step.ESDAtControl_kgpm3), "kg/m\u{00B3}")
                metricPill("SABP", format0(step.requiredSABP_kPa), "kPa")
                metricPill("\u{0394}SABP", format0(step.deltaSABP_kPa), "kPa")
            }

            if let pickup = step.pickupHookLoad_kN, let slackOff = step.slackOffHookLoad_kN {
                HStack(spacing: 0) {
                    metricPill("Pickup", format1(pickup / 10.0), "kDaN")
                    metricPill("Slack-off", format1(slackOff / 10.0), "kDaN")
                    if let free = step.freeHangingWeight_kN {
                        metricPill("Free", format1(free / 10.0), "kDaN")
                    }
                }
            }

            if step.pumpRate_m3perMin > 0 || step.apl_kPa > 0 {
                HStack(spacing: 0) {
                    metricPill("Rate", format2(step.pumpRate_m3perMin), "m\u{00B3}/min")
                    metricPill("APL", format0(step.apl_kPa), "kPa")
                }
            }
        }
        .padding(.vertical, 2)
    }
    #endif

    // MARK: - Ream Out Results

    private var reamOutResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.reamOutSteps.isEmpty {
                Text("No results available")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(viewModel.reamOutSteps.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepSlider(count: viewModel.reamOutSteps.count)
                }

                #if os(iOS)
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.reamOutSteps.enumerated()), id: \.element.id) { idx, step in
                        reamOutStepRow(step, index: idx)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(idx == viewModel.selectedStepIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedStepIndex = idx
                                viewModel.stepSlider = Double(idx)
                                viewModel.updateFromSlider()
                            }
                        Divider().padding(.leading)
                    }
                }
                #else
                Table(viewModel.reamOutSteps) {
                    TableColumn("MD (m)") { step in
                        Text(String(format: "%.0f", step.bitMD_m))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("SABP Static") { step in
                        Text(String(format: "%.0f", step.SABP_kPa))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("Swab") { step in
                        Text(String(format: "%.0f", step.swab_kPa))
                    }
                    .width(min: 50, max: 70)

                    TableColumn("APL") { step in
                        Text(String(format: "%.0f", step.apl_kPa))
                    }
                    .width(min: 50, max: 70)

                    TableColumn("SABP Dyn") { step in
                        Text(String(format: "%.0f", step.SABP_Dynamic_kPa))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("ESD") { step in
                        Text(String(format: "%.1f", step.ESDatTD_kgpm3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("ECD") { step in
                        Text(String(format: "%.1f", step.ECD_kgpm3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Rate") { step in
                        Text(String(format: "%.2f", step.pumpRate_m3perMin))
                    }
                    .width(min: 50, max: 70)

                    TableColumn("Fill (m\u{00B3})") { step in
                        Text(String(format: "%.2f", step.cumulativeBackfill_m3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Float") { step in
                        Text(step.floatState)
                    }
                    .width(min: 60, max: 90)
                }
                .frame(minHeight: 200, maxHeight: 400)
                #endif
            }
        }
    }

    #if os(iOS)
    private func reamOutStepRow(_ step: ReamOutStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MD: \(format0(step.bitMD_m))m")
                    .font(.subheadline.bold())
                Text("TVD: \(format0(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                metricPill("SABP", format0(step.SABP_kPa), "kPa")
                metricPill("Swab", format0(step.swab_kPa), "kPa")
                metricPill("APL", format0(step.apl_kPa), "kPa")
                metricPill("Dyn SABP", format0(step.SABP_Dynamic_kPa), "kPa")
            }

            HStack(spacing: 0) {
                metricPill("ESD", format1(step.ESDatTD_kgpm3), "kg/m\u{00B3}")
                metricPill("ECD", format1(step.ECD_kgpm3), "kg/m\u{00B3}")
                metricPill("Rate", format2(step.pumpRate_m3perMin), "m\u{00B3}/min")
                metricPill("Fill", format2(step.cumulativeBackfill_m3), "m\u{00B3}")
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Float")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(step.floatState)
                        .font(.caption2)
                        .foregroundStyle(step.floatState.contains("OPEN") ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                metricPill("DP Wet", format3(step.expectedFillIfClosed_m3), "m\u{00B3}")
                metricPill("Step Fill", format3(step.stepBackfill_m3), "m\u{00B3}")
            }
        }
        .padding(.vertical, 2)
    }
    #endif

    // MARK: - Ream In Results

    private var reamInResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.reamInSteps.isEmpty {
                Text("No results available")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(viewModel.reamInSteps.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepSlider(count: viewModel.reamInSteps.count)
                }

                #if os(iOS)
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.reamInSteps.enumerated()), id: \.element.id) { idx, step in
                        reamInStepRow(step, index: idx)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(idx == viewModel.selectedStepIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedStepIndex = idx
                                viewModel.stepSlider = Double(idx)
                                viewModel.updateFromSlider()
                            }
                        Divider().padding(.leading)
                    }
                }
                #else
                Table(viewModel.reamInSteps) {
                    TableColumn("MD (m)") { step in
                        Text(String(format: "%.0f", step.bitMD_m))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Choke Static") { step in
                        Text(String(format: "%.0f", step.requiredChokePressure_kPa))
                    }
                    .width(min: 80, max: 100)

                    TableColumn("Surge") { step in
                        Text(String(format: "%.0f", step.surge_kPa))
                    }
                    .width(min: 50, max: 70)

                    TableColumn("APL") { step in
                        Text(String(format: "%.0f", step.apl_kPa))
                    }
                    .width(min: 50, max: 70)

                    TableColumn("Choke Dyn") { step in
                        Text(String(format: "%.0f", step.dynamicChoke_kPa))
                    }
                    .width(min: 70, max: 90)

                    TableColumn("ESD") { step in
                        Text(String(format: "%.1f", step.ESDAtControl_kgpm3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("ECD") { step in
                        Text(String(format: "%.1f", step.ECD_kgpm3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Rate") { step in
                        Text(String(format: "%.2f", step.pumpRate_m3perMin))
                    }
                    .width(min: 50, max: 70)

                    TableColumn("Fill (m\u{00B3})") { step in
                        Text(String(format: "%.2f", step.cumulativeFillVolume_m3))
                    }
                    .width(min: 60, max: 80)

                    TableColumn("Float") { step in
                        Text(step.floatState)
                    }
                    .width(min: 60, max: 90)
                }
                .frame(minHeight: 200, maxHeight: 400)
                #endif
            }
        }
    }

    #if os(iOS)
    private func reamInStepRow(_ step: ReamInStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MD: \(format0(step.bitMD_m))m")
                    .font(.subheadline.bold())
                Text("TVD: \(format0(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                metricPill("Choke", format0(step.requiredChokePressure_kPa), "kPa")
                metricPill("Surge", format0(step.surge_kPa), "kPa")
                metricPill("APL", format0(step.apl_kPa), "kPa")
                metricPill("Dyn Choke", format0(step.dynamicChoke_kPa), "kPa")
            }

            HStack(spacing: 0) {
                metricPill("ESD", format1(step.ESDAtControl_kgpm3), "kg/m\u{00B3}")
                metricPill("ECD", format1(step.ECD_kgpm3), "kg/m\u{00B3}")
                metricPill("Rate", format2(step.pumpRate_m3perMin), "m\u{00B3}/min")
                metricPill("Fill", format2(step.cumulativeFillVolume_m3), "m\u{00B3}")
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Float")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(step.floatState)
                        .font(.caption2)
                        .foregroundStyle(step.floatState.contains("OPEN") ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                metricPill("Disp", format3(step.cumulativeDisplacementReturns_m3), "m\u{00B3}")
            }
        }
        .padding(.vertical, 2)
    }
    #endif

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
