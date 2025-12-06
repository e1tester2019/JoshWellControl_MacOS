//
//  CementJobViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for cement job calculations and management.
//

import Foundation
import SwiftData
import SwiftUI
import Observation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// ViewModel for managing cement job calculations, stages, and summary generation.
@Observable
class CementJobViewModel {
    // MARK: - State

    /// Currently selected cement job
    var selectedJob: CementJob?

    /// Currently selected stage for editing
    var selectedStage: CementJobStage?

    /// Show stage editor sheet
    var showingStageEditor: Bool = false

    /// Show new job sheet
    var showingNewJobSheet: Bool = false

    /// Computed volume breakdown for display
    var volumeBreakdown: VolumeBreakdown = VolumeBreakdown()

    /// Error message for display
    var errorMessage: String?

    // MARK: - Volume Breakdown

    struct VolumeBreakdown {
        // Lead cement volumes
        var leadCasedVolume_m3: Double = 0
        var leadOpenHoleVolume_m3: Double = 0
        var leadExcessPercent: Double = 0
        var leadExcessVolume_m3: Double = 0
        var leadTotalVolume_m3: Double = 0

        // Tail cement volumes
        var tailCasedVolume_m3: Double = 0
        var tailOpenHoleVolume_m3: Double = 0
        var tailExcessPercent: Double = 0
        var tailExcessVolume_m3: Double = 0
        var tailTotalVolume_m3: Double = 0

        // Combined totals
        var totalVolume_m3: Double = 0

        // Mud return (volume of cement pumped = mud displaced)
        var mudReturn_m3: Double = 0

        // Volume to bump (drill string volume to float collar)
        var volumeToBump_m3: Double = 0

        /// Volume breakdown by section
        var sectionVolumes: [SectionVolume] = []

        struct SectionVolume: Identifiable {
            let id = UUID()
            let sectionName: String
            let isCased: Bool
            let volume_m3: Double
            let topMD_m: Double
            let bottomMD_m: Double
        }
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Volume Calculations

    /// Calculate detailed volume breakdown for a cement job
    func calculateVolumeBreakdown(for job: CementJob, project: ProjectState) -> VolumeBreakdown {
        let sections = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        let drillStrings = project.drillString ?? []

        var breakdown = VolumeBreakdown()

        // Calculate lead cement volumes (leadTopMD_m to leadBottomMD_m)
        var leadCased = 0.0
        var leadOpenHole = 0.0

        for section in sections {
            let overlapTop = max(job.leadTopMD_m, section.topDepth_m)
            let overlapBottom = min(job.leadBottomMD_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            let overlapLength = overlapBottom - overlapTop
            let volumeFraction = section.length_m > 0 ? overlapLength / section.length_m : 0
            let sectionVolume = section.effectiveAnnularVolume(with: drillStrings) * volumeFraction

            if section.isCased {
                leadCased += sectionVolume
            } else {
                leadOpenHole += sectionVolume
            }
        }

        breakdown.leadCasedVolume_m3 = leadCased
        breakdown.leadOpenHoleVolume_m3 = leadOpenHole
        breakdown.leadExcessPercent = job.leadExcessPercent
        breakdown.leadExcessVolume_m3 = leadOpenHole * (job.leadExcessPercent / 100.0)
        breakdown.leadTotalVolume_m3 = leadCased + leadOpenHole + breakdown.leadExcessVolume_m3

        // Calculate tail cement volumes (tailTopMD_m to tailBottomMD_m)
        var tailCased = 0.0
        var tailOpenHole = 0.0

        for section in sections {
            let overlapTop = max(job.tailTopMD_m, section.topDepth_m)
            let overlapBottom = min(job.tailBottomMD_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            let overlapLength = overlapBottom - overlapTop
            let volumeFraction = section.length_m > 0 ? overlapLength / section.length_m : 0
            let sectionVolume = section.effectiveAnnularVolume(with: drillStrings) * volumeFraction

            if section.isCased {
                tailCased += sectionVolume
            } else {
                tailOpenHole += sectionVolume
            }
        }

        breakdown.tailCasedVolume_m3 = tailCased
        breakdown.tailOpenHoleVolume_m3 = tailOpenHole
        breakdown.tailExcessPercent = job.tailExcessPercent
        breakdown.tailExcessVolume_m3 = tailOpenHole * (job.tailExcessPercent / 100.0)
        breakdown.tailTotalVolume_m3 = tailCased + tailOpenHole + breakdown.tailExcessVolume_m3

        // Combined total
        breakdown.totalVolume_m3 = breakdown.leadTotalVolume_m3 + breakdown.tailTotalVolume_m3

        // Volume to bump = drill string internal volume from surface to float collar
        let stringVolume = calculateDrillStringVolume(
            drillStrings: drillStrings,
            toDepth: job.floatCollarDepth_m
        )
        breakdown.volumeToBump_m3 = stringVolume

        // Mud return = annulus volume (cased + open hole, NO excess) + string volume
        // This is the actual mud volume that will be displaced to surface
        let totalAnnulusNoExcess = (breakdown.leadCasedVolume_m3 + breakdown.leadOpenHoleVolume_m3 +
                                    breakdown.tailCasedVolume_m3 + breakdown.tailOpenHoleVolume_m3)
        breakdown.mudReturn_m3 = totalAnnulusNoExcess + stringVolume

        // Build section volumes for display (using full cement interval)
        for section in sections {
            let overlapTop = max(job.topMD_m, section.topDepth_m)
            let overlapBottom = min(job.bottomMD_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            let overlapLength = overlapBottom - overlapTop
            let volumeFraction = section.length_m > 0 ? overlapLength / section.length_m : 0
            let sectionVolume = section.effectiveAnnularVolume(with: drillStrings) * volumeFraction

            let sectionInfo = VolumeBreakdown.SectionVolume(
                sectionName: section.name,
                isCased: section.isCased,
                volume_m3: sectionVolume,
                topMD_m: overlapTop,
                bottomMD_m: overlapBottom
            )
            breakdown.sectionVolumes.append(sectionInfo)
        }

        return breakdown
    }

    /// Calculate drill string internal volume from surface to float collar depth
    private func calculateDrillStringVolume(drillStrings: [DrillStringSection], toDepth: Double) -> Double {
        guard toDepth > 0 else { return 0 }

        let sortedSections = drillStrings.sorted { $0.topDepth_m < $1.topDepth_m }
        var totalVolume = 0.0

        for section in sortedSections {
            let sectionTop = section.topDepth_m
            let sectionBottom = min(section.bottomDepth_m, toDepth)

            guard sectionBottom > sectionTop else { continue }

            let length = sectionBottom - sectionTop
            let area = .pi * pow(section.innerDiameter_m / 2, 2)
            totalVolume += area * length

            // Stop if we've reached the float collar depth
            if section.bottomDepth_m >= toDepth { break }
        }

        return totalVolume
    }

    /// Update volume calculations for the selected job
    func updateVolumes(project: ProjectState) {
        guard let job = selectedJob else { return }

        volumeBreakdown = calculateVolumeBreakdown(for: job, project: project)

        // Update the job's stored values (combine lead + tail)
        job.casedVolume_m3 = volumeBreakdown.leadCasedVolume_m3 + volumeBreakdown.tailCasedVolume_m3
        job.openHoleVolume_m3 = volumeBreakdown.leadOpenHoleVolume_m3 + volumeBreakdown.tailOpenHoleVolume_m3
        job.totalVolumeWithExcess_m3 = volumeBreakdown.totalVolume_m3
        job.updatedAt = .now
    }

    // MARK: - Stage Management

    /// Add a new stage to the selected cement job
    func addStage(_ stage: CementJobStage, to job: CementJob, context: ModelContext) {
        job.addStage(stage)
        updateStageCalculations(stage, job: job)
        context.insert(stage)
        try? context.save()
    }

    /// Remove a stage from the cement job
    func removeStage(_ stage: CementJobStage, from job: CementJob, context: ModelContext) {
        job.removeStage(stage)
        context.delete(stage)
        try? context.save()
    }

    /// Update calculations for a cement stage (tonnage, mix water)
    /// Uses lead-specific or tail-specific yield/water ratios based on stage type
    func updateStageCalculations(_ stage: CementJobStage, job: CementJob) {
        let yieldFactor: Double
        let waterRatio: Double

        switch stage.stageType {
        case .leadCement:
            yieldFactor = job.leadYieldFactor_m3_per_tonne
            waterRatio = job.leadMixWaterRatio_m3_per_tonne
        case .tailCement:
            yieldFactor = job.tailYieldFactor_m3_per_tonne
            waterRatio = job.tailMixWaterRatio_m3_per_tonne
        default:
            // Use legacy/default values for non-cement stages
            yieldFactor = job.yieldFactor_m3_per_tonne
            waterRatio = job.mixWaterRatio_m3_per_tonne
        }

        stage.updateCalculations(
            yieldFactor: yieldFactor,
            waterRatio_m3_per_tonne: waterRatio
        )
    }

    /// Update all stage calculations for a job
    func updateAllStageCalculations(_ job: CementJob) {
        for stage in job.sortedStages {
            updateStageCalculations(stage, job: job)
        }
    }

    // MARK: - Cement Job Management

    /// Create a new cement job
    func createCementJob(
        name: String,
        casingType: CementJob.CasingType,
        topMD_m: Double,
        bottomMD_m: Double,
        excessPercent: Double,
        project: ProjectState,
        context: ModelContext
    ) -> CementJob {
        let job = CementJob(
            name: name,
            casingType: casingType,
            topMD_m: topMD_m,
            bottomMD_m: bottomMD_m,
            excessPercent: excessPercent,
            project: project
        )

        if project.cementJobs == nil {
            project.cementJobs = []
        }
        project.cementJobs?.append(job)
        context.insert(job)

        // Calculate volumes
        job.recalculateVolumes()

        try? context.save()
        return job
    }

    /// Delete a cement job
    func deleteCementJob(_ job: CementJob, from project: ProjectState, context: ModelContext) {
        project.cementJobs?.removeAll { $0.id == job.id }
        context.delete(job)
        try? context.save()

        if selectedJob?.id == job.id {
            selectedJob = nil
        }
    }

    // MARK: - Clipboard Summary Generation

    /// Generate a complete job summary text for clipboard
    func generateJobSummary(_ job: CementJob) -> String {
        var parts: [String] = []

        // Job header
        parts.append("\(job.casingType.displayName.lowercased()) cement job")

        // Sorted stages
        let stages = job.sortedStages

        for stage in stages {
            let summary = stage.summaryText()
            if !summary.isEmpty {
                parts.append(summary)
            }
        }

        // Add cement-to-surface info if we have any cement stages
        let cementStages = stages.filter { $0.stageType.isCementStage }
        if !cementStages.isEmpty {
            // Check if cement is expected to surface based on volumes
            let totalCementVol = cementStages.reduce(0) { $0 + $1.volume_m3 }
            if totalCementVol > job.totalVolumeWithExcess_m3 * 0.8 {
                let excessVol = totalCementVol - job.totalVolumeWithExcess_m3
                if excessVol > 0 {
                    parts.append("Pre flush to surface and \(String(format: "%.1f", excessVol))m³ cement to surface")
                }
            }
        }

        // Add total displacement summary
        let displacementVol = job.displacementVolume_m3
        if displacementVol > 0 {
            parts.append("total displacement \(String(format: "%.2f", displacementVol))m³ (\(String(format: "%.0f", displacementVol * 1000))L)")
        }

        // Build the final string with proper punctuation
        var result = ""
        for (index, part) in parts.enumerated() {
            if index == 0 {
                // Capitalize first part
                result = part.prefix(1).uppercased() + part.dropFirst()
            } else {
                result += ", " + part
            }
        }

        if !result.isEmpty {
            result += "."
        }

        return result
    }

    /// Copy job summary to clipboard
    func copyToClipboard(_ job: CementJob) {
        let summary = generateJobSummary(job)

        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summary, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = summary
        #endif
    }

    // MARK: - Template Stages

    /// Create a set of template stages for a typical cement job
    func createTemplateStages(for job: CementJob, context: ModelContext) {
        // Pre-flush sweep
        let preFlush = CementJobStage(
            stageType: .preFlush,
            name: "MAG Active Sweep-LC",
            volume_m3: 3.0,
            density_kgm3: 1175,
            color: .orange
        )
        addStage(preFlush, to: job, context: context)

        // Pressure test lines operation
        let pressureTest = CementJobStage.operation(
            type: .pressureTestLines,
            pressure_MPa: 35.0,
            cementJob: job
        )
        addStage(pressureTest, to: job, context: context)

        // Trip set operation
        let tripSet = CementJobStage.operation(
            type: .tripSet,
            pressure_MPa: 15.0,
            cementJob: job
        )
        addStage(tripSet, to: job, context: context)

        // Spacer
        let spacer = CementJobStage(
            stageType: .spacer,
            name: "MAG Sweep",
            volume_m3: 1.0,
            density_kgm3: 1175,
            color: .yellow
        )
        addStage(spacer, to: job, context: context)

        // Lead cement (use calculated volume)
        let leadVolume = job.totalVolumeWithExcess_m3 * 0.8  // 80% lead
        let leadCement = CementJobStage(
            stageType: .leadCement,
            name: "MAG EV 1300-BC",
            volume_m3: leadVolume,
            density_kgm3: 1300,
            color: .gray
        )
        addStage(leadCement, to: job, context: context)

        // Tail cement (use calculated volume)
        let tailVolume = job.totalVolumeWithExcess_m3 * 0.2  // 20% tail
        let tailCement = CementJobStage(
            stageType: .tailCement,
            name: "MAG EV 1550-BC",
            volume_m3: tailVolume,
            density_kgm3: 1550,
            color: .init(red: 0.3, green: 0.3, blue: 0.3)
        )
        addStage(tailCement, to: job, context: context)

        // Plug drop
        let plugDrop = CementJobStage.operation(
            type: .plugDrop,
            cementJob: job
        )
        addStage(plugDrop, to: job, context: context)

        // Displacement (calculate from string volume to shoe)
        let displacement = CementJobStage(
            stageType: .displacement,
            name: "invert mud",
            volume_m3: 40.0,  // Will need to be calculated from string geometry
            density_kgm3: 1200,
            color: .brown
        )
        addStage(displacement, to: job, context: context)

        // Water displacement at end
        let waterDisp = CementJobStage(
            stageType: .displacement,
            name: "water",
            volume_m3: 2.6,
            density_kgm3: 1000,
            color: .blue
        )
        addStage(waterDisp, to: job, context: context)

        // Bump plug
        let bumpPlug = CementJobStage.operation(
            type: .bumpPlug,
            pressure_MPa: 10.0,
            overPressure_MPa: 3.5,
            cementJob: job
        )
        addStage(bumpPlug, to: job, context: context)

        // Pressure test casing
        let casingTest = CementJobStage.operation(
            type: .pressureTestCasing,
            pressure_MPa: 32.0,
            duration_min: 11.0,
            cementJob: job
        )
        addStage(casingTest, to: job, context: context)

        // Float check
        let floatCheck = CementJobStage.operation(
            type: .floatCheck,
            cementJob: job
        )
        addStage(floatCheck, to: job, context: context)

        // Bleed back
        let bleedBack = CementJobStage.operation(
            type: .bleedBack,
            volume_L: 400.0,
            cementJob: job
        )
        addStage(bleedBack, to: job, context: context)

        // Rig out
        let rigOut = CementJobStage.operation(
            type: .rigOut,
            cementJob: job
        )
        addStage(rigOut, to: job, context: context)
    }

    // MARK: - Volume Calculations from Geometry

    /// Calculate annulus volume between two depths using project annulus sections
    func calculateAnnulusVolume(project: ProjectState, topMD_m: Double, bottomMD_m: Double, excessPercent: Double) -> Double {
        let sections = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        let drillStrings = project.drillString ?? []
        var totalVolume = 0.0

        for section in sections {
            // Calculate overlap between cement interval and this section
            let overlapTop = max(topMD_m, section.topDepth_m)
            let overlapBottom = min(bottomMD_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            // Calculate volume fraction for the overlap
            let overlapLength = overlapBottom - overlapTop
            let volumeFraction = section.length_m > 0 ? overlapLength / section.length_m : 0

            // Use effective annular volume (accounts for drill string ODs)
            let sectionVolume = section.effectiveAnnularVolume(with: drillStrings) * volumeFraction

            // Apply excess for open hole only
            if section.isCased {
                totalVolume += sectionVolume
            } else {
                totalVolume += sectionVolume * (1 + excessPercent / 100.0)
            }
        }

        return totalVolume
    }

    /// Calculate lead cement volume from geometry
    func calculateLeadCementVolume(job: CementJob, project: ProjectState) -> Double {
        guard job.leadBottomMD_m > job.leadTopMD_m else { return 0 }
        return calculateAnnulusVolume(
            project: project,
            topMD_m: job.leadTopMD_m,
            bottomMD_m: job.leadBottomMD_m,
            excessPercent: job.leadExcessPercent
        )
    }

    /// Calculate tail cement volume from geometry
    func calculateTailCementVolume(job: CementJob, project: ProjectState) -> Double {
        guard job.tailBottomMD_m > job.tailTopMD_m else { return 0 }
        return calculateAnnulusVolume(
            project: project,
            topMD_m: job.tailTopMD_m,
            bottomMD_m: job.tailBottomMD_m,
            excessPercent: job.tailExcessPercent
        )
    }

    /// Calculate displacement volume from string geometry to float collar depth
    func calculateDisplacementVolume(project: ProjectState, floatCollarDepth_m: Double) -> Double {
        let drillStrings = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        var totalVolume = 0.0

        for section in drillStrings {
            let overlapTop = max(0, section.topDepth_m)
            let overlapBottom = min(floatCollarDepth_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            let overlapLength = overlapBottom - overlapTop
            let area = .pi * pow(section.innerDiameter_m / 2, 2)
            totalVolume += area * overlapLength
        }

        // Add surface line volume
        totalVolume += project.surfaceLineVolume_m3

        return totalVolume
    }

    /// Calculate all cement job volumes from geometry and return a summary
    func calculateJobVolumes(job: CementJob, project: ProjectState) -> CalculatedVolumes {
        let leadVolume = calculateLeadCementVolume(job: job, project: project)
        let tailVolume = calculateTailCementVolume(job: job, project: project)
        let displacementVolume = job.floatCollarDepth_m > 0
            ? calculateDisplacementVolume(project: project, floatCollarDepth_m: job.floatCollarDepth_m)
            : 0

        return CalculatedVolumes(
            leadCementVolume_m3: leadVolume,
            tailCementVolume_m3: tailVolume,
            totalDisplacementVolume_m3: displacementVolume
        )
    }

    struct CalculatedVolumes {
        var leadCementVolume_m3: Double
        var tailCementVolume_m3: Double
        var totalDisplacementVolume_m3: Double
    }

    // MARK: - Statistics

    /// Get summary statistics for display
    func getJobStatistics(_ job: CementJob) -> JobStatistics {
        let stages = job.sortedStages

        let pumpStages = stages.filter { $0.stageType.isPumpStage }
        let cementStages = stages.filter { $0.stageType.isCementStage }
        let operations = stages.filter { $0.stageType == .operation }

        return JobStatistics(
            totalPumpVolume_m3: pumpStages.reduce(0) { $0 + $1.volume_m3 },
            leadCementVolume_m3: job.leadCementVolume_m3,
            tailCementVolume_m3: job.tailCementVolume_m3,
            totalCementTonnage_t: job.totalCementTonnage_t,
            totalMixWater_L: job.totalMixWater_L,
            totalMixWater_m3: job.totalMixWater_m3,
            displacementVolume_m3: job.displacementVolume_m3,
            displacementVolume_L: job.displacementVolume_L,
            washUpVolume_m3: job.washUpVolume_m3,
            pumpOutVolume_m3: job.pumpOutVolume_m3,
            totalWaterUsage_m3: job.totalWaterUsage_m3,
            totalWaterUsage_L: job.totalWaterUsage_L,
            numberOfOperations: operations.count,
            numberOfCementStages: cementStages.count
        )
    }

    struct JobStatistics {
        var totalPumpVolume_m3: Double
        var leadCementVolume_m3: Double
        var tailCementVolume_m3: Double
        var totalCementTonnage_t: Double
        var totalMixWater_L: Double
        var totalMixWater_m3: Double
        var displacementVolume_m3: Double
        var displacementVolume_L: Double
        var washUpVolume_m3: Double
        var pumpOutVolume_m3: Double
        var totalWaterUsage_m3: Double
        var totalWaterUsage_L: Double
        var numberOfOperations: Int
        var numberOfCementStages: Int
    }

    // MARK: - Water Requirements Breakdown

    /// Get per-stage water requirements (excludes mud displacement)
    func getWaterRequirements(_ job: CementJob) -> WaterRequirements {
        let stages = job.sortedStages

        // Pre-flush water (volume is the water requirement)
        let preFlushWater_L = stages
            .filter { $0.stageType == .preFlush }
            .reduce(0.0) { $0 + $1.volume_m3 * 1000 }

        // Spacer water (volume is the water requirement)
        let spacerWater_L = stages
            .filter { $0.stageType == .spacer }
            .reduce(0.0) { $0 + $1.volume_m3 * 1000 }

        // Lead cement mix water
        let leadMixWater_L = stages
            .filter { $0.stageType == .leadCement }
            .reduce(0.0) { $0 + ($1.mixWater_L ?? 0) }

        // Tail cement mix water
        let tailMixWater_L = stages
            .filter { $0.stageType == .tailCement }
            .reduce(0.0) { $0 + ($1.mixWater_L ?? 0) }

        // Water displacement only (excludes mud displacement)
        let displacementWater_L = stages
            .filter { $0.stageType == .displacement }
            .reduce(0.0) { $0 + $1.volume_m3 * 1000 }

        // Additional water volumes from job
        let washUpWater_L = job.washUpVolume_m3 * 1000
        let pumpOutWater_L = job.pumpOutVolume_m3 * 1000

        let totalWater_L = preFlushWater_L + spacerWater_L + leadMixWater_L + tailMixWater_L + displacementWater_L + washUpWater_L + pumpOutWater_L

        return WaterRequirements(
            preFlushWater_L: preFlushWater_L,
            spacerWater_L: spacerWater_L,
            leadMixWater_L: leadMixWater_L,
            tailMixWater_L: tailMixWater_L,
            displacementWater_L: displacementWater_L,
            washUpWater_L: washUpWater_L,
            pumpOutWater_L: pumpOutWater_L,
            totalWater_L: totalWater_L
        )
    }

    struct WaterRequirements {
        var preFlushWater_L: Double
        var spacerWater_L: Double
        var leadMixWater_L: Double
        var tailMixWater_L: Double
        var displacementWater_L: Double
        var washUpWater_L: Double
        var pumpOutWater_L: Double
        var totalWater_L: Double

        var totalWater_m3: Double { totalWater_L / 1000.0 }
    }
}
