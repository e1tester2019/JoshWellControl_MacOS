//
//  TripSimulationViewModel.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-03.
//

import Foundation


extension TripSimulationView {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 5983.28
    var endMD_m: Double = 0
    var shoeMD_m: Double = 2910
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1260
    var backfillDensity_kgpm3: Double = 1200
    var targetESDAtTD_kgpm3: Double = 1320
    var crackFloat_kPa: Double = 2100
    var initialSABP_kPa: Double = 0
    var holdSABPOpen: Bool = false

    // New property for backfill mud selection
    var backfillMudID: UUID? = nil

    // View options
    var colorByComposition: Bool = false
    var showDetails: Bool = false

    // Results / selection
    var steps: [TripStep] = []
    var selectedIndex: Int? = nil
    var stepSlider: Double = 0

    func bootstrap(from project: ProjectState) {
      if let maxMD = (project.finalLayers ?? []).map({ $0.bottomMD_m }).max() {
        startBitMD_m = maxMD
        endMD_m = 0
      }
      let baseActive = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3
      baseMudDensity_kgpm3 = baseActive
      backfillDensity_kgpm3 = baseActive
      backfillMudID = project.activeMud?.id
      targetESDAtTD_kgpm3 = baseActive

      #if DEBUG
      let layerCount = (project.finalLayers ?? []).count
      print("[TripSim] Bootstrap: found \(layerCount) final layers, startBitMD=\(startBitMD_m)")
      #endif
    }

    func runSimulation(project: ProjectState) {
      #if DEBUG
      let annLayers = project.finalAnnulusLayersSorted
      let strLayers = project.finalStringLayersSorted
      print("[TripSim] Running with \(annLayers.count) annulus layers, \(strLayers.count) string layers")
      for l in annLayers { print("  [Ann] \(l.name): \(l.topMD_m)-\(l.bottomMD_m) m, ρ=\(l.density_kgm3) kg/m³") }
      for l in strLayers { print("  [Str] \(l.name): \(l.topMD_m)-\(l.bottomMD_m) m, ρ=\(l.density_kgm3) kg/m³") }
      #endif

      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in project.tvd(of: md) }
      )
      let input = NumericalTripModel.TripInput(
        tvdOfMd: { md in project.tvd(of: md) },
        shoeTVD_m: project.tvd(of: shoeMD_m),
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        crackFloat_kPa: crackFloat_kPa,
        step_m: step_m,
        baseMudDensity_kgpm3: (project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3),
        backfillDensity_kgpm3: (
            (backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id })?.density_kgm3 })
            ?? project.activeMud?.density_kgm3
            ?? backfillDensity_kgpm3
        ),
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen
      )
      let model = NumericalTripModel()
      self.steps = model.run(input, geom: geom, project: project)
      self.selectedIndex = steps.isEmpty ? nil : 0
      self.stepSlider = 0
    }

    func esdAtControlText(project: ProjectState) -> String {
      let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let candidates = [annMax, dsMax].filter { $0 > 0 }
      let limit = candidates.min()
      let controlMDRaw = max(0.0, shoeMD_m)
      let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
      let controlTVD = project.tvd(of: controlMD)

      guard let idx = selectedIndex, steps.indices.contains(idx) else { return "" }
      let s = steps[idx]
      var pressure_kPa: Double = s.SABP_kPa

      if controlTVD <= s.bitTVD_m + 1e-9 {
        var remaining = controlTVD
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remaining -= seg
            if remaining <= 1e-9 { break }
          }
        }
      } else {
        var remainingA = s.bitTVD_m
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remainingA, max(0.0, min(r.bottomTVD, s.bitTVD_m) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingA -= seg
            if remainingA <= 1e-9 { break }
          }
        }
        var remainingP = controlTVD - s.bitTVD_m
        for r in s.layersPocket where r.bottomTVD > r.topTVD {
          let top = max(r.topTVD, s.bitTVD_m)
          let bot = min(r.bottomTVD, controlTVD)
          let seg = max(0.0, bot - top)
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingP -= seg
            if remainingP <= 1e-9 { break }
          }
        }
      }

      let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
      return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }
  }
}

#if (os(iOS))
extension TripSimulationViewIOS {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 5983.28
    var endMD_m: Double = 0
    var shoeMD_m: Double = 2910
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1260
    var backfillDensity_kgpm3: Double = 1200
    var targetESDAtTD_kgpm3: Double = 1320
    var crackFloat_kPa: Double = 2100
    var initialSABP_kPa: Double = 0
    var holdSABPOpen: Bool = false

    // New property for backfill mud selection
    var backfillMudID: UUID? = nil

    // View options
    var colorByComposition: Bool = false
    var showDetails: Bool = false

    // Results / selection
    var steps: [TripStep] = []
    var selectedIndex: Int? = nil
    var stepSlider: Double = 0

    func bootstrap(from project: ProjectState) {
      if let maxMD = (project.finalLayers ?? []).map({ $0.bottomMD_m }).max() {
        startBitMD_m = maxMD
        endMD_m = 0
      }
      let baseActive = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3
      baseMudDensity_kgpm3 = baseActive
      backfillDensity_kgpm3 = baseActive
      backfillMudID = project.activeMud?.id
      targetESDAtTD_kgpm3 = baseActive
    }

    func runSimulation(project: ProjectState) {
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in project.tvd(of: md) }
      )
      let input = NumericalTripModel.TripInput(
        tvdOfMd: { md in project.tvd(of: md) },
        shoeTVD_m: project.tvd(of: shoeMD_m),
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        crackFloat_kPa: crackFloat_kPa,
        step_m: step_m,
        baseMudDensity_kgpm3: (project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3),
        backfillDensity_kgpm3: (
            (backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id })?.density_kgm3 })
            ?? project.activeMud?.density_kgm3
            ?? backfillDensity_kgpm3
        ),
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen
      )
      let model = NumericalTripModel()
      self.steps = model.run(input, geom: geom, project: project)
      self.selectedIndex = steps.isEmpty ? nil : 0
      self.stepSlider = 0
    }

    func esdAtControlText(project: ProjectState) -> String {
      let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let candidates = [annMax, dsMax].filter { $0 > 0 }
      let limit = candidates.min()
      let controlMDRaw = max(0.0, shoeMD_m)
      let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
      let controlTVD = project.tvd(of: controlMD)

      guard let idx = selectedIndex, steps.indices.contains(idx) else { return "" }
      let s = steps[idx]
      var pressure_kPa: Double = s.SABP_kPa

      if controlTVD <= s.bitTVD_m + 1e-9 {
        var remaining = controlTVD
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remaining -= seg
            if remaining <= 1e-9 { break }
          }
        }
      } else {
        var remainingA = s.bitTVD_m
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remainingA, max(0.0, min(r.bottomTVD, s.bitTVD_m) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingA -= seg
            if remainingA <= 1e-9 { break }
          }
        }
        var remainingP = controlTVD - s.bitTVD_m
        for r in s.layersPocket where r.bottomTVD > r.topTVD {
          let top = max(r.topTVD, s.bitTVD_m)
          let bot = min(r.bottomTVD, controlTVD)
          let seg = max(0.0, bot - top)
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingP -= seg
            if remainingP <= 1e-9 { break }
          }
        }
      }

      let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
      return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }
  }
}
#endif
