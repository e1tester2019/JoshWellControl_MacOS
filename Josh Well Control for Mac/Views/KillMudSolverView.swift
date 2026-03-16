//
//  KillMudSolverView.swift
//  Josh Well Control for Mac
//
//  Kill mud calculator UI — computes pipe kill density analytically,
//  then shows annulus kill options at 100%/75%/50%/25% fill fractions,
//  each validated with a NumericalTripModel run.
//

import SwiftUI

struct KillMudSolverView: View {
    var project: ProjectState
    var startMD_m: Double
    var endMD_m: Double
    var controlMD_m: Double
    var targetESD_kgpm3: Double
    var baseMudDensity_kgpm3: Double
    var baseMudPV_cP: Double
    var baseMudYP_Pa: Double
    var crackFloat_kPa: Double
    var tripSpeed_m_per_s: Double
    var eccentricityFactor: Double
    var step_m: Double
    var onApply: (KillMudSolverService.SolverResult) -> Void

    @State private var porePressureESD: Double = 0
    @State private var fracGradientESD: Double = 0
    @State private var sweepStart: Double = 1500
    @State private var sweepEnd: Double = 1700
    @State private var sweepStep: Double = 10
    @State private var geometry: KillMudSolverService.SolverGeometry?
    @State private var results: [KillMudSolverService.SolverResult] = []
    @State private var isRunning = false
    @State private var selectedResultID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kill Mud Calculator")
                .font(.title2.bold())

            instructionsSection

            Divider()

            inputsSection

            Divider()

            if isRunning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Validating candidates\u{2026}")
                        .foregroundStyle(.secondary)
                }
            } else if let geom = geometry {
                geometrySection(geom)
                Divider()
                resultsSection
            }

            Spacer()

            buttonsSection
        }
        .padding()
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            if porePressureESD == 0 {
                porePressureESD = targetESD_kgpm3
            }
            if fracGradientESD == 0 {
                fracGradientESD = targetESD_kgpm3 + 100
            }
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pipe kill \u{03C1} = target ESD + crack float / (g \u{00D7} TVD). Pipe volume fills string to heel.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Baseline sim with pipe kill mud determines remaining SABP. Annulus \u{03C1} = base MW + SABP / (backfill TVD \u{00D7} g), validated with a full trip simulation.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Inputs

    private var inputsSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Pore Pressure ESD (kg/m\u{00B3}):")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: $porePressureESD, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            GridRow {
                Text("Frac Gradient ESD (kg/m\u{00B3}):")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: $fracGradientESD, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            GridRow {
                Text("Target ESD (kg/m\u{00B3}):")
                    .frame(width: 200, alignment: .trailing)
                Text(String(format: "%.1f", targetESD_kgpm3))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GridRow {
                Text("Control MD (m):")
                    .frame(width: 200, alignment: .trailing)
                Text(String(format: "%.0f", controlMD_m))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GridRow {
                Text("Trip Range:")
                    .frame(width: 200, alignment: .trailing)
                Text("\(String(format: "%.0f", startMD_m)) \u{2192} \(String(format: "%.0f", endMD_m)) m")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Divider()

            GridRow {
                Text("Ann \u{03C1} Sweep Start (kg/m\u{00B3}):")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: $sweepStart, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            GridRow {
                Text("Ann \u{03C1} Sweep End (kg/m\u{00B3}):")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: $sweepEnd, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            GridRow {
                Text("Sweep Step (kg/m\u{00B3}):")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: $sweepStep, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        }
    }

    // MARK: - Geometry Summary

    private func geometrySection(_ geom: KillMudSolverService.SolverGeometry) -> some View {
        let g = 0.00981
        let killPressure = (targetESD_kgpm3 - baseMudDensity_kgpm3) * geom.bitTVD_m * g
        let additionalPressure = killPressure + crackFloat_kPa
        let floatMW = geom.bitTVD_m > 0 ? crackFloat_kPa / (g * geom.bitTVD_m) : 0
        let killMWDiff = targetESD_kgpm3 - baseMudDensity_kgpm3

        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            // --- Well geometry ---
            GridRow {
                Text("Bit TVD:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f m", geom.bitTVD_m))
                    .monospacedDigit()
            }
            GridRow {
                Text("Control TVD:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f m", geom.controlTVD_m))
                    .monospacedDigit()
            }
            GridRow {
                Text("Heel MD:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f m", geom.heelMD_m))
                    .monospacedDigit()
            }

            Divider()

            // --- Pipe kill breakdown ---
            GridRow {
                Text("Kill Pressure (target\u{2212}base)\u{00D7}TVD\u{00D7}g:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kPa", killPressure))
                    .monospacedDigit()
            }
            GridRow {
                Text("Crack Float Pressure:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kPa", crackFloat_kPa))
                    .monospacedDigit()
            }
            GridRow {
                Text("Additional (kill + float):")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kPa", additionalPressure))
                    .monospacedDigit()
            }
            GridRow {
                Text("Kill MW Diff (target\u{2212}base):")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kg/m\u{00B3}", killMWDiff))
                    .monospacedDigit()
            }
            GridRow {
                Text("Float MW (crack float / g / TVD):")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kg/m\u{00B3}", floatMW))
                    .monospacedDigit()
            }
            GridRow {
                Text("Pipe Kill \u{03C1} (target + diff + float):")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kg/m\u{00B3}", geom.pipeDensity_kgpm3))
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            GridRow {
                Text("Pipe Volume (to \(String(format: "%.0f", geom.heelMD_m)) m):")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f m\u{00B3}", geom.pipeVolume_m3))
                    .monospacedDigit()
            }
            if geom.slugDrop_m3 > 0.01 {
                GridRow {
                    Text("Slug Drop (U-tube drain):")
                        .frame(width: 200, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f m\u{00B3}", geom.slugDrop_m3))
                        .monospacedDigit()
                }
            }

            Divider()

            // --- Annulus side (mass balance) ---
            GridRow {
                Text("Steel Displacement:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f m\u{00B3}", geom.steelDisplacement_m3))
                    .monospacedDigit()
            }
            GridRow {
                Text("Backfill Height:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f m", geom.maxBackfillHeight_m))
                    .monospacedDigit()
            }
            GridRow {
                Text("Bore Vol to Control:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f m\u{00B3}", geom.boreVolToControl_m3))
                    .monospacedDigit()
            }
            GridRow {
                Text("Avg \u{03C1} at Control (mass bal):")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kg/m\u{00B3}", geom.avgDensityAtControl_kgpm3))
                    .monospacedDigit()
            }
            GridRow {
                Text("Total Kill Pressure:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kPa", geom.totalKillPressure_kPa))
                    .monospacedDigit()
            }
            GridRow {
                Text("Remaining for Backfill:")
                    .frame(width: 200, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f kPa", geom.remainingPressure_kPa))
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
        }
        .font(.callout)
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Density Sweep Results")
                .font(.headline)

            Table(results, selection: $selectedResultID) {
                TableColumn("Ann \u{03C1} (kg/m\u{00B3})") { r in
                    Text(String(format: "%.0f", r.annulusKillDensity_kgpm3))
                        .monospacedDigit()
                }
                .width(min: 80, max: 110)

                TableColumn("Kill Depth (m)") { r in
                    Text(String(format: "%.0f", r.sustainedKillDepth_m))
                        .monospacedDigit()
                }
                .width(min: 80, max: 110)

                TableColumn("Max ESD") { r in
                    Text(String(format: "%.1f", r.maxESDAtControl_kgpm3))
                        .monospacedDigit()
                        .foregroundStyle(r.maxESDAtControl_kgpm3 > fracGradientESD ? .red :
                                         r.maxESDAtControl_kgpm3 > targetESD_kgpm3 + 15 ? .orange : .primary)
                }
                .width(min: 70, max: 90)

                TableColumn("Max SABP (kPa)") { r in
                    Text(String(format: "%.0f", r.maxSABP_kPa))
                        .monospacedDigit()
                }
                .width(min: 80, max: 110)

                TableColumn("") { r in
                    HStack(spacing: 4) {
                        if !r.feasible {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .help("Exceeds frac gradient or below pore pressure")
                        }
                        if r.relived {
                            Image(systemName: "arrow.uturn.up")
                                .foregroundStyle(.orange)
                                .help("Well re-lives after initial kill")
                        }
                        if r.feasible && !r.relived {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .width(min: 30, max: 50)
            }
            .frame(minHeight: 140, maxHeight: 260)
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        HStack {
            Button("Calculate") {
                runSolver()
            }
            .disabled(isRunning || porePressureESD <= 0 || fracGradientESD <= 0)
            .keyboardShortcut(.return, modifiers: .command)

            Spacer()

            if !results.isEmpty {
                Button("Export Kill Sheet") {
                    exportKillSheet()
                }
            }

            if let selectedID = selectedResultID,
               let selected = results.first(where: { $0.id == selectedID }) {
                Button("Apply Selected") {
                    onApply(selected)
                    dismiss()
                }
            }

            Button("Close") {
                dismiss()
            }
        }
    }

    // MARK: - Run

    private func runSolver() {
        isRunning = true
        results = []
        geometry = nil

        let snapshot = NumericalTripModel.ProjectSnapshot(from: project)

        let solverInput = KillMudSolverService.SolverInput(
            annulusSections: project.annulus ?? [],
            drillStringSections: project.drillString ?? [],
            surveys: project.surveys ?? [],
            projectSnapshot: snapshot,
            startMD_m: startMD_m,
            endMD_m: endMD_m,
            controlMD_m: controlMD_m,
            targetESD_kgpm3: targetESD_kgpm3,
            crackFloat_kPa: crackFloat_kPa,
            tripSpeed_m_per_s: tripSpeed_m_per_s,
            eccentricityFactor: eccentricityFactor,
            step_m: step_m,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            baseMudPV_cP: baseMudPV_cP,
            baseMudYP_Pa: baseMudYP_Pa,
            porePressureESD_kgpm3: porePressureESD,
            fracGradientESD_kgpm3: fracGradientESD,
            sweepStartDensity_kgpm3: sweepStart,
            sweepEndDensity_kgpm3: sweepEnd,
            sweepStep_kgpm3: sweepStep
        )

        Task.detached(priority: .userInitiated) {
            let (geom, solverResults) = await KillMudSolverService.solve(input: solverInput)
            await MainActor.run {
                geometry = geom
                results = solverResults
                isRunning = false
            }
        }
    }

    // MARK: - Export

    private func exportKillSheet() {
        guard let geom = geometry else { return }
        let g = 0.00981
        let killPressure = (targetESD_kgpm3 - baseMudDensity_kgpm3) * geom.bitTVD_m * g
        let reportData = KillMudReportData(
            wellName: project.name,
            generatedDate: Date(),
            bitMD_m: startMD_m,
            bitTVD_m: geom.bitTVD_m,
            controlMD_m: controlMD_m,
            controlTVD_m: geom.controlTVD_m,
            heelMD_m: geom.heelMD_m,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            targetESD_kgpm3: targetESD_kgpm3,
            porePressureESD_kgpm3: porePressureESD,
            fracGradientESD_kgpm3: fracGradientESD,
            crackFloat_kPa: crackFloat_kPa,
            geometry: geom,
            results: results,
            killPressure_kPa: killPressure,
            additionalPressure_kPa: killPressure + crackFloat_kPa,
            killMWDiff_kgpm3: targetESD_kgpm3 - baseMudDensity_kgpm3,
            floatMW_kgpm3: geom.bitTVD_m > 0 ? crackFloat_kPa / (g * geom.bitTVD_m) : 0
        )

        let html = KillMudHTMLGenerator.shared.generateHTML(for: reportData)
        let wellName = project.name.replacingOccurrences(of: " ", with: "_")
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        Task {
            await FileService.shared.saveTextFile(
                text: html,
                defaultName: "KillSheet_\(wellName)_\(dateStr).html",
                allowedFileTypes: ["html"]
            )
        }
    }
}
