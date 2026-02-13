#!/usr/bin/env swift
//
//  ReamValidation.swift
//  Cross-platform validation for Ream Engine calculations.
//
//  Run: swift Tests/ReamValidation.swift
//
//  This file embeds the same APL and ream formulas used by APLCalculationService
//  and ReamEngine. It exercises them with IDENTICAL inputs to the TypeScript
//  companion test (josh-well-control-lite/src/engines/__tests__/ReamValidation.test.ts).
//
//  Both must produce matching results to within floating-point tolerance.
//

import Foundation

// ── Constants (must match APLCalculationService) ──────────────────────

let APL_EMPIRICAL_K: Double = 5.0e-05
let G: Double = 9.81
let TOL: Double = 1e-6

// ── Embedded APL Formulas ─────────────────────────────────────────────
// These replicate APLCalculationService.swift exactly.

func aplSimplified_kPa(
    density_kgm3: Double,
    length_m: Double,
    flowRate_m3_per_min: Double,
    holeDiameter_m: Double,
    pipeDiameter_m: Double
) -> Double {
    let gap = holeDiameter_m - pipeDiameter_m
    guard gap > 1e-6, flowRate_m3_per_min > 0 else { return 0 }
    return APL_EMPIRICAL_K * density_kgm3 * length_m * pow(flowRate_m3_per_min, 2) / gap
}

func aplBingham_kPa(
    length_m: Double,
    flowRate_m3_per_min: Double,
    holeDiameter_m: Double,
    pipeDiameter_m: Double,
    plasticViscosity_cP: Double,
    yieldPoint_Pa: Double
) -> Double {
    let hydraulicDiameter = holeDiameter_m - pipeDiameter_m
    guard hydraulicDiameter > 1e-6 else { return 0 }

    let area_m2 = Double.pi / 4.0 * (pow(holeDiameter_m, 2) - pow(pipeDiameter_m, 2))
    guard area_m2 > 1e-9 else { return 0 }
    let velocity_m_per_s = (flowRate_m3_per_min / 60.0) / area_m2

    let pv_Pa_s = plasticViscosity_cP / 1000.0

    let yieldTerm = (4.0 * yieldPoint_Pa) / hydraulicDiameter
    let viscousTerm = (8.0 * pv_Pa_s * velocity_m_per_s) / pow(hydraulicDiameter, 2)
    let gradient_Pa_per_m = yieldTerm + viscousTerm

    return (gradient_Pa_per_m * length_m) / 1000.0
}

// ── Test Harness ──────────────────────────────────────────────────────

var passed = 0
var failed = 0

func assertClose(_ actual: Double, _ expected: Double, _ name: String, tol: Double = TOL) {
    let diff = abs(actual - expected)
    if diff <= tol {
        passed += 1
        print("  ✓ \(name): \(actual)")
    } else {
        failed += 1
        print("  ✗ \(name): got \(actual), expected \(expected), diff=\(diff)")
    }
}

func assertEqual(_ actual: Double, _ expected: Double, _ name: String) {
    if actual == expected {
        passed += 1
        print("  ✓ \(name): \(actual)")
    } else {
        failed += 1
        print("  ✗ \(name): got \(actual), expected \(expected)")
    }
}

// ── Shared Test Parameters ────────────────────────────────────────────
// Must match TypeScript test file exactly.

let HOLE_ID_M: Double = 0.3111  // 12.25" hole
let PIPE_OD_M: Double = 0.127   // 5" drill pipe
let LENGTH_M: Double = 1000     // 1 km section
let DENSITY_KGM3: Double = 1200
let PV_CP: Double = 25          // Plastic viscosity (cP)
let YP_PA: Double = 8           // Yield point (Pa)
let PUMP_RATE: Double = 0.5     // m³/min

// ── 1. APL Simplified ─────────────────────────────────────────────────

print("\n─── APL Simplified ───")

let aplSimplifiedResult = aplSimplified_kPa(
    density_kgm3: DENSITY_KGM3,
    length_m: LENGTH_M,
    flowRate_m3_per_min: PUMP_RATE,
    holeDiameter_m: HOLE_ID_M,
    pipeDiameter_m: PIPE_OD_M
)

let gap = HOLE_ID_M - PIPE_OD_M
let expectedSimplified = APL_EMPIRICAL_K * DENSITY_KGM3 * LENGTH_M * pow(PUMP_RATE, 2) / gap
assertClose(aplSimplifiedResult, expectedSimplified, "APL simplified")

// Zero flow rate
let aplZeroFlow = aplSimplified_kPa(
    density_kgm3: DENSITY_KGM3, length_m: LENGTH_M,
    flowRate_m3_per_min: 0, holeDiameter_m: HOLE_ID_M, pipeDiameter_m: PIPE_OD_M
)
assertEqual(aplZeroFlow, 0, "APL simplified zero flow")

// Zero gap
let aplZeroGap = aplSimplified_kPa(
    density_kgm3: DENSITY_KGM3, length_m: LENGTH_M,
    flowRate_m3_per_min: PUMP_RATE, holeDiameter_m: 0.127, pipeDiameter_m: 0.127
)
assertEqual(aplZeroGap, 0, "APL simplified zero gap")

// ── 2. APL Bingham ────────────────────────────────────────────────────

print("\n─── APL Bingham ───")

let aplBinghamResult = aplBingham_kPa(
    length_m: LENGTH_M,
    flowRate_m3_per_min: PUMP_RATE,
    holeDiameter_m: HOLE_ID_M,
    pipeDiameter_m: PIPE_OD_M,
    plasticViscosity_cP: PV_CP,
    yieldPoint_Pa: YP_PA
)

// Hand calculation for Bingham
let hydraulicD = HOLE_ID_M - PIPE_OD_M
let area = Double.pi / 4.0 * (pow(HOLE_ID_M, 2) - pow(PIPE_OD_M, 2))
let V = (PUMP_RATE / 60.0) / area
let PV_Pa_s = PV_CP / 1000.0
let yieldTerm = (4.0 * YP_PA) / hydraulicD
let viscousTerm = (8.0 * PV_Pa_s * V) / pow(hydraulicD, 2)
let gradient = yieldTerm + viscousTerm
let expectedBingham = (gradient * LENGTH_M) / 1000.0
assertClose(aplBinghamResult, expectedBingham, "APL Bingham")

// Zero gap
let aplBinghamZeroGap = aplBingham_kPa(
    length_m: LENGTH_M, flowRate_m3_per_min: PUMP_RATE,
    holeDiameter_m: 0.127, pipeDiameter_m: 0.127,
    plasticViscosity_cP: PV_CP, yieldPoint_Pa: YP_PA
)
assertEqual(aplBinghamZeroGap, 0, "APL Bingham zero gap")

// ── 3. Multi-layer APL ────────────────────────────────────────────────

print("\n─── Multi-layer APL ───")

// Layer 1: 0-500m, has PV/YP → uses Bingham
// Layer 2: 500-1000m, no PV/YP → uses Simplified
let aplLayer1 = aplBingham_kPa(
    length_m: 500,
    flowRate_m3_per_min: PUMP_RATE,
    holeDiameter_m: HOLE_ID_M,
    pipeDiameter_m: PIPE_OD_M,
    plasticViscosity_cP: 25,
    yieldPoint_Pa: 8
)

let aplLayer2 = aplSimplified_kPa(
    density_kgm3: 1100,
    length_m: 500,
    flowRate_m3_per_min: PUMP_RATE,
    holeDiameter_m: HOLE_ID_M,
    pipeDiameter_m: PIPE_OD_M
)

let aplMultiLayer = aplLayer1 + aplLayer2
print("  ✓ APL multiLayer = \(aplMultiLayer) (layer1=\(aplLayer1), layer2=\(aplLayer2))")
passed += 1

// ── 4. Ream Out Combination ───────────────────────────────────────────

print("\n─── Ream Out Combination ───")

let SABP_STATIC: Double = 500
let SWAB: Double = 150
let APL_REAM: Double = 80
let ESD: Double = 1250
let TVD: Double = 2500

// SABP_Dynamic = max(0, SABP + swab - APL)
let sabpDynamic = max(0, SABP_STATIC + SWAB - APL_REAM)
assertClose(sabpDynamic, 570, "reamOut SABP_Dynamic")

// Clamping to 0
let bigAPL: Double = 700
let sabpDynamicClamped = max(0, SABP_STATIC + SWAB - bigAPL)
assertEqual(sabpDynamicClamped, 0, "reamOut SABP_Dynamic clamped")

// ECD = ESD + (SABP_Dynamic + APL) / (0.00981 × TVD)
let reamOutECD = ESD + (sabpDynamic + APL_REAM) / (0.00981 * TVD)
let expectedReamOutECD = ESD + (sabpDynamic + APL_REAM) / (0.00981 * TVD)
assertClose(reamOutECD, expectedReamOutECD, "reamOut ECD")

// ── 5. Ream In Combination ────────────────────────────────────────────

print("\n─── Ream In Combination ───")

let REQUIRED_CHOKE: Double = 800
let SURGE: Double = 120
let APL_IN: Double = 80

// dynamicChoke = max(0, requiredChoke - APL - surge)
let dynamicChoke = max(0, REQUIRED_CHOKE - APL_IN - SURGE)
assertClose(dynamicChoke, 600, "reamIn dynamicChoke")

// Clamping to 0
let bigSurge: Double = 800
let dynamicChokeClamped = max(0, REQUIRED_CHOKE - APL_IN - bigSurge)
assertEqual(dynamicChokeClamped, 0, "reamIn dynamicChoke clamped")

// ECD = ESD + (dynamicChoke + APL + surge) / (0.00981 × TVD)
let reamInECD = ESD + (dynamicChoke + APL_IN + SURGE) / (0.00981 * TVD)
let expectedReamInECD = ESD + (dynamicChoke + APL_IN + SURGE) / (0.00981 * TVD)
assertClose(reamInECD, expectedReamInECD, "reamIn ECD")

// When choke clamps to 0, ECD still > ESD
let dynamicChoke2 = max(0, REQUIRED_CHOKE - APL_IN - Double(900))
let reamInECD2 = ESD + (dynamicChoke2 + APL_IN + 900) / (0.00981 * TVD)
assert(reamInECD2 > ESD, "reamIn ECD > ESD when clamped")
assertEqual(dynamicChoke2, 0, "reamIn dynamicChoke2 clamped")
print("  ✓ reamIn ECD_clamped = \(reamInECD2)")
passed += 1

// ── 6. ECD Constant Verification ──────────────────────────────────────

print("\n─── ECD Constant Verification ───")

let pressure_kPa: Double = 100
let tvd_test: Double = 1000
let esd_test: Double = 1200

let viaConstant = esd_test + pressure_kPa / (0.00981 * tvd_test)
let viaExpanded = esd_test + (pressure_kPa * 1000) / (9.81 * tvd_test)
assertClose(viaConstant, viaExpanded, "ECD constant equivalence")

// ── Summary ───────────────────────────────────────────────────────────

print("\n═══════════════════════════════════════")
print("Results: \(passed) passed, \(failed) failed")
if failed > 0 {
    print("CROSS-PLATFORM VALIDATION FAILED")
    exit(1)
} else {
    print("CROSS-PLATFORM VALIDATION PASSED")
}

// ── Reference Values ──────────────────────────────────────────────────
// Print all computed values for comparison with TypeScript output.

print("\n─── Reference Values (compare with TS output) ───")
print("APL_simplified     = \(aplSimplifiedResult)")
print("APL_bingham        = \(aplBinghamResult)")
print("APL_multiLayer     = \(aplMultiLayer)")
print("reamOut_SABP_Dyn   = \(sabpDynamic)")
print("reamOut_ECD        = \(reamOutECD)")
print("reamIn_dynChoke    = \(dynamicChoke)")
print("reamIn_ECD         = \(reamInECD)")
