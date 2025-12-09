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

    // MARK: - Loss Zone

    /// Defines a loss zone at a specific depth where losses can occur
    struct LossZone {
        let depth_m: Double          // MD of the loss zone
        let tvd_m: Double            // TVD of the loss zone
        let frac_kPa: Double         // Fracture pressure at this depth (kPa)
        let fracGradient_kPa_per_m: Double  // Frac gradient (kPa/m)
        var isActive: Bool = true    // Whether to use this loss zone in simulation

        /// Frac gradient as EMW (kg/m³)
        var fracEMW_kg_m3: Double {
            fracGradient_kPa_per_m * 1000.0 / 9.80665
        }
    }

    /// Active loss zones for this simulation (sorted by depth, deepest first)
    var lossZones: [LossZone] = []

    /// Total volume lost to formation during simulation (m³)
    var totalLossVolume_m3: Double = 0.0

    /// Debug info for loss zone state
    var lossZoneDebugInfo: String = ""

    // MARK: - Pump Rate and APL

    /// Current pump rate (m³/min) - adjustable during simulation
    var pumpRate_m3_per_min: Double = 0.5

    /// Calculated annular pressure loss above loss zone (kPa)
    var aplAboveLossZone_kPa: Double = 0.0

    /// Total pressure at loss zone (HP + APL)
    var totalPressureAtLossZone_kPa: Double = 0.0

    /// Info about each annulus geometry section for display
    struct AnnulusSectionInfo: Identifiable {
        let id = UUID()
        let name: String           // e.g., "Open Hole", "9-5/8\" Casing"
        let topMD_m: Double
        let bottomMD_m: Double
        let innerDiameter_m: Double  // Pipe OD
        let outerDiameter_m: Double  // Hole/Casing ID
        let area_m2: Double
        let velocity_m_per_min: Double
        let isOverSpeedLimit: Bool
    }

    /// Current annular velocities per geometry section
    var annulusSectionInfos: [AnnulusSectionInfo] = []

    /// Maximum velocity limit from job (if set)
    var maxVelocityLimit_m_per_min: Double? {
        boundJob?.maxAnnularVelocity_m_per_min
    }

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

        // Rheology for APL calculations
        let plasticViscosity_cP: Double
        let yieldPoint_Pa: Double

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
        didSet {
            syncTankVolumeToExpected()
            updateFluidStacks()
        }
    }

    /// Current tank volume reading (m³) - can be overridden by user
    var currentTankVolume_m3: Double = 0.0

    /// Expected tank volume based on 1:1 return ratio (computed to always be accurate)
    var expectedTankVolume_m3: Double {
        initialTankVolume_m3 + cumulativePumpedVolume_m3
    }

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

    /// Sync current tank volume to expected minus losses (when auto-tracking)
    func syncTankVolumeToExpected() {
        if isAutoTrackingTankVolume {
            currentTankVolume_m3 = expectedTankVolume_m3 - totalLossVolume_m3
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
        // Rheology for APL calculations
        var plasticViscosity_cP: Double = 20.0
        var yieldPoint_Pa: Double = 8.0
    }

    var stringStack: [FluidSegment] = []
    var annulusStack: [FluidSegment] = []

    /// Simulated cement returns (cement that overflowed at surface assuming 1:1 return)
    private var simulatedCementReturns_m3: Double = 0.0

    /// All fluid returns in order they came out of annulus (name, volume)
    var fluidReturnsInOrder: [(name: String, volume_m3: Double)] = []

    /// Flag indicating tank adjustment was already applied via loss zone conveyor belt
    private var lossZoneTankAdjustmentApplied: Bool = false

    /// Adjusted cement returns accounting for tank volume difference
    /// If tank shows less than expected (losses), cement returns is reduced by that amount
    /// Note: For loss zone case, adjustment is already applied in the conveyor belt logic
    var cementReturns_m3: Double {
        if lossZoneTankAdjustmentApplied {
            // Already adjusted via conveyor belt - use as-is
            return max(0, simulatedCementReturns_m3)
        } else {
            // No loss zone - apply tank difference directly
            return max(0, simulatedCementReturns_m3 + tankVolumeDifference_m3)
        }
    }

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

        // Initialize pump rate from job default
        pumpRate_m3_per_min = job.defaultPumpRate_m3_per_min

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
                operationType: stage.operationType,
                plasticViscosity_cP: stage.plasticViscosity_cP,
                yieldPoint_Pa: stage.yieldPoint_Pa
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
        syncTankVolumeToExpected()
        updateFluidStacks()
    }

    func previousStage() {
        if progress > 0.0001 {
            progress = 0
        } else if currentStageIndex > 0 {
            currentStageIndex -= 1
            progress = 1.0
        }
        syncTankVolumeToExpected()
        updateFluidStacks()
    }

    func setProgress(_ newProgress: Double) {
        progress = max(0, min(1, newProgress))
        syncTankVolumeToExpected()
        updateFluidStacks()
    }

    /// Set pump rate and recalculate pressures and velocities
    func setPumpRate(_ rate_m3_per_min: Double) {
        pumpRate_m3_per_min = max(0, rate_m3_per_min)
        updateFluidStacks()
    }

    func jumpToStage(_ index: Int) {
        guard index >= 0 && index < stages.count else { return }
        currentStageIndex = index
        progress = 0
        isAutoTrackingTankVolume = true
        syncTankVolumeToExpected()
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

    /// Reset tank volume to expected minus losses (resume auto-tracking)
    func resetTankVolumeToExpected() {
        isAutoTrackingTankVolume = true
        currentTankVolume_m3 = expectedTankVolume_m3 - totalLossVolume_m3
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

    // MARK: - Loss Zone Setup

    /// Add a loss zone at a specific MD depth. Fetches frac pressure from project's pressure window.
    func addLossZone(atMD depth_m: Double) {
        guard let project = boundProject else { return }
        let tvd = project.tvd(of: depth_m)
        guard let frac_kPa = project.window.frac_kPa(atTVD: tvd) else { return }

        // Calculate gradient (kPa/m of TVD)
        let fracGradient = tvd > 0 ? frac_kPa / tvd : 0

        let zone = LossZone(
            depth_m: depth_m,
            tvd_m: tvd,
            frac_kPa: frac_kPa,
            fracGradient_kPa_per_m: fracGradient
        )
        lossZones.append(zone)
        // Keep sorted deepest first (closest to bit first)
        lossZones.sort { $0.depth_m > $1.depth_m }
    }

    /// Clear all loss zones
    func clearLossZones() {
        lossZones.removeAll()
    }

    // MARK: - Loss Zone Pressure Calculations

    /// Calculate hydrostatic pressure (kPa) of fluid above a loss zone depth
    /// Uses fast approximation: assumes linear volume-to-length ratio for performance
    private func hydrostaticPressureAboveLossZone(
        lossZoneDepth_m: Double,
        aboveZoneParcels: [VolumeParcel],
        aboveZoneCapacity_m3: Double,
        geom: ProjectGeometryService
    ) -> Double {
        guard let project = boundProject else { return 0 }

        // Fast approximation: use average length-per-volume ratio
        // This avoids expensive binary search for each parcel
        let totalLength = lossZoneDepth_m  // From surface to loss zone
        let avgLengthPerVolume = totalLength / max(aboveZoneCapacity_m3, 0.001)

        // Get TVD ratio (for deviated wells)
        let lossZoneTVD = project.tvd(of: lossZoneDepth_m)
        let tvdRatio = lossZoneTVD / max(lossZoneDepth_m, 1.0)

        let g = 9.80665
        var totalHP_kPa = 0.0
        var usedVolume: Double = 0.0

        for parcel in aboveZoneParcels {
            guard parcel.volume_m3 > 1e-9 else { continue }

            // Approximate TVD height from volume
            let length = parcel.volume_m3 * avgLengthPerVolume
            let tvdHeight = length * tvdRatio

            // HP contribution = ρ × g × h (in kPa)
            totalHP_kPa += (parcel.density_kgm3 * g * tvdHeight) / 1000.0
            usedVolume += parcel.volume_m3
        }

        return totalHP_kPa
    }

    /// Calculate the volume that can be added above the loss zone before the valve opens
    /// Uses fast analytical calculation based on density difference
    private func volumeToTransition(
        lossZone: LossZone,
        aboveZoneParcels: [VolumeParcel],
        newParcelDensity: Double,
        aboveZoneCapacity: Double,
        currentHP: Double,
        geom: ProjectGeometryService
    ) -> Double {
        guard let project = boundProject else { return 0 }

        // If already at or above frac, no volume can pass
        if currentHP >= lossZone.frac_kPa {
            return 0
        }

        // Fast analytical calculation:
        // When new fluid enters, it displaces old fluid (which overflows to surface)
        // The HP change depends on density difference between new and displaced fluid
        let margin_kPa = lossZone.frac_kPa - currentHP

        // Get the density of fluid that will be displaced (top of the stack = last parcel)
        let displacedDensity = aboveZoneParcels.last?.density_kgm3 ?? 1000.0

        // Net density change per unit volume
        let densityDiff = newParcelDensity - displacedDensity

        // If new fluid is lighter or same, valve won't open from this fluid
        if densityDiff <= 0 {
            return Double.greatestFiniteMagnitude  // Can add unlimited amount
        }

        // Calculate volume that causes margin_kPa pressure increase
        // HP = ρ × g × h, and h ≈ V × (L / V_total) × tvdRatio
        let lossZoneTVD = project.tvd(of: lossZone.depth_m)
        let tvdRatio = lossZoneTVD / max(lossZone.depth_m, 1.0)
        let lengthPerVolume = lossZone.depth_m / max(aboveZoneCapacity, 0.001)

        let g = 9.80665
        // ΔHP = Δρ × g × Δh / 1000
        // margin = densityDiff × g × (V × lengthPerVolume × tvdRatio) / 1000
        // V = margin × 1000 / (densityDiff × g × lengthPerVolume × tvdRatio)
        let volumeToFrac = (margin_kPa * 1000.0) / (densityDiff * g * lengthPerVolume * tvdRatio)

        return max(0, volumeToFrac)
    }

    // MARK: - APL (Annular Pressure Loss) Calculations

    /// Calculate annular velocity given flow rate and geometry
    /// - Parameters:
    ///   - flowRate_m3_per_min: Flow rate in m³/min
    ///   - holeDiameter_m: Hole or casing ID (m)
    ///   - pipeDiameter_m: Pipe OD (m)
    /// - Returns: Velocity in m/min
    private func annularVelocity(
        flowRate_m3_per_min: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double
    ) -> Double {
        let area_m2 = Double.pi / 4.0 * (pow(holeDiameter_m, 2) - pow(pipeDiameter_m, 2))
        guard area_m2 > 1e-9 else { return 0 }
        return flowRate_m3_per_min / area_m2
    }

    /// Calculate friction pressure gradient using Bingham Plastic model (laminar flow)
    /// - Parameters:
    ///   - velocity_m_per_s: Flow velocity in m/s
    ///   - holeDiameter_m: Hole or casing ID (m)
    ///   - pipeDiameter_m: Pipe OD (m)
    ///   - plasticViscosity_cP: Plastic viscosity in centipoise (mPa·s)
    ///   - yieldPoint_Pa: Yield point in Pascals
    /// - Returns: Friction gradient in kPa/m
    private func binghamFrictionGradient(
        velocity_m_per_s: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double,
        plasticViscosity_cP: Double,
        yieldPoint_Pa: Double
    ) -> Double {
        let hydraulicDiameter = holeDiameter_m - pipeDiameter_m
        guard hydraulicDiameter > 1e-6 else { return 0 }

        // Convert PV from cP to Pa·s
        let pv_Pa_s = plasticViscosity_cP / 1000.0

        // Bingham plastic friction gradient for laminar flow in annulus:
        // dP/dL = (4 × YP) / (D_h - D_p) + (8 × PV × V) / (D_h - D_p)²
        // Result in Pa/m, convert to kPa/m

        let yieldTerm = (4.0 * yieldPoint_Pa) / hydraulicDiameter
        let viscousTerm = (8.0 * pv_Pa_s * velocity_m_per_s) / pow(hydraulicDiameter, 2)

        return (yieldTerm + viscousTerm) / 1000.0  // kPa/m
    }

    /// Calculate total APL above a loss zone from the fluid parcels
    private func annularPressureLossAboveLossZone(
        lossZoneDepth_m: Double,
        aboveZoneParcels: [VolumeParcel],
        aboveZoneCapacity_m3: Double,
        pumpRate_m3_per_min: Double,
        geom: ProjectGeometryService
    ) -> Double {
        guard let project = boundProject else { return 0 }
        guard pumpRate_m3_per_min > 0.001 else { return 0 }

        // Get annulus sections above the loss zone
        let annulusSections = project.annulus ?? []
        let drillStrings = project.drillString ?? []

        var totalAPL_kPa = 0.0
        let flowRate_m3_per_s = pumpRate_m3_per_min / 60.0

        // For simplicity, use average rheology from parcels weighted by volume
        var totalVolume = 0.0
        var weightedPV = 0.0
        var weightedYP = 0.0

        for parcel in aboveZoneParcels {
            guard parcel.volume_m3 > 1e-9 else { continue }
            totalVolume += parcel.volume_m3
            weightedPV += parcel.plasticViscosity_cP * parcel.volume_m3
            weightedYP += parcel.yieldPoint_Pa * parcel.volume_m3
        }

        let avgPV = totalVolume > 0 ? weightedPV / totalVolume : 20.0
        let avgYP = totalVolume > 0 ? weightedYP / totalVolume : 8.0

        // Calculate APL for each geometry section above loss zone
        for section in annulusSections {
            // Only consider sections above the loss zone
            let sectionTop = section.topDepth_m
            let sectionBottom = min(section.bottomDepth_m, lossZoneDepth_m)

            guard sectionBottom > sectionTop else { continue }
            let sectionLength = sectionBottom - sectionTop

            // Get geometry
            let holeID = section.innerDiameter_m
            let pipeOD = drillStrings.first?.outerDiameter_m ?? 0.127  // Default 5" pipe

            // Calculate velocity and friction
            let area_m2 = Double.pi / 4.0 * (pow(holeID, 2) - pow(pipeOD, 2))
            guard area_m2 > 1e-9 else { continue }

            let velocity_m_per_s = flowRate_m3_per_s / area_m2
            let frictionGrad = binghamFrictionGradient(
                velocity_m_per_s: velocity_m_per_s,
                holeDiameter_m: holeID,
                pipeDiameter_m: pipeOD,
                plasticViscosity_cP: avgPV,
                yieldPoint_Pa: avgYP
            )

            totalAPL_kPa += frictionGrad * sectionLength
        }

        return totalAPL_kPa
    }

    /// Update annulus section info for display (velocities per section)
    private func updateAnnulusSectionInfos(pumpRate_m3_per_min: Double, geom: ProjectGeometryService) {
        guard let project = boundProject else {
            annulusSectionInfos = []
            return
        }

        let annulusSections = project.annulus ?? []
        let drillStrings = project.drillString ?? []
        let maxVelocity = maxVelocityLimit_m_per_min

        var infos: [AnnulusSectionInfo] = []

        for section in annulusSections {
            // Only show sections in the annulus (above shoe)
            guard section.topDepth_m < shoeDepth_m else { continue }

            let holeID = section.innerDiameter_m
            let pipeOD = drillStrings.first?.outerDiameter_m ?? 0.127

            let area_m2 = Double.pi / 4.0 * (pow(holeID, 2) - pow(pipeOD, 2))
            let velocity_m_per_min = area_m2 > 1e-9 ? pumpRate_m3_per_min / area_m2 : 0

            let isOverLimit = maxVelocity.map { velocity_m_per_min > $0 } ?? false

            let sectionName = section.isCased
                ? "\(String(format: "%.1f", holeID * 1000))mm Casing"
                : "Open Hole \(String(format: "%.1f", holeID * 1000))mm"

            infos.append(AnnulusSectionInfo(
                name: sectionName,
                topMD_m: section.topDepth_m,
                bottomMD_m: min(section.bottomDepth_m, shoeDepth_m),
                innerDiameter_m: pipeOD,
                outerDiameter_m: holeID,
                area_m2: area_m2,
                velocity_m_per_min: velocity_m_per_min,
                isOverSpeedLimit: isOverLimit
            ))
        }

        annulusSectionInfos = infos.sorted { $0.topMD_m < $1.topMD_m }
    }

    // MARK: - Fluid Stack Calculation

    func updateFluidStacks() {
        guard let project = boundProject, let job = boundJob else { return }

        // Reset flags at start of recalculation
        lossZoneTankAdjustmentApplied = false

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

        var expelledAtBit: [VolumeParcel] = []

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
                    add: VolumeParcel(
                        volume_m3: stagePumped,
                        color: stage.color,
                        name: stage.name,
                        density_kgm3: stage.density_kgm3,
                        isCement: isCement,
                        plasticViscosity_cP: stage.plasticViscosity_cP,
                        yieldPoint_Pa: stage.yieldPoint_Pa
                    ),
                    capacity_m3: stringCapacity_m3,
                    expelled: &expelledAtBit
                )
            }
        }

        // Get the active loss zone (for now, just the first/deepest one)
        let activeLossZone = lossZones.first(where: { $0.isActive })

        if let lossZone = activeLossZone {
            // --- Loss Zone Logic ---
            // Split annulus into two sections: below loss zone and above loss zone

            let belowZoneCapacity_m3 = geom.volumeInAnnulus_m3(lossZone.depth_m, shoeDepth_m)
            let aboveZoneCapacity_m3 = geom.volumeInAnnulus_m3(0, lossZone.depth_m)

            // Initialize both sections with active mud
            var belowZoneParcels: [VolumeParcel] = [
                VolumeParcel(volume_m3: belowZoneCapacity_m3, color: activeColor, name: activeName, density_kgm3: activeDensity)
            ]
            var aboveZoneParcels: [VolumeParcel] = [
                VolumeParcel(volume_m3: aboveZoneCapacity_m3, color: activeColor, name: activeName, density_kgm3: activeDensity)
            ]

            var lostToFormation: [VolumeParcel] = []
            var overflowAtSurface: [VolumeParcel] = []
            var debugLines: [String] = []

            // Calculate initial HP and APL (before any pumping)
            let initialHP = hydrostaticPressureAboveLossZone(
                lossZoneDepth_m: lossZone.depth_m,
                aboveZoneParcels: aboveZoneParcels,
                aboveZoneCapacity_m3: aboveZoneCapacity_m3,
                geom: geom
            )
            let initialAPL = annularPressureLossAboveLossZone(
                lossZoneDepth_m: lossZone.depth_m,
                aboveZoneParcels: aboveZoneParcels,
                aboveZoneCapacity_m3: aboveZoneCapacity_m3,
                pumpRate_m3_per_min: pumpRate_m3_per_min,
                geom: geom
            )
            let initialTotal = initialHP + initialAPL

            debugLines.append("Loss Zone @ \(String(format: "%.0f", lossZone.depth_m))m MD (TVD: \(String(format: "%.0f", project.tvd(of: lossZone.depth_m)))m)")
            debugLines.append("Frac pressure: \(String(format: "%.0f", lossZone.frac_kPa)) kPa")
            debugLines.append("Pump rate: \(String(format: "%.2f", pumpRate_m3_per_min)) m³/min")
            debugLines.append("Initial: HP=\(String(format: "%.0f", initialHP)) + APL=\(String(format: "%.0f", initialAPL)) = \(String(format: "%.0f", initialTotal)) kPa")
            debugLines.append("Margin: \(String(format: "%.0f", lossZone.frac_kPa - initialTotal)) kPa")
            debugLines.append("---")

            // Process each expelled parcel through the loss zone valve
            for parcel in expelledAtBit {
                guard parcel.volume_m3 > 0.001 else { continue }

                // First, push into below-zone section
                var overflowFromBelow: [VolumeParcel] = []
                pushToBottomAndOverflowTop(
                    annulusParcels: &belowZoneParcels,
                    add: parcel,
                    capacity_m3: belowZoneCapacity_m3,
                    overflowAtSurface: &overflowFromBelow
                )

                // Any overflow from below-zone arrives at the loss zone valve
                for overflow in overflowFromBelow {
                    guard overflow.volume_m3 > 0.001 else { continue }

                    // Check current valve state ONCE per parcel for performance
                    // Total pressure = HP (hydrostatic) + APL (friction)
                    let currentHP = hydrostaticPressureAboveLossZone(
                        lossZoneDepth_m: lossZone.depth_m,
                        aboveZoneParcels: aboveZoneParcels,
                        aboveZoneCapacity_m3: aboveZoneCapacity_m3,
                        geom: geom
                    )
                    let currentAPL = annularPressureLossAboveLossZone(
                        lossZoneDepth_m: lossZone.depth_m,
                        aboveZoneParcels: aboveZoneParcels,
                        aboveZoneCapacity_m3: aboveZoneCapacity_m3,
                        pumpRate_m3_per_min: pumpRate_m3_per_min,
                        geom: geom
                    )
                    let totalPressure = currentHP + currentAPL
                    let valveOpen = totalPressure >= lossZone.frac_kPa

                    if valveOpen {
                        // Valve is open - all goes to losses
                        lostToFormation.append(VolumeParcel(
                            volume_m3: overflow.volume_m3,
                            color: overflow.color,
                            name: overflow.name,
                            density_kgm3: overflow.density_kgm3,
                            isCement: overflow.isCement,
                            plasticViscosity_cP: overflow.plasticViscosity_cP,
                            yieldPoint_Pa: overflow.yieldPoint_Pa
                        ))
                        debugLines.append("OPEN: \(String(format: "%.2f", overflow.volume_m3)) m³ \(overflow.name) → loss (HP+APL=\(String(format: "%.0f", totalPressure)))")
                    } else {
                        // Valve is closed - calculate how much can pass before it opens
                        // Use totalPressure (HP + APL) to compute margin to frac
                        let volumeToOpen = volumeToTransition(
                            lossZone: lossZone,
                            aboveZoneParcels: aboveZoneParcels,
                            newParcelDensity: overflow.density_kgm3,
                            aboveZoneCapacity: aboveZoneCapacity_m3,
                            currentHP: totalPressure,  // Use total pressure (HP + APL)
                            geom: geom
                        )

                        if volumeToOpen <= 0.01 {
                            // Valve about to open - send all to losses
                            lostToFormation.append(VolumeParcel(
                                volume_m3: overflow.volume_m3,
                                color: overflow.color,
                                name: overflow.name,
                                density_kgm3: overflow.density_kgm3,
                                isCement: overflow.isCement,
                                plasticViscosity_cP: overflow.plasticViscosity_cP,
                                yieldPoint_Pa: overflow.yieldPoint_Pa
                            ))
                            debugLines.append("OPENING: \(String(format: "%.2f", overflow.volume_m3)) m³ \(overflow.name) → loss")
                        } else if volumeToOpen >= overflow.volume_m3 - 0.01 {
                            // Entire parcel can pass without opening valve
                            var surfaceOverflow: [VolumeParcel] = []
                            pushToBottomAndOverflowTop(
                                annulusParcels: &aboveZoneParcels,
                                add: overflow,
                                capacity_m3: aboveZoneCapacity_m3,
                                overflowAtSurface: &surfaceOverflow
                            )
                            overflowAtSurface.append(contentsOf: surfaceOverflow)
                            debugLines.append("CLOSED: \(String(format: "%.2f", overflow.volume_m3)) m³ \(overflow.name) → above (HP+APL=\(String(format: "%.0f", totalPressure)))")
                        } else {
                            // Partial transfer - some passes, rest goes to losses
                            var surfaceOverflow: [VolumeParcel] = []
                            pushToBottomAndOverflowTop(
                                annulusParcels: &aboveZoneParcels,
                                add: VolumeParcel(
                                    volume_m3: volumeToOpen,
                                    color: overflow.color,
                                    name: overflow.name,
                                    density_kgm3: overflow.density_kgm3,
                                    isCement: overflow.isCement,
                                    plasticViscosity_cP: overflow.plasticViscosity_cP,
                                    yieldPoint_Pa: overflow.yieldPoint_Pa
                                ),
                                capacity_m3: aboveZoneCapacity_m3,
                                overflowAtSurface: &surfaceOverflow
                            )
                            overflowAtSurface.append(contentsOf: surfaceOverflow)

                            let lossVolume = overflow.volume_m3 - volumeToOpen
                            lostToFormation.append(VolumeParcel(
                                volume_m3: lossVolume,
                                color: overflow.color,
                                name: overflow.name,
                                density_kgm3: overflow.density_kgm3,
                                isCement: overflow.isCement,
                                plasticViscosity_cP: overflow.plasticViscosity_cP,
                                yieldPoint_Pa: overflow.yieldPoint_Pa
                            ))
                            debugLines.append("SPLIT: \(String(format: "%.2f", volumeToOpen)) m³ → above, \(String(format: "%.2f", lossVolume)) m³ → loss")
                        }
                    }
                }
            }

            // Calculate final HP, APL, and valve state for debug
            let finalHP = hydrostaticPressureAboveLossZone(
                lossZoneDepth_m: lossZone.depth_m,
                aboveZoneParcels: aboveZoneParcels,
                aboveZoneCapacity_m3: aboveZoneCapacity_m3,
                geom: geom
            )
            let finalAPL = annularPressureLossAboveLossZone(
                lossZoneDepth_m: lossZone.depth_m,
                aboveZoneParcels: aboveZoneParcels,
                aboveZoneCapacity_m3: aboveZoneCapacity_m3,
                pumpRate_m3_per_min: pumpRate_m3_per_min,
                geom: geom
            )
            let finalTotal = finalHP + finalAPL

            // Store for external access
            aplAboveLossZone_kPa = finalAPL
            totalPressureAtLossZone_kPa = finalTotal

            // Calculate total losses
            totalLossVolume_m3 = lostToFormation.reduce(0) { $0 + $1.volume_m3 }

            // Calculate above-zone fluid breakdown
            let aboveZoneCement = aboveZoneParcels.filter { $0.isCement }.reduce(0.0) { $0 + $1.volume_m3 }
            let aboveZoneTotal = aboveZoneParcels.reduce(0.0) { $0 + $1.volume_m3 }

            debugLines.append("---")
            debugLines.append("FINAL STATE:")
            debugLines.append("HP=\(String(format: "%.0f", finalHP)) + APL=\(String(format: "%.0f", finalAPL)) = \(String(format: "%.0f", finalTotal)) kPa")
            debugLines.append("Frac: \(String(format: "%.0f", lossZone.frac_kPa)) kPa | Margin: \(String(format: "%.0f", lossZone.frac_kPa - finalTotal)) kPa")
            debugLines.append("Valve: \(finalTotal >= lossZone.frac_kPa ? "OPEN" : "CLOSED")")
            debugLines.append("Above zone: \(String(format: "%.2f", aboveZoneTotal)) m³ (cement: \(String(format: "%.2f", aboveZoneCement)) m³)")
            debugLines.append("Losses: \(String(format: "%.2f", totalLossVolume_m3)) m³")

            // Combine the two sections for visualization
            // Above zone parcels come first (they're at shallower depth)
            // Below zone parcels come after (they're at deeper depth)
            var combinedAnnulusParcels: [VolumeParcel] = []

            // Add below-zone parcels first (they're at the bottom of the annulus)
            combinedAnnulusParcels.append(contentsOf: belowZoneParcels)

            // Add above-zone parcels (they're above the loss zone)
            combinedAnnulusParcels.append(contentsOf: aboveZoneParcels)

            // --- Tank Volume Override for Loss Zone ---
            // Bidirectional adjustment: shuffle parcels between returns, above-zone, and losses
            // Like a conveyor belt: overflowAtSurface ←→ aboveZoneParcels ←→ lostToFormation
            var adjustedAboveZone = aboveZoneParcels
            var adjustedLosses = lostToFormation
            var adjustedReturns = overflowAtSurface

            if !isAutoTrackingTankVolume {
                let simulatedLosses = lostToFormation.reduce(0.0) { $0 + $1.volume_m3 }
                let actualLosses = -tankVolumeDifference_m3  // positive = losses

                // adjustment > 0 means MORE actual losses than simulated (push down)
                // adjustment < 0 means FEWER actual losses than simulated (push up)
                let adjustment = actualLosses - simulatedLosses

                if adjustment > 0.01 {
                    // MORE losses - take from returns, push into top of above-zone, bottom goes to losses
                    var volumeToShift = adjustment
                    debugLines.append("Tank override: shifting \(String(format: "%.2f", volumeToShift)) m³ DOWN (more losses)")

                    while volumeToShift > 0.001 && !adjustedReturns.isEmpty {
                        // Pop from returns (most recent first - end of array)
                        var returnParcel = adjustedReturns.removeLast()
                        let takeVolume = min(volumeToShift, returnParcel.volume_m3)

                        if takeVolume < returnParcel.volume_m3 - 0.001 {
                            // Put remainder back into returns
                            adjustedReturns.append(VolumeParcel(
                                volume_m3: returnParcel.volume_m3 - takeVolume,
                                color: returnParcel.color,
                                name: returnParcel.name,
                                density_kgm3: returnParcel.density_kgm3,
                                isCement: returnParcel.isCement,
                                plasticViscosity_cP: returnParcel.plasticViscosity_cP,
                                yieldPoint_Pa: returnParcel.yieldPoint_Pa
                            ))
                        }

                        // Insert at TOP of above-zone (end of array = surface)
                        adjustedAboveZone.append(VolumeParcel(
                            volume_m3: takeVolume,
                            color: returnParcel.color,
                            name: returnParcel.name,
                            density_kgm3: returnParcel.density_kgm3,
                            isCement: returnParcel.isCement,
                            plasticViscosity_cP: returnParcel.plasticViscosity_cP,
                            yieldPoint_Pa: returnParcel.yieldPoint_Pa
                        ))

                        // Remove same volume from BOTTOM of above-zone (start of array = loss zone)
                        var remainingToRemove = takeVolume
                        while remainingToRemove > 0.001 && !adjustedAboveZone.isEmpty {
                            if adjustedAboveZone[0].volume_m3 <= remainingToRemove {
                                let removed = adjustedAboveZone.removeFirst()
                                remainingToRemove -= removed.volume_m3
                                // Push to losses
                                adjustedLosses.append(removed)
                            } else {
                                // Partial removal - split the parcel
                                let bottomParcel = adjustedAboveZone[0]
                                adjustedLosses.append(VolumeParcel(
                                    volume_m3: remainingToRemove,
                                    color: bottomParcel.color,
                                    name: bottomParcel.name,
                                    density_kgm3: bottomParcel.density_kgm3,
                                    isCement: bottomParcel.isCement,
                                    plasticViscosity_cP: bottomParcel.plasticViscosity_cP,
                                    yieldPoint_Pa: bottomParcel.yieldPoint_Pa
                                ))
                                adjustedAboveZone[0] = VolumeParcel(
                                    volume_m3: bottomParcel.volume_m3 - remainingToRemove,
                                    color: bottomParcel.color,
                                    name: bottomParcel.name,
                                    density_kgm3: bottomParcel.density_kgm3,
                                    isCement: bottomParcel.isCement,
                                    plasticViscosity_cP: bottomParcel.plasticViscosity_cP,
                                    yieldPoint_Pa: bottomParcel.yieldPoint_Pa
                                )
                                remainingToRemove = 0
                            }
                        }

                        volumeToShift -= takeVolume
                    }

                } else if adjustment < -0.01 {
                    // FEWER losses - take from losses, push into bottom of above-zone, top goes to returns
                    var volumeToShift = -adjustment
                    debugLines.append("Tank override: shifting \(String(format: "%.2f", volumeToShift)) m³ UP (fewer losses)")

                    while volumeToShift > 0.001 && !adjustedLosses.isEmpty {
                        // Pop from losses (most recent first - end of array)
                        var lossParcel = adjustedLosses.removeLast()
                        let takeVolume = min(volumeToShift, lossParcel.volume_m3)

                        if takeVolume < lossParcel.volume_m3 - 0.001 {
                            // Put remainder back into losses
                            adjustedLosses.append(VolumeParcel(
                                volume_m3: lossParcel.volume_m3 - takeVolume,
                                color: lossParcel.color,
                                name: lossParcel.name,
                                density_kgm3: lossParcel.density_kgm3,
                                isCement: lossParcel.isCement,
                                plasticViscosity_cP: lossParcel.plasticViscosity_cP,
                                yieldPoint_Pa: lossParcel.yieldPoint_Pa
                            ))
                        }

                        // Insert at BOTTOM of above-zone (start of array = loss zone)
                        adjustedAboveZone.insert(VolumeParcel(
                            volume_m3: takeVolume,
                            color: lossParcel.color,
                            name: lossParcel.name,
                            density_kgm3: lossParcel.density_kgm3,
                            isCement: lossParcel.isCement,
                            plasticViscosity_cP: lossParcel.plasticViscosity_cP,
                            yieldPoint_Pa: lossParcel.yieldPoint_Pa
                        ), at: 0)

                        // Remove same volume from TOP of above-zone (end of array = surface)
                        var remainingToRemove = takeVolume
                        while remainingToRemove > 0.001 && !adjustedAboveZone.isEmpty {
                            let lastIdx = adjustedAboveZone.count - 1
                            if adjustedAboveZone[lastIdx].volume_m3 <= remainingToRemove {
                                let removed = adjustedAboveZone.removeLast()
                                remainingToRemove -= removed.volume_m3
                                // Push to returns
                                adjustedReturns.append(removed)
                            } else {
                                // Partial removal - split the parcel
                                let topParcel = adjustedAboveZone[lastIdx]
                                adjustedReturns.append(VolumeParcel(
                                    volume_m3: remainingToRemove,
                                    color: topParcel.color,
                                    name: topParcel.name,
                                    density_kgm3: topParcel.density_kgm3,
                                    isCement: topParcel.isCement,
                                    plasticViscosity_cP: topParcel.plasticViscosity_cP,
                                    yieldPoint_Pa: topParcel.yieldPoint_Pa
                                ))
                                adjustedAboveZone[lastIdx] = VolumeParcel(
                                    volume_m3: topParcel.volume_m3 - remainingToRemove,
                                    color: topParcel.color,
                                    name: topParcel.name,
                                    density_kgm3: topParcel.density_kgm3,
                                    isCement: topParcel.isCement,
                                    plasticViscosity_cP: topParcel.plasticViscosity_cP,
                                    yieldPoint_Pa: topParcel.yieldPoint_Pa
                                )
                                remainingToRemove = 0
                            }
                        }

                        volumeToShift -= takeVolume
                    }
                }
            }

            // Update total losses from adjusted collection
            totalLossVolume_m3 = adjustedLosses.reduce(0.0) { $0 + $1.volume_m3 }

            // Mark that tank adjustment was applied via conveyor belt (prevents double-adjustment)
            lossZoneTankAdjustmentApplied = !isAutoTrackingTankVolume

            // Convert to segments - need special handling for two-section annulus
            stringStack = segmentsFromStringParcels(stringParcels, maxDepth: floatCollarDepth_m, geom: geom)
            annulusStack = segmentsFromTwoSectionAnnulus(
                belowZoneParcels: belowZoneParcels,
                aboveZoneParcels: adjustedAboveZone,
                lossZoneDepth_m: lossZone.depth_m,
                shoeDepth_m: shoeDepth_m,
                geom: geom
            )

            // Use adjusted returns for cement returns and fluid returns
            simulatedCementReturns_m3 = adjustedReturns.filter { $0.isCement }.reduce(0.0) { $0 + $1.volume_m3 }

            // Calculate returns in order they came out (merge consecutive same-name parcels)
            fluidReturnsInOrder = buildOrderedReturns(from: adjustedReturns)

            lossZoneDebugInfo = debugLines.joined(separator: "\n")

        } else {
            // --- No Loss Zone - Simple Logic with Tank Volume Override Support ---

            // Calculate loss volume from tank override BEFORE building annulus
            var lossVolumeFromOverride: Double = 0.0
            if !isAutoTrackingTankVolume {
                let difference = tankVolumeDifference_m3  // negative means losses
                if difference < -0.01 {
                    lossVolumeFromOverride = -difference
                }
            }

            // Start with annulus full of active fluid (mud)
            var annulusParcels: [VolumeParcel] = [
                VolumeParcel(volume_m3: annulusCapacity_m3, color: activeColor, name: activeName, density_kgm3: activeDensity)
            ]
            var overflowAtSurface: [VolumeParcel] = []

            // If we have losses from tank override, reduce the expelled volumes proportionally
            // This simulates fluid being lost before it can displace the annulus
            var adjustedExpelledAtBit = expelledAtBit
            if lossVolumeFromOverride > 0.01 {
                var remainingLossToApply = lossVolumeFromOverride

                // Remove loss volume from the expelled parcels (starting from the end/most recent)
                // This represents fluid that was lost and never made it to displace the annulus
                var i = adjustedExpelledAtBit.count - 1
                while i >= 0 && remainingLossToApply > 0.001 {
                    let parcel = adjustedExpelledAtBit[i]
                    if parcel.volume_m3 <= remainingLossToApply {
                        remainingLossToApply -= parcel.volume_m3
                        adjustedExpelledAtBit[i] = VolumeParcel(
                            volume_m3: 0,
                            color: parcel.color,
                            name: parcel.name,
                            density_kgm3: parcel.density_kgm3,
                            isCement: parcel.isCement,
                            plasticViscosity_cP: parcel.plasticViscosity_cP,
                            yieldPoint_Pa: parcel.yieldPoint_Pa
                        )
                    } else {
                        adjustedExpelledAtBit[i] = VolumeParcel(
                            volume_m3: parcel.volume_m3 - remainingLossToApply,
                            color: parcel.color,
                            name: parcel.name,
                            density_kgm3: parcel.density_kgm3,
                            isCement: parcel.isCement,
                            plasticViscosity_cP: parcel.plasticViscosity_cP,
                            yieldPoint_Pa: parcel.yieldPoint_Pa
                        )
                        remainingLossToApply = 0
                    }
                    i -= 1
                }
            }

            // Now push the adjusted expelled volumes into the annulus
            for parcel in adjustedExpelledAtBit {
                if parcel.volume_m3 > 0.001 {
                    pushToBottomAndOverflowTop(
                        annulusParcels: &annulusParcels,
                        add: parcel,
                        capacity_m3: annulusCapacity_m3,
                        overflowAtSurface: &overflowAtSurface
                    )
                }
            }

            stringStack = segmentsFromStringParcels(stringParcels, maxDepth: floatCollarDepth_m, geom: geom)
            annulusStack = segmentsFromAnnulusParcels(annulusParcels, maxDepth: shoeDepth_m, geom: geom)
            simulatedCementReturns_m3 = overflowAtSurface.filter { $0.isCement }.reduce(0.0) { $0 + $1.volume_m3 }

            // Calculate returns in order they came out (merge consecutive same-name parcels)
            fluidReturnsInOrder = buildOrderedReturns(from: overflowAtSurface)

            totalLossVolume_m3 = lossVolumeFromOverride
            aplAboveLossZone_kPa = 0
            totalPressureAtLossZone_kPa = 0

            // Update debug info based on override state
            if !isAutoTrackingTankVolume && lossVolumeFromOverride > 0.01 {
                lossZoneDebugInfo = "Tank override active: \(String(format: "%.2f", lossVolumeFromOverride)) m³ losses removed from displacement"
            } else if !isAutoTrackingTankVolume {
                lossZoneDebugInfo = "Tank override active (no losses)"
            } else {
                lossZoneDebugInfo = "No active loss zones"
            }
        }

        // Update annular velocity info for all sections
        updateAnnulusSectionInfos(pumpRate_m3_per_min: pumpRate_m3_per_min, geom: geom)
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
        stringParcels.insert(VolumeParcel(
            volume_m3: addV,
            color: add.color,
            name: add.name,
            density_kgm3: add.density_kgm3,
            isCement: add.isCement,
            plasticViscosity_cP: add.plasticViscosity_cP,
            yieldPoint_Pa: add.yieldPoint_Pa
        ), at: 0)

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
                expelled.append(VolumeParcel(
                    volume_m3: overflow,
                    color: last.color,
                    name: last.name,
                    density_kgm3: last.density_kgm3,
                    isCement: last.isCement,
                    plasticViscosity_cP: last.plasticViscosity_cP,
                    yieldPoint_Pa: last.yieldPoint_Pa
                ))
                stringParcels.append(VolumeParcel(
                    volume_m3: v - overflow,
                    color: last.color,
                    name: last.name,
                    density_kgm3: last.density_kgm3,
                    isCement: last.isCement,
                    plasticViscosity_cP: last.plasticViscosity_cP,
                    yieldPoint_Pa: last.yieldPoint_Pa
                ))
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
        annulusParcels.insert(VolumeParcel(
            volume_m3: addV,
            color: add.color,
            name: add.name,
            density_kgm3: add.density_kgm3,
            isCement: add.isCement,
            plasticViscosity_cP: add.plasticViscosity_cP,
            yieldPoint_Pa: add.yieldPoint_Pa
        ), at: 0)

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
                overflowAtSurface.append(VolumeParcel(
                    volume_m3: overflow,
                    color: last.color,
                    name: last.name,
                    density_kgm3: last.density_kgm3,
                    isCement: last.isCement,
                    plasticViscosity_cP: last.plasticViscosity_cP,
                    yieldPoint_Pa: last.yieldPoint_Pa
                ))
                annulusParcels.append(VolumeParcel(
                    volume_m3: v - overflow,
                    color: last.color,
                    name: last.name,
                    density_kgm3: last.density_kgm3,
                    isCement: last.isCement,
                    plasticViscosity_cP: last.plasticViscosity_cP,
                    yieldPoint_Pa: last.yieldPoint_Pa
                ))
                overflow = 0
            }
        }
    }

    // MARK: - Build Ordered Returns

    /// Build ordered returns list from overflow parcels, merging consecutive same-name fluids
    private func buildOrderedReturns(from overflowParcels: [VolumeParcel]) -> [(name: String, volume_m3: Double)] {
        var result: [(name: String, volume_m3: Double)] = []

        for parcel in overflowParcels {
            guard parcel.volume_m3 > 0.001 else { continue }

            // If the last entry has the same name, add to it; otherwise create new entry
            if let lastIndex = result.indices.last, result[lastIndex].name == parcel.name {
                result[lastIndex].volume_m3 += parcel.volume_m3
            } else {
                result.append((name: parcel.name, volume_m3: parcel.volume_m3))
            }
        }

        // Filter out very small volumes
        return result.filter { $0.volume_m3 > 0.01 }
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

    /// Convert two-section annulus (below and above loss zone) into MD segments for visualization
    private func segmentsFromTwoSectionAnnulus(
        belowZoneParcels: [VolumeParcel],
        aboveZoneParcels: [VolumeParcel],
        lossZoneDepth_m: Double,
        shoeDepth_m: Double,
        geom: ProjectGeometryService
    ) -> [FluidSegment] {
        var segments: [FluidSegment] = []

        // Process below-zone parcels (from shoe upward to loss zone)
        var usedFromBottom: Double = 0.0
        let belowZoneLength = shoeDepth_m - lossZoneDepth_m

        for parcel in belowZoneParcels {
            let v = max(0.0, parcel.volume_m3)
            guard v > 1e-12 else { continue }

            let length = lengthForAnnulusVolumeFromBottom(
                volume: v,
                bottomMD: shoeDepth_m,
                usedFromBottom: usedFromBottom,
                geom: geom
            )
            if length <= 1e-12 { continue }

            let topMD = max(lossZoneDepth_m, shoeDepth_m - usedFromBottom - length)
            let botMD = max(lossZoneDepth_m, shoeDepth_m - usedFromBottom)

            if botMD > topMD + 0.5 {
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

            if usedFromBottom >= belowZoneLength - 1e-9 { break }
        }

        // Process above-zone parcels (from loss zone upward to surface)
        usedFromBottom = 0.0

        for parcel in aboveZoneParcels {
            let v = max(0.0, parcel.volume_m3)
            guard v > 1e-12 else { continue }

            let length = lengthForAnnulusVolumeFromBottom(
                volume: v,
                bottomMD: lossZoneDepth_m,
                usedFromBottom: usedFromBottom,
                geom: geom
            )
            if length <= 1e-12 { continue }

            let topMD = max(0.0, lossZoneDepth_m - usedFromBottom - length)
            let botMD = max(0.0, lossZoneDepth_m - usedFromBottom)

            if botMD > topMD + 0.5 {
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

            if usedFromBottom >= lossZoneDepth_m - 1e-9 { break }
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

        // Cement tops in annulus (merge adjacent segments with same name)
        lines.append("CEMENT TOPS (THEORETICAL):")
        let cementSegments = annulusStack.filter { $0.isCement }.sorted { $0.topMD_m < $1.topMD_m }
        if cementSegments.isEmpty {
            lines.append("  No cement in annulus yet")
        } else {
            // Merge adjacent segments with same name
            var mergedSegments: [(name: String, topMD: Double, bottomMD: Double, topTVD: Double, bottomTVD: Double)] = []
            for segment in cementSegments {
                if let last = mergedSegments.last, last.name == segment.name, abs(last.bottomMD - segment.topMD_m) < 1.0 {
                    // Merge with previous segment
                    mergedSegments[mergedSegments.count - 1].bottomMD = segment.bottomMD_m
                    mergedSegments[mergedSegments.count - 1].bottomTVD = segment.bottomTVD_m
                } else {
                    mergedSegments.append((segment.name, segment.topMD_m, segment.bottomMD_m, segment.topTVD_m, segment.bottomTVD_m))
                }
            }
            for segment in mergedSegments {
                lines.append("  \(segment.name):")
                lines.append("    Top: \(Int(segment.topMD))m MD / \(Int(segment.topTVD))m TVD")
                lines.append("    Bottom: \(Int(segment.bottomMD))m MD / \(Int(segment.bottomTVD))m TVD")
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

        // Fluid returns breakdown
        if !fluidReturnsInOrder.isEmpty {
            lines.append("FLUID RETURNS (in order):")
            for (fluidName, volume) in fluidReturnsInOrder {
                lines.append("  \(fluidName): \(String(format: "%.2f", volume))m³")
            }
            lines.append("")
        }

        // Cement returns
        lines.append("Cement returns: \(String(format: "%.2f", cementReturns_m3))m³")

        // Losses to formation
        if totalLossVolume_m3 > 0.01 {
            lines.append("Losses to formation: \(String(format: "%.2f", totalLossVolume_m3))m³")
        }

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
            if totalLossVolume_m3 > 0.01 {
                lines.append("  Losses: \(String(format: "%.2f", totalLossVolume_m3))m³")
            }
        }

        // Loss zone info if active
        if let lossZone = lossZones.first(where: { $0.isActive }) {
            lines.append("")
            lines.append("LOSS ZONE:")
            lines.append("  Depth: \(Int(lossZone.depth_m))m MD / \(Int(lossZone.tvd_m))m TVD")
            lines.append("  Frac pressure: \(String(format: "%.0f", lossZone.frac_kPa)) kPa")
            lines.append("  Final pressure at zone: \(String(format: "%.0f", totalPressureAtLossZone_kPa)) kPa")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate prose-style job report summary for pasting into reports
    func generateJobReportText(jobName: String, casingType: String) -> String {
        var parts: [String] = []

        // Header
        parts.append("\(casingType) cement job")

        // Track total displacement and when displacements end
        var totalDisplacement_m3: Double = 0
        var lastDisplacementIndex: Int = -1

        for (index, stage) in stages.enumerated() {
            if stage.isOperation {
                guard let sourceStage = stage.sourceStage else { continue }
                let opType = stage.operationType

                switch opType {
                case .pressureTestLines:
                    if let pressure = sourceStage.pressure_MPa {
                        parts.append("pressure test lines to \(String(format: "%.1f", pressure))MPa")
                    } else {
                        parts.append("pressure test lines")
                    }

                case .tripSet:
                    if let pressure = sourceStage.pressure_MPa {
                        parts.append("trips set at \(String(format: "%.1f", pressure))MPa")
                    } else {
                        parts.append("trips set")
                    }

                case .plugDrop:
                    if let volume = sourceStage.operationVolume_L, volume > 0 {
                        parts.append("lines pumped out with \(String(format: "%.1f", volume / 1000))m³, drop plug")
                    } else {
                        parts.append("drop plug on the fly")
                    }

                case .bumpPlug:
                    // Insert total displacement before bump plug if we have any
                    if totalDisplacement_m3 > 0.01 && lastDisplacementIndex >= 0 {
                        parts.append("total displacement \(String(format: "%.2f", totalDisplacement_m3))m³")
                        totalDisplacement_m3 = 0 // Reset so we don't add it again
                    }
                    if let overPressure = sourceStage.overPressure_MPa, let finalPressure = sourceStage.pressure_MPa {
                        parts.append("bumped plug \(String(format: "%.1f", overPressure))MPa over FCP to \(String(format: "%.1f", finalPressure))MPa")
                    } else if let finalPressure = sourceStage.pressure_MPa {
                        parts.append("bumped plug to \(String(format: "%.1f", finalPressure))MPa")
                    } else {
                        parts.append("bumped plug")
                    }

                case .pressureTestCasing:
                    var text = "pressure tested casing"
                    if let pressure = sourceStage.pressure_MPa {
                        text += " to \(String(format: "%.1f", pressure))MPa"
                    }
                    if let duration = sourceStage.duration_min {
                        text += " (\(Int(duration))min)"
                    }
                    // Add notes if present (for "ok" or other results)
                    if !sourceStage.notes.isEmpty {
                        text += " \(sourceStage.notes)"
                    }
                    parts.append(text)

                case .floatCheck:
                    if sourceStage.floatsClosed {
                        parts.append("floats held")
                    } else {
                        parts.append("floats did not hold")
                    }

                case .bleedBack:
                    if let volume = sourceStage.operationVolume_L, volume > 0 {
                        parts.append("bled back \(Int(volume))L")
                    } else {
                        parts.append("bled back")
                    }

                case .rigOut:
                    parts.append(stage.name)

                case .other, .none:
                    if !stage.name.isEmpty {
                        parts.append(stage.name)
                    }
                }
            } else {
                // Pump stage
                let volume = stage.volume_m3
                let density = stage.density_kgm3
                let name = stage.name

                switch stage.stageType {
                case .preFlush, .spacer:
                    parts.append("pump \(String(format: "%.1f", volume)) m³ \(name) at \(Int(density))kg/m³")

                case .leadCement:
                    if let sourceStage = stage.sourceStage, let tonnage = sourceStage.tonnage_t {
                        parts.append("pump lead cement \(String(format: "%.1f", volume)) m³ (\(String(format: "%.2f", tonnage))t) \(name) at \(Int(density))kg/m³")
                    } else {
                        parts.append("pump lead cement \(String(format: "%.1f", volume)) m³ \(name) at \(Int(density))kg/m³")
                    }

                case .tailCement:
                    if let sourceStage = stage.sourceStage, let tonnage = sourceStage.tonnage_t {
                        parts.append("pump tail cement \(String(format: "%.1f", volume)) m³ (\(String(format: "%.2f", tonnage))t) \(name) at \(Int(density))kg/m³")
                    } else {
                        parts.append("pump tail cement \(String(format: "%.1f", volume)) m³ \(name) at \(Int(density))kg/m³")
                    }

                case .mudDisplacement:
                    totalDisplacement_m3 += volume
                    lastDisplacementIndex = index
                    // Check if previous part was also a displacement
                    if let lastPart = parts.last, lastPart.hasPrefix("displaced with") {
                        // Remove "displaced with" prefix and add as continuation
                        parts.append("\(String(format: "%.1f", volume)) m³ of \(Int(density))kg/m³ \(name)")
                    } else {
                        parts.append("displaced with \(String(format: "%.1f", volume)) m³ of \(Int(density))kg/m³ \(name)")
                    }

                case .displacement:
                    totalDisplacement_m3 += volume
                    lastDisplacementIndex = index
                    // Check if previous part was also a displacement
                    if let lastPart = parts.last, (lastPart.hasPrefix("displaced with") || lastPart.contains("m³ of")) {
                        parts.append("\(String(format: "%.1f", volume)) m³ of \(Int(density))kg/m³ water")
                    } else {
                        parts.append("displaced with \(String(format: "%.1f", volume)) m³ of \(Int(density))kg/m³ water")
                    }

                case .operation:
                    break // Handled above
                }
            }
        }

        // Add total displacement at end if it wasn't already added (no bump plug operation)
        if totalDisplacement_m3 > 0.01 {
            parts.append("total displacement \(String(format: "%.2f", totalDisplacement_m3))m³")
        }

        // Add returns information in order they came out of annulus (skip mud)
        var returnsText: [String] = []
        for (fluidName, volume) in fluidReturnsInOrder {
            // Skip mud returns as they're expected
            if !fluidName.lowercased().contains("mud") {
                returnsText.append("\(String(format: "%.2f", volume))m³ \(fluidName) returns")
            }
        }

        if !returnsText.isEmpty {
            parts.append(returnsText.joined(separator: ", "))
        }

        // Add losses information if there were any
        if totalLossVolume_m3 > 0.01 {
            parts.append("\(String(format: "%.2f", totalLossVolume_m3))m³ losses")
        }

        // Add return ratio if not 1:1 (only when there's meaningful pumped volume)
        if cumulativePumpedVolume_m3 > 0.1 {
            let ratio = overallReturnRatio
            if abs(ratio - 1.0) > 0.02 {
                // Significant deviation from 1:1
                parts.append("return ratio 1:\(String(format: "%.2f", ratio))")
            }
        }

        return parts.joined(separator: ", ") + "."
    }
}
