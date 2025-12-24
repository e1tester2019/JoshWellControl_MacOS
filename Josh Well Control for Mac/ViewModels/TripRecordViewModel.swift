//
//  TripRecordViewModel.swift
//  Josh Well Control for Mac
//
//  Created for managing trip recording sessions.
//

import Foundation
import SwiftData
import Observation

/// ViewModel for managing trip recording sessions - comparing field observations to simulation predictions.
@Observable
class TripRecordViewModel {

    // MARK: - Current Record

    /// The trip record being edited/viewed
    var tripRecord: TripRecord?

    /// All steps in the current record, sorted by index
    var steps: [TripRecordStep] {
        tripRecord?.sortedSteps ?? []
    }

    // MARK: - Selection State

    /// Currently selected step index (for slider/visualization sync)
    var selectedIndex: Int = 0

    /// Slider value (mirrors selectedIndex)
    var stepSlider: Double = 0

    /// Currently selected step
    var selectedStep: TripRecordStep? {
        guard steps.indices.contains(selectedIndex) else { return nil }
        return steps[selectedIndex]
    }

    // MARK: - View State

    /// Whether to show variance highlighting in the table
    var showVarianceHighlights: Bool = true

    /// SABP variance threshold for warning (kPa)
    var sabpWarningThreshold_kPa: Double = 50

    /// Backfill variance threshold for warning (%)
    var backfillWarningThreshold_percent: Double = 5.0

    /// Current editing step index (for inline editing)
    var editingStepIndex: Int?

    /// Show details panel
    var showDetails: Bool = false

    /// Visualization mode: simulated, adjusted, or both
    var visualizationMode: VisualizationMode = .simulated

    enum VisualizationMode: String, CaseIterable {
        case simulated = "Simulated"
        case adjusted = "Adjusted"
        case sideBySide = "Side by Side"
    }

    // MARK: - Configuration (from source simulation)

    var shoeMD_m: Double { tripRecord?.shoeMD_m ?? 0 }
    var tdMD_m: Double { tripRecord?.startBitMD_m ?? 0 }
    var endMD_m: Double { tripRecord?.endMD_m ?? 0 }

    // MARK: - Initialization

    init() {}

    /// Load an existing trip record for viewing/editing
    func load(_ record: TripRecord) {
        tripRecord = record
        selectedIndex = 0
        stepSlider = 0
    }

    /// Create a new trip record from a simulation
    func createFromSimulation(_ simulation: TripSimulation, project: ProjectState, context: ModelContext) {
        let record = TripRecord.createFrom(simulation: simulation, project: project)
        context.insert(record)
        tripRecord = record
        selectedIndex = 0
        stepSlider = 0
    }

    /// Clear the current record
    func clear() {
        tripRecord = nil
        selectedIndex = 0
        stepSlider = 0
    }

    // MARK: - Step Selection

    /// Update selection from slider value
    func updateFromSlider() {
        let idx = Int(stepSlider.rounded())
        if idx != selectedIndex && steps.indices.contains(idx) {
            selectedIndex = idx
        }
    }

    /// Update slider from selection
    func updateSliderFromSelection() {
        if Double(selectedIndex) != stepSlider {
            stepSlider = Double(selectedIndex)
        }
    }

    /// Select next step
    func selectNextStep() {
        let next = selectedIndex + 1
        if steps.indices.contains(next) {
            selectedIndex = next
            stepSlider = Double(next)
        }
    }

    /// Select previous step
    func selectPreviousStep() {
        let prev = selectedIndex - 1
        if steps.indices.contains(prev) {
            selectedIndex = prev
            stepSlider = Double(prev)
        }
    }

    // MARK: - Recording Actual Values

    /// Record actual values for a specific step
    func recordActual(at index: Int, backfill: Double?, sabp: Double?, pitChange: Double?, notes: String = "") {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        step.recordActual(backfill: backfill, sabp: sabp, pitChange: pitChange, notes: notes)
        tripRecord?.updateVarianceSummary()
        tripRecord?.updatedAt = .now
    }

    /// Mark a step as skipped
    func skipStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        step.markSkipped()
        tripRecord?.updateVarianceSummary()
        tripRecord?.updatedAt = .now
    }

    /// Clear actual values for a step
    func clearStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        step.clearActual()
        tripRecord?.updateVarianceSummary()
        tripRecord?.updatedAt = .now
    }

    /// Record and advance to next step
    func recordAndAdvance(backfill: Double?, sabp: Double?, pitChange: Double?, notes: String = "") {
        recordActual(at: selectedIndex, backfill: backfill, sabp: sabp, pitChange: pitChange, notes: notes)
        selectNextStep()
    }

    // MARK: - Variance Helpers

    /// Get color for SABP variance
    func sabpVarianceColor(_ variance: Double?) -> VarianceLevel {
        guard let v = variance else { return .none }
        let absV = abs(v)
        if absV <= sabpWarningThreshold_kPa / 2 { return .good }
        if absV <= sabpWarningThreshold_kPa { return .warning }
        return .critical
    }

    /// Get color for backfill variance
    func backfillVarianceColor(_ variancePercent: Double?) -> VarianceLevel {
        guard let v = variancePercent else { return .none }
        let absV = abs(v)
        if absV <= backfillWarningThreshold_percent / 2 { return .good }
        if absV <= backfillWarningThreshold_percent { return .warning }
        return .critical
    }

    enum VarianceLevel {
        case none, good, warning, critical
    }

    // MARK: - Status

    /// Mark the record as complete
    func markComplete() {
        tripRecord?.markComplete()
    }

    /// Unmark the record as complete (return to in progress)
    func unmarkComplete() {
        tripRecord?.unmarkComplete()
    }

    /// Mark the record as cancelled
    func markCancelled() {
        tripRecord?.markCancelled()
    }

    // MARK: - Layer Visualization

    /// Get simulated layer rows for well visualization at the selected step
    func layersForVisualization() -> (annulus: [NumericalTripModel.LayerRow], string: [NumericalTripModel.LayerRow], pocket: [NumericalTripModel.LayerRow]) {
        guard let step = selectedStep else { return ([], [], []) }
        return (
            step.simLayersAnnulus.map { $0.toLayerRow() },
            step.simLayersString.map { $0.toLayerRow() },
            step.simLayersPocket.map { $0.toLayerRow() }
        )
    }

    /// Get adjusted layer rows based on actual backfill variance
    /// Adjusts the annulus top layer depth based on difference between actual and simulated backfill
    func adjustedLayersForVisualization(project: ProjectState) -> (annulus: [NumericalTripModel.LayerRow], string: [NumericalTripModel.LayerRow], pocket: [NumericalTripModel.LayerRow]) {
        guard let step = selectedStep, let record = tripRecord else { return ([], [], []) }

        var annulusLayers = step.simLayersAnnulus.map { $0.toLayerRow() }
        var stringLayers = step.simLayersString.map { $0.toLayerRow() }
        let pocketLayers = step.simLayersPocket.map { $0.toLayerRow() }

        // Calculate backfill variance - how much more or less we pumped than expected
        let backfillVariance_m3 = step.backfillVariance_m3 ?? 0

        // If we have actual backfill data and annulus layers, adjust the top layer
        if step.actualBackfill_m3 != nil && !annulusLayers.isEmpty {
            // Sort annulus layers by MD (top first)
            annulusLayers.sort { $0.topMD < $1.topMD }

            // Find the topmost layer (backfill layer at surface)
            if var topLayer = annulusLayers.first {
                // Negative variance = less backfill = annulus level higher (more fluid at top)
                // Positive variance = more backfill = annulus level lower (less fluid at top)

                // Calculate depth adjustment based on backfill variance and annulus capacity
                // Estimate annulus capacity per meter from the top layer
                let topLayerHeight = abs(topLayer.bottomMD - topLayer.topMD)
                let volumePerMeter = topLayerHeight > 0 ? topLayer.volume_m3 / topLayerHeight : 0.01

                // Depth change = volume variance / capacity per meter
                let depthChange_m = volumePerMeter > 0 ? -backfillVariance_m3 / volumePerMeter : 0

                // Adjust the top layer depth
                let newBottomMD = max(topLayer.topMD + 1, topLayer.bottomMD + depthChange_m)
                let newBottomTVD = project.tvd(of: newBottomMD)

                // Recalculate hydrostatic for adjusted layer
                let newHeight = newBottomTVD - topLayer.topTVD
                let newDeltaHydro = 0.00981 * topLayer.rho_kgpm3 * max(0, newHeight)

                topLayer = NumericalTripModel.LayerRow(
                    side: topLayer.side,
                    topMD: topLayer.topMD,
                    bottomMD: newBottomMD,
                    topTVD: topLayer.topTVD,
                    bottomTVD: newBottomTVD,
                    rho_kgpm3: topLayer.rho_kgpm3,
                    deltaHydroStatic_kPa: newDeltaHydro,
                    volume_m3: topLayer.volume_m3 - backfillVariance_m3,
                    color: NumericalTripModel.ColorRGBA(r: 0.2, g: 0.6, b: 1.0, a: 0.8) // Blue tint for adjusted
                )

                annulusLayers[0] = topLayer
            }
        }

        // Check for potential float crack based on SABP differential
        // If actual SABP is significantly lower than expected, float may have cracked
        if let actualSABP = step.actualSABP_kPa {
            let sabpDiff = step.simSABP_kPa - actualSABP
            let crackThreshold = record.crackFloat_kPa * 0.8 // 80% of crack pressure as warning

            if sabpDiff > crackThreshold && !stringLayers.isEmpty {
                // Float may be cracking - mark string layers to indicate potential slug drainage
                stringLayers = stringLayers.map { layer in
                    var adjusted = layer
                    adjusted = NumericalTripModel.LayerRow(
                        side: layer.side,
                        topMD: layer.topMD,
                        bottomMD: layer.bottomMD,
                        topTVD: layer.topTVD,
                        bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3,
                        deltaHydroStatic_kPa: layer.deltaHydroStatic_kPa,
                        volume_m3: layer.volume_m3,
                        color: NumericalTripModel.ColorRGBA(r: 1.0, g: 0.4, b: 0.2, a: 0.8) // Orange tint for potential slug drain
                    )
                    return adjusted
                }
            }
        }

        return (annulusLayers, stringLayers, pocketLayers)
    }

    /// Calculate actual ESD at control depth using actual SABP and adjusted layers
    func actualESDAtControl(project: ProjectState) -> Double? {
        guard let step = selectedStep, let actualSABP = step.actualSABP_kPa else { return nil }

        let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let candidates = [annMax, dsMax].filter { $0 > 0 }
        let limit = candidates.min()
        let controlMDRaw = max(0.0, shoeMD_m)
        let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
        let controlTVD = project.tvd(of: controlMD)

        guard controlTVD > 0 else { return nil }

        // Get adjusted layers for hydrostatic calculation
        let adjusted = adjustedLayersForVisualization(project: project)
        let annRows = adjusted.annulus.sorted { $0.topTVD < $1.topTVD }

        // Integrate hydrostatic up to control TVD
        var hydroPressure_kPa = 0.0

        for r in annRows {
            if r.topTVD >= controlTVD { break }
            let layerBot = min(r.bottomTVD, controlTVD)
            let seg = max(0, layerBot - r.topTVD)
            if seg > 1e-9 {
                let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                hydroPressure_kPa += r.deltaHydroStatic_kPa * frac
            }
        }

        // Total pressure at control = hydrostatic + actual SABP
        let totalPressure_kPa = hydroPressure_kPa + actualSABP

        // ESD = pressure / (g * TVD)
        let actualESD = totalPressure_kPa / 0.00981 / controlTVD
        return actualESD
    }

    /// Simulated ESD at control depth (for comparison)
    func simulatedESDAtControl(project: ProjectState) -> Double? {
        guard let step = selectedStep else { return nil }

        let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let candidates = [annMax, dsMax].filter { $0 > 0 }
        let limit = candidates.min()
        let controlMDRaw = max(0.0, shoeMD_m)
        let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
        let controlTVD = project.tvd(of: controlMD)

        guard controlTVD > 0 else { return nil }

        let annRows = step.simLayersAnnulus.map { $0.toLayerRow() }.sorted { $0.topTVD < $1.topTVD }

        var hydroPressure_kPa = 0.0
        for r in annRows {
            if r.topTVD >= controlTVD { break }
            let layerBot = min(r.bottomTVD, controlTVD)
            let seg = max(0, layerBot - r.topTVD)
            if seg > 1e-9 {
                let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                hydroPressure_kPa += r.deltaHydroStatic_kPa * frac
            }
        }

        let totalPressure_kPa = hydroPressure_kPa + step.simSABP_kPa
        return totalPressure_kPa / 0.00981 / controlTVD
    }

    /// Text showing both simulated and actual ESD at control
    func esdComparisonText(project: ProjectState) -> String {
        let simESD = simulatedESDAtControl(project: project)
        let actESD = actualESDAtControl(project: project)

        var text = "ESD@Control: "
        if let sim = simESD {
            text += String(format: "Sim %.1f", sim)
        }
        if let act = actESD {
            text += String(format: " | Act %.1f", act)
            if let sim = simESD {
                let diff = act - sim
                text += String(format: " (%+.1f)", diff)
            }
        } else if simESD != nil {
            text += " | Act --"
        }
        text += " kg/m³"
        return text
    }

    /// Check if float may be cracking based on pressure differential
    func floatStatus(project: ProjectState) -> FloatStatus {
        guard let step = selectedStep, let record = tripRecord else { return .unknown }
        guard let actualSABP = step.actualSABP_kPa else { return .unknown }

        let sabpDiff = step.simSABP_kPa - actualSABP

        if sabpDiff > record.crackFloat_kPa {
            return .cracked
        } else if sabpDiff > record.crackFloat_kPa * 0.7 {
            return .nearCrack
        } else if sabpDiff > 0 {
            return .pressureLow
        } else {
            return .normal
        }
    }

    enum FloatStatus {
        case unknown, normal, pressureLow, nearCrack, cracked

        var label: String {
            switch self {
            case .unknown: return "Unknown"
            case .normal: return "Normal"
            case .pressureLow: return "Pressure Low"
            case .nearCrack: return "Near Crack"
            case .cracked: return "Float Cracked?"
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .normal: return "checkmark.circle"
            case .pressureLow: return "arrow.down.circle"
            case .nearCrack: return "exclamationmark.triangle"
            case .cracked: return "exclamationmark.octagon"
            }
        }
    }

    // MARK: - ESD at Control Depth

    /// Calculate ESD at control depth text (matches TripSimulationViewModel pattern)
    func esdAtControlText(project: ProjectState) -> String {
        let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let candidates = [annMax, dsMax].filter { $0 > 0 }
        let limit = candidates.min()
        let controlMDRaw = max(0.0, shoeMD_m)
        let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
        let controlTVD = project.tvd(of: controlMD)

        guard let s = selectedStep else { return "" }

        // Integrate annulus layers up to control TVD
        let annRows = s.simLayersAnnulus.map { $0.toLayerRow() }
        let sorted = annRows.sorted { $0.topTVD < $1.topTVD }

        var pressure_kPa = 0.0
        var remainingP = controlTVD

        for r in sorted {
            if r.topTVD >= controlTVD { break }
            let layerBot = min(r.bottomTVD, controlTVD)
            let seg = max(0, layerBot - r.topTVD)
            if seg > 1e-9 {
                let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                pressure_kPa += r.deltaHydroStatic_kPa * frac
                remainingP -= seg
                if remainingP <= 1e-9 { break }
            }
        }

        let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
        return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }

    // MARK: - Summary Text

    /// Summary text for header
    var summaryText: String {
        guard let record = tripRecord else { return "No record loaded" }
        let total = record.stepCount
        let recorded = record.stepsRecorded
        let skipped = record.stepsSkipped
        let pending = total - recorded - skipped
        return "\(recorded) recorded, \(skipped) skipped, \(pending) pending of \(total)"
    }

    /// Progress percentage
    var progressPercent: Double {
        tripRecord?.progressPercent ?? 0
    }

    /// Average SABP variance text
    var avgSABPVarianceText: String {
        guard let record = tripRecord, record.stepsRecorded > 0 else { return "--" }
        return String(format: "%+.0f kPa", record.avgSABPVariance_kPa)
    }

    /// Average backfill variance text
    var avgBackfillVarianceText: String {
        guard let record = tripRecord, record.stepsRecorded > 0 else { return "--" }
        return String(format: "%+.3f m³", record.avgBackfillVariance_m3)
    }

    // MARK: - Delete Record

    /// Delete the current record from the context
    func deleteRecord(context: ModelContext) {
        guard let record = tripRecord else { return }
        context.delete(record)
        clear()
    }
}

// MARK: - Formatting Helpers

extension TripRecordViewModel {
    func format0(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    func format1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    func format2(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    func format3(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    func formatVariance(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%+.1f", v)
    }

    func formatVariancePercent(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%+.1f%%", v)
    }
}
