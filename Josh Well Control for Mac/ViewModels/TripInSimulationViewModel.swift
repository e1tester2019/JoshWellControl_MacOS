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

    // Trip speed for surge calculation (0 = no surge)
    var tripSpeed_m_per_min: Double = 0

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
        // Surge pressure fields
        let surgePressure_kPa: Double
        let surgeECD_kgm3: Double
        let dynamicESDAtControl_kgpm3: Double

        // Layers for visualization
        var layersAnnulus: [TripLayerSnapshot] = []
        var layersString: [TripLayerSnapshot] = []
        var layersPocket: [TripLayerSnapshot] = []
    }

    /// Summary: max surge pressure
    var maxSurgePressure_kPa: Double {
        steps.map { $0.surgePressure_kPa }.max() ?? 0
    }

    /// Summary: max surge ECD contribution
    var maxSurgeECD_kgm3: Double {
        steps.map { $0.surgeECD_kgm3 }.max() ?? 0
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

        // Combine pocket + annulus layers from the snapshot (matches SuperSim behavior).
        // TripInService.calculateDisplacedPocketLayers handles isInAnnulus layers
        // correctly (no expansion, shift only).
        importedPocketLayers = state.layersPocket + state.layersAnnulus

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

        // Compute surge profile if trip speed is set
        var surgeProfile: [TripInService.SurgePressurePoint] = []
        if tripSpeed_m_per_min > 0 {
            let annSections = project.annulus ?? []
            let fillMud = fillMudID.flatMap { id in (project.muds ?? []).first { $0.id == id } }
            let dsSections: [DrillStringSection]
            if let projectDS = project.drillString, !projectDS.isEmpty {
                dsSections = projectDS
            } else {
                let syntheticDS = DrillStringSection(
                    name: "Trip-In String",
                    topDepth_m: 0,
                    length_m: endBitMD_m,
                    outerDiameter_m: pipeOD_m,
                    innerDiameter_m: pipeID_m
                )
                dsSections = [syntheticDS]
            }

            // Use fill mud if available (has PV/YP), otherwise use project active mud
            let surgeMud = fillMud ?? project.activeMud

            if surgeMud != nil, (surgeMud?.pv_Pa_s ?? 0) > 0 || (surgeMud?.yp_Pa ?? 0) > 0 {
                let calculator = SurgeSwabCalculator(
                    tripSpeed_m_per_min: tripSpeed_m_per_min,
                    startBitMD_m: startBitMD_m,
                    endBitMD_m: endBitMD_m,
                    depthStep_m: step_m,
                    annulusSections: annSections,
                    drillStringSections: dsSections,
                    mud: surgeMud,
                    pipeEndType: isFloatedCasing ? .closed : .open
                )
                let results = calculator.calculate(tvdLookup: { md in
                    tvdSampler.tvd(of: md)
                })
                surgeProfile = results.map { r in
                    TripInService.SurgePressurePoint(md: r.bitMD_m, surgePressure_kPa: r.surgePressure_kPa)
                }
            }
        }

        // Build TripInService input and delegate to the shared service
        let serviceInput = TripInService.TripInInput(
            startBitMD_m: startBitMD_m,
            endBitMD_m: endBitMD_m,
            controlMD_m: controlMD_m,
            step_m: step_m,
            pipeOD_m: pipeOD_m,
            pipeID_m: pipeID_m,
            activeMudDensity_kgpm3: activeMudDensity_kgpm3,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            targetESD_kgpm3: targetESD_kgpm3,
            isFloatedCasing: isFloatedCasing,
            floatSubMD_m: floatSubMD_m,
            crackFloat_kPa: crackFloat_kPa,
            pocketLayers: importedPocketLayers,
            annulusSections: project.annulus ?? [],
            tvdSampler: tvdSampler,
            surgeProfile: surgeProfile
        )

        let serviceResult = TripInService.run(serviceInput)

        // Map TripInService.TripInStepResult → TripInStep
        steps = serviceResult.steps.map { sr in
            TripInStep(
                stepIndex: sr.stepIndex,
                bitMD_m: sr.bitMD_m,
                bitTVD_m: sr.bitTVD_m,
                stepFillVolume_m3: sr.stepFillVolume_m3,
                cumulativeFillVolume_m3: sr.cumulativeFillVolume_m3,
                expectedFillClosed_m3: sr.expectedFillClosed_m3,
                expectedFillOpen_m3: sr.expectedFillOpen_m3,
                stepDisplacementReturns_m3: sr.stepDisplacementReturns_m3,
                cumulativeDisplacementReturns_m3: sr.cumulativeDisplacementReturns_m3,
                ESDAtControl_kgpm3: sr.ESDAtControl_kgpm3,
                ESDAtBit_kgpm3: sr.ESDAtBit_kgpm3,
                requiredChokePressure_kPa: sr.requiredChokePressure_kPa,
                isBelowTarget: sr.isBelowTarget,
                differentialPressureAtBottom_kPa: sr.differentialPressureAtBottom_kPa,
                annulusPressureAtBit_kPa: sr.annulusPressureAtBit_kPa,
                stringPressureAtBit_kPa: sr.stringPressureAtBit_kPa,
                floatState: sr.floatState,
                mudDensityAtControl_kgpm3: sr.ESDAtControl_kgpm3,
                surgePressure_kPa: sr.surgePressure_kPa,
                surgeECD_kgm3: sr.surgeECD_kgm3,
                dynamicESDAtControl_kgpm3: sr.dynamicESDAtControl_kgpm3,
                layersPocket: sr.layersPocket
            )
        }

        isRunning = false
        progressMessage = "Complete"
        selectedIndex = 0
        stepSlider = 0
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
                surgePressure_kPa: step.surgePressure_kPa,
                surgeECD_kgm3: step.surgeECD_kgm3,
                dynamicESDAtControl_kgpm3: step.dynamicESDAtControl_kgpm3,
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
                surgePressure_kPa: step.surgePressure_kPa,
                surgeECD_kgm3: step.surgeECD_kgm3,
                dynamicESDAtControl_kgpm3: step.dynamicESDAtControl_kgpm3,
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
            surgePressure_kPa: 0,
            surgeECD_kgm3: 0,
            dynamicESDAtControl_kgpm3: previewESDAtControl,
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

        // Remove all steps after the current one
        steps = Array(steps.prefix(stepIndex + 1))

        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

        // Delegate to TripInService starting from the current depth
        let serviceInput = TripInService.TripInInput(
            startBitMD_m: startingBitMD,
            endBitMD_m: endBitMD_m,
            controlMD_m: controlMD_m,
            step_m: step_m,
            pipeOD_m: pipeOD_m,
            pipeID_m: pipeID_m,
            activeMudDensity_kgpm3: activeMudDensity_kgpm3,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            targetESD_kgpm3: targetESD_kgpm3,
            isFloatedCasing: isFloatedCasing,
            floatSubMD_m: floatSubMD_m,
            crackFloat_kPa: crackFloat_kPa,
            pocketLayers: startingStep.layersPocket,
            annulusSections: project.annulus ?? [],
            tvdSampler: tvdSampler,
            initialCumulativeFill_m3: startingStep.cumulativeFillVolume_m3,
            initialCumulativeDisplacement_m3: startingStep.cumulativeDisplacementReturns_m3
        )

        let serviceResult = TripInService.run(serviceInput)

        // Skip the first result (at startingBitMD, which we already have)
        let baseStepCount = steps.count
        for (i, sr) in serviceResult.steps.dropFirst().enumerated() {
            steps.append(TripInStep(
                stepIndex: baseStepCount + i,
                bitMD_m: sr.bitMD_m,
                bitTVD_m: sr.bitTVD_m,
                stepFillVolume_m3: sr.stepFillVolume_m3,
                cumulativeFillVolume_m3: sr.cumulativeFillVolume_m3,
                expectedFillClosed_m3: sr.expectedFillClosed_m3,
                expectedFillOpen_m3: sr.expectedFillOpen_m3,
                stepDisplacementReturns_m3: sr.stepDisplacementReturns_m3,
                cumulativeDisplacementReturns_m3: sr.cumulativeDisplacementReturns_m3,
                ESDAtControl_kgpm3: sr.ESDAtControl_kgpm3,
                ESDAtBit_kgpm3: sr.ESDAtBit_kgpm3,
                requiredChokePressure_kPa: sr.requiredChokePressure_kPa,
                isBelowTarget: sr.isBelowTarget,
                differentialPressureAtBottom_kPa: sr.differentialPressureAtBottom_kPa,
                annulusPressureAtBit_kPa: sr.annulusPressureAtBit_kPa,
                stringPressureAtBit_kPa: sr.stringPressureAtBit_kPa,
                floatState: sr.floatState,
                mudDensityAtControl_kgpm3: sr.ESDAtControl_kgpm3,
                surgePressure_kPa: sr.surgePressure_kPa,
                surgeECD_kgm3: sr.surgeECD_kgm3,
                dynamicESDAtControl_kgpm3: sr.dynamicESDAtControl_kgpm3,
                layersPocket: sr.layersPocket
            ))
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

        // Remove all steps after the current one
        steps = Array(steps.prefix(fromStepIndex + 1))

        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

        // Delegate to TripInService starting from current depth
        let serviceInput = TripInService.TripInInput(
            startBitMD_m: currentBitMD,
            endBitMD_m: endBitMD_m,
            controlMD_m: controlMD_m,
            step_m: step_m,
            pipeOD_m: pipeOD_m,
            pipeID_m: pipeID_m,
            activeMudDensity_kgpm3: activeMudDensity_kgpm3,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            targetESD_kgpm3: targetESD_kgpm3,
            isFloatedCasing: isFloatedCasing,
            floatSubMD_m: floatSubMD_m,
            crackFloat_kPa: crackFloat_kPa,
            pocketLayers: currentStep.layersPocket,
            annulusSections: project.annulus ?? [],
            tvdSampler: tvdSampler,
            initialCumulativeFill_m3: currentStep.cumulativeFillVolume_m3,
            initialCumulativeDisplacement_m3: currentStep.cumulativeDisplacementReturns_m3
        )

        let serviceResult = TripInService.run(serviceInput)

        // Skip the first result (at currentBitMD, which we already have)
        let baseStepCount = steps.count
        for (i, sr) in serviceResult.steps.dropFirst().enumerated() {
            steps.append(TripInStep(
                stepIndex: baseStepCount + i,
                bitMD_m: sr.bitMD_m,
                bitTVD_m: sr.bitTVD_m,
                stepFillVolume_m3: sr.stepFillVolume_m3,
                cumulativeFillVolume_m3: sr.cumulativeFillVolume_m3,
                expectedFillClosed_m3: sr.expectedFillClosed_m3,
                expectedFillOpen_m3: sr.expectedFillOpen_m3,
                stepDisplacementReturns_m3: sr.stepDisplacementReturns_m3,
                cumulativeDisplacementReturns_m3: sr.cumulativeDisplacementReturns_m3,
                ESDAtControl_kgpm3: sr.ESDAtControl_kgpm3,
                ESDAtBit_kgpm3: sr.ESDAtBit_kgpm3,
                requiredChokePressure_kPa: sr.requiredChokePressure_kPa,
                isBelowTarget: sr.isBelowTarget,
                differentialPressureAtBottom_kPa: sr.differentialPressureAtBottom_kPa,
                annulusPressureAtBit_kPa: sr.annulusPressureAtBit_kPa,
                stringPressureAtBit_kPa: sr.stringPressureAtBit_kPa,
                floatState: sr.floatState,
                mudDensityAtControl_kgpm3: sr.ESDAtControl_kgpm3,
                surgePressure_kPa: sr.surgePressure_kPa,
                surgeECD_kgm3: sr.surgeECD_kgm3,
                dynamicESDAtControl_kgpm3: sr.dynamicESDAtControl_kgpm3,
                layersPocket: sr.layersPocket
            ))
        }

        isRunning = false
        progressMessage = "Complete"

        // Move selection to last step
        selectedIndex = steps.count - 1
        stepSlider = Double(selectedIndex)
    }
}
