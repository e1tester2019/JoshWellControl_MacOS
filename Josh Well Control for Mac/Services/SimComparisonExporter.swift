//
//  SimComparisonExporter.swift
//  Josh Well Control for Mac
//
//  Tab-separated columnar export of simulation results for diffing
//  against the Rust SuperSimulation app.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct SimComparisonExporter {

    // MARK: - Rounding helpers

    private static func d2(_ v: Double) -> String { String(format: "%.2f", v) }
    private static func d4(_ v: Double) -> String { String(format: "%.4f", v) }
    private static func yn(_ v: Bool) -> String { v ? "YES" : "NO" }

    private static let tab = "\t"

    // MARK: - Trip-Out Export

    static func exportTripOut(steps: [NumericalTripModel.TripStep], activeMW: Double) -> String {
        guard let first = steps.first, let last = steps.last else { return "" }

        var lines: [String] = []

        // Header block
        lines.append("# App: JoshWellControl_MacOS (Swift)")
        lines.append("# SimType: TripOut")
        lines.append("# Date: \(isoDate())")
        lines.append("# BitDepthStart_m: \(d2(first.bitMD_m))")
        lines.append("# BitDepthEnd_m: \(d2(last.bitMD_m))")
        lines.append("# StepCount: \(steps.count)")
        lines.append("# ActiveMW_kgpm3: \(d2(activeMW))")
        lines.append("# --- begin data ---")

        // Column header
        let header = [
            "BitMD_m", "BitTVD_m", "SABP_kPa", "SABP_Raw_kPa",
            "ESD_TD", "ESD_Bit", "ESD_Control",
            "BackfillRem_m3", "SwabDrop_kPa", "SABP_Dyn_kPa",
            "FloatState", "StepBackfill_m3", "CumBackfill_m3",
            "ExpFillClosed_m3", "ExpFillOpen_m3",
            "SlugContrib_m3", "CumSlugContrib_m3",
            "PitGain_m3", "CumPitGain_m3",
            "TankDelta_m3", "CumTankDelta_m3"
        ].joined(separator: tab)
        lines.append(header)

        // Data rows
        for s in steps {
            let row = [
                d2(s.bitMD_m),
                d2(s.bitTVD_m),
                d2(s.SABP_kPa),
                d2(s.SABP_kPa_Raw),
                d2(s.ESDatTD_kgpm3),
                d2(s.ESDatBit_kgpm3),
                d2(s.ESDatControl_kgpm3),
                d4(s.backfillRemaining_m3),
                d2(s.swabDropToBit_kPa),
                d2(s.SABP_Dynamic_kPa),
                s.floatState,
                d4(s.stepBackfill_m3),
                d4(s.cumulativeBackfill_m3),
                d4(s.expectedFillIfClosed_m3),
                d4(s.expectedFillIfOpen_m3),
                d4(s.slugContribution_m3),
                d4(s.cumulativeSlugContribution_m3),
                d4(s.pitGain_m3),
                d4(s.cumulativePitGain_m3),
                d4(s.surfaceTankDelta_m3),
                d4(s.cumulativeSurfaceTankDelta_m3)
            ].joined(separator: tab)
            lines.append(row)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Trip-In Export

    static func exportTripIn(steps: [TripInService.TripInStepResult], activeMW: Double) -> String {
        guard let first = steps.first, let last = steps.last else { return "" }

        var lines: [String] = []

        // Header block
        lines.append("# App: JoshWellControl_MacOS (Swift)")
        lines.append("# SimType: TripIn")
        lines.append("# Date: \(isoDate())")
        lines.append("# BitDepthStart_m: \(d2(first.bitMD_m))")
        lines.append("# BitDepthEnd_m: \(d2(last.bitMD_m))")
        lines.append("# StepCount: \(steps.count)")
        lines.append("# ActiveMW_kgpm3: \(d2(activeMW))")
        lines.append("# --- begin data ---")

        // Column header
        let header = [
            "BitMD_m", "BitTVD_m", "StepFill_m3", "CumFill_m3",
            "ExpFillClosed_m3", "ExpFillOpen_m3",
            "StepDispReturns_m3", "CumDispReturns_m3",
            "ESD_Control", "ESD_Bit",
            "ChokePressure_kPa", "IsBelowTarget",
            "DiffPressBot_kPa", "AnnPressBot_kPa", "StringPressBot_kPa",
            "FloatState", "SurgePressure_kPa", "SurgeECD", "DynESD_Control"
        ].joined(separator: tab)
        lines.append(header)

        // Data rows
        for s in steps {
            let row = [
                d2(s.bitMD_m),
                d2(s.bitTVD_m),
                d4(s.stepFillVolume_m3),
                d4(s.cumulativeFillVolume_m3),
                d4(s.expectedFillClosed_m3),
                d4(s.expectedFillOpen_m3),
                d4(s.stepDisplacementReturns_m3),
                d4(s.cumulativeDisplacementReturns_m3),
                d2(s.ESDAtControl_kgpm3),
                d2(s.ESDAtBit_kgpm3),
                d2(s.requiredChokePressure_kPa),
                yn(s.isBelowTarget),
                d2(s.differentialPressureAtBottom_kPa),
                d2(s.annulusPressureAtBit_kPa),
                d2(s.stringPressureAtBit_kPa),
                s.floatState,
                d2(s.surgePressure_kPa),
                d2(s.surgeECD_kgm3),
                d2(s.dynamicESDAtControl_kgpm3)
            ].joined(separator: tab)
            lines.append(row)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - SuperSim Density-Out Export
    //
    // Bit-depth-indexed flowline-density time-series across the full SuperSim
    // operation chain, intended for diffing against actual rig data (Pason).
    //
    // Flowline density per step is the topmost parcel of the annulus column
    // (smallest topMD in layersAnnulus). CumExitTotal_m3 grows only when mud
    // is actually leaving the flowline:
    //   - TripIn       → steel-displacement returns (Δ cumulativeDisplacementReturns_m3)
    //   - Circulate    → pump volume (Δ volumePumped_m3)
    //   - TripOut/Ream → 0 (backfill / not actively returning)
    // Density is still logged for the non-returning ops so the trace is
    // continuous and the annulus column at each bit depth is visible.

    static func exportSuperSimDensityOut(reportData: SuperSimReportData) -> String {
        var lines: [String] = []

        // Header block
        lines.append("# App: JoshWellControl_MacOS (Swift)")
        lines.append("# SimType: SuperSimDensityOut")
        lines.append("# Date: \(isoDate())")
        lines.append("# Well: \(reportData.wellName)")
        lines.append("# Project: \(reportData.projectName)")
        lines.append("# OperationCount: \(reportData.operations.count)")
        lines.append("# Note: CumExitTotal_m3 grows only on TripIn (steel disp.) and Circulate (pump). Trip/Ream-Out rows log density for context only.")
        lines.append("# --- begin data ---")

        let header = [
            "OpIdx", "OpType", "OpLabel", "StepIdx", "GlobalStep",
            "BitMD_m", "CumPumpedInOp_m3", "CumExitTotal_m3",
            "FlowlineDensity_kgpm3", "PumpRate_m3pmin", "IsReturningFlow"
        ].joined(separator: tab)
        lines.append(header)

        var cumExitTotal: Double = 0
        var globalStep: Int = 0

        for op in reportData.operations {
            let opIdx = op.index
            let opType = op.type.rawValue.replacingOccurrences(of: " ", with: "")
            let opLabel = sanitizeLabel(op.label)

            switch op.type {
            case .tripOut:
                for (i, step) in (op.tripOutSteps ?? []).enumerated() {
                    globalStep += 1
                    let rho = topAnnulusDensity(step.layersAnnulus)
                    lines.append([
                        "\(opIdx)", opType, opLabel,
                        "\(i + 1)", "\(globalStep)",
                        d2(step.bitMD_m),
                        d4(0),
                        d4(cumExitTotal),
                        d2(rho),
                        d4(0),
                        yn(false)
                    ].joined(separator: tab))
                }

            case .tripIn:
                var prevReturns: Double = 0
                for (i, step) in (op.tripInSteps ?? []).enumerated() {
                    globalStep += 1
                    let stepReturns = max(0, step.cumulativeDisplacementReturns_m3 - prevReturns)
                    prevReturns = step.cumulativeDisplacementReturns_m3
                    cumExitTotal += stepReturns
                    let rho = topAnnulusDensity(step.layersAnnulus)
                    lines.append([
                        "\(opIdx)", opType, opLabel,
                        "\(i + 1)", "\(globalStep)",
                        d2(step.bitMD_m),
                        d4(0),
                        d4(cumExitTotal),
                        d2(rho),
                        d4(0),
                        yn(true)
                    ].joined(separator: tab))
                }

            case .circulate:
                var prevPumped: Double = 0
                for (i, step) in (op.circulationSteps ?? []).enumerated() {
                    globalStep += 1
                    let stepPumped = max(0, step.volumePumped_m3 - prevPumped)
                    prevPumped = step.volumePumped_m3
                    cumExitTotal += stepPumped
                    let rho = topAnnulusDensity(step.layersAnnulus)
                    lines.append([
                        "\(opIdx)", opType, opLabel,
                        "\(i + 1)", "\(globalStep)",
                        d2(step.bitMD_m),
                        d4(step.volumePumped_m3),
                        d4(cumExitTotal),
                        d2(rho),
                        d4(step.pumpRate_m3perMin),
                        yn(step.pumpRate_m3perMin > 0)
                    ].joined(separator: tab))
                }

            case .reamOut:
                for (i, step) in (op.reamOutSteps ?? []).enumerated() {
                    globalStep += 1
                    let rho = topAnnulusDensity(step.layersAnnulus)
                    lines.append([
                        "\(opIdx)", opType, opLabel,
                        "\(i + 1)", "\(globalStep)",
                        d2(step.bitMD_m),
                        d4(0),
                        d4(cumExitTotal),
                        d2(rho),
                        d4(step.pumpRate_m3perMin),
                        yn(false)
                    ].joined(separator: tab))
                }

            case .reamIn:
                for (i, step) in (op.reamInSteps ?? []).enumerated() {
                    globalStep += 1
                    let rho = topAnnulusDensity(step.layersAnnulus)
                    lines.append([
                        "\(opIdx)", opType, opLabel,
                        "\(i + 1)", "\(globalStep)",
                        d2(step.bitMD_m),
                        d4(0),
                        d4(cumExitTotal),
                        d2(rho),
                        d4(step.pumpRate_m3perMin),
                        yn(step.pumpRate_m3perMin > 0)
                    ].joined(separator: tab))
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func topAnnulusDensity(_ layers: [SuperSimReportData.LayerData]) -> Double {
        guard !layers.isEmpty else { return 0 }
        return layers.min(by: { $0.topMD < $1.topMD })?.rho_kgpm3 ?? 0
    }

    private static func sanitizeLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ")
         .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Save to File

    @MainActor
    static func saveToFile(content: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Private

    private static func isoDate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date())
    }
}
