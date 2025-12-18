//
//  TripTrackerViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for process-based trip tracking with manual step-by-step inputs.
//

import Foundation
import SwiftData

@Observable
class TripTrackerViewModel {
    // MARK: - State

    /// The active trip track being recorded
    var tripTrack: TripTrack?

    /// Current bit depth (before next step)
    var currentBitMD_m: Double = 0

    /// Current SABP (before next step)
    var currentSABP_kPa: Double = 0

    // MARK: - Runtime Layer State (not persisted until step locked)

    private var annulusLayers: [TripLayerSnapshot] = []
    private var stringLayers: [TripLayerSnapshot] = []
    private var pocketLayers: [TripLayerSnapshot] = []

    // MARK: - Input State (pending step)

    /// Target bit depth after this step (user enters depth after pulling stand)
    var inputBitMD_m: Double = 0

    /// Backfill volume pumped (m³)
    var inputBackfill_m3: Double = 0

    /// Backfill density for this step (kg/m³)
    var inputBackfillDensity_kgpm3: Double = 1080

    /// Observed SABP from gauge (kPa)
    var inputSABP_kPa: Double = 0

    /// Observed pit/tank change (m³)
    var inputPitChange_m3: Double = 0

    /// Float state override: nil = auto, .closed, .open
    var inputFloatOverride: TripTrackStep.FloatOverride? = nil

    /// Notes for this step
    var inputNotes: String = ""

    // MARK: - Preview State (calculated, not committed)

    var previewCalculated: Bool = false
    var previewESDatTD_kgpm3: Double = 0
    var previewESDatBit_kgpm3: Double = 0
    var previewCalculatedSABP_kPa: Double = 0
    var previewFloatState: String = "CLOSED 100%"
    var previewExpectedIfClosed_m3: Double = 0
    var previewExpectedIfOpen_m3: Double = 0
    var previewBackfillDiscrepancy_m3: Double = 0
    var previewSABPDiscrepancy_kPa: Double = 0

    /// Preview layer state (for visualization)
    var previewLayersAnnulus: [NumericalTripModel.LayerRow] = []
    var previewLayersString: [NumericalTripModel.LayerRow] = []
    var previewLayersPocket: [NumericalTripModel.LayerRow] = []

    // MARK: - Reference Simulation (optional)

    var referenceTripSimulation: TripSimulation?
    var referenceStepAtDepth: TripSimulationStep?

    // MARK: - Configuration

    var tdMD_m: Double = 0
    var shoeMD_m: Double = 0
    var targetESD_kgpm3: Double = 1080
    var crackFloat_kPa: Double = 2100
    var baseMudDensity_kgpm3: Double = 1080

    // MARK: - View State

    var showDetails: Bool = false
    var colorByComposition: Bool = false

    // MARK: - Computed Properties

    /// Sorted locked steps
    var sortedSteps: [TripTrackStep] {
        tripTrack?.sortedSteps ?? []
    }

    /// Cumulative backfill so far
    var cumulativeBackfill_m3: Double {
        tripTrack?.totalBackfill_m3 ?? 0
    }

    /// Cumulative tank delta so far
    var cumulativeTankDelta_m3: Double {
        tripTrack?.totalTankDelta_m3 ?? 0
    }

    /// Trip progress (how far we've tripped)
    var tripProgress_m: Double {
        guard let track = tripTrack else { return 0 }
        return abs(track.initialBitMD_m - currentBitMD_m)
    }

    /// Current layers for visualization (before pending step)
    var currentLayersAnnulus: [NumericalTripModel.LayerRow] {
        annulusLayers.map { $0.toLayerRow() }
    }

    var currentLayersString: [NumericalTripModel.LayerRow] {
        stringLayers.map { $0.toLayerRow() }
    }

    var currentLayersPocket: [NumericalTripModel.LayerRow] {
        pocketLayers.map { $0.toLayerRow() }
    }

    // MARK: - Initialization Methods

    /// Start fresh from project fluid layers
    func initializeFresh(project: ProjectState, name: String = "") {
        // Create new TripTrack
        let track = TripTrack(
            name: name.isEmpty ? "Trip \(Date.now.formatted(date: .abbreviated, time: .shortened))" : name,
            sourceType: .fresh,
            project: project
        )

        // Get starting depth from project layers
        let maxMD = (project.finalLayers ?? []).map { $0.bottomMD_m }.max() ?? 0
        track.initialBitMD_m = maxMD
        track.currentBitMD_m = maxMD
        track.tdMD_m = maxMD

        // Get shoe depth
        let annulusSections = project.annulus ?? []
        if let deepestCasing = annulusSections.filter({ $0.isCased }).max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
            track.shoeMD_m = deepestCasing.bottomDepth_m
        }

        // Get mud properties
        let activeMud = project.activeMud
        track.baseMudDensity_kgpm3 = activeMud?.density_kgm3 ?? 1080
        track.backfillDensity_kgpm3 = activeMud?.density_kgm3 ?? 1080
        track.targetESD_kgpm3 = activeMud?.density_kgm3 ?? 1080
        track.backfillMud = activeMud

        // Initialize layer state from project
        annulusLayers = project.finalAnnulusLayersSorted.map { layer in
            TripLayerSnapshot(
                side: "annulus",
                topMD: layer.topMD_m,
                bottomMD: layer.bottomMD_m,
                topTVD: project.tvd(of: layer.topMD_m),
                bottomTVD: project.tvd(of: layer.bottomMD_m),
                rho_kgpm3: layer.density_kgm3,
                deltaHydroStatic_kPa: 0, // Will be recalculated
                volume_m3: 0 // Will be recalculated
            )
        }

        stringLayers = project.finalStringLayersSorted.map { layer in
            TripLayerSnapshot(
                side: "string",
                topMD: layer.topMD_m,
                bottomMD: layer.bottomMD_m,
                topTVD: project.tvd(of: layer.topMD_m),
                bottomTVD: project.tvd(of: layer.bottomMD_m),
                rho_kgpm3: layer.density_kgm3,
                deltaHydroStatic_kPa: 0,
                volume_m3: 0
            )
        }

        pocketLayers = [] // No pocket at start

        // Store layer state in track
        track.layersAnnulus = annulusLayers
        track.layersString = stringLayers
        track.layersPocket = pocketLayers

        // Set ViewModel state
        self.tripTrack = track
        self.currentBitMD_m = maxMD
        self.currentSABP_kPa = 0
        self.tdMD_m = maxMD
        self.shoeMD_m = track.shoeMD_m
        self.targetESD_kgpm3 = track.targetESD_kgpm3
        self.crackFloat_kPa = track.crackFloat_kPa
        self.baseMudDensity_kgpm3 = track.baseMudDensity_kgpm3
        self.inputBackfillDensity_kgpm3 = track.backfillDensity_kgpm3

        // Reset input state
        resetInputs()
    }

    /// Load initial state from a saved TripSimulation at a specific step
    func initializeFromSimulation(_ simulation: TripSimulation, stepIndex: Int, project: ProjectState, name: String = "") {
        guard let step = simulation.sortedSteps[safe: stepIndex] else { return }

        // Create new TripTrack from simulation
        let track = TripTrack(
            name: name.isEmpty ? "Trip from \(simulation.name)" : name,
            sourceType: .simulation,
            sourceTripSimulationID: simulation.id,
            initialBitMD_m: step.bitMD_m,
            tdMD_m: simulation.startBitMD_m,
            shoeMD_m: simulation.shoeMD_m,
            targetESD_kgpm3: simulation.targetESDAtTD_kgpm3,
            crackFloat_kPa: simulation.crackFloat_kPa,
            baseMudDensity_kgpm3: simulation.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: simulation.backfillDensity_kgpm3,
            project: project,
            backfillMud: simulation.backfillMud
        )

        track.currentBitMD_m = step.bitMD_m
        track.currentSABP_kPa = step.SABP_kPa

        // Load layer state from simulation step
        annulusLayers = step.layersAnnulus
        stringLayers = step.layersString
        pocketLayers = step.layersPocket

        track.layersAnnulus = annulusLayers
        track.layersString = stringLayers
        track.layersPocket = pocketLayers

        // Set ViewModel state
        self.tripTrack = track
        self.currentBitMD_m = step.bitMD_m
        self.currentSABP_kPa = step.SABP_kPa
        self.tdMD_m = simulation.startBitMD_m
        self.shoeMD_m = simulation.shoeMD_m
        self.targetESD_kgpm3 = simulation.targetESDAtTD_kgpm3
        self.crackFloat_kPa = simulation.crackFloat_kPa
        self.baseMudDensity_kgpm3 = simulation.baseMudDensity_kgpm3
        self.inputBackfillDensity_kgpm3 = simulation.backfillDensity_kgpm3

        // Store reference simulation for comparison
        self.referenceTripSimulation = simulation

        resetInputs()
    }

    /// Load from an existing TripTrack (resume tracking)
    func loadTrack(_ track: TripTrack) {
        self.tripTrack = track
        self.currentBitMD_m = track.currentBitMD_m
        self.currentSABP_kPa = track.currentSABP_kPa
        self.tdMD_m = track.tdMD_m
        self.shoeMD_m = track.shoeMD_m
        self.targetESD_kgpm3 = track.targetESD_kgpm3
        self.crackFloat_kPa = track.crackFloat_kPa
        self.baseMudDensity_kgpm3 = track.baseMudDensity_kgpm3
        self.inputBackfillDensity_kgpm3 = track.backfillDensity_kgpm3

        // Load layer state
        annulusLayers = track.layersAnnulus
        stringLayers = track.layersString
        pocketLayers = track.layersPocket

        resetInputs()
    }

    // MARK: - Preview Calculation

    /// Calculate preview state for current inputs (does NOT modify committed state)
    func calculatePreview(project: ProjectState) {
        guard inputBitMD_m < currentBitMD_m else {
            // Can only trip out (reduce bit depth)
            previewCalculated = false
            return
        }

        let geom = ProjectGeometryService(
            project: project,
            currentStringBottomMD: currentBitMD_m,
            tvdMapper: { md in project.tvd(of: md) }
        )

        let deltaMD = currentBitMD_m - inputBitMD_m // Positive when pulling out

        // Calculate expected fill volumes
        previewExpectedIfClosed_m3 = geom.volumeOfStringOD_m3(inputBitMD_m, currentBitMD_m)
        previewExpectedIfOpen_m3 = geom.steelDisplacement_m2(currentBitMD_m) * deltaMD

        // Calculate pressures using current layer state
        let annulusPressure = calculatePressure(layers: annulusLayers, bitMD: currentBitMD_m, sabp: currentSABP_kPa, project: project)
        let stringPressure = calculatePressure(layers: stringLayers, bitMD: currentBitMD_m, sabp: 0, project: project)

        // Determine float state
        let floatClosed: Bool
        if let override = inputFloatOverride {
            floatClosed = (override == .closed)
            previewFloatState = override == .closed ? "CLOSED (override)" : "OPEN (override)"
        } else {
            floatClosed = stringPressure <= annulusPressure + 5.0 // 5 kPa tolerance
            previewFloatState = floatClosed ? "CLOSED 100%" : "OPEN"
        }

        // Calculate SABP required to maintain target ESD
        let tdTVD = project.tvd(of: tdMD_m)
        let targetPressure_kPa = targetESD_kgpm3 * NumericalTripModel.g * tdTVD / 1000.0

        // Simple approximation: SABP needed = target pressure - hydrostatic from layers
        let currentHydrostatic = annulusPressure - currentSABP_kPa
        previewCalculatedSABP_kPa = max(0, targetPressure_kPa - currentHydrostatic)

        // Calculate ESD at TD and bit
        let bitTVD = project.tvd(of: inputBitMD_m)
        previewESDatTD_kgpm3 = (annulusPressure) / (NumericalTripModel.g * tdTVD / 1000.0)
        previewESDatBit_kgpm3 = bitTVD > 0 ? (annulusPressure) / (NumericalTripModel.g * bitTVD / 1000.0) : 0

        // Calculate discrepancies
        let expectedFill = floatClosed ? previewExpectedIfClosed_m3 : previewExpectedIfOpen_m3
        previewBackfillDiscrepancy_m3 = inputBackfill_m3 - expectedFill
        previewSABPDiscrepancy_kPa = inputSABP_kPa - previewCalculatedSABP_kPa

        // Generate preview layers (simplified - just show current with new bit position)
        previewLayersAnnulus = annulusLayers.map { $0.toLayerRow() }
        previewLayersString = stringLayers.filter { $0.bottomMD <= inputBitMD_m }.map { $0.toLayerRow() }
        previewLayersPocket = pocketLayers.map { $0.toLayerRow() }

        // Update reference step if we have a simulation
        updateReferenceStep()

        previewCalculated = true
    }

    // MARK: - Step Operations

    /// Lock in current step, commit to database
    func lockStep(project: ProjectState, context: ModelContext) -> TripTrackStep? {
        guard let track = tripTrack else { return nil }
        guard previewCalculated else { return nil }
        guard inputBitMD_m < currentBitMD_m else { return nil }

        let stepIndex = (track.steps?.count ?? 0)
        let bitTVD = project.tvd(of: inputBitMD_m)

        // Determine float state (used for expected fill calculation)
        let floatClosed: Bool
        if let override = inputFloatOverride {
            floatClosed = (override == .closed)
        } else {
            let annulusPressure = calculatePressure(layers: annulusLayers, bitMD: currentBitMD_m, sabp: currentSABP_kPa, project: project)
            let stringPressure = calculatePressure(layers: stringLayers, bitMD: currentBitMD_m, sabp: 0, project: project)
            floatClosed = stringPressure <= annulusPressure + 5.0
        }
        _ = floatClosed // Used for calculating expected fill in discrepancy check

        // Create step
        let step = TripTrackStep(
            stepIndex: stepIndex,
            bitMD_m: inputBitMD_m,
            bitTVD_m: bitTVD,
            observedBackfill_m3: inputBackfill_m3,
            observedSABP_kPa: inputSABP_kPa,
            observedPitChange_m3: inputPitChange_m3,
            floatOverride: inputFloatOverride,
            backfillDensity_kgpm3: inputBackfillDensity_kgpm3,
            calculatedSABP_kPa: previewCalculatedSABP_kPa,
            calculatedESDatTD_kgpm3: previewESDatTD_kgpm3,
            calculatedESDatBit_kgpm3: previewESDatBit_kgpm3,
            expectedFillIfClosed_m3: previewExpectedIfClosed_m3,
            expectedFillIfOpen_m3: previewExpectedIfOpen_m3,
            calculatedFloatState: previewFloatState,
            cumulativeBackfill_m3: cumulativeBackfill_m3 + inputBackfill_m3,
            cumulativePitChange_m3: (track.totalPitGain_m3) + inputPitChange_m3,
            cumulativeTankDelta_m3: cumulativeTankDelta_m3 + (inputBackfill_m3 - inputPitChange_m3),
            notes: inputNotes
        )

        // Update layer state for new bit position
        // For now, simple approach: filter layers to new bit depth
        annulusLayers = annulusLayers.map { layer in
            var updated = layer
            updated.bottomMD = min(layer.bottomMD, inputBitMD_m)
            return updated
        }.filter { $0.bottomMD > $0.topMD }

        stringLayers = stringLayers.map { layer in
            var updated = layer
            updated.bottomMD = min(layer.bottomMD, inputBitMD_m)
            return updated
        }.filter { $0.bottomMD > $0.topMD }

        // Add carved material to pocket (simplified)
        // In reality, this would involve the NumericalTripModel carving logic
        if !pocketLayers.isEmpty || currentBitMD_m > inputBitMD_m {
            // Simplified: just note that there's pocket below the bit
            // Full implementation would blend carved materials
        }

        // Store layers in step
        step.layersAnnulus = annulusLayers
        step.layersString = stringLayers
        step.layersPocket = pocketLayers

        // Add step to track
        if track.steps == nil { track.steps = [] }
        step.tripTrack = track
        track.steps?.append(step)

        // Update track state
        track.currentBitMD_m = inputBitMD_m
        track.currentSABP_kPa = inputSABP_kPa
        track.totalBackfill_m3 += inputBackfill_m3
        track.totalTankDelta_m3 += (inputBackfill_m3 - inputPitChange_m3)
        track.layersAnnulus = annulusLayers
        track.layersString = stringLayers
        track.layersPocket = pocketLayers
        track.updatedAt = .now

        // Update ViewModel state
        currentBitMD_m = inputBitMD_m
        currentSABP_kPa = inputSABP_kPa

        // Insert and save
        context.insert(step)
        try? context.save()

        // Reset inputs for next step
        resetInputs()

        return step
    }

    /// Undo last step
    func undoLastStep(context: ModelContext) {
        guard let track = tripTrack else { return }
        guard let lastStep = track.removeLastStep() else { return }

        // Restore layer state from previous step or initial
        annulusLayers = track.layersAnnulus
        stringLayers = track.layersString
        pocketLayers = track.layersPocket

        // Update ViewModel state
        currentBitMD_m = track.currentBitMD_m
        currentSABP_kPa = track.currentSABP_kPa

        // Delete from context
        context.delete(lastStep)
        try? context.save()

        resetInputs()
    }

    // MARK: - Helper Methods

    private func resetInputs() {
        // Set default input for next step
        inputBitMD_m = max(0, currentBitMD_m - 30) // Default ~30m stand
        inputBackfill_m3 = 0
        inputSABP_kPa = currentSABP_kPa
        inputPitChange_m3 = 0
        inputFloatOverride = nil
        inputNotes = ""
        previewCalculated = false
    }

    private func calculatePressure(layers: [TripLayerSnapshot], bitMD: Double, sabp: Double, project: ProjectState) -> Double {
        var pressure = sabp
        for layer in layers {
            let topMD = max(0, min(layer.topMD, bitMD))
            let bottomMD = max(0, min(layer.bottomMD, bitMD))
            guard bottomMD > topMD else { continue }

            let topTVD = project.tvd(of: topMD)
            let bottomTVD = project.tvd(of: bottomMD)
            let dH = max(0, bottomTVD - topTVD)
            pressure += layer.rho_kgpm3 * NumericalTripModel.g * dH / 1000.0
        }
        return pressure
    }

    private func updateReferenceStep() {
        guard let simulation = referenceTripSimulation else {
            referenceStepAtDepth = nil
            return
        }

        // Find the simulation step closest to current input depth
        referenceStepAtDepth = simulation.sortedSteps.min(by: { step1, step2 in
            abs(step1.bitMD_m - inputBitMD_m) < abs(step2.bitMD_m - inputBitMD_m)
        })
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
