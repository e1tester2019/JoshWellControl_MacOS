# Launch Screen Visual Guide

## Standard Launch Screen (Default)

```
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║    🌊 Animated depth markers (pulsing circles)       ║
║                                                       ║
║              ╭─────────────────╮                     ║
║              │    ⟳ Outer Ring │  ← Rotating slowly  ║
║              │   ⟲ Middle Ring │  ← Counter-rotating ║
║              │                 │                      ║
║              │    ✦ Drill Bit  │  ← Rotating fast    ║
║              │     (6 blades)  │                      ║
║              │                 │                      ║
║              ╰─────────────────╯                     ║
║          Pulsing cyan glow effect                    ║
║                                                       ║
║         Josh Well Control                            ║
║         ══════════════════                           ║
║    Managed Pressure Drilling &                       ║
║      Wellbore Hydraulics                             ║
║                                                       ║
║                                                       ║
║         ━━━━━━━━━━━━━━━━━━                          ║
║         [████████░░░░░░░░] 45%                       ║
║            Initializing...                           ║
║                                                       ║
║                                                       ║
║       Version 1.0 • © 2025 Josh Sallows             ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝

Colors:
- Background: Dark blue-gray gradient
- Outer ring: Blue → Cyan gradient
- Middle ring: Orange → Yellow gradient
- Drill bit: White → Cyan gradient
- Text: White with cyan gradient
- Progress: Blue → Cyan gradient
```

## Minimal Launch Screen

```
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
║                     💧                               ║
║                  (droplet)                           ║
║                  Scale pulse                         ║
║                                                       ║
║                                                       ║
║              Josh Well Control                       ║
║                                                       ║
║                                                       ║
║           ▓▓▓▓▓▓▓▓▓▓░░░░░░░░                        ║
║              (progress bar)                          ║
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝

Colors:
- Background: Solid dark blue-gray
- Droplet: Blue → Cyan gradient
- Text: White
- Progress: Cyan linear bar
```

## Professional Launch Screen

```
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║                                                       ║
║                                                       ║
║                 ╭─────────╮                          ║
║                 │    🏢   │                          ║
║                 │  Badge  │  ← Circular blue badge  ║
║                 │  Icon   │     with shadow         ║
║                 ╰─────────╯                          ║
║                  ECG symbol                          ║
║                                                       ║
║              Josh Well Control                       ║
║         ─────────────────────────                   ║
║               (animated line)                        ║
║        Wellbore Hydraulics Engineering              ║
║                                                       ║
║                                                       ║
║                                                       ║
║                                                       ║
║                     ⚙️                               ║
║                 (spinner)                            ║
║                  Loading...                          ║
║                                                       ║
║                 Version 1.0                          ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝

Colors:
- Background: Very dark blue gradient (nearly black)
- Badge: Blue → Cyan gradient with shadow
- Divider line: Cyan gradient (fades in/out)
- Text: White
- Spinner: Cyan
```

## Animation Sequences

### Standard (Default) - Timeline

```
Time:  0s      0.5s     1.0s     1.5s     2.0s     2.5s
       │        │        │        │        │        │
Fade   ░▒▓█████████████████████████████████████████  100%
Scale  ▁▃▅█████████████████████████████████████████  1.0x
Rings  ↻───────↻───────↻───────↻───────↻───────↻──  360°/8s
Pulse  ▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁▅█▅▁  1.0-1.3x
Waves  ⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇⌇  Continuous
Bar    ▁▁▂▃▄▅▆▇███████████████████████████████████  Fill
       │        │        │        │        │        │
State: [--Appear--][----Initializing----][--Ready--]
```

### Minimal - Timeline

```
Time:  0s      0.5s     1.0s     1.5s     2.0s     2.5s
       │        │        │        │        │        │
Fade   ░▒▓█████████████████████████████████████████  100%
Scale  ▁▃▅█████████████████████████████████████████  1.0x
Bar    ░░░░░░░███████████████████████████████████  Linear
       │        │        │        │        │        │
State: [Quick Fade][--------Loading---------][Done]
```

### Professional - Timeline

```
Time:  0s      0.5s     1.0s     1.5s     2.0s     2.5s
       │        │        │        │        │        │
Fade   ░▒▓█████████████████████████████████████████  100%
Line   ▁▃▅▇███▇▅▃▁░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Expand
Spin   ○●◐◑◐●○●◐◑◐●○●◐◑◐●○●◐◑◐●○●◐◑◐●○●◐◑◐●○  Rotate
       │        │        │        │        │        │
State: [--Appear--][-----Processing------][--Done--]
```

## Element Breakdown

### Standard Launch Screen Elements

1. **Background Layer**
   - Gradient: 3 color stops
   - 15 animated circles (depth markers)
   - Opacity: 0.02 per circle
   - Animation: Vertical oscillation, 3s cycle

2. **Logo Layer**
   - Pulsing glow (radial gradient)
   - Outer ring: 140pt diameter, 4pt stroke
   - Middle ring: 100pt diameter, 3pt stroke
   - Inner drill bit: 6 blades, 30pt length
   - All rotating at different speeds

3. **Text Layer**
   - Title: 36pt bold rounded
   - Subtitle: 14pt medium
   - Both with gradient fills

4. **Progress Layer**
   - Container: 240pt × 4pt
   - Bar: Animated fill
   - Status text: 12pt medium

5. **Footer Layer**
   - Version: 10pt
   - Opacity: 0.3

### Minimal Launch Screen Elements

1. **Background**: Solid color
2. **Icon**: Single droplet (80pt)
3. **Title**: 32pt semibold
4. **Progress**: Linear bar (200pt wide)

### Professional Launch Screen Elements

1. **Background**: Clean gradient
2. **Badge**: 120pt circle with icon
3. **Title**: 34pt bold
4. **Divider**: Animated line (200pt)
5. **Spinner**: System circular progress
6. **Footer**: Version info

## Size Specifications

### Standard Launch
- Window size: Flexible, scales to fit
- Optimal: 800-1200pt wide × 600-900pt tall
- Icon group: 140pt × 140pt
- Text area: ~300pt wide
- Progress: 240pt × 4pt

### Minimal Launch
- Window size: Flexible
- Optimal: 400-800pt wide × 400-700pt tall
- Icon: 80pt × 80pt
- Text: ~250pt wide
- Progress: 200pt × 4pt

### Professional Launch
- Window size: Flexible
- Optimal: 600-1000pt wide × 500-800pt tall
- Badge: 120pt × 120pt
- Text: ~350pt wide
- Divider: 200pt × 2pt

## Color Values (RGB)

### Standard Launch
```swift
Background top:    (0.05, 0.10, 0.15) - Very dark blue-gray
Background mid:    (0.10, 0.15, 0.20) - Dark blue-gray  
Background bottom: (0.15, 0.20, 0.25) - Medium-dark blue-gray

Outer ring start:  Blue (0.0, 0.5, 1.0) at 60% opacity
Outer ring end:    Cyan (0.0, 1.0, 1.0) at 40% opacity

Middle ring start: Orange (1.0, 0.6, 0.0) at 60% opacity
Middle ring end:   Yellow (1.0, 1.0, 0.0) at 40% opacity

Drill bit start:   White (1.0, 1.0, 1.0) at 100% opacity
Drill bit end:     Cyan (0.0, 1.0, 1.0) at 80% opacity

Text title:        White → Cyan gradient
Text subtitle:     White at 70% opacity
Text loading:      White at 60% opacity
Text footer:       White at 30% opacity

Progress bg:       White at 10% opacity
Progress bar:      Blue → Cyan gradient
```

### Animation Durations

| Element | Duration | Type | Repeats |
|---------|----------|------|---------|
| Fade in | 0.6s | Ease out | Once |
| Scale up | 0.6s | Ease out | Once |
| Outer ring | 8.0s | Linear | Forever |
| Middle ring | ~5.3s | Linear | Forever |
| Drill bit | 4.0s | Linear | Forever |
| Pulse glow | 2.0s | Ease in-out | Forever (auto-reverse) |
| Depth markers | 3.0s | Ease in-out | Forever (auto-reverse) |
| Progress bar | 1.5s | Ease in-out | Forever |
| Transition out | 0.5s | Ease in-out | Once |

## Comparison Chart

| Feature | Standard | Minimal | Professional |
|---------|----------|---------|--------------|
| **Complexity** | High | Low | Medium |
| **Animations** | Multiple | Few | Some |
| **Load time** | ~2.5s | ~1.0s | ~1.5s |
| **CPU usage** | Medium | Low | Low-Medium |
| **Theme** | Industrial | Clean | Corporate |
| **Best for** | Branding | Speed | Enterprise |
| **Customizable** | Very | Limited | Medium |

## Recommendations

**Use Standard when:**
- First launch or important app updates
- Branding is important
- Target users appreciate visual polish
- Desktop/tablet form factor

**Use Minimal when:**
- Developing/debugging
- Fast launches are critical
- Mobile devices with slower performance
- Accessibility concerns

**Use Professional when:**
- Enterprise/corporate deployments
- Consistent with company branding
- Balance between speed and polish needed
- Presentation to stakeholders

## Quick Switch Guide

To change styles, edit `AppLaunchCoordinator.swift`:

```swift
// Standard (default)
LaunchScreenView()

// Minimal
MinimalLaunchScreen()

// Professional  
ProfessionalLaunchScreen()
```

Or set configuration:
```swift
let coordinator = AppLaunchCoordinator(
    configuration: .fast  // Uses minimal style implicitly
)
```
