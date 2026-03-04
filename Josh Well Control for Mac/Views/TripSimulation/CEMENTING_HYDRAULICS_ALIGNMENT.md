# Cementing Simulator Hydraulics Alignment

## Problem Statement

The cementing simulator currently implements its own hydraulics modeling that differs from the approach used in:
- **CirculationService** (used by Super Simulation's "Circulate" operation)
- **ReamEngine** (used by Super Simulation's "Ream Out" and "Ream In" operations)

This creates inconsistency in how annular pressure losses (APL) are calculated across the application.

## Current Architecture

### CirculationService (Circulation & Reaming)
**Location:** `CirculationService.swift`

**Method:** `calculateAPLFromParcels()`

**Approach:**
1. Uses **volume parcels** with fluid properties (density, PV, YP, dial readings)
2. Maps parcels to depth ranges using geometry
3. Delegates to **APLCalculationService.shared** for segment-by-segment calculation
4. Supports multiple rheology models with priority:
   - Priority 1: Explicit K/n (Power Law parameters)
   - Priority 2: Derive K/n from Fann dial readings (dial600, dial300)
   - Priority 3: Bingham Plastic model (PV, YP)

**Used By:**
- Super Simulation → Circulate operation
- Super Simulation → Ream Out operation (via `calculateAPLFromLayerRows`)
- Super Simulation → Ream In operation

### CementJobSimulationViewModel (Cementing)
**Location:** `CementJobSimulationViewModel.swift`

**Method:** `annularPressureLossAboveLossZone()`

**Approach:**
1. Uses **volume parcels** similar to CirculationService
2. **Re-implements** volume-weighted rheology averaging
3. **Re-implements** segment-by-segment APL calculation
4. Delegates to **APLCalculationService.shared** BUT with custom logic
5. Same priority for rheology models BUT implemented separately

**Issues:**
- Code duplication with CirculationService
- Potential for divergence in calculations
- Not using the proven `calculateAPLFromParcels()` method
- Harder to maintain consistency

## Key Differences

### 1. Parcel Handling
| Aspect | CirculationService | CementJob |
|--------|-------------------|-----------|
| Parcel structure | `VolumeParcel` in CirculationService | `VolumeParcel` in CementJobSimulationViewModel |
| Mapping to depth | `lengthForAnnulusParcelVolumeFromBottom()` | Custom logic in `annularPressureLossAboveLossZone()` |
| Segment iteration | Walks parcels, maps to geometry | Walks geometry, averages parcels |

### 2. Rheology Model Selection
Both use the same priority, but implemented differently:

**CirculationService:**
```swift
// Priority 1: Explicit K/n
if hasExplicitKN {
    aplService.aplFromKN(...)
}
// Priority 2: Derive from dials
else if hasDials {
    let (n, K) = deriveKN(dial600, dial300)
    aplService.aplFromKN(...)
}
// Priority 3: Bingham
else {
    aplService.aplBingham(...)
}
```

**CementJob:**
```swift
if knVolume > totalVolume * 0.5 {
    // Priority 1: Explicit K/n
    aplService.aplFromKN(...)
} else if dialVolume > totalVolume * 0.5 {
    // Priority 2: Derive from dials
    let (n, K) = deriveKN(dial600, dial300)
    aplService.aplFromKN(...)
} else {
    // Priority 3: Bingham
    aplService.aplBingham(...)
}
```

### 3. Loss Zone Consideration
**CementJob only:** Has special logic to calculate APL only **above** the loss zone depth.

This is actually a **valid difference** because cementing has unique requirements:
- Tracks losses to formation at specific depths
- Only cares about friction above the loss zone
- Needs to determine when losses will occur during pumping

## Proposed Solution

### Option 1: Extend CirculationService (Recommended)

Enhance `CirculationService.calculateAPLFromParcels()` to support partial depth ranges:

```swift
static func calculateAPLFromParcels(
    annulusParcels: [VolumeParcel],
    bitMD: Double,
    geom: ProjectGeometryService,
    annulusSections: [AnnulusSection],
    drillStringSections: [DrillStringSection],
    pumpRate_m3perMin: Double,
    limitToDepthRange: (top: Double, bottom: Double)? = nil  // NEW parameter
) -> Double {
    // ... existing code ...
    
    // NEW: Skip segments outside the depth range
    if let range = limitToDepthRange {
        let sectionTop = max(section.topDepth_m, range.top)
        let sectionBottom = min(section.bottomDepth_m, range.bottom)
        guard sectionBottom > sectionTop else { continue }
        // ... calculate APL for this segment ...
    } else {
        // Existing behavior: all segments
    }
}
```

**Then update CementJob to use it:**

```swift
private func annularPressureLossAboveLossZone(
    lossZoneDepth_m: Double,
    aboveZoneParcels: [VolumeParcel],
    pumpRate_m3_per_min: Double,
    geom: ProjectGeometryService
) -> Double {
    guard let project = boundProject else { return 0 }
    
    // Convert to CirculationService.VolumeParcel format (if different)
    let circulationParcels = aboveZoneParcels.map { p in
        CirculationService.VolumeParcel(
            volume_m3: p.volume_m3,
            colorR: p.colorR,
            colorG: p.colorG,
            colorB: p.colorB,
            colorA: p.colorA,
            density_kgm3: p.density_kgm3,
            plasticViscosity_cP: p.plasticViscosity_cP,
            yieldPoint_Pa: p.yieldPoint_Pa,
            dial600: p.dial600,
            dial300: p.dial300,
            n_annulus: p.n_annulus,
            K_annulus: p.K_annulus
        )
    }
    
    // Use shared service with depth limit
    return CirculationService.calculateAPLFromParcels(
        annulusParcels: circulationParcels,
        bitMD: lossZoneDepth_m,  // Treat loss zone as "bit" depth
        geom: geom,
        annulusSections: project.annulus ?? [],
        drillStringSections: project.drillString ?? [],
        pumpRate_m3perMin: pumpRate_m3_per_min,
        limitToDepthRange: (top: 0, bottom: lossZoneDepth_m)  // Only above loss zone
    )
}
```

### Option 2: Create Shared APL Utility Class

Extract common logic into a new `AnnularPressureLossCalculator` class:

```swift
class AnnularPressureLossCalculator {
    static func calculateFromParcels(
        parcels: [VolumeParcel],
        depthRange: (top: Double, bottom: Double),
        geometry: ProjectGeometryService,
        annulusSections: [AnnulusSection],
        drillStringSections: [DrillStringSection],
        pumpRate: Double
    ) -> Double {
        // Unified implementation used by all simulators
    }
}
```

Then both CirculationService and CementJob use this shared calculator.

### Option 3: Keep Separate (Not Recommended)

Document the differences and ensure both implementations stay in sync manually.

**Pros:** No refactoring needed
**Cons:** 
- Maintenance burden
- Risk of divergence
- Harder to validate consistency

## Implementation Steps (Option 1 - Recommended)

### Step 1: Check VolumeParcel Compatibility
Verify that `CementJobSimulationViewModel.VolumeParcel` and `CirculationService.VolumeParcel` have the same structure.

```swift
// If they're the same, we can use one definition
// If different, we need conversion logic
```

### Step 2: Add Optional Depth Range to CirculationService

```swift
// In CirculationService.swift
static func calculateAPLFromParcels(
    annulusParcels: [VolumeParcel],
    bitMD: Double,
    geom: ProjectGeometryService,
    annulusSections: [AnnulusSection],
    drillStringSections: [DrillStringSection],
    pumpRate_m3perMin: Double,
    depthRange: ClosedRange<Double>? = nil  // NEW: optional depth filter
) -> Double {
    // ... existing code ...
    
    for section in sortedSections {
        var effectiveTop = section.topDepth_m
        var effectiveBottom = section.bottomDepth_m
        
        // NEW: Apply depth range filter
        if let range = depthRange {
            effectiveTop = max(effectiveTop, range.lowerBound)
            effectiveBottom = min(effectiveBottom, range.upperBound)
        }
        
        guard effectiveBottom > effectiveTop else { continue }
        
        // ... rest of existing logic ...
    }
}
```

### Step 3: Update CementJob to Use CirculationService

```swift
// In CementJobSimulationViewModel.swift
private func annularPressureLossAboveLossZone(
    lossZoneDepth_m: Double,
    aboveZoneParcels: [VolumeParcel],
    pumpRate_m3_per_min: Double,
    geom: ProjectGeometryService
) -> Double {
    guard let project = boundProject else { return 0 }
    
    // Use the shared CirculationService method
    return CirculationService.calculateAPLFromParcels(
        annulusParcels: aboveZoneParcels,
        bitMD: lossZoneDepth_m,
        geom: geom,
        annulusSections: project.annulus ?? [],
        drillStringSections: project.drillString ?? [],
        pumpRate_m3perMin: pumpRate_m3_per_min,
        depthRange: 0...lossZoneDepth_m  // Only surface to loss zone
    )
}
```

### Step 4: Remove Duplicate Code

Delete the custom APL calculation logic from CementJobSimulationViewModel:
- `binghamFrictionGradient()` method (redundant)
- `annularVelocity()` method (already in APLCalculationService)
- Volume-weighted rheology averaging (now in CirculationService)

### Step 5: Testing

**Test Cases:**
1. **Same setup in both sims:**
   - Run cement job with no loss zones
   - Run circulation with same fluids and pump rate
   - APL should match

2. **Cement with loss zone:**
   - Verify APL only calculated above loss zone
   - Compare to manual calculation

3. **Multiple fluid types:**
   - Spacer → Cement → Mud
   - Verify rheology transitions handled correctly

4. **Edge cases:**
   - Zero pump rate → APL should be zero
   - Very high pump rate → Check for turbulence handling
   - Empty parcels → Should skip correctly

## Benefits

1. **Consistency:** All simulators use the same hydraulics engine
2. **Maintainability:** Single source of truth for APL calculations
3. **Validation:** Easier to verify against field data
4. **Features:** Improvements to CirculationService benefit cementing automatically
5. **Testing:** Shared test cases ensure all sims work correctly

## Risks & Mitigation

### Risk 1: Breaking Existing Cementing Behavior
**Mitigation:** 
- Run comprehensive comparison tests before/after
- Keep old method as `annularPressureLossAboveLossZone_Legacy()` temporarily
- Compare results side-by-side during development

### Risk 2: Performance Impact
**Mitigation:**
- CirculationService is already optimized for performance
- Depth range filtering may actually improve performance (fewer segments)
- Profile before/after to measure impact

### Risk 3: Parcel Structure Incompatibility
**Mitigation:**
- If structures differ, create lightweight conversion function
- Consider unifying VolumeParcel definition across all services

## Next Steps

1. **Review this document** - Confirm approach makes sense
2. **Check VolumeParcel compatibility** - See if conversion is needed
3. **Implement Step 1** - Add depth range parameter to CirculationService
4. **Create test harness** - Compare old vs new APL calculations
5. **Update CementJob** - Switch to shared service
6. **Remove duplicate code** - Clean up CementJobSimulationViewModel
7. **Test thoroughly** - Run all cement job scenarios
8. **Document changes** - Update comments and docs

## Questions to Resolve

1. Are there any cement-specific APL considerations not in CirculationService?
2. Should we also align the main circulation step calculation?
3. Do we want to refactor SuperSimulation to use the unified service?
4. Should VolumeParcel be moved to a shared file?

## Recommendation

**Proceed with Option 1** - Extend CirculationService with optional depth range filtering. This provides:
- ✅ Minimal code changes
- ✅ Maintains backward compatibility
- ✅ Achieves consistency goal
- ✅ Easy to test and validate
- ✅ Future-proof architecture

The key insight is that cementing's loss zone consideration is just a **depth filtering** requirement, not a fundamentally different calculation approach.
