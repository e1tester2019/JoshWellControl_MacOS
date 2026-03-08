# Slug and Back Fill: A Numerical Approach to Managed Pressure Tripping
## Presentation Template

---

### SLIDE 1 — Title

**Slug and Back Fill: A Numerical Approach to Managed Pressure Tripping**

*Developing, Validating, and Operationalizing a Multi-Layer Wellbore Hydraulics Model*

[Your Name]
[Company / Rig]
[Date]

---

### SLIDE 2 — The Challenge

**What we inherited:**

- Slug and back fill method attempted in the previous drilling season
- Ad-hoc adjustments required during execution — calculations were not matching reality
- Attempted to kill the well by 1000m — exceeded fracture pressure, well went on losses
- The existing models were underestimating the required kill mud volume

**The question:** Why were the calculations wrong, and could we do better?

---

### SLIDE 3 — Root Cause: Why the Old Models Failed

**Discovery #1: Kill at 1000m was physically impossible**
- With the mud weights in use, the math showed it could not be done without exceeding fracture pressure
- Kill at ~300m was achievable — talked the oil company into allowing the trip

**Discovery #2: Float valve behavior was not modeled**
- Air in the drill string must be replaced with mud by the time you're out of the well
- The slug draining through the float adds significantly more kill mud to the annulus than old models accounted for
- Old models were underestimating kill mud volume by up to ~4 m3

**Discovery #3: Single-density assumptions break down**
- Real wellbores have multiple fluid layers with different densities and rheologies
- A single-rheology APL calculation gives incorrect friction pressures
- Back pressure recommendations based on single-fluid models are wrong

---

### SLIDE 4 — The Numerical Model: Core Concepts

**Multi-layer fluid column representation**

- Wellbore divided into three compartments: String, Annulus, Pocket (below bit)
- Each compartment tracks individual fluid layers with:
  - Density (kg/m3)
  - Rheology (PV, YP, or dial readings for n & K)
  - Volume and measured depth position
  - Color for visual identification

**Unlike traditional models:**
| Traditional | This Model |
|-------------|------------|
| Single mud weight in annulus | Multiple layers with individual densities |
| Single rheology for APL | Per-layer rheology for accurate friction |
| No float valve physics | Dynamic float state with U-tube equilibration |
| Static fill calculation | Step-by-step simulation with volume tracking |
| Trip out only | Trip out + Trip in + Circulate + Ream |

---

### SLIDE 5 — Float Valve Physics

**Why this matters:**

- Float opens when string hydrostatic > annulus hydrostatic + crack pressure
- When open: slug drains, air fills string, backfill requirement drops to steel displacement only
- When closed: full pipe OD volume must be backfilled

**The model tracks:**
- Float state at every step (OPEN/CLOSED with percentage)
- Slug contribution volume (how much drained from string)
- U-tube equilibration iterations until pressure balance

**Key insight:** The slug drainage adds kill-weight mud to the annulus. Old models that didn't account for this were planning insufficient kill mud volumes, then discovering they needed more during execution.

[SCREENSHOT: App showing float state column and wellbore visualization with slug draining]

---

### SLIDE 6 — SABP at Control Depth

**Critical correction: Where do you maintain pressure?**

- Previous approach: Target ESD at TD
- Corrected approach: Target ESD at the **control depth** (casing shoe)
- Why: The shoe is where losses occur — that's where you need to control pressure

**ESD at control depth calculation:**

ESD_control = (Hydrostatic to control TVD + SABP) / (0.00981 x Control TVD)

- Hydrostatic computed from all layers (annulus + pocket) down to control TVD
- Accounts for toe-up well profiles where TVD may decrease below heel

[SCREENSHOT: App showing ESD@Ctrl column in the steps table]

---

### SLIDE 7 — Pocket Hydrostatic Analysis

**Understanding what fills the pocket:**

As pipe is pulled, fluid from the annulus (and string, if float is open) fills the space below the bit.

**Pre-blend source tracking:**
- Tracks how much of each original mud density contributed to each pocket layer
- Example: 0.5 m3 of 1400 kg/m3 from string + 0.3 m3 of 1200 kg/m3 from annulus

**Hydrostatic summary:**
- Blended layers grouped by density
- TVD height and hydrostatic contribution per density
- Total hydrostatic to control depth

**Why this matters:** Knowing the pocket composition tells you whether your kill strategy is working — are you getting enough heavy mud below the bit?

[SCREENSHOT: App showing pocket mud inventory and hydrostatic summary]

---

### SLIDE 8 — Swab and Surge Pressure

**Trip out (swab) — Power-law rheology:**
- n and K derived from Fann viscometer readings (theta 600/300)
- Burkhardt clinging factor: Kc = 0.45 + 0.45 x (Dp/Dh)^2
- Annular velocity: Va = Vpipe x (1 + Kc) x (Adisp/Aann) x f_ecc
- Per-section calculation through variable geometry

**Trip in (surge) — Bingham plastic model:**
- Uses PV and YP for wall shear stress
- Turbulent flow check via Hedstrom number
- Surge ECD added to hydrostatic for total ESD

**Eccentricity factor:**
- 1.0 = concentric (pipe centered)
- >1.0 = eccentric (pipe off-center, increases velocity on narrow side)
- Adjustable per operation — typical field value: 1.2

---

### SLIDE 9 — Season Progression: ECD Mud Caps

**Before slug and back fill was ready:**

- Used ECD mud caps for tripping
- Involves spotting fluid in both annulus and drill string
- Annulus cap maintains EMD at ECD while tripping

**Observation:** Others were spotting the drill string mud component in the wrong place, causing the well to be under the desired EMD

**The model helped:**
- Visualize where fluids actually were in the wellbore
- Confirm correct placement of mud cap components
- Mud caps improved trips back to bottom — additional pressure holds open tight spots

---

### SLIDE 10 — Season Progression: Optimizing Dry Pipe Trips

**Regular tripping (non-slug and back fill):**

- App used to determine the maximum amount of dry pipe that could be pulled
- Allows pulling dry pipe as long as possible before the well requires backfill
- Direct improvement to trip times

**How:**
- Model shows at what depth the float opens
- Shows how much slug drains at each step
- Allows you to plan the slug volume to maximize dry pipe interval

---

### SLIDE 11 — Season Progression: First Slug and Back Fill

**Trip 1: First execution**
- Successfully got out of hole — no losses (first time ever with this method)
- Pulled wet pipe

**Trip 2: Added regular slug on top**
- Placed normal tripping slug on top of the pipe kill slug
- Got out of hole with no losses AND pulled dry pipe to surface

**The difference:** The model showed exactly how much slug was needed and where fluids would be at every depth. No ad-hoc adjustments needed.

[SCREENSHOT: App showing the trip out simulation for this well]

---

### SLIDE 12 — Season Progression: Kill Mud Optimization

**Confidence in the model grew:**

- Model fill volumes matched actual rig trip sheet volumes
- This confirmed the model accuracy

**Reducing kill mud density:**
- Old modelers were using up to 4 m3 more annulus kill mud than needed
- Started reducing density to stay closer to target pressure
- Old modelers objected — said it was not safe
- They were proved wrong — the model was correct

**Why this matters:**
- Less kill mud = lower cost
- Closer to target = less risk of exceeding fracture pressure
- Accurate volumes = better trip planning

---

### SLIDE 13 — Season Progression: Annulus Mud Cap + Slug and Back Fill

**Combined approach:**

- Spot annulus mud cap prior to performing slug and back fill
- Result: Well dead at **2000m** (vs. the old attempt at 1000m that failed)

**Why 2000m is significant:**
- Gives time to adjust and confirm the well is dead
- Helps keep the well overbalanced while running casing
- 2x the depth of the previous season's failed attempt

---

### SLIDE 14 — Season Progression: Mixed Density Optimization

**Advanced application:**

- Realized that using full kill mud for the entire backfill would exceed fracture pressure at deeper depths
- Need to switch from kill mud to lighter active mud partway through

**The app showed:**
- How using different densities allows killing the well at different depths
- The effect on stripping pressures
- How lighter active mud reduces ESD while maintaining wellbore stability

**Real-time adjustment:**
- On one trip, kill mud density came in higher than designed
- Adjusted back fill volume quickly using the app
- No losses, no problems

---

### SLIDE 15 — Why Trip In Simulation Was Needed

**The problem:**

- After tripping out, what happens when you trip back in?
- Different drill string size means different displacement
- Where are the fluids at each depth?
- When do you go underbalanced?

**Discovery:**
- Saw that we would be going underbalanced at 1800m on trip in
- Could not yet solve this problem at the time, but knowing it was there was critical

**The trip-in model tracks:**
- Layer expansion as pipe enters (layers expand by up to 3x in tight annulus)
- Displacement returns to surface
- ESD at control depth at every step
- Required choke pressure to maintain target ESD
- Surge pressure with per-layer rheology

---

### SLIDE 16 — Super Simulation: Chaining Operations

**The key insight: Real operations are not isolated**

A trip involves:
1. Trip out (slug and back fill)
2. Hit tight hole — need to pump/circulate
3. Continue tripping
4. Circulate at shoe
5. Trip back in

**Each operation changes the fluid distribution, which changes everything downstream.**

**What Super Simulation does:**
- Chains any sequence of: Trip Out, Trip In, Circulate, Ream Out, Ream In
- Carries the complete fluid state (all layers, all densities, all rheologies) from one operation to the next
- Shows continuous ESD, back pressure, and pump rate across all operations
- Allows "what if" planning: what happens if I need to circulate at 2000m?

---

### SLIDE 17 — Super Simulation: Multi-Fluid Rheology

**The differentiator nobody else has:**

| Single-Fluid Models | This Model |
|---------------------|------------|
| One PV/YP for entire annulus | Each layer has its own PV/YP |
| One APL calculation | APL computed through each layer individually |
| Back pressure based on uniform mud | Back pressure based on actual fluid distribution |

**Why this matters for slug and back fill:**
- Kill mud (1500 kg/m3) has different rheology than active mud (1200 kg/m3)
- When you circulate, you're moving kill mud out and active mud in
- The APL changes as the fluid composition changes
- If pump rate is too high, APL may exceed fracture pressure

**The app shows APL vs pump rate with the actual fluid stack** — lets you find the rate that works without exceeding limits.

[SCREENSHOT: Super Sim ESD chart showing multi-operation sequence]

---

### SLIDE 18 — Super Simulation: Tight Hole Scenario

**Example: Pumping during trip out**

1. Tripping out with slug and back fill — well is dead at 300m
2. Hit tight hole at 2500m — need to circulate to free pipe
3. Circulating removes kill mud from below the bit
4. Kill zone retreats — now dead at higher depth
5. Continue tripping — need to adjust back pressure

**Without the model:** You don't know how much kill mud was removed, what the new fluid distribution looks like, or what back pressure to use.

**With the model:** Run the Super Sim with the circulation event. See exactly where fluids are, what ESD is at control depth, and what back pressure is needed.

[SCREENSHOT: Super Sim showing trip out → circulate → continue trip sequence]

---

### SLIDE 19 — Torque & Drag

**Hook load prediction across all simulations**

- Pickup, slackoff, rotating, and free-hanging hook loads
- Buoyancy from the live multi-fluid stack — not a single mud weight
- Friction factor calibrated per well section (casing vs open hole)
- APL piston force from annular pressure losses

**Integration:**
- Independent T&D parameters per simulation (trip out, trip in, circulating, Super Sim)
- Hook load cursors on charts alongside ESD and back pressure
- Pump Schedule: T&D computed at each displacement stage, shown in hydraulics panel and HTML reports
- Calibrate predicted hook loads against actual rig data

---

### SLIDE 20 — Tapered String Support

**Real drill strings are not uniform**

- DP, HWDP, drill collars — each section has different OD/ID
- Pipe capacity, annular velocity, displacement volume, and buoyancy all vary per section
- Friction computed within uniform-geometry sub-intervals
- When a fluid layer spans a geometry change, it is split at the boundary
- T&D uses actual weight-per-meter and cross-section for each component

---

### SLIDE 21 — Standpipe Pressure (SPP)

**SPP = String Friction + Bit Nozzle ΔP + Annulus Friction + Surface Back Pressure**

- Power-law rheology from Fann 35 dial readings (600/300) or PV/YP
- Turbulent flow detection via Metzner-Reed generalized Reynolds number
- Turbulent friction via Dodge-Metzner correlation (iterative Fanning friction factor)
- Bit nozzle ΔP = ρV² / (2Cd²) where V = Q/TFA, Cd = 0.95
- Geometry-split integration: friction split at geometry boundaries to prevent midpoint-sampling errors
- Validated against actual rig SPP — laminar-only models underestimate by 40–60%

---

### SLIDE 22 — Validation Summary

| Validation Method | Result |
|-------------------|--------|
| Fill volume vs trip sheet | Match |
| Float state prediction | Confirmed by fill rate |
| Kill depth prediction (300m vs 1000m) | No losses at 300m, losses at 1000m |
| Kill mud volume (old vs new model) | Old model ~4 m3 short |
| Reduced kill mud density | No losses, old modelers proved wrong |
| Mud cap placement | Corrected others' errors |
| First slug and back fill trip | No losses |
| Real-time density adjustment | Successful, no losses |
| Dead at 2000m with mud cap | Achieved |
| SPP vs actual rig pressure | Within expected range at multiple flow rates and depths |
| Hook load vs rig data | Calibrated friction factors match pickup/slackoff weights |

---

### SLIDE 23 — What's Next

**Remaining challenges:**
- Trip-in underbalanced zone at ~1800m — need to solve this
- Further optimization of kill mud volumes
- Integration with real-time rig data for automated trip monitoring

**Model enhancements:**
- Fracture pressure / pore pressure overlay on charts
- Automated optimization of backfill density schedule
- Real-time comparison: predicted vs actual during operations

---

### SLIDE 24 — Summary

**Key takeaways:**

1. **The old models were fundamentally flawed** — missing float valve physics, underestimating kill mud by ~4 m3, attempting impossible kill depths

2. **Multi-layer simulation with real rheology works** — fill volumes match trip sheets, predictions are reliable

3. **Progressive validation through the season** — each trip built confidence, from ECD mud caps to first successful slug and back fill to dry pipe to surface

4. **Super Simulation is the differentiator** — chaining operations with multi-fluid rheology enables planning that spreadsheets and single-fluid models cannot do

5. **Real-time adaptability** — when conditions change (wrong mud weight, tight hole), the model gives immediate, accurate answers

6. **The model keeps growing** — torque & drag predicts hook loads across all operations, tapered string geometry handles real BHAs, and standpipe pressure with turbulent flow detection matches what the driller sees on the gauge

---

### SLIDE 25 — Questions

[Contact information]

---

## APPENDIX SLIDES

### APPENDIX A — Model Equations Summary

**Hydrostatic pressure (multi-layer):**
P = P_surface + SUM(rho_i x g x delta_TVD_i)

**ESD at control depth:**
ESD = (Hydrostatic + SABP) / (0.00981 x TVD_control)

**Float state criterion:**
OPEN if P_string > P_annulus + P_crack + P_tolerance

**Swab (power-law):**
n = ln(theta600/theta300) / ln(2)
K = 0.4788 x theta600 / 1022^n
Va = Vpipe x (1 + Kc) x (Adisp/Aann) x f_ecc

**Surge (Bingham plastic):**
tau = tau_y + mu_p x gamma_dot
dP/dL = 2 x tau_w / De

### APPENDIX B — Volume Definitions

| Term | Definition |
|------|------------|
| DP Wet | Pipe OD volume (capacity + displacement) |
| DP Dry | Steel displacement only (metal ring area) |
| Backfill | Volume pumped from surface |
| Pit Gain | Volume overflow at surface |
| Slug Contribution | String fluid draining to annulus |

### APPENDIX C — Software Architecture

- SwiftUI + SwiftData application (macOS/iOS)
- Multi-layer fluid stacks with per-layer rheology
- Real-time simulation with adaptive stepping
- Super Simulation: chain Trip Out, Trip In, Circulate, Ream Out, Ream In
- PDF/HTML export for documentation
- Wellbore visualization with composition colors

### APPENDIX D — Nomenclature

[Reference the SPE paper nomenclature table]
