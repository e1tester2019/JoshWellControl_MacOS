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

    // Eccentricity factor for surge/swab (1.0 = concentric, >1.0 = eccentric)
    var eccentricityFactor: Double = 1.2

    // Choke
    var holdSABPOpen: Bool = false

    // Torque & drag
    var tdEnabled: Bool = false
    var tdCasedFF: Double = 0.20
    var tdOpenHoleFF: Double = 0.30
    var tdBlockWeight_kN: Double = 0
    var tdAplEccentricity: Double = 1.0
    var tdPressureAreaBuoyancy: Bool = true
    var tdTripSpeedCased_m_per_s: Double = 0
    var tdTripSpeedOpenHole_m_per_s: Double = 0
    var tdRotationEfficiencyUp: Double = 0.5
    var tdRotationEfficiencyDown: Double = 0.5
    var tdSheaveLineFriction: Double = 0

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

    // View options
    var showHookLoadChart: Bool = false

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

        // Torque & drag (nil if not computed)
        var pickupHookLoad_kN: Double? = nil
        var slackOffHookLoad_kN: Double? = nil
        var rotatingHookLoad_kN: Double? = nil
        var freeHangingWeight_kN: Double? = nil
        var surfaceTorque_kNm: Double? = nil
        var bucklingOnsetMD: Double? = nil
        var stretch_m: Double? = nil

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
        case wellboreState = "Wellbore State"
    }

    var sourceType: SourceType = .none

    // Initial pocket layers imported from source
    var importedPocketLayers: [TripLayerSnapshot] = []

    // MARK: - Import from Wellbore State Snapshot

    /// Import from a WellboreStateSnapshot (e.g., mid-trip-out handoff)
    func importFromWellboreState(_ state: WellboreStateSnapshot, project: ProjectState) {
        sourceType = .wellboreState
        sourceSimulationID = nil
        sourceSimulationName = state.sourceDescription
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

        // Fill gap between deepest imported layer and TD with active mud
        let deepestLayerBottom = importedPocketLayers.map(\.bottomMD).max() ?? 0
        if deepestLayerBottom < endBitMD_m - 1.0 {
            let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
            let gapTopTVD = tvdSampler.tvd(of: deepestLayerBottom)
            let gapBottomTVD = tvdSampler.tvd(of: endBitMD_m)
            let mudDensity = project.activeMud?.density_kgm3 ?? activeMudDensity_kgpm3
            let gapLayer = TripLayerSnapshot(
                side: "pocket",
                topMD: deepestLayerBottom,
                bottomMD: endBitMD_m,
                topTVD: gapTopTVD,
                bottomTVD: gapBottomTVD,
                rho_kgpm3: mudDensity,
                deltaHydroStatic_kPa: mudDensity * 0.00981 * (gapBottomTVD - gapTopTVD),
                volume_m3: 0,
                colorR: project.activeMud?.colorR,
                colorG: project.activeMud?.colorG,
                colorB: project.activeMud?.colorB,
                colorA: project.activeMud?.colorA,
                isInAnnulus: false
            )
            importedPocketLayers.append(gapLayer)
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

        // Build geometry service for per-step surge calculation
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
        let surgeGeom = ProjectGeometryService(
            annulus: project.annulus ?? [],
            string: dsSections,
            currentStringBottomMD: endBitMD_m,
            mdToTvd: { tvdSampler.tvd(of: $0) }
        )

        // Get fallback rheology from fill mud or active mud
        let fillMud = fillMudID.flatMap { id in (project.muds ?? []).first { $0.id == id } }
        let surgeMud = fillMud ?? project.activeMud
        let fallbackTheta600: Double? = surgeMud?.dial600
        let fallbackTheta300: Double? = surgeMud?.dial300

        // If no pocket layers were imported, create a default layer filled with active mud
        let effectivePocketLayers: [TripLayerSnapshot]
        if importedPocketLayers.isEmpty {
            let tdMD = endBitMD_m
            let tdTVD = tvdSampler.tvd(of: tdMD)
            // Extract active mud color
            let colorR = project.activeMud?.colorR
            let colorG = project.activeMud?.colorG
            let colorB = project.activeMud?.colorB
            let colorA = project.activeMud?.colorA
            let defaultLayer = TripLayerSnapshot(
                side: "pocket",
                topMD: 0,
                bottomMD: tdMD,
                topTVD: 0,
                bottomTVD: tdTVD,
                rho_kgpm3: activeMudDensity_kgpm3,
                deltaHydroStatic_kPa: activeMudDensity_kgpm3 * 0.00981 * tdTVD,
                volume_m3: 0,
                colorR: colorR,
                colorG: colorG,
                colorB: colorB,
                colorA: colorA,
                isInAnnulus: false
            )
            effectivePocketLayers = [defaultLayer]
        } else {
            effectivePocketLayers = importedPocketLayers
        }

        // Build TripInService input and delegate to the shared service
        var serviceInput = TripInService.TripInInput(
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
            pocketLayers: effectivePocketLayers,
            annulusSections: project.annulus ?? [],
            tvdSampler: tvdSampler,
            tripSpeed_m_per_s: tripSpeed_m_per_min / 60.0,
            eccentricityFactor: eccentricityFactor,
            floatIsOpen: !isFloatedCasing,
            fallbackTheta600: fallbackTheta600,
            fallbackTheta300: fallbackTheta300,
            geom: surgeGeom
        )
        serviceInput.holdSABPOpen = holdSABPOpen

        // Wire T&D if enabled
        if tdEnabled {
            let surveys = project.surveys ?? []
            let drillStringForTD = project.drillString ?? dsSections
            let annulusSections = project.annulus ?? []
            if !surveys.isEmpty && !drillStringForTD.isEmpty {
                serviceInput.tdSurveys = TorqueDragEngine.surveyPoints(from: surveys, tvdSampler: tvdSampler)
                serviceInput.tdStringSegments = TorqueDragEngine.stringSegments(from: drillStringForTD)
                serviceInput.tdHoleSections = TorqueDragEngine.holeSections(from: annulusSections)
                serviceInput.tdFriction = TorqueDragEngine.FrictionFactors(cased: tdCasedFF, openHole: tdOpenHoleFF)
                serviceInput.tdBlockWeight_kN = tdBlockWeight_kN
                serviceInput.tdAplEccentricity = tdAplEccentricity
                serviceInput.tdPressureAreaBuoyancy = tdPressureAreaBuoyancy
                serviceInput.tdTripSpeedCased_m_per_s = tdTripSpeedCased_m_per_s
                serviceInput.tdTripSpeedOpenHole_m_per_s = tdTripSpeedOpenHole_m_per_s
                serviceInput.tdRotationEfficiencyUp = tdRotationEfficiencyUp
                serviceInput.tdRotationEfficiencyDown = tdRotationEfficiencyDown
                serviceInput.tdSheaveLineFriction = tdSheaveLineFriction
            }
        }

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
                pickupHookLoad_kN: sr.pickupHookLoad_kN,
                slackOffHookLoad_kN: sr.slackOffHookLoad_kN,
                rotatingHookLoad_kN: sr.rotatingHookLoad_kN,
                freeHangingWeight_kN: sr.freeHangingWeight_kN,
                surfaceTorque_kNm: sr.surfaceTorque_kNm,
                bucklingOnsetMD: sr.bucklingOnsetMD,
                stretch_m: sr.stretch_m,
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

    // MARK: - Persistence

    /// Save/upsert the current inputs to the project's single TripInSimulation.
    func saveInputs(project: ProjectState, context: ModelContext) {
        let simulation: TripInSimulation
        if let existing = project.tripInSimulations?.first {
            simulation = existing
        } else {
            simulation = TripInSimulation()
            simulation.project = project
            simulation.well = project.well
            context.insert(simulation)
            if project.tripInSimulations == nil { project.tripInSimulations = [] }
            project.tripInSimulations?.append(simulation)
        }

        simulation.sourceSimulationID = sourceSimulationID
        simulation.sourceSimulationName = sourceSimulationName
        simulation.startBitMD_m = startBitMD_m
        simulation.endBitMD_m = endBitMD_m
        simulation.controlMD_m = controlMD_m
        simulation.step_m = step_m
        simulation.stringName = stringName
        simulation.pipeOD_m = pipeOD_m
        simulation.pipeID_m = pipeID_m
        simulation.pipeWeight_kgm = pipeWeight_kgm
        simulation.isFloatedCasing = isFloatedCasing
        simulation.floatSubMD_m = floatSubMD_m
        simulation.crackFloat_kPa = crackFloat_kPa
        simulation.fillMudID = fillMudID
        simulation.activeMudDensity_kgpm3 = activeMudDensity_kgpm3
        simulation.targetESD_kgpm3 = targetESD_kgpm3
        simulation.baseMudDensity_kgpm3 = baseMudDensity_kgpm3
        simulation.tripSpeed_m_per_min = tripSpeed_m_per_min
        simulation.eccentricityFactor = eccentricityFactor
        simulation.tdEnabled = tdEnabled
        simulation.tdCasedFF = tdCasedFF
        simulation.tdOpenHoleFF = tdOpenHoleFF
        simulation.tdBlockWeight_kN = tdBlockWeight_kN
        simulation.tdAplEccentricity = tdAplEccentricity
        simulation.tdPressureAreaBuoyancy = tdPressureAreaBuoyancy
        simulation.tdTripSpeedCased_m_per_s = tdTripSpeedCased_m_per_s
        simulation.tdTripSpeedOpenHole_m_per_s = tdTripSpeedOpenHole_m_per_s
        simulation.tdRotationEfficiencyUp = tdRotationEfficiencyUp
        simulation.tdRotationEfficiencyDown = tdRotationEfficiencyDown
        simulation.tdSheaveLineFriction = tdSheaveLineFriction
        simulation.holdSABPOpen = holdSABPOpen
        simulation.updatedAt = .now

        try? context.save()
    }

    /// Load saved inputs from the project's TripInSimulation. Returns true if inputs were loaded.
    @discardableResult
    func loadSavedInputs(project: ProjectState) -> Bool {
        guard let simulation = project.tripInSimulations?.first else { return false }
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
        tripSpeed_m_per_min = simulation.tripSpeed_m_per_min
        eccentricityFactor = simulation.eccentricityFactor
        tdEnabled = simulation.tdEnabled
        tdCasedFF = simulation.tdCasedFF
        tdOpenHoleFF = simulation.tdOpenHoleFF
        tdBlockWeight_kN = simulation.tdBlockWeight_kN
        tdAplEccentricity = simulation.tdAplEccentricity
        tdPressureAreaBuoyancy = simulation.tdPressureAreaBuoyancy
        tdTripSpeedCased_m_per_s = simulation.tdTripSpeedCased_m_per_s
        tdTripSpeedOpenHole_m_per_s = simulation.tdTripSpeedOpenHole_m_per_s
        tdRotationEfficiencyUp = simulation.tdRotationEfficiencyUp
        tdRotationEfficiencyDown = simulation.tdRotationEfficiencyDown
        tdSheaveLineFriction = simulation.tdSheaveLineFriction
        holdSABPOpen = simulation.holdSABPOpen
        return true
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
        let operation = CirculationService.PumpOperation(volume_m3: volume_m3, fluid: FluidIdentity(from: mud))
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

        // Build T&D params if enabled
        var tdSurveys: [TorqueDragEngine.SurveyPoint]? = nil
        var tdStrSegs: [TorqueDragEngine.StringSegment]? = nil
        var tdHoleSegs: [TorqueDragEngine.HoleSection]? = nil
        var tdFriction: TorqueDragEngine.FrictionFactors? = nil
        if tdEnabled {
            let surveys = project.surveys ?? []
            let drillString = project.drillString ?? []
            let annSections = project.annulus ?? []
            if !surveys.isEmpty && !drillString.isEmpty {
                tdSurveys = TorqueDragEngine.surveyPoints(from: surveys, tvdSampler: tvdSampler)
                tdStrSegs = TorqueDragEngine.stringSegments(from: drillString)
                tdHoleSegs = TorqueDragEngine.holeSections(from: annSections)
                tdFriction = TorqueDragEngine.FrictionFactors(cased: tdCasedFF, openHole: tdOpenHoleFF)
            }
        }

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
            activeMudDensity_kgpm3: activeMudDensity_kgpm3,
            tdSurveys: tdSurveys,
            tdStringSegments: tdStrSegs,
            tdHoleSections: tdHoleSegs,
            tdFriction: tdFriction,
            tdBlockWeight_kN: tdBlockWeight_kN,
            tdAplEccentricity: tdAplEccentricity,
            tdPressureAreaBuoyancy: tdPressureAreaBuoyancy,
            tdTripSpeedCased_m_per_s: tdTripSpeedCased_m_per_s,
            tdTripSpeedOpenHole_m_per_s: tdTripSpeedOpenHole_m_per_s,
            tdRotationEfficiencyUp: tdRotationEfficiencyUp,
            tdRotationEfficiencyDown: tdRotationEfficiencyDown,
            tdSheaveLineFriction: tdSheaveLineFriction
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

    // MARK: - Ballooning Field Adjustment

    var ballooningActualVolume_m3: Double = 0.0
    var ballooningResult: BallooningAdjustmentCalculator.Result?

    func recalculateBallooning(project: ProjectState) {
        guard selectedIndex >= 0 && selectedIndex < steps.count else {
            ballooningResult = nil
            return
        }
        let step = steps[selectedIndex]
        let simulatedVol = step.cumulativeFillVolume_m3

        let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
        let geom = ProjectGeometryService(
            project: project,
            currentStringBottomMD: step.bitMD_m,
            tvdMapper: { md in tvdSampler.tvd(of: md) }
        )

        let killDensity = activeMudDensity_kgpm3
        let baseDensity = baseMudDensity_kgpm3

        ballooningResult = BallooningAdjustmentCalculator.calculate(.init(
            simulatedSABP_kPa: step.requiredChokePressure_kPa,
            simulatedKillMudVolume_m3: simulatedVol,
            actualKillMudVolume_m3: ballooningActualVolume_m3,
            killMudDensity_kgpm3: killDensity,
            originalMudDensity_kgpm3: baseDensity,
            geom: geom
        ))
    }
}
