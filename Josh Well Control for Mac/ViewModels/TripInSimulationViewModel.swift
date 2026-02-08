//
//  TripInSimulationViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for trip-in simulation - running pipe into a well.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
class TripInSimulationViewModel {
    // MARK: - Current Simulation

    var currentSimulation: TripInSimulation?

    // MARK: - Input Parameters

    // Source trip-out simulation
    var sourceSimulationID: UUID?
    var sourceSimulationName: String = ""

    // Depths
    var startBitMD_m: Double = 0  // Start at surface
    var endBitMD_m: Double = 0    // Run to TD
    var controlMD_m: Double = 0   // Shoe/control depth
    var step_m: Double = 100

    // String configuration
    var stringName: String = "7\" Casing"
    var pipeOD_m: Double = 0.1778   // 7"
    var pipeID_m: Double = 0.1572   // 6.184"
    var pipeWeight_kgm: Double = 35.7

    // Floated casing
    var isFloatedCasing: Bool = false
    var floatSubMD_m: Double = 0
    var crackFloat_kPa: Double = 2100

    // Fluids
    var fillMudID: UUID?  // Selected fill-up mud from project muds
    var activeMudDensity_kgpm3: Double = 1200  // Density of selected fill mud
    var targetESD_kgpm3: Double = 1200
    var baseMudDensity_kgpm3: Double = 1200

    /// Update density when fill mud is selected
    func updateFillMudDensity(from muds: [MudProperties]) {
        if let mudID = fillMudID, let mud = muds.first(where: { $0.id == mudID }) {
            activeMudDensity_kgpm3 = mud.density_kgm3
        }
    }

    // MARK: - Results

    var steps: [TripInStep] = []
    var selectedIndex: Int = 0
    var stepSlider: Double = 0

    // MARK: - State

    var isRunning: Bool = false
    var progressValue: Double = 0.0
    var progressMessage: String = ""

    // TVD source selection - use directional plan instead of surveys for projection
    var useDirectionalPlanForTVD: Bool = false

    // MARK: - Computed Properties

    var selectedStep: TripInStep? {
        guard selectedIndex >= 0 && selectedIndex < steps.count else { return nil }
        return steps[selectedIndex]
    }

    /// Summary: total fill volume
    var totalFillVolume_m3: Double {
        steps.last?.cumulativeFillVolume_m3 ?? 0
    }

    /// Summary: total displacement returns
    var totalDisplacementReturns_m3: Double {
        steps.last?.cumulativeDisplacementReturns_m3 ?? 0
    }

    /// Summary: max required choke pressure
    var maxChokePressure_kPa: Double {
        steps.map { $0.requiredChokePressure_kPa }.max() ?? 0
    }

    /// Summary: min ESD at control
    var minESDAtControl_kgpm3: Double {
        steps.map { $0.ESDAtControl_kgpm3 }.min() ?? 0
    }

    /// First depth where ESD drops below target
    var depthBelowTarget_m: Double? {
        steps.first(where: { $0.isBelowTarget })?.bitMD_m
    }

    /// Max differential pressure for floated casing
    var maxDifferentialPressure_kPa: Double {
        steps.map { $0.differentialPressureAtBottom_kPa }.max() ?? 0
    }

    // MARK: - Step Data Structure

    struct TripInStep: Identifiable {
        let id = UUID()
        let stepIndex: Int
        let bitMD_m: Double
        let bitTVD_m: Double
        let stepFillVolume_m3: Double
        let cumulativeFillVolume_m3: Double
        let expectedFillClosed_m3: Double
        let expectedFillOpen_m3: Double
        let stepDisplacementReturns_m3: Double
        let cumulativeDisplacementReturns_m3: Double
        let ESDAtControl_kgpm3: Double
        let ESDAtBit_kgpm3: Double
        let requiredChokePressure_kPa: Double
        let isBelowTarget: Bool
        let differentialPressureAtBottom_kPa: Double
        let annulusPressureAtBit_kPa: Double
        let stringPressureAtBit_kPa: Double
        let floatState: String
        let mudDensityAtControl_kgpm3: Double

        // Layers for visualization
        var layersAnnulus: [TripLayerSnapshot] = []
        var layersString: [TripLayerSnapshot] = []
        var layersPocket: [TripLayerSnapshot] = []
    }

    // MARK: - Bootstrap from Project

    func bootstrap(from project: ProjectState) {
        // Set depths from project geometry
        let annulusSections = project.annulus ?? []
        if let deepest = annulusSections.max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
            endBitMD_m = deepest.bottomDepth_m
        }
        if let deepestCasing = annulusSections.filter({ $0.isCased }).max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
            controlMD_m = deepestCasing.bottomDepth_m
        }

        // Fluid properties
        if let activeMud = project.activeMud {
            activeMudDensity_kgpm3 = activeMud.density_kgm3
            baseMudDensity_kgpm3 = activeMud.density_kgm3
            targetESD_kgpm3 = activeMud.density_kgm3
        }

        // String from project (use deepest section as default)
        let drillString = project.drillString ?? []
        if let deepestSection = drillString.max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
            pipeOD_m = deepestSection.outerDiameter_m
            pipeID_m = deepestSection.innerDiameter_m
            stringName = deepestSection.name.isEmpty ? "Drill String" : deepestSection.name
        }
    }

    // MARK: - Source Type

    enum SourceType: String {
        case none = "None"
        case tripSimulation = "Trip Simulation"
        case tripTracker = "Trip Tracker"
        case wellboreState = "Wellbore State"
    }

    var sourceType: SourceType = .none

    // For Trip Tracker source
    var sourceTripTrackID: UUID?
    var sourceTripTrackName: String = ""

    // Initial pocket layers imported from source
    var importedPocketLayers: [TripLayerSnapshot] = []

    // MARK: - Import from Trip Simulation

    /// Import pocket layers by querying for just the final step (no JSON cache needed)
    func importFromTripSimulation(_ simulation: TripSimulation, project: ProjectState, context: ModelContext) {
        let totalStart = CFAbsoluteTimeGetCurrent()
        print("🔄 Starting import from: \(simulation.name)")

        var t = CFAbsoluteTimeGetCurrent()
        sourceType = .tripSimulation
        sourceSimulationID = simulation.id
        sourceSimulationName = simulation.name
        sourceTripTrackID = nil
        sourceTripTrackName = ""
        controlMD_m = simulation.shoeMD_m
        baseMudDensity_kgpm3 = simulation.baseMudDensity_kgpm3
        targetESD_kgpm3 = simulation.targetESDAtTD_kgpm3
        endBitMD_m = simulation.startBitMD_m
        startBitMD_m = simulation.endMD_m
        print("📋 Copied parameters: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t))s")

        // Query for just the final step
        t = CFAbsoluteTimeGetCurrent()
        let simID = simulation.id
        var descriptor = FetchDescriptor<TripSimulationStep>(
            predicate: #Predicate { step in
                step.simulation?.id == simID
            },
            sortBy: [SortDescriptor(\.stepIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        print("📝 Built descriptor: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t))s")

        do {
            t = CFAbsoluteTimeGetCurrent()
            let steps = try context.fetch(descriptor)
            print("🔍 Fetch query: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t))s")

            if let finalStep = steps.first {
                print("✅ Got final step (index \(finalStep.stepIndex))")

                // Check both layer types
                let pocketLayers = finalStep.layersPocket
                let annulusLayers = finalStep.layersAnnulus

                print("📦 Pocket layers: \(pocketLayers.count)")

                // Analyze layer structure
                let topMDs = pocketLayers.map { $0.topMD }
                let bottomMDs = pocketLayers.map { $0.bottomMD }
                let uniqueTopMDs = Set(topMDs)
                let uniqueBottomMDs = Set(bottomMDs)
                print("   Unique topMD values: \(uniqueTopMDs.count), bottomMD values: \(uniqueBottomMDs.count)")
                if let minTop = topMDs.min(), let maxTop = topMDs.max() {
                    print("   TopMD range: \(String(format: "%.1f", minTop)) to \(String(format: "%.1f", maxTop))")
                }
                if let minBottom = bottomMDs.min(), let maxBottom = bottomMDs.max() {
                    print("   BottomMD range: \(String(format: "%.1f", minBottom)) to \(String(format: "%.1f", maxBottom))")
                }

                // Show first few and last few layers
                for (i, layer) in pocketLayers.prefix(3).enumerated() {
                    print("   [\(i)] \(String(format: "%.1f", layer.topMD))-\(String(format: "%.1f", layer.bottomMD))m, ρ=\(String(format: "%.0f", layer.rho_kgpm3)), vol=\(String(format: "%.3f", layer.volume_m3))m³")
                }
                if pocketLayers.count > 6 {
                    print("   ... (\(pocketLayers.count - 6) more) ...")
                }
                for (i, layer) in pocketLayers.suffix(3).enumerated() {
                    let idx = pocketLayers.count - 3 + i
                    print("   [\(idx)] \(String(format: "%.1f", layer.topMD))-\(String(format: "%.1f", layer.bottomMD))m, ρ=\(String(format: "%.0f", layer.rho_kgpm3)), vol=\(String(format: "%.3f", layer.volume_m3))m³")
                }

                print("📦 Annulus layers: \(annulusLayers.count)")
                if let first = annulusLayers.first, let last = annulusLayers.last {
                    print("   First: \(String(format: "%.0f", first.topMD))-\(String(format: "%.0f", first.bottomMD))m, ρ=\(String(format: "%.0f", first.rho_kgpm3))")
                    print("   Last: \(String(format: "%.0f", last.topMD))-\(String(format: "%.0f", last.bottomMD))m, ρ=\(String(format: "%.0f", last.rho_kgpm3))")
                }

                // Use pocket layers as requested
                importedPocketLayers = pocketLayers
                print("💾 Imported \(importedPocketLayers.count) pocket layers")
            } else {
                print("⚠️ No steps found for simulation")
            }
        } catch {
            print("❌ Failed to fetch final step: \(error)")
        }

        print("✅ Import complete, total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - totalStart))s")
    }

    // MARK: - Import from Trip Tracker

    func importFromTripTracker(_ tripTrack: TripTrack, project: ProjectState) {
        sourceType = .tripTracker
        sourceTripTrackID = tripTrack.id
        sourceTripTrackName = tripTrack.name
        sourceSimulationID = nil
        sourceSimulationName = ""

        // Copy parameters
        controlMD_m = tripTrack.shoeMD_m
        baseMudDensity_kgpm3 = tripTrack.baseMudDensity_kgpm3
        targetESD_kgpm3 = tripTrack.targetESD_kgpm3
        endBitMD_m = tripTrack.tdMD_m  // Trip-in goes to TD
        startBitMD_m = tripTrack.currentBitMD_m  // Start where tracker currently is

        // Get current pocket layers from trip tracker
        importedPocketLayers = tripTrack.layersPocket
    }

    // MARK: - Import from Wellbore State Snapshot

    /// Import from a WellboreStateSnapshot (e.g., mid-trip-out handoff)
    func importFromWellboreState(_ state: WellboreStateSnapshot, project: ProjectState) {
        sourceType = .wellboreState
        sourceSimulationID = nil
        sourceSimulationName = state.sourceDescription
        sourceTripTrackID = nil
        sourceTripTrackName = ""

        // Use pocket layers from the snapshot
        importedPocketLayers = state.layersPocket

        // Start where the snapshot's bit is (e.g., mid-trip-out depth)
        startBitMD_m = state.bitMD_m

        // End at TD (deepest annulus section)
        let annulusSections = project.annulus ?? []
        if let deepest = annulusSections.max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
            endBitMD_m = deepest.bottomDepth_m
        }

        // Carry over target ESD from snapshot
        targetESD_kgpm3 = state.ESDAtControl_kgpm3

        // Fluid properties from project
        if let activeMud = project.activeMud {
            activeMudDensity_kgpm3 = activeMud.density_kgm3
            baseMudDensity_kgpm3 = activeMud.density_kgm3
        }
    }

    /// Display name for source
    var sourceDisplayName: String {
        switch sourceType {
        case .none:
            return "No source selected"
        case .tripSimulation:
            return sourceSimulationName.isEmpty ? "Trip Simulation" : sourceSimulationName
        case .tripTracker:
            return sourceTripTrackName.isEmpty ? "Trip Tracker" : sourceTripTrackName
        case .wellboreState:
            return sourceSimulationName.isEmpty ? "Wellbore State" : sourceSimulationName
        }
    }

    // MARK: - Run Simulation

    func runSimulation(project: ProjectState) {
        isRunning = true
        progressValue = 0.0
        progressMessage = "Running trip-in simulation..."
        steps.removeAll()
        circulationHistory.removeAll()

        // Create TVD sampler - preferPlan uses directional plan for projection
        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

        // Get geometry service (may be used for annulus capacity calculations in future)
        _ = ProjectGeometryService(
            project: project,
            currentStringBottomMD: endBitMD_m,
            tvdMapper: { md in tvdSampler.tvd(of: md) }
        )

        // Calculate step depths (surface to TD)
        var depths: [Double] = []
        var currentDepth = startBitMD_m
        while currentDepth <= endBitMD_m {
            depths.append(currentDepth)
            currentDepth += step_m
        }
        if depths.last != endBitMD_m {
            depths.append(endBitMD_m)
        }

        var cumulativeFill: Double = 0
        var cumulativeDisplacement: Double = 0
        let controlTVD = tvdSampler.tvd(of: controlMD_m)

        // Use imported pocket layers (from Trip Simulation or Trip Tracker)
        let currentPocketLayers: [TripLayerSnapshot] = importedPocketLayers

        print("🏃 Running simulation with \(currentPocketLayers.count) pocket layers")
        print("📍 Start: \(startBitMD_m)m, End: \(endBitMD_m)m, Control: \(controlMD_m)m")
        if let first = currentPocketLayers.first {
            print("📦 First layer: \(first.topMD)-\(first.bottomMD)m, ρ=\(first.rho_kgpm3)")
        }
        if let last = currentPocketLayers.last {
            print("📦 Last layer: \(last.topMD)-\(last.bottomMD)m, ρ=\(last.rho_kgpm3)")
        }

        for (index, bitMD) in depths.enumerated() {
            let bitTVD = tvdSampler.tvd(of: bitMD)
            let prevMD = index > 0 ? depths[index - 1] : startBitMD_m

            // Pipe geometry for this interval
            let pipeCapacity = Double.pi / 4.0 * pipeID_m * pipeID_m  // m³/m
            let pipeDisplacement = Double.pi / 4.0 * (pipeOD_m * pipeOD_m - pipeID_m * pipeID_m)  // steel volume per meter
            let intervalLength = abs(bitMD - prevMD)

            // Fill volume: pipe capacity for this interval (if not floated, or above float sub)
            let stepFill: Double
            if isFloatedCasing && bitMD > floatSubMD_m {
                // Below float sub - no fill (air section)
                stepFill = 0
            } else {
                stepFill = pipeCapacity * intervalLength
            }
            cumulativeFill += stepFill

            // Displacement returns: pipe displacing annulus
            let stepDisplacement = (Double.pi / 4.0 * pipeOD_m * pipeOD_m) * intervalLength
            cumulativeDisplacement += stepDisplacement

            // Expected fill calculations
            let expectedClosed = pipeCapacity * bitMD  // Full pipe capacity to this depth
            let expectedOpen = pipeDisplacement * bitMD  // Just steel displacement

            // Get wellbore ID from project annulus geometry at this depth
            let annulusSections = project.annulus ?? []
            let sectionAtDepth = annulusSections.first { section in
                bitMD >= section.topDepth_m && bitMD <= section.bottomDepth_m
            }
            // Use section's inner diameter (wellbore ID), fallback to 8.5" if no section found
            let wellboreID_m = sectionAtDepth?.innerDiameter_m ?? 0.2159

            // Calculate annular capacity (wellbore minus pipe)
            _ = max(0.001, Double.pi / 4.0 * (wellboreID_m * wellboreID_m - pipeOD_m * pipeOD_m))

            // Calculate displaced pocket layers for this step
            // As pipe enters, layers expand (same volume in narrower annulus = taller)
            // Expansion pushes layers above upward, overflowing at surface
            let displacedPockets = calculateDisplacedPocketLayers(
                bitMD: bitMD,
                pocketLayers: currentPocketLayers,
                annulusSections: annulusSections,
                pipeOD_m: pipeOD_m,
                tvdSampler: tvdSampler,
                debugStep: index
            )

            // Calculate ESD from the displaced layers
            let ESDAtControl = calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: controlMD_m,
                tvdSampler: tvdSampler
            )

            let ESDAtBit = calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: bitMD,
                tvdSampler: tvdSampler
            )

            // Summary debug for first and last step
            if index == 0 || index == depths.count - 1 {
                print("📊 Step \(index): bitMD=\(String(format: "%.1f", bitMD))m, disp=\(String(format: "%.2f", cumulativeDisplacement))m³, layers=\(displacedPockets.count), ESD@Ctrl=\(String(format: "%.1f", ESDAtControl))")
            }

            // Check if below target
            let isBelowTarget = ESDAtControl < targetESD_kgpm3

            // Required choke pressure to compensate
            let requiredChoke: Double
            if isBelowTarget {
                // Choke pressure = (target - actual) × 0.00981 × TVD
                requiredChoke = max(0, (targetESD_kgpm3 - ESDAtControl) * 0.00981 * controlTVD)
            } else {
                requiredChoke = 0
            }

            // Differential pressure at bottom of string
            // ΔP = P_annulus - P_string at bit depth
            var floatState = "N/A"

            // Annulus pressure at bit = ESD × 0.00981 × TVD
            let annulusHP = ESDAtBit * 0.00981 * bitTVD
            var stringHP: Double = 0

            if isFloatedCasing && bitMD >= floatSubMD_m {
                // Floated casing: string has air column below fill level
                // Calculate mud height inside string based on cumulative fill
                let pipeCapacityPerMeter = Double.pi / 4.0 * pipeID_m * pipeID_m
                let mudHeightInString = cumulativeFill / pipeCapacityPerMeter
                let fillLevelMD = min(mudHeightInString, bitMD)
                let fillLevelTVD = tvdSampler.tvd(of: fillLevelMD)

                // String pressure at bit = mud column pressure only (air below is ~0)
                stringHP = activeMudDensity_kgpm3 * 0.00981 * fillLevelTVD

                // Float state based on differential vs crack pressure at float sub
                let floatSubTVD = tvdSampler.tvd(of: floatSubMD_m)
                let annulusPressureAtFloat = baseMudDensity_kgpm3 * 0.00981 * floatSubTVD
                let mudAboveFloat = min(mudHeightInString, floatSubMD_m)
                let insidePressureAtFloat = activeMudDensity_kgpm3 * 0.00981 * tvdSampler.tvd(of: mudAboveFloat)
                let diffAtFloat = annulusPressureAtFloat - insidePressureAtFloat

                if diffAtFloat >= crackFloat_kPa {
                    let openPercent = min(100, Int((diffAtFloat / crackFloat_kPa - 1.0) * 100 + 50))
                    floatState = "OPEN \(openPercent)%"
                } else {
                    let closedPercent = Int((1.0 - diffAtFloat / crackFloat_kPa) * 100)
                    floatState = "CLOSED \(closedPercent)%"
                }
            } else {
                // Non-floated casing or above float sub: full mud column in string
                stringHP = activeMudDensity_kgpm3 * 0.00981 * bitTVD
                floatState = "Full"
            }

            let differentialPressure = annulusHP - stringHP

            // Create step with displaced pocket layers (pushed up by pipe displacement)
            let step = TripInStep(
                stepIndex: index,
                bitMD_m: bitMD,
                bitTVD_m: bitTVD,
                stepFillVolume_m3: stepFill,
                cumulativeFillVolume_m3: cumulativeFill,
                expectedFillClosed_m3: expectedClosed,
                expectedFillOpen_m3: expectedOpen,
                stepDisplacementReturns_m3: stepDisplacement,
                cumulativeDisplacementReturns_m3: cumulativeDisplacement,
                ESDAtControl_kgpm3: ESDAtControl,
                ESDAtBit_kgpm3: ESDAtBit,
                requiredChokePressure_kPa: requiredChoke,
                isBelowTarget: isBelowTarget,
                differentialPressureAtBottom_kPa: differentialPressure,
                annulusPressureAtBit_kPa: annulusHP,
                stringPressureAtBit_kPa: stringHP,
                floatState: floatState,
                mudDensityAtControl_kgpm3: ESDAtControl,
                layersAnnulus: [],
                layersString: [],
                layersPocket: displacedPockets
            )

            steps.append(step)
            progressValue = Double(index + 1) / Double(depths.count)
        }

        isRunning = false
        progressMessage = "Complete"
        selectedIndex = 0
        stepSlider = 0
    }

    // MARK: - ESD Calculations

    /// Calculate ESD at control depth from displaced layers
    private func calculateESDFromLayers(
        layers: [TripLayerSnapshot],
        atDepthMD: Double,
        tvdSampler: TvdSampler
    ) -> Double {
        let depthTVD = tvdSampler.tvd(of: atDepthMD)
        guard depthTVD > 0 else { return 0 }

        // Calculate hydrostatic pressure from layers down to the specified depth
        var totalPressure_kPa: Double = 0

        for layer in layers {
            let layerTop = layer.topMD
            let layerBottom = min(layer.bottomMD, atDepthMD)

            if layerBottom > layerTop && layerTop < atDepthMD {
                let topTVD = tvdSampler.tvd(of: layerTop)
                let bottomTVD = tvdSampler.tvd(of: layerBottom)
                let tvdInterval = bottomTVD - topTVD

                if tvdInterval > 0 {
                    totalPressure_kPa += layer.rho_kgpm3 * 0.00981 * tvdInterval
                }
            }
        }

        // ESD = total pressure / (0.00981 × TVD)
        return totalPressure_kPa / (0.00981 * depthTVD)
    }

    /// Calculate displaced pocket layers at current bit depth
    /// Models pipe displacement with geometry-aware expansion during trip-IN
    ///
    /// Physics (cup analogy with varying diameter):
    /// - As pipe enters a layer, that layer EXPANDS (same volume in narrower annulus = taller)
    /// - Expansion factor = original wellbore capacity / new annular capacity
    /// - Expanded layers push layers above them upward
    /// - Top layers overflow at surface and are removed
    /// - Layers below the bit are unchanged (pipe hasn't reached them)
    private func calculateDisplacedPocketLayers(
        bitMD: Double,
        pocketLayers: [TripLayerSnapshot],
        annulusSections: [AnnulusSection],
        pipeOD_m: Double,
        tvdSampler: TvdSampler,
        debugStep: Int? = nil
    ) -> [TripLayerSnapshot] {
        guard !pocketLayers.isEmpty else { return [] }

        let isDebug = debugStep == 0 || debugStep == 1

        // Helper: get wellbore ID at a given depth from annulus sections
        func wellboreID(at depth: Double) -> Double {
            if let section = annulusSections.first(where: { depth >= $0.topDepth_m && depth <= $0.bottomDepth_m }) {
                return section.innerDiameter_m
            }
            // Fallback: use deepest section's ID or default 8.5"
            return annulusSections.max(by: { $0.bottomDepth_m < $1.bottomDepth_m })?.innerDiameter_m ?? 0.2159
        }

        // Helper: calculate expansion factor at a depth
        // Expansion = original wellbore area / new annular area
        func expansionFactor(at depth: Double) -> Double {
            let wellboreID_m = wellboreID(at: depth)
            let originalArea = Double.pi / 4.0 * wellboreID_m * wellboreID_m
            let annularArea = Double.pi / 4.0 * (wellboreID_m * wellboreID_m - pipeOD_m * pipeOD_m)
            guard annularArea > 0.0001 else { return 1.0 }
            return originalArea / annularArea
        }

        if isDebug {
            print("🔬 calculateDisplacedPocketLayers: bitMD=\(String(format: "%.1f", bitMD))m")
            print("   Input layers: \(pocketLayers.count), pipeOD=\(String(format: "%.4f", pipeOD_m))m")
            let sampleExpansion = expansionFactor(at: bitMD)
            print("   Expansion factor at bit: \(String(format: "%.3f", sampleExpansion))")
        }

        // Sort layers from bottom to top (deepest bottomMD first)
        // This lets us process from bottom up, accumulating expansion shift
        let sortedLayers = pocketLayers.sorted { $0.bottomMD > $1.bottomMD }

        // First pass: calculate new heights for each layer
        // Layers the pipe has passed through expand
        // Layers below the bit stay at original height
        struct LayerTransform {
            let layer: TripLayerSnapshot
            let originalHeight: Double
            let newHeight: Double
            let expansion: Double  // newHeight - originalHeight
        }

        var transforms: [LayerTransform] = []

        for layer in sortedLayers {
            let originalHeight = layer.bottomMD - layer.topMD
            guard originalHeight > 0 else { continue }

            let newHeight: Double
            let midpoint = (layer.topMD + layer.bottomMD) / 2.0

            // IMPORTANT: Layers already in annulus coordinates (e.g., pumped fluid) should NOT expand
            // They only shift upward from pipe displacement, not expand due to area change
            let alreadyInAnnulus = layer.isInAnnulus == true

            if layer.bottomMD <= bitMD {
                // Layer is entirely above the bit (pipe has passed through it)
                if alreadyInAnnulus {
                    // Already in annulus coordinates - no expansion, just shift
                    newHeight = originalHeight
                } else {
                    // Original wellbore layer - expands based on local geometry
                    let factor = expansionFactor(at: midpoint)
                    newHeight = originalHeight * factor
                }
            } else if layer.topMD < bitMD {
                // Layer spans the bit - partially expanded
                // Portion above bit expands (if not already in annulus), portion below stays same
                let aboveBitHeight = bitMD - layer.topMD
                let belowBitHeight = layer.bottomMD - bitMD
                if alreadyInAnnulus {
                    // Already in annulus - no expansion
                    newHeight = originalHeight
                } else {
                    let factor = expansionFactor(at: (layer.topMD + bitMD) / 2.0)
                    newHeight = (aboveBitHeight * factor) + belowBitHeight
                }
            } else {
                // Layer is entirely below the bit - no expansion yet
                newHeight = originalHeight
            }

            let expansion = newHeight - originalHeight
            transforms.append(LayerTransform(
                layer: layer,
                originalHeight: originalHeight,
                newHeight: newHeight,
                expansion: expansion
            ))
        }

        // Second pass: calculate new positions
        // Process from bottom to top - each layer's expansion pushes layers above it up
        // IMPORTANT: Enforce contiguity - each layer's top becomes next layer's bottom
        var resultLayers: [TripLayerSnapshot] = []
        var skippedOverflow = 0

        // Start from the deepest layer - its bottom stays at original position
        // (it's below the bit, no shift yet)
        var nextLayerBottom: Double? = nil  // Track for contiguity

        for (idx, transform) in transforms.enumerated() {
            let layer = transform.layer

            // Calculate new bottom
            let newBottom: Double
            if let prevTop = nextLayerBottom {
                // Use previous layer's top as this layer's bottom (ensures contiguity)
                newBottom = prevTop
            } else {
                // First layer (deepest) - use original bottom
                newBottom = layer.bottomMD
            }

            // New top = new bottom - new height
            let newTop = newBottom - transform.newHeight

            // Track this layer's top for the next layer's bottom
            nextLayerBottom = newTop

            // Debug
            if isDebug && (idx < 3 || idx >= transforms.count - 3) {
                print("   [\(idx)] orig=\(String(format: "%.1f", layer.topMD))-\(String(format: "%.1f", layer.bottomMD))m h=\(String(format: "%.1f", transform.originalHeight)) → new=\(String(format: "%.1f", newTop))-\(String(format: "%.1f", newBottom))m h=\(String(format: "%.1f", transform.newHeight))")
            }

            // Skip if layer overflowed at surface
            if newBottom <= 0 {
                skippedOverflow += 1
                continue
            }

            // Clamp to surface
            let clampedTop = max(0, newTop)
            let clampedBottom = newBottom

            if clampedTop >= clampedBottom {
                skippedOverflow += 1
                continue
            }

            let newTopTVD = tvdSampler.tvd(of: clampedTop)
            let newBottomTVD = tvdSampler.tvd(of: clampedBottom)
            let deltaP = layer.rho_kgpm3 * 0.00981 * (newBottomTVD - newTopTVD)

            resultLayers.append(TripLayerSnapshot(
                side: layer.side,
                topMD: clampedTop,
                bottomMD: clampedBottom,
                topTVD: newTopTVD,
                bottomTVD: newBottomTVD,
                rho_kgpm3: layer.rho_kgpm3,
                deltaHydroStatic_kPa: deltaP,
                volume_m3: 0,
                colorR: layer.colorR,
                colorG: layer.colorG,
                colorB: layer.colorB,
                colorA: layer.colorA,
                isInAnnulus: layer.isInAnnulus  // Preserve flag for pumped fluids
            ))
        }

        if isDebug {
            print("   Result: \(resultLayers.count) layers, \(skippedOverflow) overflowed")
            if let first = resultLayers.first, let last = resultLayers.last {
                print("   First: \(String(format: "%.1f", first.topMD))-\(String(format: "%.1f", first.bottomMD))m, ρ=\(String(format: "%.0f", first.rho_kgpm3))")
                print("   Last: \(String(format: "%.1f", last.topMD))-\(String(format: "%.1f", last.bottomMD))m, ρ=\(String(format: "%.0f", last.rho_kgpm3))")
            }
        }

        return resultLayers
    }

    // MARK: - Slider Sync

    func updateFromSlider() {
        let index = Int(stepSlider.rounded())
        if index >= 0 && index < steps.count {
            selectedIndex = index
        }
    }

    func syncSliderToSelection() {
        stepSlider = Double(selectedIndex)
    }

    // MARK: - Save Simulation

    func saveSimulation(to project: ProjectState, context: ModelContext) -> TripInSimulation {
        let simulation = TripInSimulation(
            name: "Trip In - \(stringName)",
            sourceSimulationID: sourceSimulationID,
            sourceSimulationName: sourceSimulationName,
            startBitMD_m: startBitMD_m,
            endBitMD_m: endBitMD_m,
            controlMD_m: controlMD_m,
            step_m: step_m,
            stringName: stringName,
            pipeOD_m: pipeOD_m,
            pipeID_m: pipeID_m,
            pipeWeight_kgm: pipeWeight_kgm,
            isFloatedCasing: isFloatedCasing,
            floatSubMD_m: floatSubMD_m,
            crackFloat_kPa: crackFloat_kPa,
            fillMudID: fillMudID,
            activeMudDensity_kgpm3: activeMudDensity_kgpm3,
            targetESD_kgpm3: targetESD_kgpm3,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            project: project
        )

        // Add steps
        print("💾 Saving \(steps.count) steps")
        for step in steps {
            let savedStep = TripInSimulationStep(
                stepIndex: step.stepIndex,
                bitMD_m: step.bitMD_m,
                bitTVD_m: step.bitTVD_m,
                stepFillVolume_m3: step.stepFillVolume_m3,
                cumulativeFillVolume_m3: step.cumulativeFillVolume_m3,
                expectedFillClosed_m3: step.expectedFillClosed_m3,
                expectedFillOpen_m3: step.expectedFillOpen_m3,
                stepDisplacementReturns_m3: step.stepDisplacementReturns_m3,
                cumulativeDisplacementReturns_m3: step.cumulativeDisplacementReturns_m3,
                ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                ESDAtBit_kgpm3: step.ESDAtBit_kgpm3,
                requiredChokePressure_kPa: step.requiredChokePressure_kPa,
                isBelowTarget: step.isBelowTarget,
                differentialPressureAtBottom_kPa: step.differentialPressureAtBottom_kPa,
                annulusPressureAtBit_kPa: step.annulusPressureAtBit_kPa,
                stringPressureAtBit_kPa: step.stringPressureAtBit_kPa,
                floatState: step.floatState,
                mudDensityAtControl_kgpm3: step.mudDensityAtControl_kgpm3
            )
            // Save all layer types
            savedStep.layersAnnulus = step.layersAnnulus
            savedStep.layersString = step.layersString
            savedStep.layersPocket = step.layersPocket

            if step.stepIndex == 0 || step.stepIndex == steps.count - 1 {
                print("   Step \(step.stepIndex): \(step.layersPocket.count) pocket layers, HP Ann=\(step.annulusPressureAtBit_kPa)")
            }

            simulation.addStep(savedStep)
        }

        simulation.updateSummaryResults()
        context.insert(simulation)

        // Freeze inputs for data integrity - ensures simulation remains valid if project changes
        let fillMud = fillMudID.flatMap { id in (project.muds ?? []).first { $0.id == id } }
        simulation.freezeInputs(from: project, fillMud: fillMud)

        // Clear step layer data to reduce storage (layers can be recomputed from frozen inputs)
        simulation.clearStepLayerData()

        if project.tripInSimulations == nil {
            project.tripInSimulations = []
        }
        project.tripInSimulations?.append(simulation)

        try? context.save()
        currentSimulation = simulation
        return simulation
    }

    // MARK: - Load Simulation

    func loadSimulation(_ simulation: TripInSimulation) {
        currentSimulation = simulation

        // Load parameters
        sourceSimulationID = simulation.sourceSimulationID
        sourceSimulationName = simulation.sourceSimulationName
        startBitMD_m = simulation.startBitMD_m
        endBitMD_m = simulation.endBitMD_m
        controlMD_m = simulation.controlMD_m
        step_m = simulation.step_m
        stringName = simulation.stringName
        pipeOD_m = simulation.pipeOD_m
        pipeID_m = simulation.pipeID_m
        pipeWeight_kgm = simulation.pipeWeight_kgm
        isFloatedCasing = simulation.isFloatedCasing
        floatSubMD_m = simulation.floatSubMD_m
        crackFloat_kPa = simulation.crackFloat_kPa
        fillMudID = simulation.fillMudID
        activeMudDensity_kgpm3 = simulation.activeMudDensity_kgpm3
        targetESD_kgpm3 = simulation.targetESD_kgpm3
        baseMudDensity_kgpm3 = simulation.baseMudDensity_kgpm3

        // Load steps - explicitly access the steps array to ensure SwiftData faults in the data
        let savedSteps = simulation.steps ?? []
        print("📥 Loading simulation '\(simulation.name)' with \(savedSteps.count) steps")

        steps = savedSteps.sorted { $0.stepIndex < $1.stepIndex }.map { step in
            // Explicitly access layersPocketData to ensure it's faulted in
            let pocketLayers = step.layersPocket
            let annulusLayers = step.layersAnnulus
            let stringLayers = step.layersString

            if step.stepIndex == 0 || step.stepIndex == savedSteps.count - 1 {
                print("   Step \(step.stepIndex): \(pocketLayers.count) pocket layers, HP Ann=\(step.annulusPressureAtBit_kPa), HP Str=\(step.stringPressureAtBit_kPa)")
            }

            return TripInStep(
                stepIndex: step.stepIndex,
                bitMD_m: step.bitMD_m,
                bitTVD_m: step.bitTVD_m,
                stepFillVolume_m3: step.stepFillVolume_m3,
                cumulativeFillVolume_m3: step.cumulativeFillVolume_m3,
                expectedFillClosed_m3: step.expectedFillClosed_m3,
                expectedFillOpen_m3: step.expectedFillOpen_m3,
                stepDisplacementReturns_m3: step.stepDisplacementReturns_m3,
                cumulativeDisplacementReturns_m3: step.cumulativeDisplacementReturns_m3,
                ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                ESDAtBit_kgpm3: step.ESDAtBit_kgpm3,
                requiredChokePressure_kPa: step.requiredChokePressure_kPa,
                isBelowTarget: step.isBelowTarget,
                differentialPressureAtBottom_kPa: step.differentialPressureAtBottom_kPa,
                annulusPressureAtBit_kPa: step.annulusPressureAtBit_kPa,
                stringPressureAtBit_kPa: step.stringPressureAtBit_kPa,
                floatState: step.floatState,
                mudDensityAtControl_kgpm3: step.mudDensityAtControl_kgpm3,
                layersAnnulus: annulusLayers,
                layersString: stringLayers,
                layersPocket: pocketLayers
            )
        }

        print("📥 Loaded \(steps.count) steps")
        if let firstStep = steps.first {
            print("   First step pocket layers: \(firstStep.layersPocket.count)")
        }

        circulationHistory.removeAll()
        selectedIndex = 0
        stepSlider = 0
    }

    // MARK: - Clear

    func clear() {
        currentSimulation = nil
        steps.removeAll()
        circulationHistory.removeAll()
        selectedIndex = 0
        stepSlider = 0
    }

    // MARK: - Delete Simulation

    /// Delete a saved simulation
    func deleteSimulation(_ simulation: TripInSimulation, context: ModelContext) {
        // If this is the currently loaded simulation, clear the view
        if currentSimulation?.id == simulation.id {
            clear()
        }
        context.delete(simulation)
        try? context.save()
    }

    // MARK: - Wellbore State Export

    /// Export the wellbore state at the currently selected step for handoff to Trip Out or Pump Schedule.
    func wellboreStateAtSelectedStep() -> WellboreStateSnapshot? {
        guard selectedIndex >= 0 && selectedIndex < steps.count else { return nil }
        let step = steps[selectedIndex]
        return WellboreStateSnapshot(
            bitMD_m: step.bitMD_m,
            bitTVD_m: step.bitTVD_m,
            layersPocket: step.layersPocket,
            layersAnnulus: step.layersAnnulus,
            layersString: step.layersString,
            SABP_kPa: step.requiredChokePressure_kPa,
            ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
            sourceDescription: "Trip In at \(Int(step.bitMD_m))m MD",
            timestamp: .now
        )
    }

    // MARK: - Circulate At Depth (Interactive)
    // Uses CirculationService for dual-stack (string+annulus) circulation physics.

    /// Current circulate-out schedule (preview before committing)
    var circulateOutSchedule: [CirculationService.CirculateOutStep] = []

    /// Pump output for stroke calculations (m³/stroke)
    var pumpOutput_m3perStroke: Double = 0.01  // Default ~10 L/stroke

    /// Queue of pump operations to execute in series
    var pumpQueue: [CirculationService.PumpOperation] = []

    /// Currently selected mud for adding to queue
    var selectedCirculateMudID: UUID?

    /// Volume for next pump operation (m³)
    var circulateVolume_m3: Double = 5.0

    /// Preview layers after all queued operations (before committing)
    var previewPocketLayers: [TripLayerSnapshot] = []

    /// ESD after proposed circulation
    var previewESDAtControl: Double = 0

    /// Required SABP after proposed circulation
    var previewRequiredSABP: Double = 0

    /// History of committed circulation operations
    var circulationHistory: [CirculationService.CirculationRecord] = []

    /// Add a pump operation to the queue
    func addToPumpQueue(mud: MudProperties, volume_m3: Double) {
        let operation = CirculationService.PumpOperation(
            mudID: mud.id,
            mudName: mud.name,
            mudDensity_kgpm3: mud.density_kgm3,
            mudColorR: mud.colorR,
            mudColorG: mud.colorG,
            mudColorB: mud.colorB,
            volume_m3: volume_m3
        )
        pumpQueue.append(operation)
    }

    /// Remove an operation from the queue
    func removeFromPumpQueue(at index: Int) {
        guard index >= 0 && index < pumpQueue.count else { return }
        pumpQueue.remove(at: index)
    }

    /// Clear the entire pump queue
    func clearPumpQueue() {
        pumpQueue.removeAll()
        previewPocketLayers = []
        circulateOutSchedule = []
        previewESDAtControl = 0
        previewRequiredSABP = 0
    }

    /// Preview the effect of all queued pump operations.
    /// Models fluid flowing DOWN the drill string and UP the annulus.
    func previewPumpQueue(
        fromStepIndex: Int,
        project: ProjectState
    ) {
        guard fromStepIndex >= 0 && fromStepIndex < steps.count else { return }
        guard !pumpQueue.isEmpty else { return }

        let currentStep = steps[fromStepIndex]
        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
        let geom = ProjectGeometryService(
            project: project,
            currentStringBottomMD: currentStep.bitMD_m,
            tvdMapper: { md in tvdSampler.tvd(of: md) }
        )

        let result = CirculationService.previewPumpQueue(
            pocketLayers: currentStep.layersPocket,
            stringLayers: currentStep.layersString,
            bitMD: currentStep.bitMD_m,
            controlMD: controlMD_m,
            targetESD_kgpm3: targetESD_kgpm3,
            geom: geom,
            tvdSampler: tvdSampler,
            pumpQueue: pumpQueue,
            pumpOutput_m3perStroke: pumpOutput_m3perStroke,
            activeMudDensity_kgpm3: activeMudDensity_kgpm3
        )

        circulateOutSchedule = result.schedule
        previewPocketLayers = result.resultLayersPocket
        previewESDAtControl = result.ESDAtControl
        previewRequiredSABP = result.requiredSABP
    }

    /// Commit all queued pump operations - updates the pocket layers and recalculates all subsequent steps
    func commitPumpQueue(
        fromStepIndex: Int,
        project: ProjectState
    ) {
        guard fromStepIndex >= 0 && fromStepIndex < steps.count else { return }
        guard !previewPocketLayers.isEmpty else { return }
        guard !pumpQueue.isEmpty else { return }

        let currentStep = steps[fromStepIndex]
        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

        // Calculate ESD before
        let esdBefore = CirculationService.calculateESDFromLayers(
            layers: currentStep.layersPocket,
            atDepthMD: controlMD_m,
            tvdSampler: tvdSampler
        )

        // Record the circulation
        let record = CirculationService.CirculationRecord(
            timestamp: Date(),
            atBitMD_m: currentStep.bitMD_m,
            operations: pumpQueue,
            ESDBeforeAtControl_kgpm3: esdBefore,
            ESDAfterAtControl_kgpm3: previewESDAtControl,
            SABPRequired_kPa: previewRequiredSABP
        )
        circulationHistory.append(record)

        // Mark ALL layers above the current bit as isInAnnulus = true
        // because they've already been expanded to annular coordinates at this bit depth.
        // Without this, recalculation would apply expansion again to these layers.
        let bitMD = currentStep.bitMD_m
        let markedLayers = previewPocketLayers.map { layer -> TripLayerSnapshot in
            if layer.bottomMD <= bitMD {
                // Layer is entirely above the bit - already in annulus coordinates
                var marked = layer
                marked.isInAnnulus = true
                return marked
            } else {
                // Layer below the bit (or spanning) - in original wellbore coordinates
                // previewPumpQueue already splits layers at the bit, so spanning shouldn't occur
                return layer
            }
        }

        // Update imported pocket layers (used when re-running simulation)
        importedPocketLayers = markedLayers

        // Update the current step
        steps[fromStepIndex] = TripInStep(
            stepIndex: currentStep.stepIndex,
            bitMD_m: currentStep.bitMD_m,
            bitTVD_m: currentStep.bitTVD_m,
            stepFillVolume_m3: currentStep.stepFillVolume_m3,
            cumulativeFillVolume_m3: currentStep.cumulativeFillVolume_m3,
            expectedFillClosed_m3: currentStep.expectedFillClosed_m3,
            expectedFillOpen_m3: currentStep.expectedFillOpen_m3,
            stepDisplacementReturns_m3: currentStep.stepDisplacementReturns_m3,
            cumulativeDisplacementReturns_m3: currentStep.cumulativeDisplacementReturns_m3,
            ESDAtControl_kgpm3: previewESDAtControl,
            ESDAtBit_kgpm3: currentStep.ESDAtBit_kgpm3,
            requiredChokePressure_kPa: previewRequiredSABP,
            isBelowTarget: previewESDAtControl < targetESD_kgpm3,
            differentialPressureAtBottom_kPa: currentStep.differentialPressureAtBottom_kPa,
            annulusPressureAtBit_kPa: currentStep.annulusPressureAtBit_kPa,
            stringPressureAtBit_kPa: currentStep.stringPressureAtBit_kPa,
            floatState: currentStep.floatState,
            mudDensityAtControl_kgpm3: previewESDAtControl,
            layersAnnulus: currentStep.layersAnnulus,
            layersString: currentStep.layersString,
            layersPocket: markedLayers
        )

        // Clear queue and preview
        pumpQueue.removeAll()
        previewPocketLayers = []
        circulateOutSchedule = []

        // Save current selection before recalculating
        let savedIndex = fromStepIndex

        // Auto-recalculate all subsequent steps with new pocket layers
        if fromStepIndex < steps.count - 1 {
            recalculateStepsFrom(stepIndex: fromStepIndex, project: project)
        }

        // Restore selection to where user was (don't jump to last step)
        selectedIndex = savedIndex
        stepSlider = Double(savedIndex)
    }

    /// Recalculate all steps from the given index forward using the pocket layers at that step
    func recalculateStepsFrom(stepIndex: Int, project: ProjectState) {
        guard stepIndex >= 0 && stepIndex < steps.count else { return }

        let startingStep = steps[stepIndex]
        let startingBitMD = startingStep.bitMD_m

        // If already at end, nothing to recalculate
        guard startingBitMD < endBitMD_m else { return }

        // IMPORTANT: Use pocket layers as a FIXED base for all steps (not chained).
        // calculateDisplacedPocketLayers is a "from scratch" function that calculates
        // displacement at any bit depth given base layers. Chaining would double-expand.
        let basePocketLayers = startingStep.layersPocket

        // Remove all steps after the current one
        steps = Array(steps.prefix(stepIndex + 1))

        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
        let controlTVD = tvdSampler.tvd(of: controlMD_m)
        let annulusSections = project.annulus ?? []

        // Calculate remaining depths
        var depths: [Double] = []
        var nextDepth = startingBitMD + step_m
        while nextDepth <= endBitMD_m {
            depths.append(nextDepth)
            nextDepth += step_m
        }
        if let last = depths.last, last != endBitMD_m {
            depths.append(endBitMD_m)
        }

        guard !depths.isEmpty else { return }

        var cumulativeFill = startingStep.cumulativeFillVolume_m3
        var cumulativeDisplacement = startingStep.cumulativeDisplacementReturns_m3

        for (index, bitMD) in depths.enumerated() {
            let bitTVD = tvdSampler.tvd(of: bitMD)
            let prevMD = index == 0 ? startingBitMD : depths[index - 1]

            let pipeCapacity = Double.pi / 4.0 * pipeID_m * pipeID_m
            let intervalLength = abs(bitMD - prevMD)

            // Fill volume
            let stepFill: Double
            if isFloatedCasing && bitMD > floatSubMD_m {
                stepFill = 0
            } else {
                stepFill = pipeCapacity * intervalLength
            }
            cumulativeFill += stepFill

            // Displacement
            let stepDisplacement = (Double.pi / 4.0 * pipeOD_m * pipeOD_m) * intervalLength
            cumulativeDisplacement += stepDisplacement

            let expectedClosed = pipeCapacity * bitMD
            let expectedOpen = (Double.pi / 4.0 * (pipeOD_m * pipeOD_m - pipeID_m * pipeID_m)) * bitMD

            // Displace pocket layers from the FIXED base (not chained from previous step)
            let displacedPockets = calculateDisplacedPocketLayers(
                bitMD: bitMD,
                pocketLayers: basePocketLayers,
                annulusSections: annulusSections,
                pipeOD_m: pipeOD_m,
                tvdSampler: tvdSampler
            )

            // Calculate ESD
            let ESDAtControl = calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: controlMD_m,
                tvdSampler: tvdSampler
            )

            let ESDAtBit = calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: bitMD,
                tvdSampler: tvdSampler
            )

            let isBelowTarget = ESDAtControl < targetESD_kgpm3

            let requiredChoke: Double
            if isBelowTarget {
                requiredChoke = max(0, (targetESD_kgpm3 - ESDAtControl) * 0.00981 * controlTVD)
            } else {
                requiredChoke = 0
            }

            // Pressure calculations
            let annulusHP = ESDAtBit * 0.00981 * bitTVD
            var stringHP: Double = 0
            var floatState = "N/A"

            if isFloatedCasing && bitMD >= floatSubMD_m {
                let pipeCapacityPerMeter = Double.pi / 4.0 * pipeID_m * pipeID_m
                let mudHeightInString = cumulativeFill / pipeCapacityPerMeter
                let fillLevelMD = min(mudHeightInString, bitMD)
                let fillLevelTVD = tvdSampler.tvd(of: fillLevelMD)

                stringHP = activeMudDensity_kgpm3 * 0.00981 * fillLevelTVD

                let floatSubTVD = tvdSampler.tvd(of: floatSubMD_m)
                let annulusPressureAtFloat = baseMudDensity_kgpm3 * 0.00981 * floatSubTVD
                let mudAboveFloat = min(mudHeightInString, floatSubMD_m)
                let insidePressureAtFloat = activeMudDensity_kgpm3 * 0.00981 * tvdSampler.tvd(of: mudAboveFloat)
                let diffAtFloat = annulusPressureAtFloat - insidePressureAtFloat

                if diffAtFloat >= crackFloat_kPa {
                    let openPercent = min(100, Int((diffAtFloat / crackFloat_kPa - 1.0) * 100 + 50))
                    floatState = "OPEN \(openPercent)%"
                } else {
                    let closedPercent = Int((1.0 - diffAtFloat / crackFloat_kPa) * 100)
                    floatState = "CLOSED \(closedPercent)%"
                }
            } else {
                stringHP = activeMudDensity_kgpm3 * 0.00981 * bitTVD
                floatState = "Full"
            }

            let differentialPressure = annulusHP - stringHP

            let step = TripInStep(
                stepIndex: steps.count,
                bitMD_m: bitMD,
                bitTVD_m: bitTVD,
                stepFillVolume_m3: stepFill,
                cumulativeFillVolume_m3: cumulativeFill,
                expectedFillClosed_m3: expectedClosed,
                expectedFillOpen_m3: expectedOpen,
                stepDisplacementReturns_m3: stepDisplacement,
                cumulativeDisplacementReturns_m3: cumulativeDisplacement,
                ESDAtControl_kgpm3: ESDAtControl,
                ESDAtBit_kgpm3: ESDAtBit,
                requiredChokePressure_kPa: requiredChoke,
                isBelowTarget: isBelowTarget,
                differentialPressureAtBottom_kPa: differentialPressure,
                annulusPressureAtBit_kPa: annulusHP,
                stringPressureAtBit_kPa: stringHP,
                floatState: floatState,
                mudDensityAtControl_kgpm3: ESDAtControl,
                layersAnnulus: [],
                layersString: [],
                layersPocket: displacedPockets
            )

            steps.append(step)
        }
    }

    /// Total volume in pump queue
    var totalQueueVolume_m3: Double {
        pumpQueue.reduce(0) { $0 + $1.volume_m3 }
    }

    // MARK: - Continue Simulation from Current Depth

    /// Continue the trip-in simulation from the current selected step to TD
    /// Uses the current pocket layers (which may have been updated by circulation)
    func continueSimulation(fromStepIndex: Int, project: ProjectState) {
        guard fromStepIndex >= 0 && fromStepIndex < steps.count else { return }

        let currentStep = steps[fromStepIndex]
        let currentBitMD = currentStep.bitMD_m

        // If already at end, nothing to do
        guard currentBitMD < endBitMD_m else { return }

        isRunning = true
        progressMessage = "Continuing simulation from \(Int(currentBitMD))m..."

        // IMPORTANT: Use pocket layers as a FIXED base for all steps (not chained).
        // calculateDisplacedPocketLayers is a "from scratch" function.
        let basePocketLayers = currentStep.layersPocket

        // Remove all steps after the current one
        steps = Array(steps.prefix(fromStepIndex + 1))

        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
        let controlTVD = tvdSampler.tvd(of: controlMD_m)

        // Calculate remaining depths
        var depths: [Double] = []
        var nextDepth = currentBitMD + step_m
        while nextDepth <= endBitMD_m {
            depths.append(nextDepth)
            nextDepth += step_m
        }
        if depths.last != endBitMD_m {
            depths.append(endBitMD_m)
        }

        guard !depths.isEmpty else {
            isRunning = false
            return
        }

        var cumulativeFill = currentStep.cumulativeFillVolume_m3
        var cumulativeDisplacement = currentStep.cumulativeDisplacementReturns_m3

        let annulusSections = project.annulus ?? []

        for (index, bitMD) in depths.enumerated() {
            let bitTVD = tvdSampler.tvd(of: bitMD)
            let prevMD = index == 0 ? currentBitMD : depths[index - 1]

            let pipeCapacity = Double.pi / 4.0 * pipeID_m * pipeID_m
            let intervalLength = abs(bitMD - prevMD)

            // Fill volume
            let stepFill: Double
            if isFloatedCasing && bitMD > floatSubMD_m {
                stepFill = 0
            } else {
                stepFill = pipeCapacity * intervalLength
            }
            cumulativeFill += stepFill

            // Displacement
            let stepDisplacement = (Double.pi / 4.0 * pipeOD_m * pipeOD_m) * intervalLength
            cumulativeDisplacement += stepDisplacement

            let expectedClosed = pipeCapacity * bitMD
            let expectedOpen = (Double.pi / 4.0 * (pipeOD_m * pipeOD_m - pipeID_m * pipeID_m)) * bitMD

            // Displace pocket layers from the FIXED base (not chained from previous step)
            let displacedPockets = calculateDisplacedPocketLayers(
                bitMD: bitMD,
                pocketLayers: basePocketLayers,
                annulusSections: annulusSections,
                pipeOD_m: pipeOD_m,
                tvdSampler: tvdSampler
            )

            // Calculate ESD
            let ESDAtControl = calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: controlMD_m,
                tvdSampler: tvdSampler
            )

            let ESDAtBit = calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: bitMD,
                tvdSampler: tvdSampler
            )

            let isBelowTarget = ESDAtControl < targetESD_kgpm3

            let requiredChoke: Double
            if isBelowTarget {
                requiredChoke = max(0, (targetESD_kgpm3 - ESDAtControl) * 0.00981 * controlTVD)
            } else {
                requiredChoke = 0
            }

            // Pressure calculations
            let annulusHP = ESDAtBit * 0.00981 * bitTVD
            var stringHP: Double = 0
            var floatState = "N/A"

            if isFloatedCasing && bitMD >= floatSubMD_m {
                let pipeCapacityPerMeter = Double.pi / 4.0 * pipeID_m * pipeID_m
                let mudHeightInString = cumulativeFill / pipeCapacityPerMeter
                let fillLevelMD = min(mudHeightInString, bitMD)
                let fillLevelTVD = tvdSampler.tvd(of: fillLevelMD)

                stringHP = activeMudDensity_kgpm3 * 0.00981 * fillLevelTVD

                let floatSubTVD = tvdSampler.tvd(of: floatSubMD_m)
                let annulusPressureAtFloat = baseMudDensity_kgpm3 * 0.00981 * floatSubTVD
                let mudAboveFloat = min(mudHeightInString, floatSubMD_m)
                let insidePressureAtFloat = activeMudDensity_kgpm3 * 0.00981 * tvdSampler.tvd(of: mudAboveFloat)
                let diffAtFloat = annulusPressureAtFloat - insidePressureAtFloat

                if diffAtFloat >= crackFloat_kPa {
                    let openPercent = min(100, Int((diffAtFloat / crackFloat_kPa - 1.0) * 100 + 50))
                    floatState = "OPEN \(openPercent)%"
                } else {
                    let closedPercent = Int((1.0 - diffAtFloat / crackFloat_kPa) * 100)
                    floatState = "CLOSED \(closedPercent)%"
                }
            } else {
                stringHP = activeMudDensity_kgpm3 * 0.00981 * bitTVD
                floatState = "Full"
            }

            let differentialPressure = annulusHP - stringHP

            let step = TripInStep(
                stepIndex: steps.count,
                bitMD_m: bitMD,
                bitTVD_m: bitTVD,
                stepFillVolume_m3: stepFill,
                cumulativeFillVolume_m3: cumulativeFill,
                expectedFillClosed_m3: expectedClosed,
                expectedFillOpen_m3: expectedOpen,
                stepDisplacementReturns_m3: stepDisplacement,
                cumulativeDisplacementReturns_m3: cumulativeDisplacement,
                ESDAtControl_kgpm3: ESDAtControl,
                ESDAtBit_kgpm3: ESDAtBit,
                requiredChokePressure_kPa: requiredChoke,
                isBelowTarget: isBelowTarget,
                differentialPressureAtBottom_kPa: differentialPressure,
                annulusPressureAtBit_kPa: annulusHP,
                stringPressureAtBit_kPa: stringHP,
                floatState: floatState,
                mudDensityAtControl_kgpm3: ESDAtControl,
                layersAnnulus: [],
                layersString: [],
                layersPocket: displacedPockets
            )

            steps.append(step)
            progressValue = Double(index + 1) / Double(depths.count)
        }

        isRunning = false
        progressMessage = "Complete"

        // Move selection to last step
        selectedIndex = steps.count - 1
        stepSlider = Double(selectedIndex)
    }
}
