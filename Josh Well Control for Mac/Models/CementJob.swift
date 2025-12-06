//
//  CementJob.swift
//  Josh Well Control for Mac
//
//  Created for cementing calculations feature.
//

import Foundation
import SwiftData
import SwiftUI

/// Represents a complete cement job with volume calculations and pump stages.
/// Used for planning and documenting primary/remedial cementing operations.
@Model
final class CementJob {
    var id: UUID = UUID()

    /// Descriptive name for this cement job (e.g., "Intermediate Casing Cement")
    var name: String = ""

    /// Type of casing being cemented
    var casingTypeRaw: Int = CasingType.intermediate.rawValue

    /// Desired cement top depth (MD in meters)
    var topMD_m: Double = 0.0

    /// Desired cement bottom depth (MD in meters) - typically shoe depth
    var bottomMD_m: Double = 0.0

    /// Excess percentage to apply to open hole sections (e.g., 50 = 50% excess)
    var excessPercent: Double = 50.0

    /// Calculated cased hole volume (m³) - no excess applied
    var casedVolume_m3: Double = 0.0

    /// Calculated open hole volume (m³) - before excess
    var openHoleVolume_m3: Double = 0.0

    /// Total volume including excess on open hole (m³)
    var totalVolumeWithExcess_m3: Double = 0.0

    /// Slurry yield factor (m³ per tonne of dry cement)
    /// Typical range: 0.5-0.7 m³/t for standard cements
    var yieldFactor_m3_per_tonne: Double = 0.62

    /// Mix water requirement (liters per tonne of dry cement)
    /// Typical range: 400-550 L/t depending on cement type
    var mixWaterRatio_L_per_tonne: Double = 480.0

    /// Timestamp when this job was created
    var createdAt: Date = Date.now

    /// Timestamp when this job was last modified
    var updatedAt: Date = Date.now

    /// Optional notes about the cement job
    var notes: String = ""

    /// Stages for this cement job (pre-flush, spacers, cement, displacement, operations)
    @Relationship(deleteRule: .cascade, inverse: \CementJobStage.cementJob)
    var stages: [CementJobStage]?

    /// Back-reference to the owning project
    /// Inverse is declared on ProjectState.cementJobs
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    // MARK: - Casing Type Enum

    enum CasingType: Int, Codable, CaseIterable {
        case surface = 0
        case intermediate = 1
        case production = 2
        case liner = 3

        var displayName: String {
            switch self {
            case .surface: return "Surface Casing"
            case .intermediate: return "Intermediate Casing"
            case .production: return "Production Casing"
            case .liner: return "Liner"
            }
        }
    }

    // MARK: - Computed Properties

    @Transient var casingType: CasingType {
        get { CasingType(rawValue: casingTypeRaw) ?? .intermediate }
        set { casingTypeRaw = newValue.rawValue }
    }

    /// Length of cement column
    @Transient var cementLength_m: Double {
        max(0, bottomMD_m - topMD_m)
    }

    /// Open hole excess volume (m³)
    @Transient var excessVolume_m3: Double {
        openHoleVolume_m3 * (excessPercent / 100.0)
    }

    /// Sorted stages by order index
    @Transient var sortedStages: [CementJobStage] {
        (stages ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Total lead cement volume from stages
    @Transient var leadCementVolume_m3: Double {
        sortedStages.filter { $0.stageType == .leadCement }.reduce(0) { $0 + $1.volume_m3 }
    }

    /// Total tail cement volume from stages
    @Transient var tailCementVolume_m3: Double {
        sortedStages.filter { $0.stageType == .tailCement }.reduce(0) { $0 + $1.volume_m3 }
    }

    /// Total cement volume from all cement stages
    @Transient var totalCementVolume_m3: Double {
        leadCementVolume_m3 + tailCementVolume_m3
    }

    /// Total cement tonnage from all cement stages
    @Transient var totalCementTonnage_t: Double {
        sortedStages
            .filter { $0.stageType == .leadCement || $0.stageType == .tailCement }
            .reduce(0) { $0 + ($1.tonnage_t ?? 0) }
    }

    /// Total mix water required (liters)
    @Transient var totalMixWater_L: Double {
        sortedStages
            .filter { $0.stageType == .leadCement || $0.stageType == .tailCement }
            .reduce(0) { $0 + ($1.mixWater_L ?? 0) }
    }

    /// Total displacement volume from stages
    @Transient var displacementVolume_m3: Double {
        sortedStages.filter { $0.stageType == .displacement }.reduce(0) { $0 + $1.volume_m3 }
    }

    // MARK: - Initializer

    init(
        name: String = "",
        casingType: CasingType = .intermediate,
        topMD_m: Double = 0.0,
        bottomMD_m: Double = 0.0,
        excessPercent: Double = 50.0,
        yieldFactor_m3_per_tonne: Double = 0.62,
        mixWaterRatio_L_per_tonne: Double = 480.0,
        project: ProjectState? = nil
    ) {
        self.name = name
        self.casingTypeRaw = casingType.rawValue
        self.topMD_m = topMD_m
        self.bottomMD_m = bottomMD_m
        self.excessPercent = excessPercent
        self.yieldFactor_m3_per_tonne = yieldFactor_m3_per_tonne
        self.mixWaterRatio_L_per_tonne = mixWaterRatio_L_per_tonne
        self.project = project
    }

    // MARK: - Volume Calculation Methods

    /// Recalculate volumes based on annulus sections from the project.
    /// Should be called whenever top/bottom depths or excess % change.
    func recalculateVolumes() {
        guard let project = project else { return }

        let sections = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }

        var casedVol = 0.0
        var openHoleVol = 0.0

        for section in sections {
            // Calculate overlap between cement interval and this section
            let overlapTop = max(topMD_m, section.topDepth_m)
            let overlapBottom = min(bottomMD_m, section.bottomDepth_m)

            guard overlapBottom > overlapTop else { continue }

            // Calculate volume for this overlap
            let overlapLength = overlapBottom - overlapTop
            let volumeFraction = overlapLength / section.length_m
            let sectionVolume = section.volume_m3 * volumeFraction

            if section.isCased {
                casedVol += sectionVolume
            } else {
                openHoleVol += sectionVolume
            }
        }

        self.casedVolume_m3 = casedVol
        self.openHoleVolume_m3 = openHoleVol
        self.totalVolumeWithExcess_m3 = casedVol + openHoleVol * (1 + excessPercent / 100.0)
        self.updatedAt = .now
    }

    /// Calculate tonnage from volume using yield factor
    func tonnageFromVolume(_ volume_m3: Double) -> Double {
        guard yieldFactor_m3_per_tonne > 0 else { return 0 }
        return volume_m3 / yieldFactor_m3_per_tonne
    }

    /// Calculate mix water from tonnage using water ratio
    func mixWaterFromTonnage(_ tonnage_t: Double) -> Double {
        return tonnage_t * mixWaterRatio_L_per_tonne
    }

    // MARK: - Stage Management

    /// Add a new stage to this cement job
    func addStage(_ stage: CementJobStage) {
        if stages == nil { stages = [] }
        let nextIndex = (stages?.map { $0.orderIndex }.max() ?? -1) + 1
        stage.orderIndex = nextIndex
        stage.cementJob = self
        stages?.append(stage)
        updatedAt = .now
    }

    /// Remove a stage from this cement job
    func removeStage(_ stage: CementJobStage) {
        stages?.removeAll { $0.id == stage.id }
        updatedAt = .now
    }

    /// Reorder stages after drag/drop
    func reorderStages(_ orderedStages: [CementJobStage]) {
        for (index, stage) in orderedStages.enumerated() {
            stage.orderIndex = index
        }
        updatedAt = .now
    }
}

// MARK: - Export Dictionary

extension CementJob {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "casingType": casingType.rawValue,
            "topMD_m": topMD_m,
            "bottomMD_m": bottomMD_m,
            "excessPercent": excessPercent,
            "casedVolume_m3": casedVolume_m3,
            "openHoleVolume_m3": openHoleVolume_m3,
            "totalVolumeWithExcess_m3": totalVolumeWithExcess_m3,
            "yieldFactor_m3_per_tonne": yieldFactor_m3_per_tonne,
            "mixWaterRatio_L_per_tonne": mixWaterRatio_L_per_tonne,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            "notes": notes,
            "stages": (stages ?? []).sorted { $0.orderIndex < $1.orderIndex }.map { $0.exportDictionary }
        ]
    }
}
