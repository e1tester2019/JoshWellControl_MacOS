# Numerical Modeling of Wellbore Hydraulics During Tripping Operations: A Comprehensive Multi-Phase Simulation Framework

**Technical Documentation — SPE Paper Style**

---

## Abstract

This paper presents a comprehensive numerical simulation framework for modeling wellbore hydraulics during both trip-out (pulling out of hole, POOH) and trip-in (running in hole, RIH) operations. The framework addresses critical challenges in Managed Pressure Drilling (MPD) where precise bottomhole pressure control is essential for wellbore stability. The trip-out model employs a multi-layer fluid column representation with dynamic float valve state transitions and real-time U-tube equilibration physics. The trip-in model simulates pipe displacement effects including layer expansion, fluid overflow, and differential pressure monitoring for floated casing operations. Both models incorporate power-law and Bingham plastic rheological correlations for surge and swab pressure calculations with Burkhardt clinging factor corrections. The framework provides comprehensive volume tracking for trip-tank reconciliation, equivalent static density (ESD) predictions, and surface applied back pressure (SABP) recommendations. Field calibration is supported through observed pit gain matching. This integrated approach enables engineers to plan complete tripping operations with confidence in predicted bottomhole pressures and fill volumes.

---

## 1. Introduction

### 1.1 Problem Statement

Tripping operations—the process of removing (trip-out) or inserting (trip-in) drillstring or casing into a wellbore—represent critical phases in drilling operations where wellbore pressure management is paramount. During these operations, the displacement of pipe creates fluid movement that can induce significant pressure transients at the bottom of the wellbore.

The complexity of tripping simulations is compounded by several factors:

1. **Heterogeneous fluid columns**: Kill weight mud, drilling mud, spacers, heavy slugs, and air may coexist in the wellbore with distinct densities and rheological properties
2. **Float valve dynamics**: Float valves may open or close depending on the pressure differential between the drillstring and annulus, fundamentally changing the hydraulic system behavior
3. **Swab and surge effects**: Pipe movement induces viscous pressure losses that reduce (swab during POOH) or increase (surge during RIH) effective bottomhole pressure
4. **Variable geometry**: Casing programs with different diameters and drill string assemblies (drill pipe, HWDP, drill collars) create non-uniform annular geometries
5. **U-tube equilibration**: When the float valve opens, fluid redistribution between string and annulus occurs until pressure balance is achieved
6. **Pocket formation**: During trip-out, fluid left below the bit accumulates in a "pocket" that continues to contribute hydrostatic pressure at total depth

### 1.2 Scope and Objectives

This numerical framework provides:

**Trip-Out (POOH) Simulation:**
- Multi-layer fluid tracking in drillstring and annulus compartments
- Float valve state transitions based on pressure equilibrium
- U-tube equilibration with iterative pressure balancing
- Pocket region physics for fluid below the bit
- Swab pressure calculations using power-law rheology
- Adaptive stepping for computational efficiency
- Volume tracking (backfill, pit gain, slug contribution)
- Composition/color tracking for fluid identification

**Trip-In (RIH) Simulation:**
- Layer displacement and expansion as pipe enters
- Surge pressure calculations using Bingham plastic model
- Floated casing differential pressure monitoring
- Required choke pressure recommendations
- Integration with prior trip-out simulation results

---

## 2. Physical System Description

### 2.1 Wellbore Compartments

The wellbore system is represented as multiple fluid regions:

**2.1.1 String Stack (Inside Drillstring)**

The fluid column inside the drillstring, extending from surface to the current bit depth. During trip-out with an open float, this column may contain:
- Heavy slug (typically high-density mud pumped before tripping)
- Base drilling mud
- Air (fills from surface as slug drains)

During trip-in, the string is typically filled with drilling mud as it runs into the hole.

**2.1.2 Annulus Stack (Annular Space)**

The fluid column in the annular space between the drillstring/casing and the wellbore wall or previous casing string. This region may contain:
- Backfill mud (pumped from surface during trip-out)
- Original drilling mud
- Spacers or other fluids
- Kill weight mud (in well control situations)

**2.1.3 Pocket Region (Below Bit)**

During trip-out, as the bit rises, the annular fluid and (if float is open) string fluid that was occupying the vacated space accumulates below the current bit position. This "pocket" is conceptually important because:
- It remains in hydrostatic communication with total depth (TD)
- It contributes to the total hydrostatic pressure at TD
- Its composition affects the equivalent static density calculation at TD

The pocket acts as a "graveyard" for fluid that has passed below the bit and can no longer be circulated or directly affected by surface operations.

### 2.2 Float Valve Behavior

The float valve (typically located in the bit or above the BHA) controls fluid communication between the drillstring interior and the annulus. Its behavior is central to the simulation:

**Closed Float State:**
- String fluid rises with the pipe (no relative movement to pipe)
- Annulus must be backfilled with full pipe OD volume ("DP Wet")
- No U-tube equilibration occurs
- String hydrostatic pressure is typically lower than annulus

**Open Float State:**
- String fluid drains through the float into the annulus
- Air fills the string from surface
- Annulus backfill requirement reduced to steel displacement only ("DP Dry")
- U-tube equilibration drives fluid redistribution
- String hydrostatic pressure was higher than annulus (causing the float to open)

**State Transition Criterion:**

$$\text{Float State} = \begin{cases}
\text{CLOSED} & \text{if } P_{string,bit} \leq P_{annulus,bit} + P_{crack} + P_{tolerance} \\
\text{OPEN} & \text{if } P_{string,bit} > P_{annulus,bit} + P_{crack} + P_{tolerance}
\end{cases}$$

Where:
- $P_{crack}$ = float valve cracking pressure (typically 35-70 kPa)
- $P_{tolerance}$ = numerical tolerance to prevent chatter (typically 5 kPa)

### 2.3 Volume Definitions

Understanding the volume terminology is critical for trip-tank reconciliation:

| Term | Definition | Formula |
|------|------------|---------|
| **DP Wet** | Pipe OD volume (capacity + displacement) | $V_{wet} = \frac{\pi D_{OD}^2}{4} \times L$ |
| **DP Dry** | Steel displacement only (metal ring area) | $V_{dry} = \frac{\pi (D_{OD}^2 - D_{ID}^2)}{4} \times L$ |
| **Backfill** | Volume pumped from surface tanks | Measured at mud tanks |
| **Pit Gain** | Volume overflow at surface | Measured at mud tanks |
| **Slug Contribution** | String fluid draining to annulus | $V_{slug} = V_{drained}$ |
| **Surface Tank Delta** | Net tank change | $\Delta V_{tank} = V_{pitgain} - V_{backfill}$ |

**Expected Fill Comparison:**

During trip-out, comparing actual backfill to expected fill indicates float status:
- Actual ≈ DP Wet → Float likely CLOSED
- Actual ≈ DP Dry → Float likely OPEN
- Actual between → Float transitioning or intermittent

---

## 3. Trip-Out Model (POOH): Governing Equations

### 3.1 Hydrostatic Pressure Calculation

The hydrostatic pressure at any measured depth is computed by integrating the fluid density along the true vertical depth path:

$$P(MD) = P_{surface} + \int_0^{TVD(MD)} \rho(z) \cdot g \, dz$$

For a discrete multi-layer representation with $N$ layers in a given stack:

$$P_{stack} = P_{surface} + \sum_{i=1}^{N} \rho_i \cdot g \cdot \Delta TVD_i$$

Where:
- $P_{surface}$ = surface applied back pressure (SABP) for annulus, 0 for string
- $\rho_i$ = density of layer $i$ (kg/m³)
- $g$ = gravitational acceleration (9.81 m/s²)
- $\Delta TVD_i = TVD(MD_{bottom,i}) - TVD(MD_{top,i})$ = true vertical thickness of layer $i$

**Pressure at Bit:**

$$P_{annulus,bit} = SABP + \sum_{annulus\ layers} \rho_i \cdot g \cdot \Delta TVD_i$$

$$P_{string,bit} = \sum_{string\ layers} \rho_i \cdot g \cdot \Delta TVD_i$$

Note: The string is open to atmosphere at surface, so there is no surface pressure term.

### 3.2 Equivalent Static Density (ESD)

The ESD provides a convenient way to express bottomhole pressure as an equivalent mud weight:

$$ESD = \frac{P_{hydrostatic}}{g \cdot TVD_{ref}}$$

Two ESD values are computed at each step:

**ESD at Total Depth (TD):**
$$ESD_{TD} = \frac{P_{pocket} + P_{annulus} + SABP}{g \cdot TVD_{TD}}$$

This represents the effective mud weight "seen" at the original TD, accounting for the pocket contribution.

**ESD at Current Bit:**
$$ESD_{bit} = \frac{P_{annulus} + SABP}{g \cdot TVD_{bit}}$$

This represents the effective mud weight at the current bit position, relevant for wellbore stability above the bit.

### 3.3 Target Pressure and SABP Calculation

For MPD operations, a target ESD at TD is specified. The required SABP to achieve this target is:

$$P_{target,TD} = ESD_{target} \cdot g \cdot TVD_{TD}$$

$$SABP_{required} = P_{target,TD} - P_{pocket} - P_{annulus,hydrostatic}$$

The SABP is constrained to non-negative values:
$$SABP = \max(0, SABP_{required})$$

**Hold SABP Open Mode:**

In some scenarios, the operator may choose to run with zero back pressure (e.g., when using a closed system with atmospheric reference). In this mode:
$$SABP = 0$$

And the simulation tracks how the ESD varies without intervention.

### 3.4 Volume Conservation

Strict volume conservation is enforced at each time step:

**Annulus Mass Balance (Float Closed):**
$$V_{backfill} = V_{pipeOD} - V_{overflow}$$

**Annulus Mass Balance (Float Open):**
$$V_{backfill} = V_{steel} - V_{overflow} + V_{slug,in}$$

Where $V_{slug,in}$ is the volume draining from the string that contributes to annulus fill.

**String Mass Balance (Float Open):**
$$V_{air,in} = V_{slug,out}$$

As slug drains from the string bottom, an equivalent volume of air enters from the surface.

---

## 4. U-Tube Equilibration Physics

### 4.1 Initial Slug Pulse

Before the trip begins, if the drillstring contains a heavy slug, the float may be open due to the higher hydrostatic pressure in the string. The model performs an initial equilibration:

**Calculated Mode:**
The system iteratively drains fluid from the string bottom to the annulus until pressure equilibrium is achieved:

```
while P_string > P_annulus + P_crack:
    // Drain small parcel (typically 10 L)
    remove fluid from string bottom
    add equivalent volume of air at string top
    push annulus fluid up by injection length
    inject drained fluid at annulus bottom
    recalculate pressures
```

**Observed Mode (Field Calibration):**
When the operator has measured the actual initial pit gain, this value can be used directly:

```
while drained_volume < observed_pit_gain:
    drain parcel from string to annulus
    track cumulative drained volume
```

This calibration mode allows the simulation to match field observations, improving accuracy for subsequent trip predictions.

### 4.2 Step-Level Equilibration

At each simulation step, if the float opens due to pressure conditions, equilibration occurs before proceeding:

1. Check float criterion: $P_{string} > P_{annulus} + P_{crack}$
2. If open, iterate until equilibrium or maximum iterations reached
3. Track slug contribution volume for this step
4. Update float state percentage (e.g., "OPEN 72%" indicates 72% of internal steps had open float)

### 4.3 Parcel Transfer Mechanics

Each equilibration iteration transfers a small fluid parcel (pulse step):

**From String:**
- Remove volume from bottom-most layer
- If layer fully depleted, remove it from stack
- Calculate equivalent length removed

**To String (Air):**
- Calculate air length equivalent to drained volume
- Insert or extend air layer at surface
- Push all other string layers down by air length

**To Annulus:**
- Push all annulus layers up by injection length
- Inject drained fluid at bit depth
- Excess fluid at surface becomes pit gain

---

## 5. Trip Step Execution Logic

### 5.1 Adaptive Stepping

The simulation uses adaptive step sizes to balance accuracy and computational efficiency:

| Condition | Step Size | Rationale |
|-----------|-----------|-----------|
| Float solidly closed ($\Delta P_{margin} > 50$ kPa) | 5 m (coarse) | Stable regime, pressure changes predictable |
| Float near transition or open | 1 m (fine) | High sensitivity to small changes |
| Near target depth | Variable | Ensure exact endpoint capture |

Results are recorded at user-specified intervals (e.g., every 10 m) regardless of internal step size.

### 5.2 Float Closed Step

When the float is closed, the following occurs during a step of length $\Delta L$:

1. **Carve annulus bottom**: Remove $\Delta L$ of fluid from annulus bottom
2. **Add to pocket**: The carved fluid plus pipe OD volume goes to pocket
3. **Translate string**: Move all string layers up by $\Delta L$ (fluid rises with pipe)
4. **Backfill annulus**: Add $V_{pipeOD}$ of backfill mud from surface
5. **Update bit depth**: $MD_{bit} = MD_{bit} - \Delta L$

**Pocket Density (Float Closed):**
$$\rho_{pocket} = \frac{m_{annulus} + \rho_{annulus} \cdot V_{pipeOD}}{V_{annulus} + V_{pipeOD}}$$

### 5.3 Float Open Step

When the float is open:

1. **Carve both stacks**: Remove $\Delta L$ from both string and annulus bottoms
2. **Add to pocket**: Combined fluid from both stacks plus steel displacement
3. **Adjust both stacks**: Re-anchor to new bit depth
4. **Backfill annulus**: Add $V_{steel}$ of backfill mud from surface
5. **Air fills string**: Handled by prior equilibration

**Pocket Density (Float Open):**
$$\rho_{pocket} = \frac{m_{annulus} + m_{string} + \rho_{avg} \cdot V_{steel}}{V_{annulus} + V_{string} + V_{steel}}$$

### 5.4 Backfill Strategy

The model supports multiple backfill strategies:

**Fixed Volume Mode:**
```
if backfill_remaining > 0:
    use backfill_density (e.g., kill mud)
    backfill_remaining -= volume_used
else if switch_to_base_after_fixed:
    use base_mud_density
```

**Continuous Mode:**
```
always use backfill_density (user's selected mud)
```

This allows simulation of scenarios where a fixed volume of heavy mud is pumped before switching to lighter base mud.

---

## 6. Swab Pressure Modeling (Trip-Out)

### 6.1 Power-Law Rheology

Drilling fluids during trip-out are modeled using the power-law (Ostwald-de Waele) constitutive equation:

$$\tau = K \cdot \dot{\gamma}^n$$

Where:
- $\tau$ = shear stress (Pa)
- $K$ = consistency index (Pa·s^n)
- $\dot{\gamma}$ = shear rate (1/s)
- $n$ = flow behavior index (dimensionless)

**Derivation from Fann Viscometer:**

The rheological parameters are derived from Fann 35 viscometer readings:

$$n = \frac{\ln(\theta_{600}/\theta_{300})}{\ln 2}$$

$$K = \frac{0.4788 \cdot \theta_{600}}{1022^n}$$

Where:
- $\theta_{600}, \theta_{300}$ = dial readings at 600 and 300 RPM
- $0.4788$ = conversion factor (dial units to Pa)
- $1022$ = shear rate at 600 RPM (1/s)

### 6.2 Burkhardt Clinging Factor

The Burkhardt (1961) clinging constant accounts for mud that adheres to the pipe and moves with it:

$$K_c = 0.45 + 0.45 \cdot \left(\frac{D_p}{D_h}\right)^2$$

This factor typically increases effective annular velocity by 50-80%.

### 6.3 Annular Velocity

The annular velocity during pipe withdrawal:

$$V_a = V_{pipe} \cdot (1 + K_c) \cdot \frac{A_{disp}}{A_{ann}} \cdot f_{ecc}$$

Where:
- $V_{pipe}$ = pipe velocity (m/s)
- $A_{disp}$ = displacement area (depends on float state)
- $A_{ann}$ = annular flow area
- $f_{ecc}$ = eccentricity correction factor

**Displacement Area:**
- Float CLOSED: $A_{disp} = \frac{\pi D_{OD}^2}{4}$
- Float OPEN: $A_{disp} = \frac{\pi (D_{OD}^2 - D_{ID}^2)}{4}$

### 6.4 Wall Shear and Pressure Gradient

Using Mooney-Rabinowitsch correction:

$$\dot{\gamma}_w = \frac{3n + 1}{4n} \cdot \frac{8 V_a}{D_h}$$

$$\tau_w = K \cdot \dot{\gamma}_w^n$$

Laminar pressure gradient:
$$\frac{dP}{dL} = \frac{4 \tau_w}{D_h}$$

### 6.5 Flow Regime (Metzner-Reed)

The generalized Reynolds number for power-law fluids:

$$Re_g = \frac{\rho \cdot V_a^{2-n} \cdot D_h^n}{K \cdot 8^{n-1}}$$

Flow is laminar if $Re_g < 2100$.

### 6.6 Total Swab Pressure

$$\Delta P_{swab} = \sum_{segments} \frac{dP}{dL} \cdot \Delta L$$

**Dynamic SABP Recommendation:**
$$SABP_{dynamic} = SABP_{static} + \Delta P_{swab} \cdot f_{safety}$$

Where $f_{safety}$ is typically 1.15 (15% margin).

---

## 7. Trip-In Model (RIH): Governing Equations

### 7.1 Physical Concept

During trip-in, the pipe displaces fluid in the wellbore. As the pipe enters previously open-hole or cased sections:

1. **Layer Expansion**: Fluid in the path of the pipe must move to the narrower annulus, causing layers to expand (same volume in smaller cross-section = greater height)
2. **Upward Displacement**: Expanded layers push fluid above them toward surface
3. **Surface Overflow**: Fluid reaching surface overflows as pit gain (displacement returns)
4. **Fill Requirement**: The pipe interior must be filled as it runs in

### 7.2 Layer Expansion Factor

When pipe enters a section, the expansion factor is:

$$f_{expansion} = \frac{A_{wellbore}}{A_{annulus}} = \frac{\frac{\pi D_h^2}{4}}{\frac{\pi (D_h^2 - D_p^2)}{4}} = \frac{D_h^2}{D_h^2 - D_p^2}$$

For a 7" pipe in 8.5" hole:
$$f_{expansion} = \frac{0.2159^2}{0.2159^2 - 0.1778^2} = \frac{0.0466}{0.0466 - 0.0316} = 3.11$$

This means layers expand to approximately 3× their original height.

### 7.3 Displaced Layer Calculation

For each layer in the pocket (from a prior trip-out):

**Fully Above Bit (pipe has passed through):**
$$h_{new} = h_{original} \times f_{expansion}(MD_{midpoint})$$

**Spanning Bit (partially displaced):**
$$h_{new} = (h_{above} \times f_{expansion}) + h_{below}$$

**Below Bit (not yet displaced):**
$$h_{new} = h_{original}$$

### 7.4 Layer Position Update

Processing from bottom to top, maintaining contiguity:

```
nextLayerBottom = deepest layer's original bottom
for each layer (bottom to top):
    newBottom = nextLayerBottom
    newTop = newBottom - newHeight
    nextLayerBottom = newTop

    if newBottom <= 0:
        layer overflowed (remove)
    else:
        clamp newTop to surface (max 0)
        add to result
```

### 7.5 ESD at Control Depth

The ESD at a control depth (typically casing shoe) is calculated from the displaced layers:

$$ESD_{control} = \frac{\sum_{layers} \rho_i \cdot g \cdot \Delta TVD_i}{g \cdot TVD_{control}}$$

If ESD falls below target, choke pressure is required:

$$P_{choke} = (ESD_{target} - ESD_{actual}) \cdot g \cdot TVD_{control}$$

### 7.6 Floated Casing Operations

For floated casing (running casing with air inside below the float sub):

**Fill Volume:**
- Above float sub: Pipe capacity × length
- Below float sub: Zero (air section)

**Differential Pressure at Float Sub:**
$$\Delta P = P_{annulus} - P_{inside}$$

Where $P_{inside}$ only includes the mud column above the float sub level.

**Float State:**
- If $\Delta P > P_{crack}$: Float may open (fluid enters casing)
- If $\Delta P < P_{crack}$: Float stays closed

---

## 8. Surge Pressure Modeling (Trip-In)

### 8.1 Bingham Plastic Rheology

For surge calculations during trip-in, a Bingham plastic model is used:

$$\tau = \tau_y + \mu_p \cdot \dot{\gamma}$$

Where:
- $\tau_y$ = yield point (Pa)
- $\mu_p$ = plastic viscosity (Pa·s)

### 8.2 Wall Shear Rate (Annular Approximation)

$$\dot{\gamma}_w = \frac{8 V_a}{D_e}$$

Where $D_e = D_h - D_p$ is the equivalent diameter.

### 8.3 Wall Shear Stress

$$\tau_w = \tau_y + \mu_p \cdot \dot{\gamma}_w$$

### 8.4 Laminar Pressure Gradient

$$\frac{dP}{dL} = \frac{2 \tau_w}{D_e}$$

### 8.5 Turbulent Flow Check

**Apparent Viscosity:**
$$\mu_{app} = \frac{\tau_w}{\dot{\gamma}_w}$$

**Apparent Reynolds Number:**
$$Re_{app} = \frac{\rho \cdot V_a \cdot D_e}{\mu_{app}}$$

**Hedstrom Number:**
$$He = \frac{\rho \cdot \tau_y \cdot D_e^2}{\mu_p^2}$$

**Critical Reynolds Number:**
$$Re_{crit} = 2100 \cdot (1 + 0.05 \cdot He^{0.3})$$

If $Re_{app} > Re_{crit}$, turbulent correlations apply:
$$f_{turb} = \frac{0.079}{Re_{app}^{0.25}}$$
$$\frac{dP}{dL}_{turb} = \frac{f_{turb} \cdot \rho \cdot V_a^2}{2 D_e}$$

### 8.6 Surge ECD

$$\Delta ECD_{surge} = \frac{\Delta P_{surge}}{g \cdot TVD_{bit}}$$

---

## 9. Geometry Service

### 9.1 Piecewise-Constant Representation

The wellbore geometry is discretized into sections:

**Annulus Sections:**
- Top depth (MD)
- Bottom depth (MD)
- Inner diameter (wellbore ID or casing ID)
- Is cased flag (for control depth identification)

**Drillstring Sections:**
- Top depth (MD)
- Bottom depth (MD)
- Outer diameter
- Inner diameter
- Component name (DP, HWDP, DC, etc.)

### 9.2 Volume Calculations

**Annular Volume:**
$$V_{ann}(MD_1, MD_2) = \sum_{sections} \frac{\pi (D_h^2 - D_p^2)}{4} \cdot \Delta L$$

**String Volume:**
$$V_{string}(MD_1, MD_2) = \sum_{sections} \frac{\pi D_{ID}^2}{4} \cdot \Delta L$$

**Pipe OD Volume:**
$$V_{OD}(MD_1, MD_2) = \sum_{sections} \frac{\pi D_{OD}^2}{4} \cdot \Delta L$$

### 9.3 Length-for-Volume Inverse

Given a starting depth and target volume, find the length required:

```
remaining = target_volume
cursor = start_MD
while remaining > 0 and cursor < max_depth:
    area = cross_section_area(cursor)
    segment_length = next_breakpoint - cursor
    segment_volume = area × segment_length

    if segment_volume >= remaining:
        return cursor + (remaining / area) - start_MD

    remaining -= segment_volume
    cursor = next_breakpoint
```

---

## 10. TVD Sampling and Trajectory

### 10.1 Survey-Based TVD

For drilled wells, TVD is interpolated from survey stations:

$$TVD(MD) = TVD_i + \frac{MD - MD_i}{MD_{i+1} - MD_i} \cdot (TVD_{i+1} - TVD_i)$$

Binary search locates the bracketing stations, then linear interpolation is applied.

### 10.2 Directional Plan Projection

For trip-in simulations projecting beyond drilled depth, the directional plan can be used:

```
if prefer_plan and plan_stations not empty:
    use directional plan for TVD
else if surveys not empty:
    use survey data
else if plan_stations not empty:
    use plan as fallback
```

This allows trip-in simulations to project ESD for casing running to planned TD before the well is actually drilled to that depth.

---

## 11. Composition and Color Tracking

### 11.1 Purpose

Visual identification of fluid layers during simulation playback helps engineers understand:
- Where heavy slug is located
- How backfill mud propagates
- Mixing at layer boundaries
- Fluid composition at any depth

### 11.2 Color Representation

Each layer carries RGBA color components:
```
ColorRGBA {
    r: Double  // Red (0-1)
    g: Double  // Green (0-1)
    b: Double  // Blue (0-1)
    a: Double  // Alpha (0-1)
}
```

### 11.3 Color Blending

When fluids mix (e.g., in the pocket), colors are volume-weighted:

$$c_{mixed} = \frac{\sum_i c_i \cdot V_i}{\sum_i V_i}$$

Applied to each color component (R, G, B, A) separately.

### 11.4 Initial Assignment

Colors are assigned based on source:
- Project fluid layers carry their defined colors
- Backfill mud uses the selected mud's color
- Base mud uses the active mud's color
- Air is rendered as clear/transparent

---

## 12. Layer Stack Operations

### 12.1 Split Operation

Divides a layer at a specified MD boundary:

```
splitAt(stack, md):
    for each layer L:
        if md > L.topMD + ε and md < L.bottomMD - ε:
            create newLayer from md to L.bottomMD
            truncate L to end at md
            insert newLayer after L
            return
```

### 12.2 Paint Operation

Sets density (and optionally color) for an interval:

```
paintInterval(stack, fromMD, toMD, ρ, color):
    splitAt(stack, fromMD)
    splitAt(stack, toMD)
    for each layer L where L.topMD ≥ fromMD and L.bottomMD ≤ toMD:
        L.ρ = ρ
        L.color = color
    ensureInvariants()
```

### 12.3 Invariant Enforcement

After each operation:

1. **Clamp depths**: Ensure all depths are within [0, bitMD]
2. **Remove zero-thickness**: Delete layers where bottom - top < ε
3. **Sort by depth**: Order layers from surface to bottom
4. **Snap contiguity**: Each layer's topMD = previous layer's bottomMD
5. **Merge identical neighbors**: Combine adjacent layers with same density

---

## 13. Numerical Implementation

### 13.1 Constants and Tolerances

| Constant | Value | Purpose |
|----------|-------|---------|
| $g$ | 9.81 m/s² | Gravitational acceleration |
| $\epsilon$ | 10⁻⁹ | Floating-point comparison tolerance |
| $\rho_{air}$ | 1.2 kg/m³ | Air density for string fill |
| Layer thickness min | 10⁻¹² m | Minimum layer height |
| Pulse step | 0.01 m³ | U-tube equilibration increment |
| Max iterations | 10,000 | Safety limit for equilibration |

### 13.2 Pressure Unit Conversions

$$P_{kPa} = \frac{\rho \cdot g \cdot TVD}{1000}$$

$$ESD = \frac{P_{kPa}}{0.00981 \cdot TVD}$$

Where 0.00981 = g/1000 is the conversion factor.

### 13.3 Concurrency Support

The model supports concurrent execution through:

- `Sendable` protocol conformance for thread-safe data transfer
- `ProjectSnapshot` for immutable input data
- `FinalLayerSnapshot` for rheology data extraction
- Progress callbacks for UI updates

```
struct ProjectSnapshot: Sendable {
    let annulusLayers: [FinalLayerSnapshot]
    let stringLayers: [FinalLayerSnapshot]
}
```

---

## 14. Output Parameters

### 14.1 Trip-Out Results

| Parameter | Units | Description |
|-----------|-------|-------------|
| Bit MD | m | Current bit measured depth |
| Bit TVD | m | Current bit true vertical depth |
| SABP | kPa | Required surface applied back pressure |
| SABP (Raw) | kPa | SABP before clamping to ≥ 0 |
| SABP Dynamic | kPa | SABP including swab compensation |
| ESD at TD | kg/m³ | Equivalent static density at total depth |
| ESD at Bit | kg/m³ | Equivalent static density at current bit |
| Float State | text | "OPEN X%" or "CLOSED X%" |
| Step Backfill | m³ | Volume pumped from surface this step |
| Cumulative Backfill | m³ | Total volume pumped from surface |
| Expected (Closed) | m³ | Expected fill if float closed (DP Wet) |
| Expected (Open) | m³ | Expected fill if float open (DP Dry) |
| Slug Contribution | m³ | String fluid draining to annulus |
| Pit Gain | m³ | Volume overflow at surface |
| Surface Tank Delta | m³ | Net tank change (+ = gain) |
| Swab Pressure | kPa | Swab pressure loss to bit |

### 14.2 Trip-In Results

| Parameter | Units | Description |
|-----------|-------|-------------|
| Bit MD | m | Current bit measured depth |
| Bit TVD | m | Current bit true vertical depth |
| Step Fill Volume | m³ | Pipe fill volume this step |
| Cumulative Fill | m³ | Total fill volume |
| Displacement Returns | m³ | Volume displaced to surface |
| ESD at Control | kg/m³ | ESD at shoe/control depth |
| ESD at Bit | kg/m³ | ESD at current bit |
| Required Choke | kPa | Choke pressure to maintain target ESD |
| Is Below Target | bool | Flag if ESD < target |
| Differential Pressure | kPa | Annulus - String at bit |
| Float State | text | State for floated casing |

---

## 15. Integration Between Trip-Out and Trip-In

### 15.1 Workflow

A typical complete tripping workflow:

1. **Run Trip-Out Simulation**: POOH from TD to target depth
2. **Export Final State**: Pocket layers, annulus layers at end of trip-out
3. **Import to Trip-In**: Use pocket layers as initial condition
4. **Run Trip-In Simulation**: RIH from current depth back to TD
5. **Analyze Combined Results**: Volume reconciliation, pressure profiles

### 15.2 Data Transfer

The trip-in model imports from trip-out:
- `importedPocketLayers`: Final pocket state from trip-out
- `sourceSimulationID`: Reference to source simulation
- `sourceSimulationName`: For documentation
- Control depth, target ESD, base mud density

### 15.3 Alternative Sources

Trip-in can also import from:
- **Trip Tracker**: Real-time tracking data from actual operations
- **Manual Entry**: User-specified initial conditions

---

## 16. Model Validation Approach

### 16.1 Conservation Checks

At each step, verify:
- Total mass in system remains constant
- Volume removed = volume added elsewhere
- Density bounds respected ($\rho > 0$)

### 16.2 Limiting Cases

The model should reproduce:

| Case | Expected Result |
|------|-----------------|
| Uniform density, vertical well | $P = \rho g h$ (exact) |
| No pipe movement | Zero swab/surge, static equilibrium |
| Zero backfill | Float must open to maintain pressure |
| Very slow trip speed | Minimal swab/surge pressure |

### 16.3 Field Calibration

**Observed Pit Gain Mode:**
Match initial slug drainage to measured pit gain, improving subsequent predictions.

**Fill Volume Comparison:**
Compare predicted vs actual backfill to validate float state predictions.

---

## 17. Conclusions

The numerical framework presented provides a comprehensive approach to simulating wellbore hydraulics during tripping operations. Key capabilities include:

1. **Multi-layer fluid tracking** with composition/color visualization
2. **Dynamic float valve modeling** with U-tube equilibration physics
3. **Dual rheological models**: Power-law for swab, Bingham plastic for surge
4. **Comprehensive volume accounting** for trip-tank reconciliation
5. **Adaptive numerics** for computational efficiency
6. **Field calibration** through observed pit gain matching
7. **Integrated trip-out/trip-in workflow** for complete operation planning

The framework enables drilling engineers to:
- Predict required backfill volumes for different scenarios
- Optimize surface applied back pressure schedules
- Identify potential kick or loss conditions
- Plan floated casing operations with confidence
- Calibrate models to field observations for improved accuracy

---

## Nomenclature

| Symbol | Description | Units |
|--------|-------------|-------|
| $A_{ann}$ | Annular flow area | m² |
| $A_{disp}$ | Displacement area | m² |
| $D_e$ | Equivalent diameter | m |
| $D_h$ | Hole/casing inner diameter | m |
| $D_{ID}$ | Pipe inner diameter | m |
| $D_{OD}$ | Pipe outer diameter | m |
| $ESD$ | Equivalent static density | kg/m³ |
| $f_{ecc}$ | Eccentricity factor | — |
| $f_{expansion}$ | Layer expansion factor | — |
| $f_{safety}$ | Safety factor | — |
| $g$ | Gravitational acceleration | m/s² |
| $He$ | Hedstrom number | — |
| $K$ | Consistency index (power-law) | Pa·s^n |
| $K_c$ | Burkhardt clinging constant | — |
| $L$ | Length | m |
| $MD$ | Measured depth | m |
| $n$ | Flow behavior index | — |
| $P$ | Pressure | Pa or kPa |
| $P_{crack}$ | Float cracking pressure | kPa |
| $SABP$ | Surface applied back pressure | kPa |
| $Re$ | Reynolds number | — |
| $TVD$ | True vertical depth | m |
| $V$ | Volume | m³ |
| $V_a$ | Annular velocity | m/s |
| $V_{pipe}$ | Pipe velocity | m/s |
| $\Delta P$ | Pressure difference | kPa |
| $\dot{\gamma}$ | Shear rate | 1/s |
| $\mu_p$ | Plastic viscosity | Pa·s |
| $\rho$ | Fluid density | kg/m³ |
| $\tau$ | Shear stress | Pa |
| $\tau_y$ | Yield point | Pa |
| $\theta_{300}$ | Fann dial reading at 300 RPM | — |
| $\theta_{600}$ | Fann dial reading at 600 RPM | — |

---

## References

1. Bourgoyne, A.T., Millheim, K.K., Chenevert, M.E., and Young, F.S.: "Applied Drilling Engineering," SPE Textbook Series, Vol. 2, 1986.

2. Burkhardt, J.A.: "Wellbore Pressure Surges Produced by Pipe Movement," Journal of Petroleum Technology, June 1961.

3. Mitchell, R.F. and Miska, S.Z.: "Fundamentals of Drilling Engineering," SPE Textbook Series, Vol. 12, 2011.

4. Metzner, A.B. and Reed, J.C.: "Flow of Non-Newtonian Fluids—Correlation of the Laminar, Transition, and Turbulent-Flow Regions," AIChE Journal, Vol. 1, No. 4, 1955.

5. Zamora, M. and Lord, D.L.: "Practical Analysis of Drilling Mud Flow in Pipes and Annuli," SPE 4976, 1974.

6. Fontenot, J.E. and Clark, R.K.: "An Improved Method for Calculating Swab and Surge Pressures and Circulating Pressures in a Drilling Well," SPE Journal, October 1974.

7. Lal, M.: "Surge and Swab Modeling for Dynamic Pressures and Safe Trip Velocities," IADC/SPE 11412, 1983.

8. Crespo, F. and Ahmed, R.: "A Simplified Surge and Swab Pressure Model for Yield Power Law Fluids," Journal of Petroleum Science and Engineering, 2013.

---

*Document generated from source code analysis of:*
- *NumericalTripModel.swift*
- *TripInSimulationViewModel.swift*
- *SwabCalculator.swift*
- *SurgeSwabCalculator.swift*
- *ProjectGeometryService.swift*
- *TvdSampler.swift*
- *TripLayerSnapshot.swift*

*Version 2.0 — Comprehensive Edition*
