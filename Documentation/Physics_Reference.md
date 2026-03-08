# Physics Reference

## 1. Standpipe Pressure (SPP)

### Overview

SPP = String Friction + Bit Nozzle ΔP + Annulus Friction + Surface Back Pressure

Friction is computed per fluid layer using each layer's own rheology, integrated through the actual wellbore geometry.

### 1.1 Power-Law Rheology (K and n)

From Fann 35 viscometer dial readings at 600 and 300 RPM:

    n = 3.322 × log₁₀(θ₆₀₀ / θ₃₀₀)

    K = (θ₆₀₀ × 0.478802) / 1022ⁿ    [Pa·sⁿ]

Constants:
- Dial-to-Pa conversion: 0.478802 Pa per dial unit
- Fann 600 RPM shear rate: 1022 s⁻¹
- Fann 300 RPM shear rate: 511 s⁻¹

If only PV/YP are available, dial readings are derived:

    θ₃₀₀ = PV(cP) + YP(Pa) / 0.478802
    θ₆₀₀ = 2 × PV(cP) + YP(Pa) / 0.478802

### 1.2 Laminar Friction Gradient

**Pipe flow:**

    γ_w = (3n+1)/(4n) × 8V/D
    τ_w = K × γ_wⁿ
    dP/dL = 4τ_w / D    [Pa/m]

**Annular flow (slot approximation):**

    D_h = D_hole − D_pipe
    V = Q / A,  where A = π/4 × (D_hole² − D_pipe²)
    γ_w = (3n+1)/(4n) × 8V/D_h
    τ_w = K × γ_wⁿ
    dP/dL = 4τ_w / D_h    [Pa/m]

### 1.3 Turbulent Flow Detection

Metzner-Reed generalized Reynolds number:

    K' = K × ((3n+1)/(4n))ⁿ
    Re_MR = Dⁿ × V⁽²⁻ⁿ⁾ × ρ / (K' × 8⁽ⁿ⁻¹⁾)

Turbulent if Re_MR > 2100.

### 1.4 Dodge-Metzner Turbulent Friction Factor

Iterative solution for Fanning friction factor f:

    1/√f = (4/n⁰·⁷⁵) × log₁₀(Re_MR × f⁽¹⁻ⁿ/²⁾) − 0.395/n¹·²

Solved iteratively (up to 50 iterations, convergence tolerance 1e-8).

Turbulent friction gradient:

    dP/dL = 2f × ρ × V² / D    [Pa/m]

### 1.5 Bit Nozzle Pressure Drop

    V_nozzle = Q / TFA
    ΔP_bit = ρ × V_nozzle² / (2 × Cd²)

Where Cd = 0.95 (discharge coefficient), TFA = total flow area of bit nozzles.

### 1.6 Geometry-Split Integration

When a fluid layer spans a geometry change (e.g., casing to open hole, or a drill string OD change), the friction integral is split at each boundary. Each sub-interval is computed with the correct hole ID, pipe OD, and hydraulic diameter.

This prevents midpoint-sampling errors — without it, pressure changes incorrectly when fluid segments split during displacement.

### 1.7 Per-Layer Rheology

Each fluid layer in the wellbore has its own rheology. Friction is computed independently for each layer using that layer's K and n values (or PV/YP converted to K, n). The total SPP is the sum across all layers in the string and annulus.

---

## 2. Torque & Drag

### Overview

Johancsik soft-string model (1984). Computation marches from bit to surface, accumulating axial force (tension/compression) and torque per survey interval.

### 2.1 Normal Force (Side Force)

At each survey interval:

    N = √(F_axial² + F_lateral²)

Where:

    F_axial = F × ΔInc + W_buoyed × sin(Inc_avg)
    F_lateral = F × sin(Inc_avg) × ΔAzi

- F = cumulative axial force at bottom of interval
- ΔInc = change in inclination across interval (radians)
- ΔAzi = change in azimuth across interval (radians)
- Inc_avg = average inclination
- W_buoyed = buoyed weight of segment

### 2.2 Axial Force Accumulation

**Trip out (pickup):**

    F_top = F_bottom + W_buoyed × cos(Inc_avg) + μ × N

**Trip in (slackoff):**

    F_top = F_bottom + W_buoyed × cos(Inc_avg) − μ × N

Where μ = friction coefficient (separate values for cased and open hole sections).

### 2.3 Torque

Torque is the rotational resistance on the string caused by friction between the pipe and the wellbore wall. It is computed per survey interval and summed from bit to surface to give surface torque.

**Rotating off-bottom (pure rotation, no axial motion):**

All friction goes to torque — there is no axial velocity to split it with:

    ΔTorque = μ × N × (contactOD / 2)

Where contactOD is the pipe body OD (or tool joint OD, whichever contacts the wellbore).

Surface torque is the cumulative sum:

    Torque_surface = Σ(ΔTorque)    from bit to surface

**Combined rotation + axial motion (rotating hoist / rotating slackoff):**

When the string is both rotating and moving axially (e.g., back-reaming, rotating while tripping), friction must be split between the axial and tangential directions. The velocity-ratio model determines the split based on the relative speed in each direction:

    V_tangential = π × contactOD × RPM/60 × rotationEfficiency
    V_axial = tripSpeed
    α = atan2(V_tangential, V_axial)

    F_axial_friction = μ × N × cos(α)
    F_torque_friction = μ × N × sin(α)
    ΔTorque = F_torque_friction × (contactOD / 2)

At high RPM relative to trip speed, α → 90° and most friction goes to torque. At high trip speed relative to RPM, α → 0° and most friction goes to axial drag.

Rotation efficiency (0–1) modulates how much the rotation reduces axial drag. A value of 1.0 means rotation is fully effective; lower values simulate partial pipe whirl or stick-slip.

### 2.4 Buoyancy — Pressure-Area Method

Standard buoyancy uses a single factor: BF = 1 − ρ_fluid / ρ_steel.

The pressure-area method accounts for different fluids inside and outside the string:

    ΔF_PA = (ρ_internal × A_id − ρ_external × A_od) × g × ΔTVD

This matters when:
- The fluid inside the string differs from the annulus fluid
- The string is tapered (cross-sections change along the string)
- Fluids are being displaced and the distribution is non-uniform

### 2.5 APL Piston Force

Annular pressure losses and surface back pressure act on the string cross-section, creating an upward (negative) force on the hook:

**Float open:**

    F_piston = (SABP + APL) × A_steel − ΔP_nozzle × A_blocked

**Float closed:**

    F_piston = SABP × A_OD

This reduces the measured hook load during circulation.

### 2.6 Surface Back Pressure Effect

SABP applies a piston force at the bit:

- Float open: acts on the steel ring area (A_OD − A_ID)
- Float closed: acts on the full outer diameter area (A_OD)

### 2.7 Sheave / Line Friction

Applied as a multiplier to the computed hook load:

    HL_pickup = HL_computed × (1 + sheave%)
    HL_slackoff = HL_computed × (1 − sheave%)

Accounts for friction in the block and tackle system.

### 2.8 Buckling (Paslay-Dawson)

**Sinusoidal buckling load:**

    I = π/64 × (OD⁴ − ID⁴)
    F_c = 2 × √(E × I × w_buoyed × sin(Inc) / r_clearance)

**Helical buckling load:**

    F_h = √2 × F_c

Where E = 207 GPa (steel), r_clearance = (D_hole − D_contact) / 2.

### 2.9 String Stretch

Elastic elongation under tension:

    ΔL = F × L / (E × A_steel)

Summed over all segments from bit to surface.

### 2.10 Circulation Friction Reduction

When circulating, annular flow creates a viscous film that reduces the contact friction coefficient:

    dragRatio = F_annular_viscous / N
    μ_effective = μ_static × max(0.7, 1 / (1 + 15 × dragRatio))

The annular viscous drag force is computed from the power-law shear stress at the pipe wall.

---

## 3. How They Connect to the Numerical Model

Both SPP and T&D draw their inputs from the live numerical model state:

- **Fluid stack**: Per-layer density and rheology from the actual fluid distribution at each simulation step
- **Geometry**: Tapered drill string sections (OD, ID, weight) and annulus sections (hole ID, casing ID)
- **Trajectory**: Directional survey stations (inclination, azimuth, TVD at each MD)
- **Operating conditions**: Pump rate, trip speed, RPM, surface back pressure

As fluids are displaced during circulation, tripping, or cementing, the SPP and hook load predictions update automatically — they are not static single-point calculations.

---

## 4. Trip Out (Numerical Trip Model)

### Overview

Step-by-step simulation of pipe extraction. Three compartments — string, annulus, and pocket (open hole below the bit) — each track individual fluid layers with density, rheology, and color. As pipe exits the well, fluid is carved from the bottom of the stacks, blended into the pocket, and backfill is injected from surface.

### 4.1 Float Valve Physics

The float valve separates string and annulus contents at the bit.

**Float opens when:**

    P_string(bit) > P_annulus(bit) + P_crack + P_tolerance

**Float closed when:**

    P_string(bit) ≤ P_annulus(bit) + P_crack + P_tolerance

Where P_tolerance = 5.0 kPa (hysteresis margin).

When the float is open, slug drains from string to annulus and the vacated space fills with air (ρ = 1.2 kg/m³).

### 4.2 U-Tube Equalization (Initial Slug Pulse)

Before the trip starts, if the string contains a heavy slug that opens the float, the model equilibrates pressures by draining slug into the annulus.

**Calculated mode:** Iteratively drain 10 L parcels from the bottom of the string into the annulus until:

    P_string(bit) ≤ P_annulus(bit) + P_crack

Maximum 10,000 iterations.

**Observed mode:** Drain exactly the user-provided observed initial pit gain volume. Calibrates the simulation to the field measurement.

### 4.3 Volume Tracking

**Pit gain** = volume that overflows at surface when slug drains from string. This equals the total drained volume.

**Surface tank delta** = cumulative pit gain − cumulative backfill pumped.

### 4.4 Backfill Logic

As pipe exits the well, the void left must be filled from surface.

**Float closed (DP Wet):**

    Backfill = pipe capacity + steel displacement = π/4 × OD² × dL

**Float open (DP Dry):**

    Backfill = steel displacement only = π/4 × (OD² − ID²) × dL

When float is open, string fluid drains to fill the annulus — only the steel volume needs replacement from surface.

Two backfill modes:
- **Fixed volume**: Pump a set volume of kill mud, then switch to base mud
- **Dynamic**: All backfill uses the selected backfill density

### 4.5 Multi-Compartment Pocket Blending

As pipe trips out, mud carved from the string and annulus enters the pocket below the bit.

**Float open:**

    V_pocket = V_string_carved + V_annulus_carved + V_steel_displacement
    ρ_mix = (m_string + m_annulus + m_steel) / V_pocket

**Float closed:**

    V_pocket = V_annulus_carved + V_pipe_OD
    ρ_mix = (m_annulus + m_OD) / V_pocket

Pocket layers are maintained with individual densities. Adjacent layers with the same density (within 1e-6 kg/m³) are merged. Rheology (PV, YP) and color are blended by volume weighting.

**Source inventory tracking** records how much of each original mud density contributed to the pocket (pre-blend), enabling traceability.

### 4.6 Hydrostatic Pressure (Multi-Layer)

Pressure at any depth is summed layer by layer:

    P(kPa) = P_surface + Σ(ρᵢ × g × ΔTVDᵢ / 1000)

For the annulus, P_surface = SABP. For the string, P_surface = 0.

**ESD at control depth:**

    P_control = P_annulus(surface → control) + P_pocket(bit → control) + SABP
    ESD_control = P_control / (0.00981 × TVD_control)

**ESD at TD:**

    ESD_TD = (P_pocket + P_annulus + SABP) / (0.00981 × TVD_TD)

### 4.7 SABP Control (Closed-Loop Pressure Management)

Maintains target ESD at the control depth (casing shoe) by dynamically computing SABP:

    Target_P = target_ESD × 0.00981 × TVD_control
    SABP = max(0, Target_P − P_hydrostatic)
    SABP_dynamic = SABP + swab_pressure

As the trip progresses and the fluid distribution changes, SABP adjusts automatically.

### 4.8 Adaptive Stepping

The internal simulation uses adaptive step sizes:
- **Coarse step (5 m):** When float is solidly closed and pressure margin > 50 kPa
- **Fine step (1 m):** Near float transitions or when float is open

Results are recorded at the user-specified interval (e.g., every 100 m), averaging internal sub-steps.

### 4.9 Swab Pressure During Trip Out

Per-step swab is computed from the current annulus fluid stack using SwabCalculator (see Section 7). Swab is averaged over all internal sub-steps within each recording interval to account for composition changes from backfill.

---

## 5. Trip In

### Overview

Step-by-step simulation of pipe insertion. Tracks layer expansion as pipe enters tighter annulus, displacement returns to surface, ESD at control depth, required choke pressure, and surge pressure.

### 5.1 Layer Expansion

When drill pipe enters the wellbore, fluid layers above the bit are pushed from the open hole into the narrower annulus around the pipe. Layer height increases:

    expansion_factor = D_wellbore² / (D_wellbore² − D_pipe²)

Example: 8.5" hole with 7" casing → expansion factor ≈ 4.37. A 100 m layer in open hole becomes 437 m in the annulus.

Layers already in the annulus (flagged `isInAnnulus`) are not re-expanded. Layers that span the bit are split: the portion above the bit expands, the portion below stays at original height.

### 5.2 Volume Tracking

**Fill volume** (pipe capacity filled from surface):

    stepFill = π/4 × D_ID² × interval_length
    cumulativeFill += stepFill

**Displacement returns** (steel volume returned to surface):

    stepDisplacement = π/4 × D_OD² × interval_length
    cumulativeDisplacement += stepDisplacement

For floated casing below the float sub, stepFill = 0 (pipe contains air/foam).

### 5.3 Choke Pressure to Maintain Target ESD

    If ESD_control < target_ESD:
        SABP = (target_ESD − ESD_control) × 0.00981 × TVD_control

    If ESD_control ≥ target_ESD:
        SABP = 0    (well is balanced or overbalanced)

### 5.4 Surge Pressure

Computed per step using SwabCalculator with the actual layer rheology (see Section 7). Surge ECD is added to static ESD:

    surge_ECD = surge_kPa / (0.00981 × TVD_control)
    dynamic_ESD = ESD_control + surge_ECD

### 5.5 Float Valve (Floated Casing)

For floated casing with a float sub at a known MD:

    P_annulus = ρ_mud × 0.00981 × TVD_float
    P_inside = ρ_active × 0.00981 × TVD_mud_level

    ΔP_float = P_annulus − P_inside

Float opens when ΔP_float ≥ P_crack. Float state is reported as a percentage of open/closed.

### 5.6 Initial State Import

Trip in can start from:
- **Manual**: Single uniform layer from surface to TD
- **Imported**: Full fluid state from a previous trip out, pump schedule, or Super Simulation

Imported layers carry density, rheology, and color. Pocket and annulus layers are combined. Any gap between the deepest imported layer and TD is filled with active mud.

### 5.7 Continuation

The simulation can be interrupted (e.g., to circulate), then resumed from the current depth with the current fluid state, cumulative volumes, and layer distributions preserved.

---

## 6. Circulation

### Overview

Dual-stack parcel transport model. Fluid is pumped into the top of the string, flows to the bit, enters the bottom of the annulus, and overflows at surface. Each parcel carries density, rheology, and color independently.

### 6.1 Volume Parcel Model

Fluid is tracked as discrete parcels with:
- Volume (m³)
- Density (kg/m³)
- Rheology: PV (cP), YP (Pa), dial600, dial300
- Color (RGBA)
- Mud identity (UUID link)

String parcels are ordered shallow → deep (surface to bit). Annulus parcels are ordered deep → shallow (bit to surface).

### 6.2 Push and Overflow

**String:** New fluid is inserted at index 0 (surface). If total volume exceeds string capacity, parcels are removed from the end (bit) and expelled.

**Annulus:** Expelled parcels from the string enter at index 0 (bit). If total volume exceeds annulus capacity, parcels are removed from the end (surface) and overflow to the pit.

Adjacent parcels with the same density, color, and rheology are coalesced to prevent array growth.

### 6.3 Annular Pressure Loss (APL)

APL is computed per parcel, walking from bit to surface through each annulus geometry section:

**Power-law model** (preferred when dial readings available):

    n = ln(θ₆₀₀ / θ₃₀₀) / ln(2)
    K = (θ₆₀₀ × 0.478802) / 1022ⁿ
    → laminar or turbulent friction gradient (see Section 1)

**Bingham plastic model** (fallback when PV/YP available):

    dP/dL = 6 × YP / D_h + 48 × PV × V / D_h²

**Simplified empirical** (final fallback):

    APL = 5.0e-05 × ρ × L × Q² / (D_h − D_p)

Each parcel is mapped to a depth range using binary search (volume → MD conversion), then APL is computed through each geometry section that overlaps that depth range.

### 6.4 Adaptive Pump Rate for Target ESD

When APL would exceed the available SABP headroom, the pump rate is reduced:

    static_SABP = max(0, (target_ESD − ESD) × 0.00981 × TVD_control)
    APL_max = APL at maximum pump rate

If APL_max > static_SABP, binary search (12 iterations) finds the pump rate where APL ≤ static_SABP:

    lo = min_pump_rate
    hi = max_pump_rate
    for 12 iterations:
        mid = (lo + hi) / 2
        if APL(mid) ≤ static_SABP: lo = mid
        else: hi = mid
    pump_rate = lo

Effective SABP = static_SABP − APL at the selected rate.

### 6.5 ESD Calculation

    P_total = Σ(ρᵢ × 0.00981 × ΔTVDᵢ)
    ESD = P_total / (0.00981 × TVD_control)

Computed from the displaced pocket layers (annulus + open hole below bit) using TVD interpolation from survey stations.

### 6.6 Step Size

Adaptive: stepVolume = max(0.5 m³, totalQueueVolume / 200). Limits the simulation to ~200 steps for performance while maintaining resolution.

---

## 7. Swab and Surge

### Overview

Power-law frictional pressure loss in the annulus from pipe displacement. Used by both Trip Out (swab) and Trip In (surge). The physics are identical — only the direction differs.

### 7.1 Power-Law Rheology

From Fann 35 dial readings:

    n = ln(θ₆₀₀ / θ₃₀₀) / ln(2)
    τ₆₀₀ = 0.478802 × θ₆₀₀    [Pa]
    K = τ₆₀₀ / 1022ⁿ    [Pa·sⁿ]

### 7.2 Burkhardt Clinging Factor

Accounts for mud clinging to the pipe surface:

    Kc = 0.45 + 0.45 × (D_pipe / D_hole)²

### 7.3 Annular Velocity

    disp_area = π/4 × D_OD²            (float closed)
    disp_area = π/4 × (D_OD² − D_ID²)  (float open)

    A_annulus = π/4 × (D_hole² − D_OD²)

    V_annular = V_pipe × (1 + Kc) × (disp_area / A_annulus) × eccentricity_factor

Default eccentricity factor: 1.2.

### 7.4 Wall Shear Rate (Mooney-Rabinowitsch)

    γ_w = ((3n + 1) / (4n)) × (8 × V_annular / D_h)

### 7.5 Pressure Gradient

    τ_w = K × γ_wⁿ
    dP/dL = 4 × τ_w / D_h    [Pa/m]

### 7.6 Turbulent Flow Detection

Metzner-Reed generalized Reynolds number:

    Re_g = (ρ × V^(2−n) × D_h^n) / (K × 8^(n−1))

Turbulent if Re_g > 2100.

### 7.7 Per-Layer Calculation

The wellbore is walked from bit to surface in segments (default 10 m for trip integration, 0.1 m for detailed profiles). At each segment:

1. Get geometry: pipe OD, hole ID, hydraulic diameter
2. Compute clinging factor and annular velocity
3. Use the layer's own rheology (K, n from dial readings; or reverse-engineer from PV/YP; or fall back to global values)
4. Compute wall shear stress and pressure gradient
5. Accumulate pressure drop

Total swab/surge = sum of all segment pressure drops.

### 7.8 Recommended SABP

    recommended_SABP = total_swab × safety_factor

Default safety factor: 1.15.

---

## 8. Cementing

### Overview

Multi-stage cement displacement simulation. Tracks fluid parcels through the string and annulus as spacer, lead cement, tail cement, and displacement fluid are pumped. Monitors ESD at control depth, annular pressure losses, annular velocity, loss zone fracture margins, and tank volumes.

### 8.1 Volume Calculations

**Lead cement volume** (from lead top MD to lead bottom MD):

For each annulus section overlapping the lead interval:
- Cased sections: annular volume with no excess
- Open hole sections: annular volume × (1 + excess%)

    V_lead = Σ(section_annular_volume × overlap_fraction × excess_multiplier)

**Tail cement volume** (from tail top MD to tail bottom MD): Same logic with separate excess%.

**Volume to bump** (displacement volume):

    V_bump = Σ(pipe_capacity × section_length)    from surface to float collar

**Mud return:**

    V_return = total_annulus_volume + string_volume    (volume displaced to surface)

### 8.2 Cement Properties

Each stage carries its own rheology:

| Stage | Typical PV (cP) | Typical YP (Pa) |
|-------|-----------------|-----------------|
| Pre-flush | 15 | 5 |
| Spacer | 20 | 8 |
| Lead cement | 60 | 10 |
| Tail cement | 80 | 15 |
| Displacement | 20 | 8 |

Lead and tail cement also have:
- Yield factor (m³/tonne) — converts volume to dry cement weight
- Mix water ratio (m³/tonne) — water required per tonne of cement
- Tonnage = volume / yield_factor
- Mix water = tonnage × water_ratio × 1000 [litres]

### 8.3 Dual-Stack Fluid Transport

Uses the same parcel transport model as circulation (Section 6):
- Pump fluid into top of string → overflow at bit → enter bottom of annulus → overflow at surface
- Each parcel carries density, rheology, color, and cement flag
- Adjacent parcels with matching properties are coalesced

### 8.4 Loss Zone Physics

A loss zone is defined by:
- Depth (MD and TVD)
- Fracture pressure (kPa) or fracture gradient (kPa/m)
- Fracture EMW = fracture_gradient × 1000 / g

**Pressure above loss zone:**

    P_above = Σ(ρᵢ × g × ΔTVDᵢ / 1000)    for all layers above loss zone depth

**Volume to fracture:**

    margin = fracture_pressure − P_above − APL_above
    Δρ = new_parcel_density − displaced_density

    If Δρ ≤ 0: unlimited (lighter fluid cannot fracture)
    If Δρ > 0: V_transition = margin × 1000 / (Δρ × g × length_per_volume × TVD_ratio)

APL is computed only through the depth range 0 → loss zone depth, using the same unified APL calculation from Section 6.3.

### 8.5 Annular Velocity

    V_annular = Q / A    where A = π/4 × (D_hole² − D_pipe²)

Maximum annular velocity limits can be set per operation — exceeding the limit triggers a warning.

### 8.6 ECD / ESD During Cementing

    ECD = ρ_static + (APL × 1000) / (g × TVD)
    ESD = ρ_static + (SABP × 1000) / (g × TVD)

As cement displaces mud in the annulus, ECD changes with the fluid stack composition.

### 8.7 Tank Volume Tracking

    expected_tank = initial_tank + cumulative_pumped    (assumes 1:1 returns)
    actual_tank = user-entered or auto-tracked
    return_ratio = actual_returned / total_pumped

Discrepancies between expected and actual indicate losses or gains.

### 8.8 Plug and Float Operations

- **Plug drop**: Top plug released (on-the-fly during pumping, or after a line cleanout)
- **Bump plug**: Pressure applied until plug seats at float collar. Recorded as bump pressure (MPa) and over-FCP pressure
- **Float check**: Verify float valve seats closed — bleed back and monitor for flow
- **Pressure test**: Casing integrity test at specified pressure and duration

---

## 9. How the Models Connect

All simulations draw from the same live numerical state:

- **Fluid stack**: Per-layer density and rheology from the actual fluid distribution at each simulation step
- **Geometry**: Tapered drill string sections (OD, ID, weight) and annulus sections (hole ID, casing ID)
- **Trajectory**: Directional survey stations (inclination, azimuth, TVD at each MD)
- **Operating conditions**: Pump rate, trip speed, RPM, surface back pressure

Super Simulation chains any sequence of operations (Trip Out, Trip In, Circulate, Ream Out, Ream In) and carries the complete fluid state from one operation to the next. SPP, hook load, and torque predictions update automatically as the fluid distribution changes.

---

## 10. Constants

| Parameter | Value | Use |
|-----------|-------|-----|
| g | 9.81 m/s² | All pressure and buoyancy calculations |
| ρ_air | 1.2 kg/m³ | String fill when float drains |
| ρ_steel | 7850 kg/m³ | Buoyancy factor, string weight |
| E_steel | 207 GPa | Buckling, string stretch |
| Fann dial-to-Pa | 0.478802 Pa/dial | Rheology conversion |
| Fann 600 RPM shear rate | 1022 s⁻¹ | Power-law K |
| Fann 300 RPM shear rate | 511 s⁻¹ | Power-law n |
| Nozzle discharge coefficient | 0.95 | Bit ΔP |
| Laminar Reynolds threshold | 2100 | Turbulent detection |
| Burkhardt clinging base | 0.45 | Swab/surge velocity |
| Default eccentricity factor | 1.2 | Swab/surge |
| Swab safety factor | 1.15 | Recommended SABP |
| Float tolerance | 5.0 kPa | Float open/close hysteresis |
| U-tube pulse step | 0.01 m³ | Slug equalization increment |
| APL empirical K | 5.0e-05 | Simplified APL fallback |
