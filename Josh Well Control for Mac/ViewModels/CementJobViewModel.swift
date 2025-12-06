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
        var casedVolume_m3: Double = 0
        var openHoleVolume_m3: Double = 0
        var excessVolume_m3: Double = 0
        var totalVolume_m3: Double = 0

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

        var breakdown = VolumeBreakdown()
        var casedVol = 0.0
        var openHoleVol = 0.0

        for section in sections {
            // Calculate overlap between cement interval and this section
            let overlapTop = max(job.topMD_m, section.topDepth_m)
            let overlapBottom = min(job.bottomMD_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            // Calculate volume for this overlap
            let overlapLength = overlapBottom - overlapTop
            let volumeFraction = section.length_m > 0 ? overlapLength / section.length_m : 0
            let sectionVolume = section.volume_m3 * volumeFraction

            let sectionInfo = VolumeBreakdown.SectionVolume(
                sectionName: section.name,
                isCased: section.isCased,
                volume_m3: sectionVolume,
                topMD_m: overlapTop,
                bottomMD_m: overlapBottom
            )
            breakdown.sectionVolumes.append(sectionInfo)

            if section.isCased {
                casedVol += sectionVolume
            } else {
                openHoleVol += sectionVolume
            }
        }

        breakdown.casedVolume_m3 = casedVol
        breakdown.openHoleVolume_m3 = openHoleVol
        breakdown.excessVolume_m3 = openHoleVol * (job.excessPercent / 100.0)
        breakdown.totalVolume_m3 = casedVol + openHoleVol + breakdown.excessVolume_m3

        return breakdown
    }

    /// Update volume calculations for the selected job
    func updateVolumes(project: ProjectState) {
        guard let job = selectedJob else { return }

        volumeBreakdown = calculateVolumeBreakdown(for: job, project: project)

        // Update the job's stored values
        job.casedVolume_m3 = volumeBreakdown.casedVolume_m3
        job.openHoleVolume_m3 = volumeBreakdown.openHoleVolume_m3
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
    func updateStageCalculations(_ stage: CementJobStage, job: CementJob) {
        stage.updateCalculations(
            yieldFactor: job.yieldFactor_m3_per_tonne,
            waterRatio: job.mixWaterRatio_L_per_tonne
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

    // MARK: - Displacement Calculation

    /// Calculate displacement volume from string geometry
    func calculateDisplacementVolume(project: ProjectState, shoeDepth_m: Double) -> Double {
        let drillStrings = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        var totalVolume = 0.0

        for section in drillStrings {
            let overlapTop = max(0, section.topDepth_m)
            let overlapBottom = min(shoeDepth_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            let overlapLength = overlapBottom - overlapTop
            let area = .pi * pow(section.innerDiameter_m / 2, 2)
            totalVolume += area * overlapLength
        }

        // Add surface line volume
        totalVolume += project.surfaceLineVolume_m3

        return totalVolume
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
            displacementVolume_m3: job.displacementVolume_m3,
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
        var displacementVolume_m3: Double
        var numberOfOperations: Int
        var numberOfCementStages: Int
    }
}
