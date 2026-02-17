//
//  SuperSimViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for the Super Simulation timeline.
//  Manages a chain of operations (trip out, trip in, circulate)
//  with sequential execution and continuous wellbore state.
//

import Foundation
import SwiftData

@Observable
class SuperSimViewModel {

    // MARK: - Timeline

    var operations: [SuperSimOperation] = []
    var selectedOperationIndex: Int? = nil

    // MARK: - Execution State

    var isRunning: Bool = false
    var currentRunningIndex: Int? = nil
    var overallProgress: Double = 0.0
    var operationProgress: Double = 0.0
    var progressMessage: String = ""

    // MARK: - Per-Operation Results

    /// Trip out steps for the currently selected operation (if tripOut type)
    var tripOutSteps: [NumericalTripModel.TripStep] = []
    /// Trip in steps for the currently selected operation (if tripIn type)
    var tripInSteps: [TripInService.TripInStepResult] = []
    /// Circulation steps for the currently selected operation (if circulate type)
    var circulationSteps: [CirculationService.CirculateOutStep] = []
    /// Ream out steps for the currently selected operation (if reamOut type)
    var reamOutSteps: [ReamOutStep] = []
    /// Ream in steps for the currently selected operation (if reamIn type)
    var reamInSteps: [ReamInStep] = []

    var selectedStepIndex: Int = 0
    var stepSlider: Double = 0

    // MARK: - Stored Results Per Operation

    private var tripOutResults: [UUID: [NumericalTripModel.TripStep]] = [:]
    private var tripInResults: [UUID: [TripInService.TripInStepResult]] = [:]
    private var circulationResults: [UUID: [CirculationService.CirculateOutStep]] = [:]
    private var reamOutResults: [UUID: [ReamOutStep]] = [:]
    private var reamInResults: [UUID: [ReamInStep]] = [:]
    /// Per-step ESD at controlMD for trip out (consistent with trip in / circulation reference depth)
    private var tripOutESDAtControl: [UUID: [Double]] = [:]
    private var reamOutESDAtControl: [UUID: [Double]] = [:]
    /// TVD at control depth (shoe), used for SABP → ESD conversion on charts
    var controlTVD_m: Double = 0

    // MARK: - Initial State

    var initialState: WellboreStateSnapshot?

    // MARK: - Operations Management

    func addOperation(_ type: OperationType) {
        var op = SuperSimOperation(type: type)

        if let lastOp = operations.last {
            // Inherit shared config from previous operation
            op.controlMD_m = lastOp.controlMD_m
            op.targetESD_kgpm3 = lastOp.targetESD_kgpm3
            op.baseMudID = lastOp.baseMudID
            op.baseMudDensity_kgpm3 = lastOp.baseMudDensity_kgpm3
            op.backfillMudID = lastOp.backfillMudID
            op.backfillDensity_kgpm3 = lastOp.backfillDensity_kgpm3
            op.backfillColorR = lastOp.backfillColorR
            op.backfillColorG = lastOp.backfillColorG
            op.backfillColorB = lastOp.backfillColorB
            op.backfillColorA = lastOp.backfillColorA
            op.fillMudID = lastOp.fillMudID
            op.fillMudDensity_kgpm3 = lastOp.fillMudDensity_kgpm3
            op.fillMudColorR = lastOp.fillMudColorR
            op.fillMudColorG = lastOp.fillMudColorG
            op.fillMudColorB = lastOp.fillMudColorB
            op.fillMudColorA = lastOp.fillMudColorA
            op.switchToActiveAfterDisplacement = lastOp.switchToActiveAfterDisplacement
            op.useOverrideDisplacementVolume = lastOp.useOverrideDisplacementVolume
            op.overrideDisplacementVolume_m3 = lastOp.overrideDisplacementVolume_m3
            op.tripInSpeed_m_per_s = lastOp.tripInSpeed_m_per_s

            // Start where previous operation ends (use output if run, else configured end)
            let prevEndMD = lastOp.outputState?.bitMD_m ?? lastOp.endMD_m

            switch type {
            case .tripOut:
                op.startMD_m = prevEndMD
                op.endMD_m = 0
            case .tripIn:
                op.startMD_m = prevEndMD
                op.endMD_m = initialState?.bitMD_m ?? 0
            case .circulate:
                op.startMD_m = prevEndMD
                op.endMD_m = prevEndMD
            case .reamOut:
                op.startMD_m = prevEndMD
                op.endMD_m = 0
            case .reamIn:
                op.startMD_m = prevEndMD
                op.endMD_m = initialState?.bitMD_m ?? 0
            }
        } else if let initial = initialState {
            // First operation — use initial project state
            op.controlMD_m = initial.controlMD_m
            op.targetESD_kgpm3 = initial.targetESD_kgpm3

            switch type {
            case .tripOut:
                op.startMD_m = initial.bitMD_m
                op.endMD_m = 0
            case .tripIn:
                op.startMD_m = 0
                op.endMD_m = initial.bitMD_m
            case .circulate:
                op.startMD_m = initial.bitMD_m
                op.endMD_m = initial.bitMD_m
            case .reamOut:
                op.startMD_m = initial.bitMD_m
                op.endMD_m = 0
            case .reamIn:
                op.startMD_m = 0
                op.endMD_m = initial.bitMD_m
            }
        }

        operations.append(op)
        selectedOperationIndex = operations.count - 1
    }

    func removeOperation(at index: Int) {
        guard index >= 0 && index < operations.count else { return }

        // Clear selection BEFORE removing to prevent view from binding to stale index
        let sel = selectedOperationIndex
        selectedOperationIndex = nil

        let removed = operations.remove(at: index)
        tripOutResults.removeValue(forKey: removed.id)
        tripOutESDAtControl.removeValue(forKey: removed.id)
        tripInResults.removeValue(forKey: removed.id)
        circulationResults.removeValue(forKey: removed.id)
        reamOutResults.removeValue(forKey: removed.id)
        reamOutESDAtControl.removeValue(forKey: removed.id)
        reamInResults.removeValue(forKey: removed.id)

        // Invalidate all subsequent
        invalidateFrom(index)

        // Restore selection to a valid index
        if operations.isEmpty {
            selectedOperationIndex = nil
        } else if let prev = sel {
            if prev == index {
                // Deleted the selected item — select the next (or last)
                selectedOperationIndex = min(index, operations.count - 1)
            } else if prev > index {
                selectedOperationIndex = prev - 1
            } else {
                selectedOperationIndex = prev
            }
        }
    }

    func moveOperation(from source: Int, to destination: Int) {
        guard source != destination else { return }
        let op = operations.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        operations.insert(op, at: insertAt)
        invalidateFrom(min(source, insertAt))
    }

    // MARK: - Selected Operation

    var selectedOperation: SuperSimOperation? {
        guard let idx = selectedOperationIndex, idx >= 0, idx < operations.count else { return nil }
        return operations[idx]
    }

    func selectOperation(_ index: Int) {
        guard index >= 0 && index < operations.count else { return }
        selectedOperationIndex = index
        loadResultsForSelectedOperation()
    }

    private func loadResultsForSelectedOperation() {
        guard let op = selectedOperation else {
            tripOutSteps = []
            tripInSteps = []
            circulationSteps = []
            reamOutSteps = []
            reamInSteps = []
            return
        }

        tripOutSteps = tripOutResults[op.id] ?? []
        tripInSteps = tripInResults[op.id] ?? []
        circulationSteps = circulationResults[op.id] ?? []
        reamOutSteps = reamOutResults[op.id] ?? []
        reamInSteps = reamInResults[op.id] ?? []
        selectedStepIndex = 0
        stepSlider = 0
    }

    // MARK: - Invalidation

    private func invalidateFrom(_ index: Int) {
        for i in index..<operations.count {
            operations[i].inputState = nil
            operations[i].outputState = nil
            operations[i].status = .pending
            tripOutResults.removeValue(forKey: operations[i].id)
            tripOutESDAtControl.removeValue(forKey: operations[i].id)
            tripInResults.removeValue(forKey: operations[i].id)
            circulationResults.removeValue(forKey: operations[i].id)
            reamOutResults.removeValue(forKey: operations[i].id)
            reamOutESDAtControl.removeValue(forKey: operations[i].id)
            reamInResults.removeValue(forKey: operations[i].id)
        }
    }

    // MARK: - Bootstrap

    func bootstrap(from project: ProjectState) {
        let annulusSections = project.annulus ?? []
        let drillString = project.drillString ?? []

        // Build initial state from project's current mud placement
        let tvdSampler = TvdSampler(project: project)
        let deepestMD = annulusSections.max(by: { $0.bottomDepth_m < $1.bottomDepth_m })?.bottomDepth_m ?? 0

        let annulusLayers = project.finalAnnulusLayersSorted.map { layer -> TripLayerSnapshot in
            let topTVD = tvdSampler.tvd(of: layer.topMD_m)
            let bottomTVD = tvdSampler.tvd(of: layer.bottomMD_m)
            return TripLayerSnapshot(
                side: "annulus",
                topMD: layer.topMD_m,
                bottomMD: layer.bottomMD_m,
                topTVD: topTVD,
                bottomTVD: bottomTVD,
                rho_kgpm3: layer.density_kgm3,
                deltaHydroStatic_kPa: layer.density_kgm3 * 0.00981 * (bottomTVD - topTVD),
                volume_m3: 0,
                colorR: layer.colorR,
                colorG: layer.colorG,
                colorB: layer.colorB,
                colorA: layer.colorA
            )
        }

        let stringLayers = project.finalStringLayersSorted.map { layer -> TripLayerSnapshot in
            let topTVD = tvdSampler.tvd(of: layer.topMD_m)
            let bottomTVD = tvdSampler.tvd(of: layer.bottomMD_m)
            return TripLayerSnapshot(
                side: "string",
                topMD: layer.topMD_m,
                bottomMD: layer.bottomMD_m,
                topTVD: topTVD,
                bottomTVD: bottomTVD,
                rho_kgpm3: layer.density_kgm3,
                deltaHydroStatic_kPa: layer.density_kgm3 * 0.00981 * (bottomTVD - topTVD),
                volume_m3: 0,
                colorR: layer.colorR,
                colorG: layer.colorG,
                colorB: layer.colorB,
                colorA: layer.colorA
            )
        }

        let controlMD = annulusSections.filter { $0.isCased }.max(by: { $0.bottomDepth_m < $1.bottomDepth_m })?.bottomDepth_m ?? 0
        let controlTVD = tvdSampler.tvd(of: controlMD)
        controlTVD_m = controlTVD
        let activeDensity = project.activeMud?.density_kgm3 ?? 1200

        let esd = CirculationService.calculateESDFromLayers(
            layers: annulusLayers,
            atDepthMD: controlMD,
            tvdSampler: tvdSampler
        )

        initialState = WellboreStateSnapshot(
            bitMD_m: deepestMD,
            bitTVD_m: tvdSampler.tvd(of: deepestMD),
            layersPocket: [],
            layersAnnulus: annulusLayers,
            layersString: stringLayers,
            SABP_kPa: 0,
            ESDAtControl_kgpm3: esd,
            controlMD_m: controlMD,
            targetESD_kgpm3: activeDensity,
            sourceDescription: "Project Initial State",
            timestamp: Date()
        )

        // Set defaults for new operations
        let activeMudID = project.activeMud?.id
        for i in operations.indices {
            if operations[i].controlMD_m == 0 {
                operations[i].controlMD_m = controlMD
            }
            if operations[i].baseMudID == nil {
                operations[i].baseMudID = activeMudID
                operations[i].baseMudDensity_kgpm3 = activeDensity
            }
        }
    }

    // MARK: - Run All

    func runAll(project: ProjectState) {
        guard !isRunning else { return }
        runFrom(operationIndex: 0, project: project)
    }

    func runFrom(operationIndex: Int, project: ProjectState) {
        guard !isRunning, operationIndex >= 0, operationIndex < operations.count else { return }

        // Bootstrap if needed
        if initialState == nil {
            bootstrap(from: project)
        }

        // Invalidate from this point forward
        invalidateFrom(operationIndex)

        isRunning = true
        overallProgress = 0.0
        progressMessage = "Starting..."

        let tvdSampler = TvdSampler(project: project)
        let annulusSections = project.annulus ?? []
        let drillString = project.drillString ?? []
        let projectSnapshot = NumericalTripModel.ProjectSnapshot(from: project)
        let activeDensity = project.activeMud?.density_kgm3 ?? 1200

        // Capture mud rheology and colors for PV/YP and color lookup (used by trip out for backfill/base mud)
        var mudRheologyMap: [UUID: MudRheology] = [:]
        var mudColorMap: [UUID: NumericalTripModel.ColorRGBA] = [:]
        for mud in (project.muds ?? []) {
            let pvCp: Double
            let ypPa: Double
            if let d600 = mud.dial600, let d300 = mud.dial300 {
                pvCp = d600 - d300
                ypPa = max(0, (d300 - pvCp) * 0.4788)
            } else if let pv = mud.pv_Pa_s, let yp = mud.yp_Pa {
                pvCp = pv * 1000.0 // Pa·s → cP
                ypPa = yp
            } else {
                pvCp = 0
                ypPa = 0
            }
            mudRheologyMap[mud.id] = MudRheology(pv_cP: pvCp, yp_Pa: ypPa)
            mudColorMap[mud.id] = NumericalTripModel.ColorRGBA(r: mud.colorR, g: mud.colorG, b: mud.colorB, a: mud.colorA)
        }

        // Ensure controlTVD_m is set from the first operation's controlMD
        if controlTVD_m == 0, let firstControlMD = operations.first?.controlMD_m, firstControlMD > 0 {
            controlTVD_m = tvdSampler.tvd(of: firstControlMD)
        }

        Task.detached { [weak self] in
            guard let self else { return }

            // Determine starting state
            var currentState: WellboreStateSnapshot
            if operationIndex == 0 {
                guard let initial = await MainActor.run(body: { self.initialState }) else {
                    await MainActor.run { self.isRunning = false }
                    return
                }
                currentState = initial
            } else {
                guard let prevOutput = await MainActor.run(body: { self.operations[operationIndex - 1].outputState }) else {
                    await MainActor.run { self.isRunning = false }
                    return
                }
                currentState = prevOutput
            }

            let totalOps = await MainActor.run { self.operations.count }

            for i in operationIndex..<totalOps {
                let op = await MainActor.run { self.operations[i] }

                await MainActor.run {
                    self.operations[i].inputState = currentState
                    self.operations[i].status = .running
                    self.currentRunningIndex = i
                    self.operationProgress = 0.0
                    switch op.type {
                    case .tripOut:
                        self.progressMessage = "Trip Out \(String(format: "%.0f", op.startMD_m))→\(String(format: "%.0f", op.endMD_m))m (\(i + 1)/\(totalOps))..."
                    case .tripIn:
                        self.progressMessage = "Trip In \(String(format: "%.0f", op.startMD_m))→\(String(format: "%.0f", op.endMD_m))m (\(i + 1)/\(totalOps))..."
                    case .circulate:
                        self.progressMessage = "Circulating @ \(String(format: "%.0f", op.startMD_m))m (\(i + 1)/\(totalOps))..."
                    case .reamOut:
                        self.progressMessage = "Ream Out \(String(format: "%.0f", op.startMD_m))→\(String(format: "%.0f", op.endMD_m))m (\(i + 1)/\(totalOps))..."
                    case .reamIn:
                        self.progressMessage = "Ream In \(String(format: "%.0f", op.startMD_m))→\(String(format: "%.0f", op.endMD_m))m (\(i + 1)/\(totalOps))..."
                    }
                }

                let result: WellboreStateSnapshot
                switch op.type {
                case .tripOut:
                    result = await self.runTripOut(op, state: currentState, tvdSampler: tvdSampler, annulusSections: annulusSections, drillString: drillString, projectSnapshot: projectSnapshot, activeDensity: activeDensity, mudRheologyMap: mudRheologyMap, mudColorMap: mudColorMap)

                case .tripIn:
                    result = self.runTripIn(op, state: currentState, tvdSampler: tvdSampler, annulusSections: annulusSections, drillString: drillString, mudRheologyMap: mudRheologyMap)

                case .circulate:
                    result = self.runCirculation(op, state: currentState, tvdSampler: tvdSampler, annulusSections: annulusSections, drillString: drillString, activeDensity: activeDensity)

                case .reamOut:
                    result = await self.executeReamOut(op, state: currentState, tvdSampler: tvdSampler, annulusSections: annulusSections, drillString: drillString, projectSnapshot: projectSnapshot, activeDensity: activeDensity, mudRheologyMap: mudRheologyMap, mudColorMap: mudColorMap)

                case .reamIn:
                    result = self.executeReamIn(op, state: currentState, tvdSampler: tvdSampler, annulusSections: annulusSections, drillString: drillString, mudRheologyMap: mudRheologyMap)
                }

                currentState = result

                await MainActor.run {
                    self.operations[i].outputState = result
                    self.operations[i].status = .complete
                    self.operationProgress = 1.0
                    self.overallProgress = Double(i + 1 - operationIndex) / Double(totalOps - operationIndex)
                }
            }

            await MainActor.run {
                self.isRunning = false
                self.currentRunningIndex = nil
                self.progressMessage = "Complete"
                self.overallProgress = 1.0
                self.loadResultsForSelectedOperation()
            }
        }
    }

    // MARK: - Trip Out Runner

    private struct MudRheology: Sendable {
        let pv_cP: Double
        let yp_Pa: Double
    }

    private func runTripOut(
        _ op: SuperSimOperation,
        state: WellboreStateSnapshot,
        tvdSampler: TvdSampler,
        annulusSections: [AnnulusSection],
        drillString: [DrillStringSection],
        projectSnapshot: NumericalTripModel.ProjectSnapshot,
        activeDensity: Double,
        mudRheologyMap: [UUID: MudRheology] = [:],
        mudColorMap: [UUID: NumericalTripModel.ColorRGBA] = [:]
    ) async -> WellboreStateSnapshot {
        let geom = ProjectGeometryService(
            annulus: annulusSections,
            string: drillString,
            currentStringBottomMD: op.startMD_m,
            mdToTvd: { md in tvdSampler.tvd(of: md) }
        )

        let shoeTVD = tvdSampler.tvd(of: op.controlMD_m)
        var backfillColor: NumericalTripModel.ColorRGBA? = nil
        if let r = op.backfillColorR, let g = op.backfillColorG, let b = op.backfillColorB {
            backfillColor = NumericalTripModel.ColorRGBA(r: r, g: g, b: b, a: op.backfillColorA ?? 1)
        }

        // Look up PV/YP and color from mud maps
        let backfillRheo = op.backfillMudID.flatMap { mudRheologyMap[$0] }
        let baseRheo = op.baseMudID.flatMap { mudRheologyMap[$0] }
        let baseMudColor = op.baseMudID.flatMap { mudColorMap[$0] }

        // Compute displacement volume for switch-to-active feature
        let displacementVolume_m3: Double
        if op.switchToActiveAfterDisplacement {
            if op.useOverrideDisplacementVolume {
                displacementVolume_m3 = op.overrideDisplacementVolume_m3
            } else {
                let odVolume = geom.volumeOfStringOD_m3(op.endMD_m, op.startMD_m)
                let idVolume = geom.volumeInString_m3(op.endMD_m, op.startMD_m)
                displacementVolume_m3 = max(0, odVolume - idVolume)
            }
        } else {
            displacementVolume_m3 = 0
        }

        var input = NumericalTripModel.TripInput(
            tvdOfMd: { md in tvdSampler.tvd(of: md) },
            shoeTVD_m: shoeTVD,
            startBitMD_m: op.startMD_m,
            endMD_m: op.endMD_m,
            crackFloat_kPa: op.crackFloat_kPa,
            step_m: op.step_m,
            baseMudDensity_kgpm3: op.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: op.backfillDensity_kgpm3,
            backfillColor: backfillColor,
            baseMudColor: baseMudColor,
            backfillPV_cP: backfillRheo?.pv_cP ?? 0,
            backfillYP_Pa: backfillRheo?.yp_Pa ?? 0,
            baseMudPV_cP: baseRheo?.pv_cP ?? 0,
            baseMudYP_Pa: baseRheo?.yp_Pa ?? 0,
            fixedBackfillVolume_m3: displacementVolume_m3,
            switchToBaseAfterFixed: op.switchToActiveAfterDisplacement,
            targetESDAtTD_kgpm3: op.targetESD_kgpm3,
            initialSABP_kPa: state.SABP_kPa,
            holdSABPOpen: op.holdSABPOpen,
            tripSpeed_m_per_s: op.tripSpeed_m_per_s,
            eccentricityFactor: op.eccentricityFactor,
            fallbackTheta600: op.fallbackTheta600,
            fallbackTheta300: op.fallbackTheta300,
            observedInitialPitGain_m3: op.useObservedPitGain ? op.observedInitialPitGain_m3 : nil
        )

        // Super Sim: inject custom initial layers from previous operation's state
        input.initialAnnulusLayers = state.layersAnnulus.isEmpty ? nil : state.layersAnnulus
        input.initialStringLayers = state.layersString.isEmpty ? nil : state.layersString
        input.initialPocketLayers = state.layersPocket.isEmpty ? nil : state.layersPocket

        let model = NumericalTripModel()
        let steps = model.run(input, geom: geom, projectSnapshot: projectSnapshot)

        // Compute per-step ESD at controlMD (consistent with trip in / circulation)
        let esdAtControl = steps.map { step -> Double in
            let allLayers = (step.layersAnnulus + step.layersPocket).map { TripLayerSnapshot(from: $0) }
            return CirculationService.calculateESDFromLayers(
                layers: allLayers, atDepthMD: op.controlMD_m, tvdSampler: tvdSampler
            )
        }

        // Store results
        await MainActor.run {
            self.tripOutResults[op.id] = steps
            self.tripOutESDAtControl[op.id] = esdAtControl
        }

        // Extract final state
        guard let lastStep = steps.last else {
            return state
        }

        let pocketLayers = lastStep.layersPocket.map { lr -> TripLayerSnapshot in
            let s = TripLayerSnapshot(from: lr)
            return TripLayerSnapshot(side: "pocket", topMD: s.topMD, bottomMD: s.bottomMD, topTVD: s.topTVD, bottomTVD: s.bottomTVD, rho_kgpm3: s.rho_kgpm3, deltaHydroStatic_kPa: s.deltaHydroStatic_kPa, volume_m3: s.volume_m3, colorR: s.colorR, colorG: s.colorG, colorB: s.colorB, colorA: s.colorA, isInAnnulus: false, pv_cP: s.pv_cP, yp_Pa: s.yp_Pa)
        }
        let annulusLayers = lastStep.layersAnnulus.map { lr -> TripLayerSnapshot in
            let s = TripLayerSnapshot(from: lr)
            return TripLayerSnapshot(side: "annulus", topMD: s.topMD, bottomMD: s.bottomMD, topTVD: s.topTVD, bottomTVD: s.bottomTVD, rho_kgpm3: s.rho_kgpm3, deltaHydroStatic_kPa: s.deltaHydroStatic_kPa, volume_m3: s.volume_m3, colorR: s.colorR, colorG: s.colorG, colorB: s.colorB, colorA: s.colorA, isInAnnulus: true, pv_cP: s.pv_cP, yp_Pa: s.yp_Pa)
        }
        let stringLayers = lastStep.layersString.map { lr -> TripLayerSnapshot in
            let s = TripLayerSnapshot(from: lr)
            return TripLayerSnapshot(side: "string", topMD: s.topMD, bottomMD: s.bottomMD, topTVD: s.topTVD, bottomTVD: s.bottomTVD, rho_kgpm3: s.rho_kgpm3, deltaHydroStatic_kPa: s.deltaHydroStatic_kPa, volume_m3: s.volume_m3, colorR: s.colorR, colorG: s.colorG, colorB: s.colorB, colorA: s.colorA, isInAnnulus: false, pv_cP: s.pv_cP, yp_Pa: s.yp_Pa)
        }

        // ESD at controlMD (not at TD) for consistent state chaining
        let finalESDAtControl = CirculationService.calculateESDFromLayers(
            layers: pocketLayers + annulusLayers,
            atDepthMD: op.controlMD_m,
            tvdSampler: tvdSampler
        )

        return WellboreStateSnapshot(
            bitMD_m: lastStep.bitMD_m,
            bitTVD_m: lastStep.bitTVD_m,
            layersPocket: pocketLayers,
            layersAnnulus: annulusLayers,
            layersString: stringLayers,
            SABP_kPa: lastStep.SABP_kPa,
            ESDAtControl_kgpm3: finalESDAtControl,
            controlMD_m: op.controlMD_m,
            targetESD_kgpm3: op.targetESD_kgpm3,
            sourceDescription: "Trip Out → \(String(format: "%.0f", lastStep.bitMD_m))m",
            timestamp: Date()
        )
    }

    // MARK: - Trip In Runner

    private func runTripIn(
        _ op: SuperSimOperation,
        state: WellboreStateSnapshot,
        tvdSampler: TvdSampler,
        annulusSections: [AnnulusSection],
        drillString: [DrillStringSection],
        mudRheologyMap: [UUID: MudRheology]
    ) -> WellboreStateSnapshot {
        // Combine all outside-pipe layers as pocket input for TripInService.
        // TripInService sorts by depth internally and uses isInAnnulus to avoid
        // re-expanding layers that already have pipe alongside them.
        let combinedPocketInput = state.layersPocket + state.layersAnnulus

        // Compute surge profile if trip speed is set
        var surgeProfile: [TripInService.SurgePressurePoint] = []
        if op.tripInSpeed_m_per_s > 0 {
            let fillMudRheo = op.fillMudID.flatMap { mudRheologyMap[$0] }
            let pvPaS = fillMudRheo.map { $0.pv_cP / 1000.0 }   // cP → Pa·s
            let ypPa = fillMudRheo?.yp_Pa

            if let pv = pvPaS, let yp = ypPa, pv > 0 || yp > 0 {
                // Use project drill string, or create synthetic from pipe OD/ID
                let dsSections: [DrillStringSection]
                if !drillString.isEmpty {
                    dsSections = drillString
                } else {
                    let syntheticDS = DrillStringSection(
                        name: "Trip-In String",
                        topDepth_m: 0,
                        length_m: op.endMD_m,
                        outerDiameter_m: op.pipeOD_m,
                        innerDiameter_m: op.pipeID_m
                    )
                    dsSections = [syntheticDS]
                }

                let syntheticMud = MudProperties()
                syntheticMud.density_kgm3 = op.fillMudDensity_kgpm3
                syntheticMud.pv_Pa_s = pv
                syntheticMud.yp_Pa = yp

                let calculator = SurgeSwabCalculator(
                    tripSpeed_m_per_min: op.tripInSpeed_m_per_s * 60.0,
                    startBitMD_m: op.startMD_m,
                    endBitMD_m: op.endMD_m,
                    depthStep_m: op.tripInStep_m,
                    annulusSections: annulusSections,
                    drillStringSections: dsSections,
                    mud: syntheticMud,
                    pipeEndType: op.isFloatedCasing ? .closed : .open
                )

                let results = calculator.calculate(tvdLookup: { md in
                    tvdSampler.tvd(of: md)
                })
                surgeProfile = results.map { r in
                    TripInService.SurgePressurePoint(md: r.bitMD_m, surgePressure_kPa: r.surgePressure_kPa)
                }
            }
        }

        var input = TripInService.TripInInput(
            startBitMD_m: op.startMD_m,
            endBitMD_m: op.endMD_m,
            controlMD_m: op.controlMD_m,
            step_m: op.tripInStep_m,
            pipeOD_m: op.pipeOD_m,
            pipeID_m: op.pipeID_m,
            activeMudDensity_kgpm3: op.fillMudDensity_kgpm3,
            baseMudDensity_kgpm3: op.baseMudDensity_kgpm3,
            targetESD_kgpm3: op.targetESD_kgpm3,
            isFloatedCasing: op.isFloatedCasing,
            floatSubMD_m: op.floatSubMD_m,
            crackFloat_kPa: op.crackFloat_kPa,
            pocketLayers: combinedPocketInput,
            annulusSections: annulusSections,
            tvdSampler: tvdSampler,
            surgeProfile: surgeProfile
        )

        let result = TripInService.run(input)

        Task { @MainActor [weak self] in
            self?.tripInResults[op.id] = result.steps
        }

        guard let lastStep = result.steps.last else { return state }

        // Split displaced layers at bit depth into annulus (above) and pocket (below)
        let split = splitLayersAtBit(
            layers: lastStep.layersPocket,
            bitMD: lastStep.bitMD_m,
            tvdSampler: tvdSampler
        )

        // Create string layer (fill mud from surface to bit)
        let bitTVD = tvdSampler.tvd(of: lastStep.bitMD_m)
        let stringLayers: [TripLayerSnapshot]
        if lastStep.bitMD_m > 0 {
            stringLayers = [TripLayerSnapshot(
                side: "string",
                topMD: 0,
                bottomMD: lastStep.bitMD_m,
                topTVD: 0,
                bottomTVD: bitTVD,
                rho_kgpm3: op.fillMudDensity_kgpm3,
                deltaHydroStatic_kPa: op.fillMudDensity_kgpm3 * 0.00981 * bitTVD,
                volume_m3: 0,
                colorR: op.fillMudColorR,
                colorG: op.fillMudColorG,
                colorB: op.fillMudColorB,
                colorA: op.fillMudColorA
            )]
        } else {
            stringLayers = []
        }

        return WellboreStateSnapshot(
            bitMD_m: lastStep.bitMD_m,
            bitTVD_m: lastStep.bitTVD_m,
            layersPocket: split.pocket,
            layersAnnulus: split.annulus,
            layersString: stringLayers,
            SABP_kPa: 0,
            ESDAtControl_kgpm3: lastStep.ESDAtControl_kgpm3,
            controlMD_m: op.controlMD_m,
            targetESD_kgpm3: op.targetESD_kgpm3,
            sourceDescription: "Trip In → \(String(format: "%.0f", lastStep.bitMD_m))m",
            timestamp: Date()
        )
    }

    // MARK: - Circulation Runner

    private func runCirculation(
        _ op: SuperSimOperation,
        state: WellboreStateSnapshot,
        tvdSampler: TvdSampler,
        annulusSections: [AnnulusSection],
        drillString: [DrillStringSection],
        activeDensity: Double
    ) -> WellboreStateSnapshot {
        let geom = ProjectGeometryService(
            annulus: annulusSections,
            string: drillString,
            currentStringBottomMD: state.bitMD_m,
            mdToTvd: { md in tvdSampler.tvd(of: md) }
        )

        // Decode pump queue from operation
        var pumpQueue: [CirculationService.PumpOperation] = []
        if let data = op.pumpQueueEncoded,
           let decoded = try? JSONDecoder().decode([CodablePumpOperation].self, from: data) {
            pumpQueue = decoded.map { $0.toPumpOperation() }
        }

        guard !pumpQueue.isEmpty else { return state }

        // CirculationService needs the FULL column (annulus + pocket) because:
        // - Annulus layers (above bit) get circulated via parcel displacement
        // - Pocket layers (below bit) stay static but are needed for ESD calculation
        // CirculationService splits them internally at bitMD.
        let fullColumnInput = state.layersAnnulus + state.layersPocket
        let stringInput = state.layersString

        let result = CirculationService.previewPumpQueue(
            pocketLayers: fullColumnInput,
            stringLayers: stringInput,
            bitMD: state.bitMD_m,
            controlMD: op.controlMD_m,
            targetESD_kgpm3: op.targetESD_kgpm3,
            geom: geom,
            tvdSampler: tvdSampler,
            pumpQueue: pumpQueue,
            activeMudDensity_kgpm3: activeDensity,
            maxPumpRate_m3perMin: op.maxPumpRate_m3perMin,
            minPumpRate_m3perMin: op.minPumpRate_m3perMin,
            annulusSections: annulusSections,
            drillStringSections: drillString,
            progressCallback: { [weak self] pumped, total in
                guard let self else { return }
                let fraction = total > 0 ? pumped / total : 0
                let pct = Int(fraction * 100)
                DispatchQueue.main.async {
                    self.operationProgress = min(fraction, 1.0)
                    self.progressMessage = "Circulating... \(String(format: "%.1f", pumped))/\(String(format: "%.1f", total)) m\u{00B3} (\(pct)%)"
                }
            }
        )

        // Store results
        Task { @MainActor [weak self] in
            self?.circulationResults[op.id] = result.schedule
        }

        // resultLayersPocket contains modified annulus + static open hole.
        // Split at bit depth to separate them for state chaining.
        let split = splitLayersAtBit(
            layers: result.resultLayersPocket,
            bitMD: state.bitMD_m,
            tvdSampler: tvdSampler
        )

        return WellboreStateSnapshot(
            bitMD_m: state.bitMD_m,
            bitTVD_m: state.bitTVD_m,
            layersPocket: split.pocket,
            layersAnnulus: split.annulus,
            layersString: result.resultLayersString,
            SABP_kPa: result.requiredSABP,
            ESDAtControl_kgpm3: result.ESDAtControl,
            controlMD_m: op.controlMD_m,
            targetESD_kgpm3: op.targetESD_kgpm3,
            sourceDescription: "Circulate @ \(String(format: "%.0f", state.bitMD_m))m",
            timestamp: Date()
        )
    }

    // MARK: - Ream Out Runner

    private func executeReamOut(
        _ op: SuperSimOperation,
        state: WellboreStateSnapshot,
        tvdSampler: TvdSampler,
        annulusSections: [AnnulusSection],
        drillString: [DrillStringSection],
        projectSnapshot: NumericalTripModel.ProjectSnapshot,
        activeDensity: Double,
        mudRheologyMap: [UUID: MudRheology] = [:],
        mudColorMap: [UUID: NumericalTripModel.ColorRGBA] = [:]
    ) async -> WellboreStateSnapshot {
        // Ream Out = Trip Out + pumping (APL). Reuse the trip-out engine then augment.
        let geom = ProjectGeometryService(
            annulus: annulusSections,
            string: drillString,
            currentStringBottomMD: op.startMD_m,
            mdToTvd: { md in tvdSampler.tvd(of: md) }
        )

        let shoeTVD = tvdSampler.tvd(of: op.controlMD_m)
        var backfillColor: NumericalTripModel.ColorRGBA? = nil
        if let r = op.backfillColorR, let g = op.backfillColorG, let b = op.backfillColorB {
            backfillColor = NumericalTripModel.ColorRGBA(r: r, g: g, b: b, a: op.backfillColorA ?? 1)
        }

        let backfillRheo = op.backfillMudID.flatMap { mudRheologyMap[$0] }
        let baseRheo = op.baseMudID.flatMap { mudRheologyMap[$0] }
        let baseMudColor = op.baseMudID.flatMap { mudColorMap[$0] }

        let displacementVolume_m3: Double
        if op.switchToActiveAfterDisplacement {
            if op.useOverrideDisplacementVolume {
                displacementVolume_m3 = op.overrideDisplacementVolume_m3
            } else {
                let odVolume = geom.volumeOfStringOD_m3(op.endMD_m, op.startMD_m)
                let idVolume = geom.volumeInString_m3(op.endMD_m, op.startMD_m)
                displacementVolume_m3 = max(0, odVolume - idVolume)
            }
        } else {
            displacementVolume_m3 = 0
        }

        var input = NumericalTripModel.TripInput(
            tvdOfMd: { md in tvdSampler.tvd(of: md) },
            shoeTVD_m: shoeTVD,
            startBitMD_m: op.startMD_m,
            endMD_m: op.endMD_m,
            crackFloat_kPa: op.crackFloat_kPa,
            step_m: op.step_m,
            baseMudDensity_kgpm3: op.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: op.backfillDensity_kgpm3,
            backfillColor: backfillColor,
            baseMudColor: baseMudColor,
            backfillPV_cP: backfillRheo?.pv_cP ?? 0,
            backfillYP_Pa: backfillRheo?.yp_Pa ?? 0,
            baseMudPV_cP: baseRheo?.pv_cP ?? 0,
            baseMudYP_Pa: baseRheo?.yp_Pa ?? 0,
            fixedBackfillVolume_m3: displacementVolume_m3,
            switchToBaseAfterFixed: op.switchToActiveAfterDisplacement,
            targetESDAtTD_kgpm3: op.targetESD_kgpm3,
            initialSABP_kPa: state.SABP_kPa,
            holdSABPOpen: op.holdSABPOpen,
            tripSpeed_m_per_s: op.tripSpeed_m_per_s,
            eccentricityFactor: op.eccentricityFactor,
            fallbackTheta600: op.fallbackTheta600,
            fallbackTheta300: op.fallbackTheta300,
            observedInitialPitGain_m3: op.useObservedPitGain ? op.observedInitialPitGain_m3 : nil
        )

        input.initialAnnulusLayers = state.layersAnnulus.isEmpty ? nil : state.layersAnnulus
        input.initialStringLayers = state.layersString.isEmpty ? nil : state.layersString
        input.initialPocketLayers = state.layersPocket.isEmpty ? nil : state.layersPocket

        // Run through ReamEngine (free function from ReamEngine.swift)
        let steps = runReamOut(
            tripInput: input,
            geom: geom,
            projectSnapshot: projectSnapshot,
            pumpRate_m3perMin: op.reamPumpRate_m3perMin,
            annulusSections: annulusSections,
            drillStringSections: drillString,
            controlMD_m: op.controlMD_m,
            tvdSampler: tvdSampler
        )

        // Compute per-step ESD at controlMD
        let esdAtControl = steps.map { step -> Double in
            let allLayers = (step.layersAnnulus + step.layersPocket).map { TripLayerSnapshot(from: $0) }
            return CirculationService.calculateESDFromLayers(
                layers: allLayers, atDepthMD: op.controlMD_m, tvdSampler: tvdSampler
            )
        }

        await MainActor.run {
            self.reamOutResults[op.id] = steps
            self.reamOutESDAtControl[op.id] = esdAtControl
        }

        guard let lastStep = steps.last else { return state }

        let pocketLayers = lastStep.layersPocket.map { lr -> TripLayerSnapshot in
            let s = TripLayerSnapshot(from: lr)
            return TripLayerSnapshot(side: "pocket", topMD: s.topMD, bottomMD: s.bottomMD, topTVD: s.topTVD, bottomTVD: s.bottomTVD, rho_kgpm3: s.rho_kgpm3, deltaHydroStatic_kPa: s.deltaHydroStatic_kPa, volume_m3: s.volume_m3, colorR: s.colorR, colorG: s.colorG, colorB: s.colorB, colorA: s.colorA, isInAnnulus: false, pv_cP: s.pv_cP, yp_Pa: s.yp_Pa)
        }
        let annulusLayers = lastStep.layersAnnulus.map { lr -> TripLayerSnapshot in
            let s = TripLayerSnapshot(from: lr)
            return TripLayerSnapshot(side: "annulus", topMD: s.topMD, bottomMD: s.bottomMD, topTVD: s.topTVD, bottomTVD: s.bottomTVD, rho_kgpm3: s.rho_kgpm3, deltaHydroStatic_kPa: s.deltaHydroStatic_kPa, volume_m3: s.volume_m3, colorR: s.colorR, colorG: s.colorG, colorB: s.colorB, colorA: s.colorA, isInAnnulus: true, pv_cP: s.pv_cP, yp_Pa: s.yp_Pa)
        }
        let stringLayers = lastStep.layersString.map { lr -> TripLayerSnapshot in
            let s = TripLayerSnapshot(from: lr)
            return TripLayerSnapshot(side: "string", topMD: s.topMD, bottomMD: s.bottomMD, topTVD: s.topTVD, bottomTVD: s.bottomTVD, rho_kgpm3: s.rho_kgpm3, deltaHydroStatic_kPa: s.deltaHydroStatic_kPa, volume_m3: s.volume_m3, colorR: s.colorR, colorG: s.colorG, colorB: s.colorB, colorA: s.colorA, isInAnnulus: false, pv_cP: s.pv_cP, yp_Pa: s.yp_Pa)
        }

        let finalESDAtControl = CirculationService.calculateESDFromLayers(
            layers: pocketLayers + annulusLayers,
            atDepthMD: op.controlMD_m,
            tvdSampler: tvdSampler
        )

        return WellboreStateSnapshot(
            bitMD_m: lastStep.bitMD_m,
            bitTVD_m: lastStep.bitTVD_m,
            layersPocket: pocketLayers,
            layersAnnulus: annulusLayers,
            layersString: stringLayers,
            SABP_kPa: lastStep.SABP_Dynamic_kPa,
            ESDAtControl_kgpm3: finalESDAtControl,
            controlMD_m: op.controlMD_m,
            targetESD_kgpm3: op.targetESD_kgpm3,
            sourceDescription: "Ream Out → \(String(format: "%.0f", lastStep.bitMD_m))m",
            timestamp: Date()
        )
    }

    // MARK: - Ream In Runner

    private func executeReamIn(
        _ op: SuperSimOperation,
        state: WellboreStateSnapshot,
        tvdSampler: TvdSampler,
        annulusSections: [AnnulusSection],
        drillString: [DrillStringSection],
        mudRheologyMap: [UUID: MudRheology]
    ) -> WellboreStateSnapshot {
        let combinedPocketInput = state.layersPocket + state.layersAnnulus

        // Build surge profile if trip speed > 0
        var surgeProfile: [TripInService.SurgePressurePoint] = []
        if op.tripInSpeed_m_per_s > 0 {
            let fillMudRheo = op.fillMudID.flatMap { mudRheologyMap[$0] }
            let pvPaS = fillMudRheo.map { $0.pv_cP / 1000.0 }
            let ypPa = fillMudRheo?.yp_Pa

            if let pv = pvPaS, let yp = ypPa, pv > 0 || yp > 0 {
                let dsSections: [DrillStringSection]
                if !drillString.isEmpty {
                    dsSections = drillString
                } else {
                    let syntheticDS = DrillStringSection(
                        name: "Trip-In String",
                        topDepth_m: 0,
                        length_m: op.endMD_m,
                        outerDiameter_m: op.pipeOD_m,
                        innerDiameter_m: op.pipeID_m
                    )
                    dsSections = [syntheticDS]
                }

                let syntheticMud = MudProperties()
                syntheticMud.density_kgm3 = op.fillMudDensity_kgpm3
                syntheticMud.pv_Pa_s = pv
                syntheticMud.yp_Pa = yp

                let calculator = SurgeSwabCalculator(
                    tripSpeed_m_per_min: op.tripInSpeed_m_per_s * 60.0,
                    startBitMD_m: op.startMD_m,
                    endBitMD_m: op.endMD_m,
                    depthStep_m: op.tripInStep_m,
                    annulusSections: annulusSections,
                    drillStringSections: dsSections,
                    mud: syntheticMud,
                    pipeEndType: op.isFloatedCasing ? .closed : .open
                )

                let results = calculator.calculate(tvdLookup: { md in
                    tvdSampler.tvd(of: md)
                })
                surgeProfile = results.map { r in
                    TripInService.SurgePressurePoint(md: r.bitMD_m, surgePressure_kPa: r.surgePressure_kPa)
                }
            }
        }

        var input = TripInService.TripInInput(
            startBitMD_m: op.startMD_m,
            endBitMD_m: op.endMD_m,
            controlMD_m: op.controlMD_m,
            step_m: op.tripInStep_m,
            pipeOD_m: op.pipeOD_m,
            pipeID_m: op.pipeID_m,
            activeMudDensity_kgpm3: op.fillMudDensity_kgpm3,
            baseMudDensity_kgpm3: op.baseMudDensity_kgpm3,
            targetESD_kgpm3: op.targetESD_kgpm3,
            isFloatedCasing: op.isFloatedCasing,
            floatSubMD_m: op.floatSubMD_m,
            crackFloat_kPa: op.crackFloat_kPa,
            pocketLayers: combinedPocketInput,
            annulusSections: annulusSections,
            tvdSampler: tvdSampler,
            surgeProfile: surgeProfile
        )

        // Run through ReamEngine (free function from ReamEngine.swift)
        let steps = runReamIn(
            tripInInput: input,
            pumpRate_m3perMin: op.reamPumpRate_m3perMin,
            annulusSections: annulusSections,
            drillStringSections: drillString,
            tvdSampler: tvdSampler,
            controlMD_m: op.controlMD_m
        )

        Task { @MainActor [weak self] in
            self?.reamInResults[op.id] = steps
        }

        guard let lastStep = steps.last else { return state }

        let split = splitLayersAtBit(
            layers: lastStep.layersPocket,
            bitMD: lastStep.bitMD_m,
            tvdSampler: tvdSampler
        )

        let bitTVD = tvdSampler.tvd(of: lastStep.bitMD_m)
        let stringLayers: [TripLayerSnapshot]
        if lastStep.bitMD_m > 0 {
            stringLayers = [TripLayerSnapshot(
                side: "string",
                topMD: 0,
                bottomMD: lastStep.bitMD_m,
                topTVD: 0,
                bottomTVD: bitTVD,
                rho_kgpm3: op.fillMudDensity_kgpm3,
                deltaHydroStatic_kPa: op.fillMudDensity_kgpm3 * 0.00981 * bitTVD,
                volume_m3: 0,
                colorR: op.fillMudColorR,
                colorG: op.fillMudColorG,
                colorB: op.fillMudColorB,
                colorA: op.fillMudColorA
            )]
        } else {
            stringLayers = []
        }

        return WellboreStateSnapshot(
            bitMD_m: lastStep.bitMD_m,
            bitTVD_m: lastStep.bitTVD_m,
            layersPocket: split.pocket,
            layersAnnulus: split.annulus,
            layersString: stringLayers,
            SABP_kPa: lastStep.dynamicChoke_kPa,
            ESDAtControl_kgpm3: lastStep.ECD_kgpm3,
            controlMD_m: op.controlMD_m,
            targetESD_kgpm3: op.targetESD_kgpm3,
            sourceDescription: "Ream In → \(String(format: "%.0f", lastStep.bitMD_m))m",
            timestamp: Date()
        )
    }

    // MARK: - Slider Sync

    func updateFromSlider() {
        let index = Int(stepSlider.rounded())
        selectedStepIndex = max(0, index)
    }

    func syncSliderToSelection() {
        stepSlider = Double(selectedStepIndex)
    }

    /// Current step count for the selected operation
    var currentStepCount: Int {
        guard let op = selectedOperation else { return 0 }
        switch op.type {
        case .tripOut: return tripOutSteps.count
        case .tripIn: return tripInSteps.count
        case .circulate: return circulationSteps.count
        case .reamOut: return reamOutSteps.count
        case .reamIn: return reamInSteps.count
        }
    }

    // MARK: - Timeline Visualization Data

    struct TimelineChartPoint: Identifiable {
        var id: Int { globalIndex }
        let globalIndex: Int
        let operationIndex: Int
        let operationType: OperationType
        let operationLabel: String
        let bitMD_m: Double
        let ESDAtControl_kgpm3: Double
        let SABP_kPa: Double          // Static back pressure
        let dynamicSABP_kPa: Double   // Dynamic back pressure (while moving/pumping)
        let controlTVD_m: Double       // TVD at control depth for SABP → ESD conversion
        let pumpRate_m3perMin: Double  // Pump rate (circulation only, 0 for trips)
        let apl_kPa: Double           // Annular pressure loss (circulation only, 0 for trips)

        /// ESD including the contribution of static back pressure
        var totalESD_kgpm3: Double {
            guard controlTVD_m > 0 else { return ESDAtControl_kgpm3 }
            return ESDAtControl_kgpm3 + SABP_kPa / (0.00981 * controlTVD_m)
        }
    }

    var timelineChartData: [TimelineChartPoint] {
        var points: [TimelineChartPoint] = []
        var globalIdx = 0
        for (opIdx, op) in operations.enumerated() {
            let label = "\(opIdx + 1). \(op.type.rawValue)"
            switch op.type {
            case .tripOut:
                let esdValues = tripOutESDAtControl[op.id] ?? []
                for (idx, step) in (tripOutResults[op.id] ?? []).enumerated() {
                    let esd = idx < esdValues.count ? esdValues[idx] : step.ESDatTD_kgpm3
                    points.append(TimelineChartPoint(
                        globalIndex: globalIdx,
                        operationIndex: opIdx,
                        operationType: .tripOut,
                        operationLabel: label,
                        bitMD_m: step.bitMD_m,
                        ESDAtControl_kgpm3: esd,
                        SABP_kPa: step.SABP_kPa,
                        dynamicSABP_kPa: step.SABP_Dynamic_kPa,
                        controlTVD_m: controlTVD_m,
                        pumpRate_m3perMin: 0,
                        apl_kPa: 0
                    ))
                    globalIdx += 1
                }
            case .tripIn:
                for step in tripInResults[op.id] ?? [] {
                    // Dynamic choke accounts for surge: higher dynamic ESD means less choke needed
                    let dynamicChoke: Double
                    if step.dynamicESDAtControl_kgpm3 >= op.targetESD_kgpm3 {
                        dynamicChoke = 0
                    } else {
                        dynamicChoke = max(0, (op.targetESD_kgpm3 - step.dynamicESDAtControl_kgpm3) * 0.00981 * controlTVD_m)
                    }
                    points.append(TimelineChartPoint(
                        globalIndex: globalIdx,
                        operationIndex: opIdx,
                        operationType: .tripIn,
                        operationLabel: label,
                        bitMD_m: step.bitMD_m,
                        ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                        SABP_kPa: step.requiredChokePressure_kPa,
                        dynamicSABP_kPa: dynamicChoke,
                        controlTVD_m: controlTVD_m,
                        pumpRate_m3perMin: 0,
                        apl_kPa: step.surgePressure_kPa
                    ))
                    globalIdx += 1
                }
            case .circulate:
                for step in circulationResults[op.id] ?? [] {
                    // Static SABP = choke needed if not pumping (before APL reduction)
                    // Dynamic SABP = actual choke while pumping (static - APL)
                    let staticSABP = step.requiredSABP_kPa + step.apl_kPa
                    points.append(TimelineChartPoint(
                        globalIndex: globalIdx,
                        operationIndex: opIdx,
                        operationType: .circulate,
                        operationLabel: label,
                        bitMD_m: op.startMD_m,
                        ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                        SABP_kPa: staticSABP,
                        dynamicSABP_kPa: step.requiredSABP_kPa,
                        controlTVD_m: controlTVD_m,
                        pumpRate_m3perMin: step.pumpRate_m3perMin,
                        apl_kPa: step.apl_kPa
                    ))
                    globalIdx += 1
                }
            case .reamOut:
                let esdValues = reamOutESDAtControl[op.id] ?? []
                for (idx, step) in (reamOutResults[op.id] ?? []).enumerated() {
                    let esd = idx < esdValues.count ? esdValues[idx] : step.ESDatTD_kgpm3
                    points.append(TimelineChartPoint(
                        globalIndex: globalIdx,
                        operationIndex: opIdx,
                        operationType: .reamOut,
                        operationLabel: label,
                        bitMD_m: step.bitMD_m,
                        ESDAtControl_kgpm3: esd,
                        SABP_kPa: step.SABP_kPa,
                        dynamicSABP_kPa: step.SABP_Dynamic_kPa,
                        controlTVD_m: controlTVD_m,
                        pumpRate_m3perMin: step.pumpRate_m3perMin,
                        apl_kPa: step.apl_kPa
                    ))
                    globalIdx += 1
                }
            case .reamIn:
                for step in reamInResults[op.id] ?? [] {
                    let dynamicChoke = step.dynamicChoke_kPa
                    points.append(TimelineChartPoint(
                        globalIndex: globalIdx,
                        operationIndex: opIdx,
                        operationType: .reamIn,
                        operationLabel: label,
                        bitMD_m: step.bitMD_m,
                        ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                        SABP_kPa: step.requiredChokePressure_kPa,
                        dynamicSABP_kPa: dynamicChoke,
                        controlTVD_m: controlTVD_m,
                        pumpRate_m3perMin: step.pumpRate_m3perMin,
                        apl_kPa: step.apl_kPa
                    ))
                    globalIdx += 1
                }
            }
        }
        return points
    }

    var operationRanges: [(start: Int, end: Int, type: OperationType, label: String)] {
        var ranges: [(start: Int, end: Int, type: OperationType, label: String)] = []
        var idx = 0
        for (opIdx, op) in operations.enumerated() {
            let count = stepCountForOperation(op)
            if count > 0 {
                ranges.append((start: idx, end: idx + count - 1, type: op.type, label: "\(opIdx + 1). \(op.type.rawValue)"))
            }
            idx += count
        }
        return ranges
    }

    var operationBoundaries: [(globalIndex: Int, label: String)] {
        var boundaries: [(globalIndex: Int, label: String)] = []
        var globalIdx = 0
        for (opIdx, op) in operations.enumerated() {
            let count = stepCountForOperation(op)
            if count > 0 {
                boundaries.append((globalIndex: globalIdx, label: "\(opIdx + 1). \(op.type.rawValue)"))
            }
            globalIdx += count
        }
        return boundaries
    }

    /// Helper to get result count for any operation type
    private func stepCountForOperation(_ op: SuperSimOperation) -> Int {
        switch op.type {
        case .tripOut: return tripOutResults[op.id]?.count ?? 0
        case .tripIn: return tripInResults[op.id]?.count ?? 0
        case .circulate: return circulationResults[op.id]?.count ?? 0
        case .reamOut: return reamOutResults[op.id]?.count ?? 0
        case .reamIn: return reamInResults[op.id]?.count ?? 0
        }
    }

    // MARK: - Global Wellbore Scrubber

    var globalStepSliderValue: Double = 0

    var totalGlobalSteps: Int {
        var total = 0
        for op in operations {
            total += stepCountForOperation(op)
        }
        return total
    }

    struct WellboreDisplayState {
        let bitMD_m: Double
        let layersPocket: [TripLayerSnapshot]
        let layersAnnulus: [TripLayerSnapshot]
        let layersString: [TripLayerSnapshot]
        let label: String
    }

    func wellboreDisplayAtGlobalStep(_ globalIndex: Int) -> WellboreDisplayState? {
        var remaining = globalIndex
        for (opIdx, op) in operations.enumerated() {
            let count = stepCountForOperation(op)
            if remaining < count {
                return wellboreDisplay(operationIndex: opIdx, stepIndex: remaining)
            }
            remaining -= count
        }
        return nil
    }

    // MARK: - Layer Splitting Helper

    /// Split a flat layer array at the bit depth into annulus (above bit, pipe present)
    /// and pocket (below bit, open hole). Layers straddling the bit are split in two.
    private func splitLayersAtBit(
        layers: [TripLayerSnapshot],
        bitMD: Double,
        tvdSampler: TvdSampler
    ) -> (annulus: [TripLayerSnapshot], pocket: [TripLayerSnapshot]) {
        var annulus: [TripLayerSnapshot] = []
        var pocket: [TripLayerSnapshot] = []

        for layer in layers {
            if layer.bottomMD <= bitMD {
                // Entirely above or at bit → annulus
                annulus.append(TripLayerSnapshot(
                    side: "annulus", topMD: layer.topMD, bottomMD: layer.bottomMD,
                    topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                    rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: layer.deltaHydroStatic_kPa,
                    volume_m3: layer.volume_m3,
                    colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA,
                    isInAnnulus: true
                ))
            } else if layer.topMD >= bitMD {
                // Entirely below bit → pocket
                pocket.append(TripLayerSnapshot(
                    side: "pocket", topMD: layer.topMD, bottomMD: layer.bottomMD,
                    topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                    rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: layer.deltaHydroStatic_kPa,
                    volume_m3: layer.volume_m3,
                    colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA,
                    isInAnnulus: false
                ))
            } else {
                // Straddles bit → split into two layers
                let bitTVD = tvdSampler.tvd(of: bitMD)

                // Above portion → annulus
                let aboveDeltaP = layer.rho_kgpm3 * 0.00981 * (bitTVD - layer.topTVD)
                annulus.append(TripLayerSnapshot(
                    side: "annulus", topMD: layer.topMD, bottomMD: bitMD,
                    topTVD: layer.topTVD, bottomTVD: bitTVD,
                    rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: aboveDeltaP,
                    volume_m3: 0,
                    colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA,
                    isInAnnulus: true
                ))

                // Below portion → pocket
                let belowDeltaP = layer.rho_kgpm3 * 0.00981 * (layer.bottomTVD - bitTVD)
                pocket.append(TripLayerSnapshot(
                    side: "pocket", topMD: bitMD, bottomMD: layer.bottomMD,
                    topTVD: bitTVD, bottomTVD: layer.bottomTVD,
                    rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: belowDeltaP,
                    volume_m3: 0,
                    colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA,
                    isInAnnulus: false
                ))
            }
        }

        return (annulus, pocket)
    }

    private func wellboreDisplay(operationIndex: Int, stepIndex: Int) -> WellboreDisplayState? {
        guard operationIndex < operations.count else { return nil }
        let op = operations[operationIndex]
        switch op.type {
        case .tripOut:
            guard let steps = tripOutResults[op.id], steps.indices.contains(stepIndex) else { return nil }
            let step = steps[stepIndex]
            return WellboreDisplayState(
                bitMD_m: step.bitMD_m,
                layersPocket: step.layersPocket.map { TripLayerSnapshot(from: $0) },
                layersAnnulus: step.layersAnnulus.map { TripLayerSnapshot(from: $0) },
                layersString: step.layersString.map { TripLayerSnapshot(from: $0) },
                label: "\(operationIndex + 1). Trip Out @ \(String(format: "%.0f", step.bitMD_m))m"
            )
        case .tripIn:
            guard let steps = tripInResults[op.id], steps.indices.contains(stepIndex) else { return nil }
            let step = steps[stepIndex]
            let bitMD = step.bitMD_m

            // Split displaced pocket layers at current bit depth for display.
            // Above bit → annulus (pipe present, shows in annulus columns)
            // Below bit → pocket (open hole, shows full width)
            var displayAnnulus: [TripLayerSnapshot] = []
            var displayPocket: [TripLayerSnapshot] = []

            for layer in step.layersPocket {
                if layer.bottomMD <= bitMD {
                    displayAnnulus.append(layer)
                } else if layer.topMD >= bitMD {
                    displayPocket.append(layer)
                } else {
                    // Straddles bit — split for display
                    displayAnnulus.append(TripLayerSnapshot(
                        side: "annulus", topMD: layer.topMD, bottomMD: bitMD,
                        topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                        colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
                    ))
                    displayPocket.append(TripLayerSnapshot(
                        side: "pocket", topMD: bitMD, bottomMD: layer.bottomMD,
                        topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                        colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
                    ))
                }
            }

            // String column: fill mud from surface to bit (grows as pipe is lowered)
            let displayString: [TripLayerSnapshot]
            if bitMD > 0 {
                displayString = [TripLayerSnapshot(
                    side: "string", topMD: 0, bottomMD: bitMD,
                    topTVD: 0, bottomTVD: bitMD,
                    rho_kgpm3: op.fillMudDensity_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                    colorR: op.fillMudColorR, colorG: op.fillMudColorG,
                    colorB: op.fillMudColorB, colorA: op.fillMudColorA
                )]
            } else {
                displayString = []
            }

            return WellboreDisplayState(
                bitMD_m: bitMD,
                layersPocket: displayPocket,
                layersAnnulus: displayAnnulus,
                layersString: displayString,
                label: "\(operationIndex + 1). Trip In @ \(String(format: "%.0f", bitMD))m"
            )
        case .circulate:
            guard let steps = circulationResults[op.id], steps.indices.contains(stepIndex) else {
                guard let state = op.outputState else { return nil }
                return WellboreDisplayState(
                    bitMD_m: state.bitMD_m,
                    layersPocket: state.layersPocket,
                    layersAnnulus: state.layersAnnulus,
                    layersString: state.layersString,
                    label: "\(operationIndex + 1). Circulate @ \(String(format: "%.0f", state.bitMD_m))m"
                )
            }
            let step = steps[stepIndex]
            let bitMD = op.inputState?.bitMD_m ?? op.startMD_m
            // step.layersPocket contains annulus + open hole; split at bit for display
            var displayAnnulus: [TripLayerSnapshot] = []
            var displayPocket: [TripLayerSnapshot] = []
            for layer in step.layersPocket {
                if layer.bottomMD <= bitMD {
                    displayAnnulus.append(layer)
                } else if layer.topMD >= bitMD {
                    displayPocket.append(layer)
                } else {
                    displayAnnulus.append(TripLayerSnapshot(
                        side: "annulus", topMD: layer.topMD, bottomMD: bitMD,
                        topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                        colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
                    ))
                    displayPocket.append(TripLayerSnapshot(
                        side: "pocket", topMD: bitMD, bottomMD: layer.bottomMD,
                        topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                        colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
                    ))
                }
            }
            return WellboreDisplayState(
                bitMD_m: bitMD,
                layersPocket: displayPocket,
                layersAnnulus: displayAnnulus,
                layersString: step.layersString,
                label: "\(operationIndex + 1). Circulate @ \(String(format: "%.0f", bitMD))m — \(String(format: "%.1f", step.volumePumped_m3))m\u{00B3}"
            )
        case .reamOut:
            guard let steps = reamOutResults[op.id], steps.indices.contains(stepIndex) else { return nil }
            let step = steps[stepIndex]
            return WellboreDisplayState(
                bitMD_m: step.bitMD_m,
                layersPocket: step.layersPocket.map { TripLayerSnapshot(from: $0) },
                layersAnnulus: step.layersAnnulus.map { TripLayerSnapshot(from: $0) },
                layersString: step.layersString.map { TripLayerSnapshot(from: $0) },
                label: "\(operationIndex + 1). Ream Out @ \(String(format: "%.0f", step.bitMD_m))m"
            )
        case .reamIn:
            guard let steps = reamInResults[op.id], steps.indices.contains(stepIndex) else { return nil }
            let step = steps[stepIndex]
            let bitMD = step.bitMD_m

            var displayAnnulus: [TripLayerSnapshot] = []
            var displayPocket: [TripLayerSnapshot] = []

            for layer in step.layersPocket {
                if layer.bottomMD <= bitMD {
                    displayAnnulus.append(layer)
                } else if layer.topMD >= bitMD {
                    displayPocket.append(layer)
                } else {
                    displayAnnulus.append(TripLayerSnapshot(
                        side: "annulus", topMD: layer.topMD, bottomMD: bitMD,
                        topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                        colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
                    ))
                    displayPocket.append(TripLayerSnapshot(
                        side: "pocket", topMD: bitMD, bottomMD: layer.bottomMD,
                        topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                        colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
                    ))
                }
            }

            let displayString: [TripLayerSnapshot]
            if bitMD > 0 {
                displayString = [TripLayerSnapshot(
                    side: "string", topMD: 0, bottomMD: bitMD,
                    topTVD: 0, bottomTVD: bitMD,
                    rho_kgpm3: op.fillMudDensity_kgpm3, deltaHydroStatic_kPa: 0, volume_m3: 0,
                    colorR: op.fillMudColorR, colorG: op.fillMudColorG,
                    colorB: op.fillMudColorB, colorA: op.fillMudColorA
                )]
            } else {
                displayString = []
            }

            return WellboreDisplayState(
                bitMD_m: bitMD,
                layersPocket: displayPocket,
                layersAnnulus: displayAnnulus,
                layersString: displayString,
                label: "\(operationIndex + 1). Ream In @ \(String(format: "%.0f", bitMD))m"
            )
        }
    }

    // MARK: - Presets (Save/Load)

    static var presetsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JoshWellControl/SuperSimPresets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var savedPresets: [SuperSimPreset] = []

    func loadPresetList() {
        let dir = Self.presetsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            savedPresets = []
            return
        }
        savedPresets = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SuperSimPreset? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(SuperSimPreset.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func savePreset(name: String, muds: [MudProperties] = []) {
        let preset = SuperSimPreset(
            name: name,
            operationConfigs: operations.map { $0.toPresetConfig(muds: muds) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(preset) else { return }

        let sanitized = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let url = Self.presetsDirectory.appendingPathComponent("\(sanitized).json")
        try? data.write(to: url)
        loadPresetList()
    }

    func loadPreset(_ preset: SuperSimPreset, muds: [MudProperties] = []) {
        operations = preset.operationConfigs.map { config in
            var op = SuperSimOperation.fromPresetConfig(config)
            // Resolve mud IDs: try UUID match first, then fall back to name match
            op.baseMudID = resolveMudID(savedID: config.baseMudID, savedName: config.baseMudName, density: config.baseMudDensity_kgpm3, muds: muds)
            op.backfillMudID = resolveMudID(savedID: config.backfillMudID, savedName: config.backfillMudName, density: config.backfillDensity_kgpm3, muds: muds)
            op.fillMudID = resolveMudID(savedID: config.fillMudID, savedName: config.fillMudName, density: config.fillMudDensity_kgpm3, muds: muds)
            if let reamDensity = config.reamMudDensity_kgpm3 {
                op.reamMudID = resolveMudID(savedID: config.reamMudID, savedName: nil, density: reamDensity, muds: muds)
            }
            return op
        }
        tripOutResults.removeAll()
        tripOutESDAtControl.removeAll()
        tripInResults.removeAll()
        circulationResults.removeAll()
        reamOutResults.removeAll()
        reamOutESDAtControl.removeAll()
        reamInResults.removeAll()
        selectedOperationIndex = operations.isEmpty ? nil : 0
        loadResultsForSelectedOperation()
    }

    private func resolveMudID(savedID: UUID?, savedName: String?, density: Double, muds: [MudProperties]) -> UUID? {
        guard !muds.isEmpty else { return savedID }
        // Exact UUID match
        if let id = savedID, muds.contains(where: { $0.id == id }) { return id }
        // Fallback: match by name
        if let name = savedName, let match = muds.first(where: { $0.name == name }) { return match.id }
        // Fallback: match by density (within 1 kg/m3)
        if let match = muds.first(where: { abs($0.density_kgm3 - density) < 1.0 }) { return match.id }
        return nil
    }

    func deletePreset(_ preset: SuperSimPreset) {
        let sanitized = preset.name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let url = Self.presetsDirectory.appendingPathComponent("\(sanitized).json")
        try? FileManager.default.removeItem(at: url)
        loadPresetList()
    }

    // MARK: - HTML Report Export

    func buildReportData(project: ProjectState) -> SuperSimReportData {
        let wellName = project.well?.name ?? "Unknown Well"
        let projectName = project.name ?? "Unknown Project"

        var operationDataArray: [SuperSimReportData.OperationData] = []
        let esdAtControlLookup = tripOutESDAtControl
        let reamOutESDLookup = reamOutESDAtControl

        for (i, op) in operations.enumerated() {
            var tripOutSteps: [SuperSimReportData.TripOutStep]? = nil
            var tripInSteps: [SuperSimReportData.TripInStep]? = nil
            var circulationSteps: [SuperSimReportData.CirculationStep]? = nil
            var reamOutReportSteps: [SuperSimReportData.ReamOutStep]? = nil
            var reamInReportSteps: [SuperSimReportData.ReamInStep]? = nil
            var stringVol: Double? = nil
            var annulusVol: Double? = nil

            switch op.type {
            case .tripOut:
                if let steps = tripOutResults[op.id] {
                    let esdValues = esdAtControlLookup[op.id] ?? []
                    tripOutSteps = steps.enumerated().map { idx, step in
                        SuperSimReportData.TripOutStep(
                            bitMD_m: step.bitMD_m,
                            bitTVD_m: step.bitTVD_m,
                            SABP_kPa: step.SABP_kPa,
                            SABP_Dynamic_kPa: step.SABP_Dynamic_kPa,
                            ESDatTD_kgpm3: idx < esdValues.count ? esdValues[idx] : step.ESDatTD_kgpm3,
                            expectedFillIfClosed_m3: step.expectedFillIfClosed_m3,
                            expectedFillIfOpen_m3: step.expectedFillIfOpen_m3,
                            stepBackfill_m3: step.stepBackfill_m3,
                            cumulativeSurfaceTankDelta_m3: step.cumulativeSurfaceTankDelta_m3,
                            floatState: step.floatState,
                            layersAnnulus: step.layersAnnulus.map { layerRowToReportData($0) },
                            layersString: step.layersString.map { layerRowToReportData($0) },
                            layersPocket: step.layersPocket.map { layerRowToReportData($0) }
                        )
                    }
                }

            case .tripIn:
                if let steps = tripInResults[op.id] {
                    tripInSteps = steps.map { step in
                        // Split pocket layers at bit into annulus (above) and pocket (below)
                        let bitMD = step.bitMD_m
                        var annulusLayers: [SuperSimReportData.LayerData] = []
                        var pocketLayers: [SuperSimReportData.LayerData] = []
                        for layer in step.layersPocket {
                            let ld = snapshotToReportData(layer)
                            if layer.bottomMD <= bitMD {
                                annulusLayers.append(ld)
                            } else if layer.topMD >= bitMD {
                                pocketLayers.append(ld)
                            } else {
                                // Straddles bit — split
                                annulusLayers.append(SuperSimReportData.LayerData(
                                    topMD: layer.topMD, bottomMD: bitMD,
                                    topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                                    rho_kgpm3: layer.rho_kgpm3,
                                    colorR: layer.colorR, colorG: layer.colorG,
                                    colorB: layer.colorB, colorA: layer.colorA
                                ))
                                pocketLayers.append(SuperSimReportData.LayerData(
                                    topMD: bitMD, bottomMD: layer.bottomMD,
                                    topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                                    rho_kgpm3: layer.rho_kgpm3,
                                    colorR: layer.colorR, colorG: layer.colorG,
                                    colorB: layer.colorB, colorA: layer.colorA
                                ))
                            }
                        }
                        // String layer: fill mud from surface to bit
                        var stringLayers: [SuperSimReportData.LayerData] = []
                        if bitMD > 0 {
                            stringLayers.append(SuperSimReportData.LayerData(
                                topMD: 0, bottomMD: bitMD,
                                topTVD: 0, bottomTVD: bitMD,
                                rho_kgpm3: op.fillMudDensity_kgpm3,
                                colorR: op.fillMudColorR, colorG: op.fillMudColorG,
                                colorB: op.fillMudColorB, colorA: op.fillMudColorA
                            ))
                        }
                        return SuperSimReportData.TripInStep(
                            bitMD_m: step.bitMD_m,
                            bitTVD_m: step.bitTVD_m,
                            ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                            requiredChokePressure_kPa: step.requiredChokePressure_kPa,
                            annulusPressureAtBit_kPa: step.annulusPressureAtBit_kPa,
                            stringPressureAtBit_kPa: step.stringPressureAtBit_kPa,
                            differentialPressureAtBottom_kPa: step.differentialPressureAtBottom_kPa,
                            cumulativeFillVolume_m3: step.cumulativeFillVolume_m3,
                            cumulativeDisplacementReturns_m3: step.cumulativeDisplacementReturns_m3,
                            floatState: step.floatState,
                            surgePressure_kPa: step.surgePressure_kPa,
                            surgeECD_kgm3: step.surgeECD_kgm3,
                            dynamicESDAtControl_kgpm3: step.dynamicESDAtControl_kgpm3,
                            layersAnnulus: annulusLayers,
                            layersString: stringLayers,
                            layersPocket: pocketLayers
                        )
                    }
                }

            case .circulate:
                let circBitMD = op.inputState?.bitMD_m ?? op.startMD_m
                if let steps = circulationResults[op.id] {
                    circulationSteps = steps.map { step in
                        // Split full column into annulus (above bit) and pocket (at/below bit)
                        let annulusOnly = step.layersPocket.filter { $0.bottomMD <= circBitMD + 0.01 }
                        let pocketOnly = step.layersPocket.filter { $0.topMD >= circBitMD - 0.01 }
                        return SuperSimReportData.CirculationStep(
                            volumePumped_m3: step.volumePumped_m3,
                            ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                            requiredSABP_kPa: step.requiredSABP_kPa,
                            deltaSABP_kPa: step.deltaSABP_kPa,
                            description: step.description,
                            layersAnnulus: annulusOnly.map { snapshotToReportData($0) },
                            layersString: step.layersString.map { snapshotToReportData($0) },
                            layersPocket: pocketOnly.map { snapshotToReportData($0) },
                            bitMD_m: circBitMD,
                            pumpRate_m3perMin: step.pumpRate_m3perMin,
                            apl_kPa: step.apl_kPa
                        )
                    }
                }

                if let state = op.inputState {
                    let annulusSections = project.annulus ?? []
                    let drillString = project.drillString ?? []
                    let tvdSampler = TvdSampler(project: project)
                    let geom = ProjectGeometryService(
                        annulus: annulusSections,
                        string: drillString,
                        currentStringBottomMD: state.bitMD_m,
                        mdToTvd: { md in tvdSampler.tvd(of: md) }
                    )
                    stringVol = geom.volumeInString_m3(0, state.bitMD_m)
                    annulusVol = geom.volumeInAnnulus_m3(0, state.bitMD_m)
                }

            case .reamOut:
                if let steps = reamOutResults[op.id] {
                    let esdValues = reamOutESDLookup[op.id] ?? []
                    reamOutReportSteps = steps.enumerated().map { idx, step in
                        SuperSimReportData.ReamOutStep(
                            bitMD_m: step.bitMD_m,
                            bitTVD_m: step.bitTVD_m,
                            SABP_kPa: step.SABP_kPa,
                            SABP_Dynamic_kPa: step.SABP_Dynamic_kPa,
                            swab_kPa: step.swab_kPa,
                            apl_kPa: step.apl_kPa,
                            pumpRate_m3perMin: step.pumpRate_m3perMin,
                            ESDatTD_kgpm3: idx < esdValues.count ? esdValues[idx] : step.ESDatTD_kgpm3,
                            ECD_kgpm3: step.ECD_kgpm3,
                            floatState: step.floatState,
                            stepBackfill_m3: step.stepBackfill_m3,
                            cumulativeBackfill_m3: step.cumulativeBackfill_m3,
                            layersAnnulus: step.layersAnnulus.map { layerRowToReportData($0) },
                            layersString: step.layersString.map { layerRowToReportData($0) },
                            layersPocket: step.layersPocket.map { layerRowToReportData($0) }
                        )
                    }
                }

            case .reamIn:
                if let steps = reamInResults[op.id] {
                    reamInReportSteps = steps.map { step in
                        let bitMD = step.bitMD_m
                        var annulusLayers: [SuperSimReportData.LayerData] = []
                        var pocketLayers: [SuperSimReportData.LayerData] = []
                        for layer in step.layersPocket {
                            let ld = snapshotToReportData(layer)
                            if layer.bottomMD <= bitMD {
                                annulusLayers.append(ld)
                            } else if layer.topMD >= bitMD {
                                pocketLayers.append(ld)
                            } else {
                                annulusLayers.append(SuperSimReportData.LayerData(
                                    topMD: layer.topMD, bottomMD: bitMD,
                                    topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                                    rho_kgpm3: layer.rho_kgpm3,
                                    colorR: layer.colorR, colorG: layer.colorG,
                                    colorB: layer.colorB, colorA: layer.colorA
                                ))
                                pocketLayers.append(SuperSimReportData.LayerData(
                                    topMD: bitMD, bottomMD: layer.bottomMD,
                                    topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
                                    rho_kgpm3: layer.rho_kgpm3,
                                    colorR: layer.colorR, colorG: layer.colorG,
                                    colorB: layer.colorB, colorA: layer.colorA
                                ))
                            }
                        }
                        var stringLayers: [SuperSimReportData.LayerData] = []
                        if bitMD > 0 {
                            stringLayers.append(SuperSimReportData.LayerData(
                                topMD: 0, bottomMD: bitMD,
                                topTVD: 0, bottomTVD: bitMD,
                                rho_kgpm3: op.fillMudDensity_kgpm3,
                                colorR: op.fillMudColorR, colorG: op.fillMudColorG,
                                colorB: op.fillMudColorB, colorA: op.fillMudColorA
                            ))
                        }
                        return SuperSimReportData.ReamInStep(
                            bitMD_m: step.bitMD_m,
                            bitTVD_m: step.bitTVD_m,
                            ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
                            requiredChokePressure_kPa: step.requiredChokePressure_kPa,
                            dynamicChoke_kPa: step.dynamicChoke_kPa,
                            surge_kPa: step.surge_kPa,
                            apl_kPa: step.apl_kPa,
                            pumpRate_m3perMin: step.pumpRate_m3perMin,
                            ECD_kgpm3: step.ECD_kgpm3,
                            cumulativeFillVolume_m3: step.cumulativeFillVolume_m3,
                            floatState: step.floatState,
                            layersAnnulus: annulusLayers,
                            layersString: stringLayers,
                            layersPocket: pocketLayers
                        )
                    }
                }
            }

            operationDataArray.append(SuperSimReportData.OperationData(
                index: i, type: op.type, label: op.label,
                startMD_m: op.startMD_m, endMD_m: op.endMD_m,
                controlMD_m: op.controlMD_m, targetESD_kgpm3: op.targetESD_kgpm3,
                tripOutSteps: tripOutSteps, tripInSteps: tripInSteps,
                circulationSteps: circulationSteps,
                reamOutSteps: reamOutReportSteps, reamInSteps: reamInReportSteps,
                stringVolume_m3: stringVol, annulusVolume_m3: annulusVol
            ))
        }

        // Build timeline steps from chart data + wellbore layers
        var timelineSteps: [SuperSimReportData.TimelineStep] = []
        let chartData = timelineChartData
        for point in chartData {
            if let display = wellboreDisplayAtGlobalStep(point.globalIndex) {
                timelineSteps.append(SuperSimReportData.TimelineStep(
                    globalIndex: point.globalIndex,
                    operationIndex: point.operationIndex,
                    operationType: point.operationType,
                    operationLabel: point.operationLabel,
                    bitMD_m: point.bitMD_m,
                    bitTVD_m: display.bitMD_m,
                    ESD_kgpm3: point.ESDAtControl_kgpm3,
                    staticSABP_kPa: point.SABP_kPa,
                    dynamicSABP_kPa: point.dynamicSABP_kPa,
                    layersAnnulus: display.layersAnnulus.map { snapshotToReportData($0) },
                    layersString: display.layersString.map { snapshotToReportData($0) },
                    layersPocket: display.layersPocket.map { snapshotToReportData($0) }
                ))
            }
        }

        return SuperSimReportData(
            wellName: wellName, projectName: projectName,
            generatedDate: Date(), controlTVD_m: controlTVD_m,
            operations: operationDataArray, timelineSteps: timelineSteps
        )
    }

    private func snapshotToReportData(_ layer: TripLayerSnapshot) -> SuperSimReportData.LayerData {
        SuperSimReportData.LayerData(
            topMD: layer.topMD, bottomMD: layer.bottomMD,
            topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
            rho_kgpm3: layer.rho_kgpm3,
            colorR: layer.colorR, colorG: layer.colorG, colorB: layer.colorB, colorA: layer.colorA
        )
    }

    private func layerRowToReportData(_ layer: NumericalTripModel.LayerRow) -> SuperSimReportData.LayerData {
        SuperSimReportData.LayerData(
            topMD: layer.topMD, bottomMD: layer.bottomMD,
            topTVD: layer.topTVD, bottomTVD: layer.bottomTVD,
            rho_kgpm3: layer.rho_kgpm3,
            colorR: layer.color?.r, colorG: layer.color?.g, colorB: layer.color?.b, colorA: layer.color?.a
        )
    }

    func exportHTMLReport(project: ProjectState) {
        guard totalGlobalSteps > 0 else { return }
        let reportData = buildReportData(project: project)
        let html = SuperSimHTMLGenerator.shared.generateHTML(for: reportData)

        let wellName = (project.well?.name ?? "SuperSim").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let defaultName = "SuperSimulation_\(wellName)_\(dateStr).html"

        Task {
            await FileService.shared.saveTextFile(
                text: html,
                defaultName: defaultName,
                allowedFileTypes: ["html"]
            )
        }
    }

    func exportZippedHTMLReport(project: ProjectState) {
        guard totalGlobalSteps > 0 else { return }
        let reportData = buildReportData(project: project)
        let html = SuperSimHTMLGenerator.shared.generateHTML(for: reportData)

        let wellName = (project.well?.name ?? "SuperSim").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let baseName = "SuperSimulation_\(wellName)_\(dateStr)"

        Task {
            await HTMLZipExporter.shared.exportZipped(
                htmlContent: html,
                htmlFileName: "\(baseName).html",
                zipFileName: "\(baseName).zip"
            )
        }
    }
}

// MARK: - Codable Helper for PumpOperation

/// Codable wrapper for CirculationService.PumpOperation (which uses UUID, not Codable by default)
private struct CodablePumpOperation: Codable {
    let mudID: UUID
    let mudName: String
    let mudDensity_kgpm3: Double
    let mudColorR: Double
    let mudColorG: Double
    let mudColorB: Double
    let volume_m3: Double

    func toPumpOperation() -> CirculationService.PumpOperation {
        CirculationService.PumpOperation(
            mudID: mudID,
            mudName: mudName,
            mudDensity_kgpm3: mudDensity_kgpm3,
            mudColorR: mudColorR,
            mudColorG: mudColorG,
            mudColorB: mudColorB,
            volume_m3: volume_m3
        )
    }
}
