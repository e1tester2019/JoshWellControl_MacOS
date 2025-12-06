//
//  CementJobSimulationViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for cement job simulation - tracks fluid movement and actual returns
//

import Foundation
import SwiftUI
import Observation
import SwiftData

@Observable
class CementJobSimulationViewModel {

    // MARK: - State

    private(set) var context: ModelContext?
    private var didBootstrap = false
    var boundProject: ProjectState?
    var boundJob: CementJob?

    // MARK: - Simulation Stages

    struct SimulationStage: Identifiable {
        let id: UUID
        let sourceStage: CementJobStage?
        let name: String
        let stageType: StageType
        let volume_m3: Double
        let color: Color
        let density_kgm3: Double
        let isOperation: Bool
        let operationType: CementJobStage.OperationType?

        // Runtime tracking
        var tankVolumeAfter_m3: Double?
        var notes: String = ""

        enum StageType {
            case preFlush
            case spacer
            case leadCement
            case tailCement
            case displacement
            case mudDisplacement
            case operation
        }
    }

    var stages: [SimulationStage] = []
    var currentStageIndex: Int = 0
    var progress: Double = 0.0 // 0-1 within current stage

    // MARK: - Tank Volume Tracking

    /// Initial mud tank volume at start of job (m³)
    var initialTankVolume_m3: Double = 0.0 {
        didSet { updateExpectedTankVolume() }
    }

    /// Current tank volume reading (m³) - can be overridden by user
    var currentTankVolume_m3: Double = 0.0

    /// Expected tank volume based on 1:1 return ratio
    var expectedTankVolume_m3: Double = 0.0

    /// Whether current tank volume is being auto-tracked (vs user override)
    var isAutoTrackingTankVolume: Bool = true

    /// Tank volume readings at each stage completion (user overrides)
    var tankReadings: [UUID: Double] = [:]

    /// User notes for each stage (keyed by stage ID)
    var stageNotes: [UUID: String] = [:]

    /// Update notes for the current stage
    func updateNotes(_ notes: String, for stageId: UUID) {
        stageNotes[stageId] = notes
    }

    /// Get notes for a stage
    func notes(for stageId: UUID) -> String {
        stageNotes[stageId] ?? ""
    }

    /// Update expected tank volume based on pumped volume
    func updateExpectedTankVolume() {
        expectedTankVolume_m3 = initialTankVolume_m3 + cumulativePumpedVolume_m3
        if isAutoTrackingTankVolume {
            currentTankVolume_m3 = expectedTankVolume_m3
        }
    }

    // MARK: - Computed Return Ratios

    /// Overall return ratio based on total pumped vs total returned
    var overallReturnRatio: Double {
        let totalPumped = cumulativePumpedVolume_m3
        guard totalPumped > 0 else { return 1.0 }
        let totalReturned = actualTotalReturned_m3
        return totalReturned / totalPumped
    }

    /// Total volume pumped up to current stage/progress
    var cumulativePumpedVolume_m3: Double {
        var total = 0.0
        for i in 0..<stages.count {
            if i < currentStageIndex {
                total += stages[i].volume_m3
            } else if i == currentStageIndex {
                total += stages[i].volume_m3 * progress
            }
        }
        return total
    }

    /// Actual total returned based on tank volume change
    var actualTotalReturned_m3: Double {
        return max(0, currentTankVolume_m3 - initialTankVolume_m3)
    }

    /// Expected return (1:1 ratio)
    var expectedReturn_m3: Double {
        return cumulativePumpedVolume_m3
    }

    /// Difference between expected and actual return
    var returnDifference_m3: Double {
        return expectedReturn_m3 - actualTotalReturned_m3
    }

    // MARK: - Fluid Stacks (for visualization)

    struct FluidSegment: Identifiable {
        let id = UUID()
        var topMD_m: Double
        var bottomMD_m: Double
        var topTVD_m: Double = 0
        var bottomTVD_m: Double = 0
        var color: Color
        var name: String
        var density_kgm3: Double
        var isCement: Bool = false
    }

    /// A volume parcel of fluid
    private struct VolumeParcel {
        var volume_m3: Double
        var color: Color
        var name: String
        var density_kgm3: Double
        var isCement: Bool = false
    }

    var stringStack: [FluidSegment] = []
    var annulusStack: [FluidSegment] = []

    /// Total cement volume currently in the annulus (m³)
    var cementReturns_m3: Double = 0.0

    // MARK: - Geometry

    var maxDepth_m: Double = 0
    var floatCollarDepth_m: Double = 0
    var shoeDepth_m: Double = 0

    /// TVD lookup function from surveys
    private var tvdMapper: ((Double) -> Double)?

    /// Get TVD for a given MD
    func tvd(of md: Double) -> Double {
        tvdMapper?(md) ?? md
    }

    // MARK: - Initialization

    init() {}

    func bootstrap(job: CementJob, project: ProjectState, context: ModelContext) {
        guard !didBootstrap else { return }
        self.context = context
        self.boundProject = project
        self.boundJob = job

        // Set up TVD mapper from project surveys
        tvdMapper = { project.tvd(of: $0) }

        // Set geometry
        maxDepth_m = max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
        floatCollarDepth_m = job.floatCollarDepth_m
        shoeDepth_m = job.bottomMD_m

        // Build simulation stages from cement job stages
        buildStages(from: job)

        // Initialize fluid stacks
        updateFluidStacks()

        didBootstrap = true
    }

    // MARK: - Stage Building

    private func buildStages(from job: CementJob) {
        stages.removeAll()

        for stage in job.sortedStages {
            let simStage = SimulationStage(
                id: stage.id,
                sourceStage: stage,
                name: stage.name.isEmpty ? stage.stageType.displayName : stage.name,
                stageType: mapStageType(stage.stageType),
                volume_m3: stage.volume_m3,
                color: stage.color,
                density_kgm3: stage.density_kgm3,
                isOperation: stage.stageType == .operation,
                operationType: stage.operationType
            )
            stages.append(simStage)
        }

        currentStageIndex = 0
        progress = 0
    }

    private func mapStageType(_ type: CementJobStage.StageType) -> SimulationStage.StageType {
        switch type {
        case .preFlush: return .preFlush
        case .spacer: return .spacer
        case .leadCement: return .leadCement
        case .tailCement: return .tailCement
        case .displacement: return .displacement
        case .mudDisplacement: return .mudDisplacement
        case .operation: return .operation
        }
    }

    // MARK: - Navigation

    var currentStage: SimulationStage? {
        guard currentStageIndex >= 0 && currentStageIndex < stages.count else { return nil }
        return stages[currentStageIndex]
    }

    var isAtStart: Bool {
        currentStageIndex == 0 && progress <= 0.0001
    }

    var isAtEnd: Bool {
        currentStageIndex >= stages.count - 1 && progress >= 0.9999
    }

    func nextStage() {
        if progress < 0.9999 {
            progress = 1.0
        } else if currentStageIndex < stages.count - 1 {
            // Record tank reading for completed stage
            if let stage = currentStage {
                tankReadings[stage.id] = currentTankVolume_m3
            }
            currentStageIndex += 1
            progress = 0
            // Reset to auto-tracking for new stage
            isAutoTrackingTankVolume = true
        }
        updateExpectedTankVolume()
        updateFluidStacks()
    }

    func previousStage() {
        if progress > 0.0001 {
            progress = 0
        } else if currentStageIndex > 0 {
            currentStageIndex -= 1
            progress = 1.0
        }
        updateExpectedTankVolume()
        updateFluidStacks()
    }

    func setProgress(_ newProgress: Double) {
        progress = max(0, min(1, newProgress))
        updateExpectedTankVolume()
        updateFluidStacks()
    }

    func jumpToStage(_ index: Int) {
        guard index >= 0 && index < stages.count else { return }
        currentStageIndex = index
        progress = 0
        isAutoTrackingTankVolume = true
        updateExpectedTankVolume()
        updateFluidStacks()
    }

    // MARK: - Tank Volume Recording

    /// Record a user-entered tank volume (overrides auto-tracking)
    func recordTankVolume(_ volume: Double) {
        isAutoTrackingTankVolume = false
        currentTankVolume_m3 = volume
        if let stage = currentStage {
            tankReadings[stage.id] = volume
        }
        // Recalculate annulus based on new return ratio
        updateFluidStacks()
    }

    /// Reset tank volume to expected (resume auto-tracking)
    func resetTankVolumeToExpected() {
        isAutoTrackingTankVolume = true
        currentTankVolume_m3 = expectedTankVolume_m3
        if let stage = currentStage {
            tankReadings.removeValue(forKey: stage.id)
        }
        updateFluidStacks()
    }

    func tankVolumeForStage(_ stageId: UUID) -> Double? {
        return tankReadings[stageId]
    }

    /// Get the return ratio for a specific stage
    func returnRatioForStage(_ index: Int) -> Double? {
        guard index >= 0 && index < stages.count else { return nil }

        // Calculate cumulative pumped up to and including this stage
        var pumpedUpToStage = 0.0
        for i in 0...index {
            pumpedUpToStage += stages[i].volume_m3
        }

        // Get tank reading after this stage
        guard let tankAfter = tankReadings[stages[index].id] else { return nil }

        let returned = tankAfter - initialTankVolume_m3
        guard pumpedUpToStage > 0 else { return nil }

        return returned / pumpedUpToStage
    }

    /// Difference between expected and actual tank volume
    var tankVolumeDifference_m3: Double {
        return currentTankVolume_m3 - expectedTankVolume_m3
    }

    // MARK: - Fluid Stack Calculation

    func updateFluidStacks() {
        guard let project = boundProject, let job = boundJob else { return }

        let geom = ProjectGeometryService(project: project, currentStringBottomMD: shoeDepth_m)
        let activeMud = project.activeMud
        let activeColor = activeMud?.color ?? .gray.opacity(0.35)
        let activeName = activeMud?.name ?? "Mud"
        let activeDensity = activeMud?.density_kgm3 ?? 1200.0

        // String and annulus capacities
        let stringCapacity_m3 = geom.volumeInString_m3(0, floatCollarDepth_m)
        let annulusCapacity_m3 = geom.volumeInAnnulus_m3(0, shoeDepth_m)

        // Initialize string with active mud (ordered shallow -> deep)
        var stringParcels: [VolumeParcel] = [
            VolumeParcel(volume_m3: stringCapacity_m3, color: activeColor, name: activeName, density_kgm3: activeDensity)
        ]

        // Initialize annulus with active mud (ordered deep -> shallow)
        var annulusParcels: [VolumeParcel] = [
            VolumeParcel(volume_m3: annulusCapacity_m3, color: activeColor, name: activeName, density_kgm3: activeDensity)
        ]

        var expelledAtBit: [VolumeParcel] = []
        var overflowAtSurface: [VolumeParcel] = []

        // Collect all pumped volumes in chronological order
        for i in 0..<stages.count {
            let stage = stages[i]
            guard !stage.isOperation else { continue }

            let stagePumped: Double
            if i < currentStageIndex {
                stagePumped = stage.volume_m3
            } else if i == currentStageIndex {
                stagePumped = stage.volume_m3 * progress
            } else {
                stagePumped = 0
            }

            if stagePumped > 0.001 {
                // Check if this is a cement stage
                let isCement = stage.stageType == .leadCement || stage.stageType == .tailCement

                // Push into top of string, collect what exits at bit
                pushToTopAndOverflow(
                    stringParcels: &stringParcels,
                    add: VolumeParcel(volume_m3: stagePumped, color: stage.color, name: stage.name, density_kgm3: stage.density_kgm3, isCement: isCement),
                    capacity_m3: stringCapacity_m3,
                    expelled: &expelledAtBit
                )
            }
        }

        // Push expelled parcels into bottom of annulus
        // Apply return ratio to adjust how much actually enters annulus
        let effectiveReturnRatio = overallReturnRatio
        for parcel in expelledAtBit {
            let adjustedVolume = parcel.volume_m3 * effectiveReturnRatio
            if adjustedVolume > 0.001 {
                pushToBottomAndOverflowTop(
                    annulusParcels: &annulusParcels,
                    add: VolumeParcel(volume_m3: adjustedVolume, color: parcel.color, name: parcel.name, density_kgm3: parcel.density_kgm3, isCement: parcel.isCement),
                    capacity_m3: annulusCapacity_m3,
                    overflowAtSurface: &overflowAtSurface
                )
            }
        }

        // Convert parcel stacks to MD segments
        stringStack = segmentsFromStringParcels(stringParcels, maxDepth: floatCollarDepth_m, geom: geom)
        annulusStack = segmentsFromAnnulusParcels(annulusParcels, maxDepth: shoeDepth_m, geom: geom)

        // Calculate cement returns volume (cement that overflowed at surface - came out of the well)
        cementReturns_m3 = overflowAtSurface.filter { $0.isCement }.reduce(0.0) { $0 + $1.volume_m3 }
    }

    // MARK: - Parcel Pushing Helpers

    private func totalVolume(_ parcels: [VolumeParcel]) -> Double {
        parcels.reduce(0.0) { $0 + max(0.0, $1.volume_m3) }
    }

    /// Push a parcel into the top of the string (surface) and compute overflow from the bottom (bit).
    /// `stringParcels` is ordered shallow (index 0) -> deep (last).
    /// `expelled` is appended in the order it exits the bit.
    private func pushToTopAndOverflow(
        stringParcels: inout [VolumeParcel],
        add: VolumeParcel,
        capacity_m3: Double,
        expelled: inout [VolumeParcel]
    ) {
        let addV = max(0.0, add.volume_m3)
        guard addV > 1e-12 else { return }

        // Add to top (surface)
        stringParcels.insert(VolumeParcel(volume_m3: addV, color: add.color, name: add.name, density_kgm3: add.density_kgm3, isCement: add.isCement), at: 0)

        // Overflow exits at the bottom (bit)
        var overflow = totalVolume(stringParcels) - max(0.0, capacity_m3)
        while overflow > 1e-9, let last = stringParcels.last {
            stringParcels.removeLast()
            let v = max(0.0, last.volume_m3)
            if v <= overflow + 1e-9 {
                expelled.append(last)
                overflow -= v
            } else {
                // Split the bottom parcel: part expelled, remainder stays in the string
                expelled.append(VolumeParcel(volume_m3: overflow, color: last.color, name: last.name, density_kgm3: last.density_kgm3, isCement: last.isCement))
                stringParcels.append(VolumeParcel(volume_m3: v - overflow, color: last.color, name: last.name, density_kgm3: last.density_kgm3, isCement: last.isCement))
                overflow = 0
            }
        }
    }

    /// Push a parcel into the bottom of the annulus (bit) and compute overflow out the top (surface).
    /// `annulusParcels` is ordered deep (index 0, at bit) -> shallow (last, at surface).
    /// `overflowAtSurface` is appended in the order it would leave the surface.
    private func pushToBottomAndOverflowTop(
        annulusParcels: inout [VolumeParcel],
        add: VolumeParcel,
        capacity_m3: Double,
        overflowAtSurface: inout [VolumeParcel]
    ) {
        let addV = max(0.0, add.volume_m3)
        guard addV > 1e-12 else { return }

        // Add to bottom (bit)
        annulusParcels.insert(VolumeParcel(volume_m3: addV, color: add.color, name: add.name, density_kgm3: add.density_kgm3, isCement: add.isCement), at: 0)

        // Overflow leaves at the top (surface)
        var overflow = totalVolume(annulusParcels) - max(0.0, capacity_m3)
        while overflow > 1e-9, let last = annulusParcels.last {
            annulusParcels.removeLast()
            let v = max(0.0, last.volume_m3)
            if v <= overflow + 1e-9 {
                overflowAtSurface.append(last)
                overflow -= v
            } else {
                // Split the top parcel: part overflows, remainder stays in annulus
                overflowAtSurface.append(VolumeParcel(volume_m3: overflow, color: last.color, name: last.name, density_kgm3: last.density_kgm3, isCement: last.isCement))
                annulusParcels.append(VolumeParcel(volume_m3: v - overflow, color: last.color, name: last.name, density_kgm3: last.density_kgm3, isCement: last.isCement))
                overflow = 0
            }
        }
    }

    // MARK: - Parcel to Segment Conversion

    /// Convert shallow->deep string volume parcel stack into MD segments from surface downward.
    private func segmentsFromStringParcels(_ parcels: [VolumeParcel], maxDepth: Double, geom: ProjectGeometryService) -> [FluidSegment] {
        var segments: [FluidSegment] = []
        var currentTop: Double = 0.0

        // Minimum segment height to display (filter artifacts)
        let minSegmentHeight = 0.5

        for parcel in parcels {
            let v = max(0.0, parcel.volume_m3)
            guard v > 1e-12 else { continue }

            let length = geom.lengthForStringVolume_m(currentTop, v)
            guard length > 1e-12 else { continue }

            let bottom = min(currentTop + length, maxDepth)
            if bottom > currentTop + minSegmentHeight {
                var segment = FluidSegment(
                    topMD_m: currentTop,
                    bottomMD_m: bottom,
                    color: parcel.color,
                    name: parcel.name,
                    density_kgm3: parcel.density_kgm3,
                    isCement: parcel.isCement
                )
                segment.topTVD_m = tvd(of: currentTop)
                segment.bottomTVD_m = tvd(of: bottom)
                segments.append(segment)
                currentTop = bottom
            } else {
                // Still advance currentTop even for small segments
                currentTop = bottom
            }

            if currentTop >= maxDepth - 1e-9 { break }
        }

        return segments
    }

    /// Convert deep->shallow annulus volume parcel stack into MD segments from bit upward.
    private func segmentsFromAnnulusParcels(_ parcels: [VolumeParcel], maxDepth: Double, geom: ProjectGeometryService) -> [FluidSegment] {
        var segments: [FluidSegment] = []
        var usedFromBottom: Double = 0.0

        // Minimum segment height to display (filter artifacts)
        let minSegmentHeight = 0.5

        for parcel in parcels {
            let v = max(0.0, parcel.volume_m3)
            guard v > 1e-12 else { continue }

            let length = lengthForAnnulusVolumeFromBottom(volume: v, bottomMD: maxDepth, usedFromBottom: usedFromBottom, geom: geom)
            if length <= 1e-12 { continue }

            let topMD = max(0.0, maxDepth - usedFromBottom - length)
            let botMD = max(0.0, maxDepth - usedFromBottom)

            if botMD > topMD + minSegmentHeight {
                var segment = FluidSegment(
                    topMD_m: topMD,
                    bottomMD_m: botMD,
                    color: parcel.color,
                    name: parcel.name,
                    density_kgm3: parcel.density_kgm3,
                    isCement: parcel.isCement
                )
                segment.topTVD_m = tvd(of: topMD)
                segment.bottomTVD_m = tvd(of: botMD)
                segments.append(segment)
            }
            usedFromBottom += length

            if usedFromBottom >= maxDepth - 1e-9 { break }
        }

        // Sort shallow to deep for display
        return segments.sorted { $0.topMD_m < $1.topMD_m }
    }

    private func lengthForAnnulusVolumeFromBottom(volume: Double, bottomMD: Double, usedFromBottom: Double, geom: ProjectGeometryService) -> Double {
        guard volume > 1e-12 else { return 0 }

        let startMD = max(0, bottomMD - usedFromBottom)
        var lo: Double = 0
        var hi: Double = startMD
        let tol = 1e-6
        var iterations = 0
        let maxIterations = 50

        while (hi - lo) > tol && iterations < maxIterations {
            iterations += 1
            let mid = 0.5 * (lo + hi)
            let topMD = max(0, startMD - mid)
            let vol = geom.volumeInAnnulus_m3(topMD, startMD)

            if vol < volume {
                lo = mid
            } else {
                hi = mid
            }
        }

        return 0.5 * (lo + hi)
    }

    // MARK: - Stage Information

    func stageDescription(_ stage: SimulationStage) -> String {
        if stage.isOperation {
            return operationDescription(stage)
        }

        var desc = stage.name
        if stage.volume_m3 > 0 {
            desc += String(format: " - %.2f m³", stage.volume_m3)
        }
        if stage.density_kgm3 > 0 {
            desc += String(format: " @ %.0f kg/m³", stage.density_kgm3)
        }
        return desc
    }

    private func operationDescription(_ stage: SimulationStage) -> String {
        guard let opType = stage.operationType else { return stage.name }

        if let sourceStage = stage.sourceStage {
            return sourceStage.summaryText()
        }

        return opType.displayName
    }

    // MARK: - Summary Statistics

    struct SimulationSummary {
        var totalPumped_m3: Double
        var expectedReturn_m3: Double
        var actualReturn_m3: Double
        var returnRatio: Double
        var volumeDifference_m3: Double
        var currentStageIndex: Int
        var totalStages: Int
        var currentStageName: String
        var isOperation: Bool
    }

    func getSummary() -> SimulationSummary {
        SimulationSummary(
            totalPumped_m3: cumulativePumpedVolume_m3,
            expectedReturn_m3: expectedReturn_m3,
            actualReturn_m3: actualTotalReturned_m3,
            returnRatio: overallReturnRatio,
            volumeDifference_m3: returnDifference_m3,
            currentStageIndex: currentStageIndex,
            totalStages: stages.count,
            currentStageName: currentStage?.name ?? "",
            isOperation: currentStage?.isOperation ?? false
        )
    }

    // MARK: - Export Summary Text

    /// Generate summary text for clipboard export
    func generateSummaryText(jobName: String) -> String {
        var lines: [String] = []

        lines.append("CEMENT JOB SUMMARY: \(jobName)")
        lines.append(String(repeating: "=", count: 40))
        lines.append("")

        // Stage-by-stage summary
        lines.append("PUMP SCHEDULE:")
        for (index, stage) in stages.enumerated() {
            let stageNum = index + 1

            if stage.isOperation {
                if let sourceStage = stage.sourceStage {
                    var opText = "  \(stageNum). \(sourceStage.summaryText())"
                    if let userNotes = stageNotes[stage.id], !userNotes.isEmpty {
                        opText += " - \(userNotes)"
                    }
                    lines.append(opText)
                } else {
                    lines.append("  \(stageNum). \(stage.name)")
                }
            } else {
                var pumpText = "  \(stageNum). pump \(String(format: "%.2f", stage.volume_m3))m³ \(stage.name) at \(Int(stage.density_kgm3))kg/m³"
                if let userNotes = stageNotes[stage.id], !userNotes.isEmpty {
                    pumpText += " - \(userNotes)"
                }
                lines.append(pumpText)
            }

            // Add tank reading if recorded
            if let tankReading = tankReadings[stage.id] {
                lines.append("      Tank volume: \(String(format: "%.2f", tankReading))m³")
            }
        }

        lines.append("")

        // Cement tops in annulus
        lines.append("CEMENT TOPS (THEORETICAL):")
        let cementSegments = annulusStack.filter { $0.isCement }
        if cementSegments.isEmpty {
            lines.append("  No cement in annulus yet")
        } else {
            for segment in cementSegments {
                lines.append("  \(segment.name):")
                lines.append("    Top: \(Int(segment.topMD_m))m MD / \(Int(segment.topTVD_m))m TVD")
                lines.append("    Bottom: \(Int(segment.bottomMD_m))m MD / \(Int(segment.bottomTVD_m))m TVD")
            }
        }

        lines.append("")

        // Returns summary
        lines.append("RETURNS SUMMARY:")
        lines.append("  Volume pumped: \(String(format: "%.2f", cumulativePumpedVolume_m3))m³")
        lines.append("  Expected return: \(String(format: "%.2f", expectedReturn_m3))m³")
        lines.append("  Actual return: \(String(format: "%.2f", actualTotalReturned_m3))m³")
        lines.append("  Return ratio: 1:\(String(format: "%.2f", overallReturnRatio))")

        if abs(returnDifference_m3) > 0.01 {
            let diffText = returnDifference_m3 > 0 ? "losses" : "gains"
            lines.append("  Difference: \(String(format: "%+.2f", -returnDifference_m3))m³ (\(diffText))")
        }

        lines.append("")

        // Cement returns
        lines.append("CEMENT RETURNS:")
        lines.append("  Total cement in annulus: \(String(format: "%.2f", cementReturns_m3))m³")

        lines.append("")

        // Tank volume tracking
        if initialTankVolume_m3 > 0 {
            lines.append("TANK VOLUME TRACKING:")
            lines.append("  Initial: \(String(format: "%.2f", initialTankVolume_m3))m³")
            lines.append("  Current: \(String(format: "%.2f", currentTankVolume_m3))m³")
            lines.append("  Expected: \(String(format: "%.2f", expectedTankVolume_m3))m³")
            if abs(tankVolumeDifference_m3) > 0.01 {
                lines.append("  Difference: \(String(format: "%+.2f", tankVolumeDifference_m3))m³")
            }
        }

        return lines.joined(separator: "\n")
    }
}
